#!/usr/bin/env bash

set -euo pipefail

#export DOCKER_BUILDKIT=0

ROOT="$(cd "$(dirname "$0")" && pwd)"

headline() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

headline "OpenVPN Appliance Build"

###############################################################################
# Web CA
###############################################################################

headline "Build: Web CA"

(
    cd "$ROOT/web_ca"
    sudo ./build.sh
)

###############################################################################
# OpenVPN Gateways (TCP + UDP + IPVS)
###############################################################################

headline "Build: OpenVPN Gateways"

(
    cd "$ROOT/openwrt_gw"
    ./build.sh
)

###############################################################################
# DDClient
###############################################################################

if [ -d "$ROOT/ddclient" ]; then

    headline "Build: DDClient"

    (
        cd "$ROOT/ddclient"

        docker compose down >/dev/null 2>&1 || true
        docker compose up -d
    )
fi

###############################################################################
# Status
###############################################################################

headline "Docker Container"

docker ps \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo

headline "Docker Networks"

docker network ls

echo

headline "Build completed"
