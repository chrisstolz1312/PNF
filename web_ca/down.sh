#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "==> Stoppe Web-CA..."

cd "$ROOT"

docker compose down

echo
echo "===================================="
echo "Web-CA wurde gestoppt."
echo "===================================="

echo
echo "==> Export-Verzeichnis leeren..."

rm -f "$ROOT/server_export"/*
