#!/bin/sh
# PNF IPVS load balancer
# --setup: configure IPVS services and backends
# --check: verify current rules, address selection and backend configuration
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin
IGNORE_TCP="${IGNORE_TCP:-0}"
LISTEN_PORT=1194
TCP_TIMEOUT=300
TCP_FIN_TIMEOUT=30
UDP_TIMEOUT=30
STATE_FILE=/run/pnf-ipvs.state
BACKENDS=/backends.conf
CONFIG=/ipvs.conf

log()  { printf '[IPVS] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

case "${1:---setup}" in
    --setup|--check) MODE="${1:---setup}" ;;
    *) fail 'Usage: /ipvs.sh --setup|--check' ;;
esac
case "$IGNORE_TCP" in
    0|1) ;;
    *) fail "IGNORE_TCP must be 0 or 1 (got: $IGNORE_TCP)" ;;
esac

[ -r "$BACKENDS" ] || fail "Backend file unavailable: $BACKENDS"
awk '$1 == "udp" && NF >= 4 { found=1 } END { exit !found }' "$BACKENDS" || fail 'No UDP backends configured'
if [ "$IGNORE_TCP" = 0 ]; then
    awk '$1 == "tcp" && NF >= 4 { found=1 } END { exit !found }' "$BACKENDS" || fail 'TCP enabled but no TCP backends configured'
fi

# ipvs.conf is a trusted, administrator-managed shell configuration file.
IPVS_IPV4=
IPVS_IPV6=
if [ -e "$CONFIG" ]; then
    [ -r "$CONFIG" ] || fail "Configuration file unreadable: $CONFIG"
    # shellcheck disable=SC1091
    . "$CONFIG"
fi

normalize_setting() {
    case "$1" in
        ''|true|TRUE|True|yes|YES|Yes|1) printf 'auto\n' ;;
        false|FALSE|False|no|NO|No|0) printf 'disabled\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

IPVS_IPV4="$(normalize_setting "$IPVS_IPV4")"
IPVS_IPV6="$(normalize_setting "$IPVS_IPV6")"
[ "$IPVS_IPV4" != disabled ] || [ "$IPVS_IPV6" != disabled ] || fail 'IPv4 and IPv6 cannot both be disabled'

# Match an address assigned to any host interface. "ip" prints canonical
# address forms; textual matching requires the same spelling as "ip addr".
host_has_address() {
    family="$1"
    wanted="$2"
    ip "-$family" -o addr show | awk -v wanted="$wanted" '
        { split($4, a, "/"); if (a[1] == wanted) found=1 }
        END { exit !found }
    '
}

# Detect the default interface separately for each address family.
default_interface() {
    ip "-$1" route show default | awk '
        /^default / { for (i=1; i<=NF; i++) if ($i=="dev") { print $(i+1); exit } }
    '
}

auto_address() {
    family="$1"
    iface="$2"
    [ -n "$iface" ] || return 0
    if [ "$family" = 4 ]; then
        ip -4 -o addr show dev "$iface" scope global | awk '
            NR == 1 { split($4, a, "/"); print a[1]; exit }
        '
    else
        ip -6 -o addr show dev "$iface" scope global | awk '
            !/temporary|deprecated|tentative|dadfailed/ {
                split($4, a, "/"); print a[1]; exit
            }
        '
    fi
}

select_address() {
    family="$1"
    setting="$2"
    iface="$3"
    if [ "$setting" = disabled ]; then
        log "IPv$family disabled" >&2
        return 0
    fi
    if [ "$setting" != auto ]; then
        if host_has_address "$family" "$setting"; then
            log "IPv$family static: $setting" >&2
            printf '%s\n' "$setting"
            return 0
        fi
        log "WARNING: IPv$family address $setting not assigned; using automatic detection" >&2
    fi
    address="$(auto_address "$family" "$iface")"
    [ -n "$address" ] || fail "No usable IPv$family address found (default interface: ${iface:-none})"
    log "IPv$family automatic: $address (interface $iface)" >&2
    printf '%s\n' "$address"
}

WAN4_IF=''
WAN6_IF=''
[ "$IPVS_IPV4" = disabled ] || WAN4_IF="$(default_interface 4)"
[ "$IPVS_IPV6" = disabled ] || WAN6_IF="$(default_interface 6)"
WAN4_IP="$(select_address 4 "$IPVS_IPV4" "$WAN4_IF")"
WAN6_IP="$(select_address 6 "$IPVS_IPV6" "$WAN6_IF")"
[ -n "$WAN4_IP" ] || [ -n "$WAN6_IP" ] || fail 'No IP address family enabled'

# Keep the state independent of the default interface when using static IPs.
expected_state() {
    printf '%s\n' "$WAN4_IP" "$WAN6_IP" "$IGNORE_TCP"
    cat "$BACKENDS"
}

RULES=''
service_exists() {
    printf '%s\n' "$RULES" | grep -F -- "-A $1 $2 -s lc" >/dev/null
}
backend_exists() {
    printf '%s\n' "$RULES" | grep -F -- "-a $1 $2 -r $3 -m" >/dev/null
}

