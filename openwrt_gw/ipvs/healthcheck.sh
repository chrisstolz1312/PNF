#!/bin/sh
# PNF IPVS backend reachability monitor. Changes weights only.
set -u

PATH=/usr/sbin:/usr/bin:/sbin:/bin
BACKENDS=${BACKENDS:-/backends.conf}
CONFIG=${CONFIG:-/ipvs.conf}
INTERVAL=${HEALTHCHECK_INTERVAL:-5}
TIMEOUT=${HEALTHCHECK_TIMEOUT:-1}
FAILS=${HEALTHCHECK_FAILS:-3}
RISES=${HEALTHCHECK_RISES:-2}
STATE_DIR=${HEALTHCHECK_STATE_DIR:-/run/pnf-healthcheck}

log() { printf '[HEALTHCHECK] %s\n' "$*"; }
error() { log "ERROR: $*" >&2; }

for item in "$INTERVAL" "$TIMEOUT" "$FAILS" "$RISES"; do
    case "$item" in ''|*[!0-9]*) error 'Intervals and thresholds must be positive integers'; exit 1 ;; esac
    [ "$item" -gt 0 ] || { error 'Intervals and thresholds must be positive'; exit 1; }
done
[ -r "$BACKENDS" ] || { error "Cannot read $BACKENDS"; exit 1; }
mkdir -p "$STATE_DIR" || exit 1

# Only the administrator-managed config controls VIP selection. Do not source it:
# healthchecks do not need to determine VIPs if they inspect existing IPVS rules.
# Resolve service/real-server tuples from the current IPVS table, matching
# backends.conf addresses and port. This also handles disabled address families.

get_weight() {
    # $1: -t or -u; $2: VIP:port; $3: realserver:port
    ipvsadm -Sn 2>/dev/null | awk -v flag="$1" -v vip="$2" -v real="$3" '
        $1=="-a" && $2==flag && $3==vip && $4=="-r" && $5==real {
            for(i=6;i<=NF;i++) if($i=="-w" && i<NF) {print $(i+1); exit}
        }
    '
}

# Reconcile desired weight against actual rules even after an external rebuild.
set_weight() {
    flag=$1 vip=$2 real=$3 weight=$4
    current=$(get_weight "$flag" "$vip" "$real")
    [ -n "$current" ] || { error "Backend missing: $flag $vip -> $real"; return 1; }
    [ "$current" = "$weight" ] && return 0
    if ipvsadm -e "$flag" "$vip" -r "$real" -m -w "$weight"; then
        log "WEIGHT $current->$weight: $flag $vip -> $real"
    else
        error "Cannot set weight=$weight: $flag $vip -> $real"
        return 1
    fi
}

# Lookup only IPVS services that are actually present, so a disabled family
# is never touched. The static backend list remains authoritative.
check_backend() {
    proto=$1 ip=$2 port=$3 family=$4
    flag=-u
    [ "$proto" = tcp ] && flag=-t
    if [ "$family" = 6 ]; then real="[$ip]:$port"; else real="$ip:$port"; fi

    # Each protocol/family/backend gets an independent state.
    key="${proto}_${family}_${ip}_${port}"
    key=$(printf '%s' "$key" | tr ':.' '__')
    state_file="$STATE_DIR/$key"
    consecutive_fail=0 consecutive_rise=0 desired=1
    if [ -r "$state_file" ]; then
        read -r consecutive_fail consecutive_rise desired < "$state_file" || :
    fi
    case "$desired" in 0|1) ;; *) desired=1 ;; esac

    if ping "-$family" -n -c 1 -W "$TIMEOUT" "$ip" >/dev/null 2>&1; then
        consecutive_fail=0
        if [ "$desired" = 0 ]; then
            consecutive_rise=$((consecutive_rise + 1))
            if [ "$consecutive_rise" -ge "$RISES" ]; then
                desired=1
                consecutive_rise=0
                log "UP $proto IPv$family $ip:$port"
            fi
        else
            consecutive_rise=0
        fi
    else
        consecutive_rise=0
        if [ "$desired" = 1 ]; then
            consecutive_fail=$((consecutive_fail + 1))
            if [ "$consecutive_fail" -ge "$FAILS" ]; then
                desired=0
                consecutive_fail=0
                log "DOWN $proto IPv$family $ip:$port"
            fi
        else
            consecutive_fail=0
        fi
    fi
    printf '%s %s %s\n' "$consecutive_fail" "$consecutive_rise" "$desired" > "$state_file"

    # Search matching real-server entries across all active VIPs. IPVS rules
    # contain the VIP, so we do not guess it from interface configuration.
    ipvsadm -Sn 2>/dev/null | awk -v flag="$flag" -v real="$real" '
        $1=="-a" && $2==flag && $4=="-r" && $5==real {print $3}
    ' | while IFS= read -r vip; do
        [ -n "$vip" ] && set_weight "$flag" "$vip" "$real" "$desired"
    done
}

log "Started: interval=${INTERVAL}s timeout=${TIMEOUT}s fails=$FAILS rises=$RISES"
while :; do
    while read -r proto ipv4 port ipv6 rest || [ -n "${proto:-}" ]; do
        case "${proto:-}" in ''|'#'*) continue ;; tcp|udp) ;; *) error "Invalid protocol: $proto"; continue ;; esac
        case "${port:-}" in ''|*[!0-9]*) error "Invalid port for $proto"; continue ;; esac
        [ -n "${ipv4:-}" ] && check_backend "$proto" "$ipv4" "$port" 4
        [ -n "${ipv6:-}" ] && check_backend "$proto" "$ipv6" "$port" 6
    done < "$BACKENDS"
    sleep "$INTERVAL"
done
