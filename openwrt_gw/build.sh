#!/usr/bin/env bash

set -Eeuo pipefail

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
    [[ -f "$CERTDIR/$f" ]] || {
        echo "ERROR: $CERTDIR/$f fehlt."
        exit 1
    }
done

echo "OK: Alle Zertifikate vorhanden."

###############################################################################
# Images vorbereiten
###############################################################################

headline "Erstelle OpenWrt-Image-Links"

SRC="$ROOT/image/$ROOTFS"

# Zentrales OpenWrt-Image prüfen
if [[ ! -s "$SRC" ]]; then
    echo "FEHLER: Zentrales OpenWrt-Image fehlt oder ist leer:"
    echo "$SRC"
    exit 1
fi

echo "Zentrales OpenWrt-Image: OK"
sha256sum "$SRC"

echo

# Alle acht Gateway-Image-Links erzeugen bzw. prüfen
for gw in "${GATEWAYS[@]}"; do

    DST="$ROOT/$gw/image"

    if [[ -L "$DST" ]]; then

        # Existierenden Symlink prüfen
        if [[ "$(readlink "$DST")" != "../image" ]]; then
            echo "FEHLER: Falscher Image-Symlink:"
            echo "$DST -> $(readlink "$DST")"
            exit 1
        fi

    elif [[ -e "$DST" ]]; then

        # Vorhandene reguläre Verzeichnisse nicht löschen
        echo "FEHLER: Image-Pfad existiert bereits und ist kein Symlink:"
        echo "$DST"
        exit 1

    else

        # Neuen Symlink auf das zentrale Image-Verzeichnis erstellen
        ln -s ../image "$DST"

    fi

    # Prüfen, ob das Archiv über den Link erreichbar ist
    if [[ ! -s "$DST/$ROOTFS" ]]; then
        echo "FEHLER: OpenWrt-Image über Link nicht erreichbar:"
        echo "$DST/$ROOTFS"
        exit 1
    fi

    echo "OK: $gw/image -> ../image"

done

echo
echo "Alle acht OpenWrt-Image-Links sind vorhanden."

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
