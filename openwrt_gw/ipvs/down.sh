#!/usr/bin/env bash

set -euo pipefail

echo
echo "========================================"
echo "Stoppe IPVS"
echo "========================================"

docker compose down
