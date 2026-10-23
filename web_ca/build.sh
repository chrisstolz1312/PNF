#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK=admin_bridge
BRIDGE=br-admin
SUBNET=192.168.255.0/24
GATEWAY=192.168.255.1

echo '==> Netzwerk prüfen...'
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  docker network create \
    --driver bridge \
    --opt "com.docker.network.bridge.name=$BRIDGE" \
    --subnet "$SUBNET" \
    --gateway "$GATEWAY" \
    "$NETWORK"
else
  actual_subnet="$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' "$NETWORK")"
  actual_gateway="$(docker network inspect -f '{{(index .IPAM.Config 0).Gateway}}' "$NETWORK")"
  actual_bridge="$(docker network inspect -f '{{index .Options "com.docker.network.bridge.name"}}' "$NETWORK")"
  if [[ "$actual_subnet" != "$SUBNET" || "$actual_gateway" != "$GATEWAY" || "$actual_bridge" != "$BRIDGE" ]]; then
    echo "[ERROR] Existing $NETWORK has unexpected settings: subnet=$actual_subnet gateway=$actual_gateway bridge=$actual_bridge" >&2
    exit 1
  fi
  echo '==> Netzwerk existiert bereits und ist korrekt konfiguriert.'
fi

mkdir -p "$ROOT/server_export"
# Bestehende CA und private Schlüssel niemals beim Start löschen.

echo '==> Image bauen...'
(cd "$ROOT" && docker compose build)
echo '==> Container starten...'
(cd "$ROOT" && docker compose up -d)

echo '==> Warte auf Container...'
for i in $(seq 1 60); do
  if [[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" == true ]]; then
    break
  fi
  sleep 1
done
[[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" == true ]] || {
  echo '[ERROR] ca-web wurde nicht gestartet.' >&2
  exit 1
}

# Skriptpfad anhand der tatsächlichen Container-Mounts ermitteln.
# Kein stiller Erfolg, wenn eine bestehende CA nicht exportiert werden kann.
if docker exec ca-web test -s /ca/pki/ca.crt; then
  echo '==> Bestehende CA erkannt. Server-Export starten...'
  if docker exec ca-web test -f /scripts/server_export.sh; then
    docker exec ca-web bash /scripts/server_export.sh
  elif docker exec ca-web test -f /app/scripts/server_export.sh; then
    docker exec ca-web bash /app/scripts/server_export.sh
  elif docker exec ca-web test -f /usr/local/bin/server_export.sh; then
    docker exec ca-web bash /usr/local/bin/server_export.sh
  else
    echo '[ERROR] server_export.sh im Container nicht gefunden. Bitte Dockerfile prüfen.' >&2
    exit 1
  fi
  for name in ca.crt server.crt server.key dh.pem tls-crypt.key; do
    [[ -s "$ROOT/server_export/$name" ]] || {
      echo "[ERROR] Exportdatei fehlt oder ist leer: $ROOT/server_export/$name" >&2
      exit 1
    }
  done
  echo '[OK] Server-Export beim Start erfolgreich aktualisiert.'
else
  echo '[INFO] Noch keine CA vorhanden; Export erfolgt nach CA-Erstellung im Webinterface.'
fi

echo '===================================='
echo 'Web CA gestartet: http://<SERVER-IP>:8080'
echo '===================================='