check_rules() {
    [ -r "$STATE_FILE" ] || fail 'No successful IPVS initialization recorded'
    [ "$(expected_state)" = "$(cat "$STATE_FILE")" ] || fail 'Address selection, TCP mode or backends changed'
    RULES="$(ipvsadm -Sn)" || fail 'Cannot read IPVS rules'

    if [ -n "$WAN4_IP" ]; then
        service_exists -u "${WAN4_IP}:${LISTEN_PORT}" || fail 'UDP IPv4 service missing'
        if [ "$IGNORE_TCP" = 0 ]; then
            service_exists -t "${WAN4_IP}:${LISTEN_PORT}" || fail 'TCP IPv4 service missing'
        fi
    fi
    if [ -n "$WAN6_IP" ]; then
        service_exists -u "[${WAN6_IP}]:${LISTEN_PORT}" || fail 'UDP IPv6 service missing'
        if [ "$IGNORE_TCP" = 0 ]; then
            service_exists -t "[${WAN6_IP}]:${LISTEN_PORT}" || fail 'TCP IPv6 service missing'
        fi
    fi

    while read -r PROTO IPV4 PORT IPV6 REST || [ -n "${PROTO:-}" ]; do
        case "${PROTO:-}" in ''|'#'*) continue ;; esac
        [ -n "${IPV4:-}" ] && [ -n "${PORT:-}" ] && [ -n "${IPV6:-}" ] || fail 'Invalid backend line'
        case "$PROTO" in
            udp) flag=-u ;;
            tcp) [ "$IGNORE_TCP" = 0 ] || continue; flag=-t ;;
            *) fail "Unknown protocol: $PROTO" ;;
        esac
        if [ -n "$WAN4_IP" ]; then
            backend_exists "$flag" "${WAN4_IP}:${LISTEN_PORT}" "${IPV4}:${PORT}" || fail "$PROTO IPv4 backend missing: $IPV4:$PORT"
        fi
        if [ -n "$WAN6_IP" ]; then
            backend_exists "$flag" "[${WAN6_IP}]:${LISTEN_PORT}" "[${IPV6}]:${PORT}" || fail "$PROTO IPv6 backend missing: $IPV6:$PORT"
        fi
    done < "$BACKENDS"
    log "CHECK OK: IPv4=${WAN4_IP:-disabled} IPv6=${WAN6_IP:-disabled}"
}

if [ "$MODE" = --check ]; then
    check_rules
    exit 0
fi

log "SETUP: IPv4=${WAN4_IP:-disabled} IPv6=${WAN6_IP:-disabled} IGNORE_TCP=$IGNORE_TCP"
[ -d /sys/module/ip_vs ] || fail 'Kernel module ip_vs not loaded'
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

# This project owns the entire host IPVS ruleset. Clearing it interrupts
# existing connections; do not share host IPVS with other applications.
rm -f "$STATE_FILE"
log 'Rebuilding IPVS rules'
ipvsadm -C
ipvsadm --set "$TCP_TIMEOUT" "$TCP_FIN_TIMEOUT" "$UDP_TIMEOUT"

if [ -n "$WAN4_IP" ]; then
    ipvsadm -A -u "${WAN4_IP}:${LISTEN_PORT}" -s lc
    if [ "$IGNORE_TCP" = 0 ]; then
        ipvsadm -A -t "${WAN4_IP}:${LISTEN_PORT}" -s lc
    fi
fi
if [ -n "$WAN6_IP" ]; then
    ipvsadm -A -u "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
    if [ "$IGNORE_TCP" = 0 ]; then
        ipvsadm -A -t "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
    fi
fi

TCP_COUNT=0
UDP_COUNT=0
while read -r PROTO IPV4 PORT IPV6 REST || [ -n "${PROTO:-}" ]; do
    case "${PROTO:-}" in ''|'#'*) continue ;; esac
    [ -n "${IPV4:-}" ] && [ -n "${PORT:-}" ] && [ -n "${IPV6:-}" ] || fail 'Invalid backend line'
    case "$PORT" in ''|*[!0-9]*) fail "Invalid backend port: $PORT" ;; esac
    case "$PROTO" in
        udp)
            if [ -n "$WAN4_IP" ]; then
                ipvsadm -a -u "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
            fi
            if [ -n "$WAN6_IP" ]; then
                ipvsadm -a -u "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
            fi
            UDP_COUNT=$((UDP_COUNT + 1)) ;;
        tcp)
            if [ "$IGNORE_TCP" = 0 ]; then
                if [ -n "$WAN4_IP" ]; then
                    ipvsadm -a -t "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
                fi
                if [ -n "$WAN6_IP" ]; then
                    ipvsadm -a -t "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
                fi
                TCP_COUNT=$((TCP_COUNT + 1))
            fi ;;
        *) fail "Unknown protocol: $PROTO" ;;
    esac
done < "$BACKENDS"
[ "$UDP_COUNT" -gt 0 ] || fail 'No UDP backends configured'
expected_state > "$STATE_FILE"
log "Ready: UDP backends=$UDP_COUNT TCP backends=$TCP_COUNT"
ipvsadm -Ln
ipvsadm -Ln --stats
