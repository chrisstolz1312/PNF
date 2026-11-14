#!/bin/sh
# PNF IPVS: feste Container-VIPs, UDP immer aktiv, TCP optional.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
IGNORE_TCP="${IGNORE_TCP:-0}"
IPVS_IPV4="${IPVS_IPV4:-172.31.255.2}"
IPVS_IPV6="${IPVS_IPV6:-fdff:ffff:dc59:1312::2}"
LISTEN_PORT=1194
TCP_TIMEOUT=300
TCP_FIN_TIMEOUT=30
UDP_TIMEOUT=30

log() { printf '[IPVS] %s\n' "$*"; }
fail() { log "ERROR: $*" >&2; exit 1; }

case "$IGNORE_TCP" in 0|1) ;; *) fail "IGNORE_TCP muss 0 oder 1 sein (ist: $IGNORE_TCP)" ;; esac
[ -r /backends.conf ] || fail '/backends.conf fehlt oder ist nicht lesbar'
awk '$1 == "udp" && NF >= 4 {found=1} END {exit !found}' /backends.conf || fail 'Keine UDP-Backends in /backends.conf'
if [ "$IGNORE_TCP" = 0 ]; then
  awk '$1 == "tcp" && NF >= 4 {found=1} END {exit !found}' /backends.conf || fail 'TCP aktiviert, aber keine TCP-Backends vorhanden'
fi

# Keine WAN-Erkennung: feste IPv4-/IPv6-Adressen aus docker-compose.yml.
ip -4 -o addr show | grep -F "inet ${IPVS_IPV4}/" >/dev/null || fail "IPv4 $IPVS_IPV4 ist nicht im Container konfiguriert"
ip -6 -o addr show | grep -F "inet6 ${IPVS_IPV6}/" >/dev/null || fail "IPv6 $IPVS_IPV6 ist nicht im Container konfiguriert"
log "VIP IPv4=$IPVS_IPV4 IPv6=$IPVS_IPV6 IGNORE_TCP=$IGNORE_TCP"
[ -d /sys/module/ip_vs ] || fail 'Kernelmodul ip_vs nicht geladen'
sysctl -w net.ipv4.ip_forward=1 >/dev/null
sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null

# Im Bridge-Modus betrifft -C den IPVS-Regelsatz dieses Netzwerk-Namespace.
log 'Setze IPVS-Regeln neu auf'
ipvsadm -C
ipvsadm --set "$TCP_TIMEOUT" "$TCP_FIN_TIMEOUT" "$UDP_TIMEOUT"
ipvsadm -A -u "${IPVS_IPV4}:${LISTEN_PORT}" -s lc
ipvsadm -A -u "[${IPVS_IPV6}]:${LISTEN_PORT}" -s lc
if [ "$IGNORE_TCP" = 0 ]; then
  ipvsadm -A -t "${IPVS_IPV4}:${LISTEN_PORT}" -s lc
  ipvsadm -A -t "[${IPVS_IPV6}]:${LISTEN_PORT}" -s lc
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
      ipvsadm -a -u "${IPVS_IPV4}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
      ipvsadm -a -u "[${IPVS_IPV6}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
      UDP_COUNT=$((UDP_COUNT + 1))
      ;;
    tcp)
      if [ "$IGNORE_TCP" = 0 ]; then
        ipvsadm -a -t "${IPVS_IPV4}:${LISTEN_PORT}" -r "${IPV4}:${PORT}" -m
        ipvsadm -a -t "[${IPVS_IPV6}]:${LISTEN_PORT}" -r "[${IPV6}]:${PORT}" -m
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
