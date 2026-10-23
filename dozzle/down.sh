#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo '==> Dozzle stoppen...'
docker compose down

echo '[OK] Dozzle gestoppt.'
