#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

headline() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

headline "OpenVPN Appliance Shutdown"

###############################################################################
# DDClient
###############################################################################

if [ -d "$ROOT/ddclient" ]; then

    headline "Stop: DDClient"

    (
        cd "$ROOT/ddclient"
        docker compose down >/dev/null 2>&1 || true
    )
fi

###############################################################################
# OpenVPN Gateways (TCP + UDP + IPVS)
###############################################################################

headline "Stop: OpenVPN Gateways"

(
    cd "$ROOT/openwrt_gw"
    ./down.sh
)

###############################################################################
# Web CA
###############################################################################

headline "Stop: Web CA"

(
    cd "$ROOT/web_ca"
    sudo ./down.sh
)

###############################################################################
# Status
###############################################################################

headline "Docker Container"

docker ps \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo

headline "Shutdown completed"
