#!/bin/bash
set -Eeuo pipefail

TMP="/tmp/server-pack"
EXPORT="/server_export"

cleanup() {
    rm -rf "$TMP"
}

on_error() {
    rc=$?
    echo "SERVER-EXPORT FEHLER: Abbruch bei Zeile ${BASH_LINENO[0]:-unbekannt} (Exit-Code ${rc})." >&2
    cleanup || true
    exit "$rc"
}
trap on_error ERR
trap cleanup EXIT

FILES=(
    "/ca/pki/ca.crt"
    "/ca/pki/issued/server.crt"
    "/ca/pki/private/server.key"
    "/ca/tls-crypt.key"
    "/ca/dh.pem"
)

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        echo "SERVER-EXPORT FEHLER: Datei fehlt oder ist nicht lesbar: $file" >&2
        exit 1
    fi
done

rm -rf "$TMP"
mkdir -p "$TMP"
for file in "${FILES[@]}"; do
    cp -- "$file" "$TMP/"
done

# Ziel erst nach erfolgreicher Prüfung und Vorbereitung aktualisieren.
mkdir -p "$EXPORT"
find "$EXPORT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$TMP"/. "$EXPORT"/

# Verifizieren, dass alle erwarteten Dateien im Export liegen.
for file in "${FILES[@]}"; do
    name="${file##*/}"
    if [[ ! -s "$EXPORT/$name" ]]; then
        echo "SERVER-EXPORT FEHLER: Exportdatei fehlt oder ist leer: $EXPORT/$name" >&2
        exit 1
    fi
done

echo "SERVER-EXPORT ERFOLGREICH: ${#FILES[@]} Dateien nach $EXPORT exportiert."
printf 'Dateien: '
printf '%s ' "${FILES[@]##*/}"
printf '\n'
