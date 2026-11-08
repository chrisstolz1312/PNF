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

    if [[ "$actual_subnet" != "$SUBNET" ||
          "$actual_gateway" != "$GATEWAY" ||
          "$actual_bridge" != "$BRIDGE" ]]; then
        echo "[ERROR] Existing $NETWORK has unexpected settings." >&2
        exit 1
    fi

    echo '[OK] Docker-Netzwerk korrekt konfiguriert.'
fi

# Bestehende CA und private Schlüssel niemals löschen.
mkdir -p "$ROOT/server_export"

echo '==> Docker-Image bauen...'
(cd "$ROOT" && docker compose build)

echo '==> Container starten...'
(cd "$ROOT" && docker compose up -d)

echo '==> Warte auf systemd...'

READY=0

for i in $(seq 1 60); do
    if docker exec ca-web systemctl is-system-running --wait \
        >/dev/null 2>&1; then
        READY=1
        break
    fi

    # A degraded systemd state is acceptable if required
    # application services are running.
    if docker exec ca-web systemctl is-active --quiet \
        nginx.service pnf-fcgiwrap.service pnf-crl.timer \
        >/dev/null 2>&1; then
        READY=1
        break
    fi

    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo '[ERROR] systemd oder erforderliche Dienste nicht bereit.' >&2

    docker logs ca-web --tail 100 || true
    docker exec ca-web systemctl --failed --no-pager || true

    exit 1
fi

echo '[OK] systemd gestartet.'

echo '==> Dienste prüfen...'

for unit in nginx.service pnf-fcgiwrap.service pnf-crl.timer; do
    if docker exec ca-web systemctl is-active --quiet "$unit"; then
        echo "[OK] $unit"
    else
        echo "[ERROR] $unit ist nicht aktiv." >&2
        docker exec ca-web systemctl status "$unit" --no-pager || true
        exit 1
    fi
done

# Existing CA: preserve the previous export behavior.
if docker exec ca-web test -s /ca/pki/ca.crt; then
    echo '==> Bestehende CA erkannt. Server-Export starten...'

    docker exec ca-web bash /scripts/server_export.sh

    for name in ca.crt server.crt server.key dh.pem tls-crypt.key; do
        if [[ ! -s "$ROOT/server_export/$name" ]]; then
            echo "[ERROR] Exportdatei fehlt: $name" >&2
            exit 1
        fi
    done

    echo '[OK] Server-Export erfolgreich.'
else
    echo '[INFO] Noch keine CA vorhanden.'
    echo '[INFO] CA-Erstellung erfolgt über das Webinterface.'
fi

echo
echo '===================================='
echo 'PNF Web CA – Debian 13'
echo '===================================='
echo 'Webinterface: http://<SERVER-IP>:8080'
echo 'CRL-Erneuerung: täglich um 00:00 Uhr'
echo '===================================='
echo

docker exec ca-web systemctl list-timers pnf-crl.timer --no-pager
