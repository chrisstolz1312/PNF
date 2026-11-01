#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# PNF Server Certificate Export
# -----------------------------------------------------------------------------
# Validate the required CA files, stage them in a temporary directory, and
# export them to the shared server export directory.
#
# Note: The existing export directory contents are removed before copying.
# This preserves the original script's behavior; the update is not atomic.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

TMP="/tmp/server-pack"
EXPORT="/server_export"

# Remove temporary files after completion or failure.
cleanup() {
    rm -rf "$TMP"
}

# Report unexpected command failures and preserve the original exit status.
on_error() {
    rc=$?
    echo "[ERROR] SERVER EXPORT: Aborted at line ${BASH_LINENO[0]:-unknown} (exit code: ${rc})." >&2
    cleanup || true
    exit "$rc"
}
trap on_error ERR
trap cleanup EXIT

# Files required for the VPN server certificate export.
FILES=(
    "/ca/pki/ca.crt"
    "/ca/pki/issued/server.crt"
    "/ca/pki/private/server.key"
    "/ca/tls-crypt.key"
    "/ca/dh.pem"
)

# Ensure all source files exist and are readable.
for file in "${FILES[@]}"; do
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        echo "[ERROR] SERVER EXPORT: Missing or unreadable file: $file" >&2
        exit 1
    fi
done

# Prepare a clean staging directory and copy the source files.
rm -rf "$TMP"
mkdir -p "$TMP"
for file in "${FILES[@]}"; do
    cp -- "$file" "$TMP/"
done

# Update the destination only after source validation and staging succeed.
# WARNING: This removes all existing entries in the export directory.
mkdir -p "$EXPORT"
find "$EXPORT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$TMP"/. "$EXPORT"/

# Verify that every expected exported file exists and is non-empty.
for file in "${FILES[@]}"; do
    name="${file##*/}"
    if [[ ! -s "$EXPORT/$name" ]]; then
        echo "[ERROR] SERVER EXPORT: Exported file is missing or empty: $EXPORT/$name" >&2
        exit 1
    fi
done

echo "[SUCCESS] SERVER EXPORT: Exported ${#FILES[@]} files to $EXPORT."
printf 'Files: '
printf '%s ' "${FILES[@]##*/}"
printf '\n'
