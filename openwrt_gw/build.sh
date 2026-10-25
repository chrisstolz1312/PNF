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

headline "Verteile OpenWrt-Image auf alle Gateways"

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

# Für jedes Gateway einen echten image/-Ordner anlegen und Rootfs kopieren.
for gw in "${GATEWAYS[@]}"; do
    DSTDIR="$ROOT/$gw/image"
    DST="$DSTDIR/$ROOTFS"

    if [[ ! -d "$ROOT/$gw" ]]; then
        echo "FEHLER: Gateway-Verzeichnis fehlt: $ROOT/$gw"
        exit 1
    fi

    # Alten Verzeichnis-Symlink entfernen (nicht sein Ziel!).
    if [[ -L "$DSTDIR" ]]; then
        rm -- "$DSTDIR"
        echo "ALTER SYMLINK ENTFERNT: $gw/image"
    elif [[ -e "$DSTDIR" && ! -d "$DSTDIR" ]]; then
        echo "FEHLER: Image-Pfad ist kein Verzeichnis: $DSTDIR"
        exit 1
    fi

    mkdir -p -- "$DSTDIR"

    # Eine vorhandene Archiv-Symlink-Datei niemals überschreiben:
    # sonst könnte das zentrale Image verändert werden.
    if [[ -L "$DST" ]]; then
        rm -- "$DST"
    elif [[ -e "$DST" && ! -f "$DST" ]]; then
        echo "FEHLER: Image-Ziel ist keine reguläre Datei: $DST"
        exit 1
    fi

    # Nur bei fehlender oder abweichender Datei neu kopieren.
    if [[ ! -f "$DST" ]] || ! cmp -s -- "$SRC" "$DST"; then
        cp -- "$SRC" "$DST"
        echo "KOPIERT: $gw/image/$ROOTFS"
    else
        echo "BEREITS AKTUELL: $gw/image/$ROOTFS"
    fi

    if [[ ! -s "$DST" || -L "$DST" ]] || ! cmp -s -- "$SRC" "$DST"; then
        echo "FEHLER: OpenWrt-Image konnte nicht korrekt kopiert werden: $DST"
        exit 1
    fi
done

echo
echo "Alle acht OpenWrt-Images liegen als reguläre Dateien vor."

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
