#!/bin/sh
# PNF IPVS: UDP immer aktiv, TCP optional via IGNORE_TCP.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
IGNORE_TCP="${IGNORE_TCP:-0}"
LISTEN_PORT=1194
TCP_TIMEOUT=300
TCP_FIN_TIMEOUT=30
UDP_TIMEOUT=30

log() { printf '[IPVS] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

case "$IGNORE_TCP" in
  0|1) ;;
  *) fail "IGNORE_TCP muss 0 oder 1 sein (ist: $IGNORE_TCP)" ;;
esac
[ -r /backends.conf ] || fail '/backends.conf fehlt oder ist nicht lesbar'

# UDP-Backends müssen immer vorhanden sein.
awk '$1 == "udp" && NF >= 4 {found=1} END {exit !found}' /backends.conf || fail 'Keine UDP-Backends in /backends.conf'
if [ "$IGNORE_TCP" = 0 ]; then
  awk '$1 == "tcp" && NF >= 4 {found=1} END {exit !found}' /backends.conf || fail 'TCP aktiviert, aber keine TCP-Backends vorhanden'
fi

WAN_IF="$(ip -4 route show default | awk '/^default / {print $5; exit}')"
[ -n "$WAN_IF" ] || fail 'Kein IPv4-Default-Interface gefunden'
WAN4_IP="$(ip -4 -o addr show dev "$WAN_IF" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')"
WAN6_IP="$(ip -6 -o addr show dev "$WAN_IF" scope global | awk '!/temporary|deprecated/ {split($4,a,"/"); print a[1]; exit}')"
[ -n "$WAN4_IP" ] || fail "Keine globale IPv4 auf $WAN_IF"
[ -n "$WAN6_IP" ] || fail "Keine globale IPv6 auf $WAN_IF"

log "WAN=$WAN_IF IPv4=$WAN4_IP IPv6=$WAN6_IP TCP_IGNORIEREN=$IGNORE_TCP"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
[ -d /sys/module/ip_vs ] || fail 'Kernelmodul ip_vs nicht geladen'

# Achtung: Der IPVS-Dienst verwaltet den IPVS-Regelsatz des Hosts exklusiv.
# -C entfernt auch Regeln anderer IPVS-Anwendungen.
log 'Setze IPVS-Regeln neu auf'
ipvsadm -C
ipvsadm --set "$TCP_TIMEOUT" "$TCP_FIN_TIMEOUT" "$UDP_TIMEOUT"

ipvsadm -A -u "${WAN4_IP}:${LISTEN_PORT}" -s lc
ipvsadm -A -u "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
if [ "$IGNORE_TCP" = 0 ]; then
  ipvsadm -A -t "${WAN4_IP}:${LISTEN_PORT}" -s lc
  ipvsadm -A -t "[${WAN6_IP}]:${LISTEN_PORT}" -s lc
else
  log 'TCP über IPVS deaktiviert; UDP bleibt aktiv'
fi

TCP_COUNT=0
UDP_COUNT=0
while read -r PROTO IPV4 PORT IPV6 REST || [ -n "${PROTO:-}" ]; do
  case "${PROTO:-}" in ''|'#'*) continue ;; esac
  [ -n "${IPV4:-}" ] && [ -n "${PORT:-}" ] && [ -n "${IPV6:-}" ] || fail "Ungültige Backend-Zeile: $PROTO ${IPV4:-} ${PORT:-} ${IPV6:-}"
  case "$PORT" in *[!0-9]*|'') fail "Ungültiger Backend-Port: $PORT" ;; esac
  case "$PROTO" in
    udp)
      ipvsadm -a -u "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
      ipvsadm -a -u "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
      UDP_COUNT=$((UDP_COUNT + 1))
      ;;
    tcp)
      if [ "$IGNORE_TCP" = 0 ]; then
        ipvsadm -a -t "${WAN4_IP}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
        ipvsadm -a -t "[${WAN6_IP}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
        TCP_COUNT=$((TCP_COUNT + 1))
      fi
      ;;
    *) fail "Unbekanntes Protokoll: $PROTO" ;;
  esac
done < /backends.conf
[ "$UDP_COUNT" -gt 0 ] || fail 'Keine UDP-Backends eingerichtet'
log "Bereit: UDP-Backends=$UDP_COUNT, TCP-Backends=$TCP_COUNT"
ipvsadm -Ln
ipvsadm -Ln --stats
exec tail -f /dev/null
