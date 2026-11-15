#!/bin/sh
# PNF IPVS: UDP immer aktiv, TCP optional via IGNORE_TCP.
# --setup: IPVS vollstaendig konfigurieren; --check: Ist-Zustand pruefen.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
IGNORE_TCP="${IGNORE_TCP:-0}"
LISTEN_PORT=1194
TCP_TIMEOUT=300
TCP_FIN_TIMEOUT=30
UDP_TIMEOUT=30
STATE_FILE=/run/pnf-ipvs.state
BACKENDS=/backends.conf

log() { printf '[IPVS] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

case "${1:---setup}" in --setup|--check) MODE="${1:---setup}" ;; *) fail 'Aufruf: /ipvs.sh --setup|--check' ;; esac
case "$IGNORE_TCP" in 0|1) ;; *) fail "IGNORE_TCP muss 0 oder 1 sein (ist: $IGNORE_TCP)" ;; esac
[ -r "$BACKENDS" ] || fail "$BACKENDS fehlt oder ist nicht lesbar"
awk '$1 == "udp" && NF >= 4 {found=1} END {exit !found}' "$BACKENDS" || fail 'Keine UDP-Backends vorhanden'
if [ "$IGNORE_TCP" = 0 ]; then
  awk '$1 == "tcp" && NF >= 4 {found=1} END {exit !found}' "$BACKENDS" || fail 'TCP aktiviert, aber keine TCP-Backends vorhanden'
fi

# Gleiche Adresserkennung fuer Setup und Check.
# WAN-Interface automatisch erkennen
WAN_IF="$(ip -4 route show default | awk '/^default / {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
[ -n "$WAN_IF" ] || fail 'Kein IPv4-Default-Interface gefunden'

# Konfiguration einlesen
IPVS_IPV4=""
IPVS_IPV6=""

if [ -r /ipvs.conf ]; then
    . /ipvs.conf
fi

# IPv4: statisch bevorzugen, sonst automatisch ermitteln
if [ -n "$IPVS_IPV4" ]; then
    if ip -4 -o addr show | awk '{split($4,a,"/"); print a[1]}' | grep -Fxq "$IPVS_IPV4"; then
        WAN4_IP="$IPVS_IPV4"
        log "IPv4 statisch: $WAN4_IP"
    else
        log "WARNUNG: Statische IPv4 $IPVS_IPV4 nicht am Host vorhanden"
        WAN4_IP=""
    fi
else
    WAN4_IP=""
fi

if [ -z "$WAN4_IP" ]; then
    WAN4_IP="$(ip -4 -o addr show dev "$WAN_IF" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')"
    log "IPv4 automatisch: $WAN4_IP"
fi

# IPv6: statisch bevorzugen, sonst automatisch ermitteln
if [ -n "$IPVS_IPV6" ]; then
    if ip -6 -o addr show | awk '{split($4,a,"/"); print a[1]}' | grep -Fxq "$IPVS_IPV6"; then
        WAN6_IP="$IPVS_IPV6"
        log "IPv6 statisch: $WAN6_IP"
    else
        log "WARNUNG: Statische IPv6 $IPVS_IPV6 nicht am Host vorhanden"
        WAN6_IP=""
    fi
else
    WAN6_IP=""
fi

if [ -z "$WAN6_IP" ]; then
    WAN6_IP="$(ip -6 -o addr show dev "$WAN_IF" scope global |
        awk '!/temporary|deprecated|tentative|dadfailed/ {split($4,a,"/"); print a[1]; exit}')"
    log "IPv6 automatisch: $WAN6_IP"
fi

[ -n "$WAN4_IP" ] || fail "Keine IPv4-Adresse verfügbar"
[ -n "$WAN6_IP" ] || fail "Keine IPv6-Adresse verfügbar"

# Ein IPVS-Service oder Backend wird anhand der ipvsadm-Save-Ausgabe geprueft.
# grep -F sucht die genauen Argumentteile, ohne IPv6 als Regex zu interpretieren.
RULES=''
service_exists() {
  printf '%s\n' "$RULES" | grep -F -- "-A $1 $2 -s lc" >/dev/null
}
backend_exists() {
  printf '%s\n' "$RULES" | grep -F -- "-a $1 $2 -r $3 -m" >/dev/null
}

