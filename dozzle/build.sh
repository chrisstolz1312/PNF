#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo '==> Dozzle-Image aktualisieren...'
docker compose pull

echo '==> Dozzle starten...'
docker compose up -d

echo '==> Containerstatus:'
docker compose ps

echo '[OK] Dozzle: http://<SERVER-IP>:8081'
