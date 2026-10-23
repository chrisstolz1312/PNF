#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
STATE="$ROOT/state.conf"
BACKENDS="$ROOT/backends.conf"
headline() { printf '\n========================================\n%s\n========================================\n' "$1"; }
# IPVS-only: no mode switch; fail if an obsolete state would disable TCP.
if [[ -f "$STATE" ]] && grep -Eq '^IGNORE_TCP=(1|true|TRUE|yes|YES)[[:space:]]*$' "$STATE"; then
  echo '[ERROR] state.conf disables TCP. PNF v0.7 requires IGNORE_TCP=0.' >&2
  exit 1
fi
IGNORE_TCP=0
headline 'Erzeuge IPVS-Backendliste'
tmp="$(mktemp "$ROOT/.backends.XXXXXXXX")"
trap 'rm -f "$tmp"' EXIT
mapfile -t gateways < <(docker ps --format '{{.Names}}' | grep '^openwrt_gw[1-4]_\(tcp\|udp\)$' | sort || true)
for C in "${gateways[@]}"; do
  ENV="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$C")"
  PROTO="$(printf '%s\n' "$ENV" | sed -n 's/^IPVS_PROT=//p' | head -n 1)"
  PORT="$(printf '%s\n' "$ENV" | sed -n 's/^IPVS_PORT=//p' | head -n 1)"
  IPV4="$(printf '%s\n' "$ENV" | sed -n 's/^IPVS_IPV4=//p' | head -n 1)"
  IPV6="$(printf '%s\n' "$ENV" | sed -n 's/^IPVS_IPV6=//p' | head -n 1)"
  case "$PROTO" in tcp|udp) ;; *) continue ;; esac
  [ -n "$PORT" ] && [ -n "$IPV4" ] && [ -n "$IPV6" ] || continue
  printf '%s %s %s %s\n' "$PROTO" "$IPV4" "$PORT" "$IPV6" >> "$tmp"
done
[ -s "$tmp" ] || { echo 'ERROR: Keine OpenVPN-Backends gefunden.' >&2; exit 1; }
if ! grep -q '^udp ' "$tmp"; then
  echo 'ERROR: Keine UDP-Backends vorhanden.' >&2; exit 1
fi
if ! grep -q '^tcp ' "$tmp"; then
  echo 'ERROR: Keine TCP-Backends vorhanden.' >&2; exit 1
fi
mv -f "$tmp" "$BACKENDS"
cat "$BACKENDS"
headline "Baue IPVS (IGNORE_TCP=$IGNORE_TCP)"
docker compose build
headline 'Starte IPVS'
# Existing ipvs.sh clears/recreates its rules on startup.
docker compose down >/dev/null 2>&1 || true
IGNORE_TCP="$IGNORE_TCP" docker compose up -d
headline 'IPVS bereit'