check_rules() {
  [ -r "$STATE_FILE" ] || fail 'Keine erfolgreiche IPVS-Initialisierung dokumentiert'
  expected_state="$(printf '%s\n' "$WAN_IF" "$WAN4_IP" "$WAN6_IP" "$IGNORE_TCP"; cat "$BACKENDS")"
  saved_state="$(cat "$STATE_FILE")"
  [ "$expected_state" = "$saved_state" ] || fail 'WAN-Adresse, TCP-Modus oder Backend-Konfiguration geaendert'
  RULES="$(ipvsadm -Sn)" || fail 'IPVS-Regeln nicht lesbar'

  service_exists -u "${WAN4_IP}:${LISTEN_PORT}" || fail 'UDP IPv4 Service fehlt'
  service_exists -u "[${WAN6_IP}]:${LISTEN_PORT}" || fail 'UDP IPv6 Service fehlt'
  if [ "$IGNORE_TCP" = 0 ]; then
    service_exists -t "${WAN4_IP}:${LISTEN_PORT}" || fail 'TCP IPv4 Service fehlt'
    service_exists -t "[${WAN6_IP}]:${LISTEN_PORT}" || fail 'TCP IPv6 Service fehlt'
  fi

  while read -r PROTO IPV4 PORT IPV6 REST || [ -n "${PROTO:-}" ]; do
    case "${PROTO:-}" in ''|'#'*) continue ;; esac
    [ -n "${IPV4:-}" ] && [ -n "${PORT:-}" ] && [ -n "${IPV6:-}" ] || fail 'Ungueltige Backend-Zeile'
    case "$PROTO" in
      udp) flag=-u ;;
      tcp) [ "$IGNORE_TCP" = 0 ] || continue; flag=-t ;;
      *) fail "Unbekanntes Protokoll: $PROTO" ;;
    esac
    backend_exists "$flag" "${WAN4_IP}:${LISTEN_PORT}" "${IPV4}:${PORT}" || fail "$PROTO IPv4 Backend fehlt: $IPV4"
    backend_exists "$flag" "[${WAN6_IP}]:${LISTEN_PORT}" "[${IPV6}]:${PORT}" || fail "$PROTO IPv6 Backend fehlt: $IPV6"
  done < "$BACKENDS"
  log "CHECK OK: $WAN_IF IPv4=$WAN4_IP IPv6=$WAN6_IP"
}

if [ "$MODE" = --check ]; then
  check_rules
  exit 0
fi

log "SETUP: WAN=$WAN_IF IPv4=$WAN4_IP IPv6=$WAN6_IP IGNORE_TCP=$IGNORE_TCP"
[ -d /sys/module/ip_vs ] || fail 'Kernelmodul ip_vs nicht geladen'
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

# Exklusiver IPVS-Host-Regelsatz: -C loescht alle IPv4/IPv6-IPVS-Regeln.
# Bei Fehlern keine veraltete Erfolgsmeldung behalten.
rm -f "$STATE_FILE"
log 'Setze IPVS-Regeln neu auf'
ipvsadm -C
ipvsadm --set "$TCP_TIMEOUT" "$TCP_FIN_TIMEOUT" "$UDP_TIMEOUT"
ipvsadm -A -u "${WAN4_IP}:${LISTEN_PORT}" -s lc
ipvsadm -A -u "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
if [ "$IGNORE_TCP" = 0 ]; then
  ipvsadm -A -t "${WAN4_IP}:${LISTEN_PORT}" -s lc
  ipvsadm -A -t "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
else
  log 'TCP ueber IPVS deaktiviert; UDP bleibt aktiv'
fi

TCP_COUNT=0
UDP_COUNT=0
while read -r PROTO IPV4 PORT IPV6 REST || [ -n "${PROTO:-}" ]; do
  case "${PROTO:-}" in ''|'#'*) continue ;; esac
  [ -n "${IPV4:-}" ] && [ -n "${PORT:-}" ] && [ -n "${IPV6:-}" ] || fail 'Ungueltige Backend-Zeile'
  case "$PORT" in ''|*[!0-9]*) fail "Ungueltiger Backend-Port: $PORT" ;; esac
  case "$PROTO" in
    udp)
      ipvsadm -a -u "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
      ipvsadm -a -u "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
      UDP_COUNT=$((UDP_COUNT + 1)) ;;
    tcp)
      if [ "$IGNORE_TCP" = 0 ]; then
        ipvsadm -a -t "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
        ipvsadm -a -t "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
        TCP_COUNT=$((TCP_COUNT + 1))
      fi ;;
    *) fail "Unbekanntes Protokoll: $PROTO" ;;
  esac
done < "$BACKENDS"
[ "$UDP_COUNT" -gt 0 ] || fail 'Keine UDP-Backends eingerichtet'
(printf '%s\n' "$WAN_IF" "$WAN4_IP" "$WAN6_IP" "$IGNORE_TCP"; cat "$BACKENDS") > "$STATE_FILE"
log "Bereit: UDP-Backends=$UDP_COUNT TCP-Backends=$TCP_COUNT"
ipvsadm -Ln
ipvsadm -Ln --stats
exit 0
