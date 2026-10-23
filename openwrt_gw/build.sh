#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CERTDIR="$ROOT/../web_ca/server_export"
ROOTFS="openwrt-x86-64-generic-rootfs.tar.gz"

GATEWAYS=(
    ovpn_gw1_tcp
    ovpn_gw2_tcp
    ovpn_gw3_tcp
    ovpn_gw4_tcp

    ovpn_gw1_udp
    ovpn_gw2_udp
    ovpn_gw3_udp
    ovpn_gw4_udp
)

REQUIRED=(
    ca.crt
    dh.pem
    server.crt
    server.key
    tls-crypt.key
)

###############################################################################
# Funktionen
###############################################################################

headline() {
    echo
    echo "========================================"
    echo "$1"
    echo "========================================"
}

###############################################################################
# Zertifikate prüfen
###############################################################################

headline "Prüfe OpenVPN-Zertifikate"

for f in "${REQUIRED[@]}"; do
    [ -f "$CERTDIR/$f" ] || {
        echo "ERROR: $CERTDIR/$f fehlt."
        exit 1
    }
done

echo "OK: Alle Zertifikate vorhanden."
###############################################################################
# Images vorbereiten
###############################################################################

headline "Bereite Images vor"

for gw in "${GATEWAYS[@]}"; do

    SRC="$ROOT/image/$ROOTFS"
    DSTDIR="$ROOT/$gw/image"
    DST="$DSTDIR/$ROOTFS"

    [ -L "$DSTDIR" ] && rm "$DSTDIR"

    mkdir -p "$DSTDIR"
    rm -f "$DST"

    if ! ln "$SRC" "$DST" 2>/dev/null; then
        cp "$SRC" "$DST"
    fi

done

###############################################################################
# Images bauen
###############################################################################

headline "Baue OpenWrt Gateways"

for gw in "${GATEWAYS[@]}"; do

    echo
    echo "----------------------------------------"
    echo "$gw"
    echo "----------------------------------------"

    (
        cd "$ROOT/$gw"
        docker compose build
    )

done

###############################################################################
# Gateways starten
###############################################################################

headline "Starte OpenWrt Gateways"

for gw in "${GATEWAYS[@]}"; do

    echo
    echo "----------------------------------------"
    echo "$gw"
    echo "----------------------------------------"

    (
        cd "$ROOT/$gw"
        docker compose up -d
    )

done

###############################################################################
# Unbound
###############################################################################

headline "Starte Unbound"

(
    cd "$ROOT/unbound"
    docker compose up -d
)

###############################################################################
# IPVS
###############################################################################

headline "Starte IPVS"

(
    cd "$ROOT/ipvs"
    ./build.sh
)

###############################################################################
# Fertig
###############################################################################

headline "Fertig"

echo "Alle OpenVPN-Gateways, Unbound und IPVS wurden erfolgreich gebaut und gestartet."
