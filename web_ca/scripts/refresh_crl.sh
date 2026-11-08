#!/usr/bin/env bash
set -Eeuo pipefail

export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki

CRL_SOURCE="/ca/pki/crl.pem"
CRL_TARGET_DIR="/crl"
CRL_TARGET="${CRL_TARGET_DIR}/crl.pem"

# Existing CA required.
if [[ ! -s /ca/pki/ca.crt ]]; then
    echo "[ERROR] CA not initialized." >&2
    exit 1
fi

cd /ca

# Regenerate CRL using EasyRSA.
EASYRSA_BATCH=1 ./easyrsa gen-crl

# Validate generated CRL.
if [[ ! -s "$CRL_SOURCE" ]]; then
    echo "[ERROR] CRL was not generated." >&2
    exit 1
fi

mkdir -p "$CRL_TARGET_DIR"

# Atomic publication.
CRL_TEMP="$(mktemp "${CRL_TARGET_DIR}/.crl.pem.XXXXXX")"
trap 'rm -f "$CRL_TEMP"' EXIT

cp "$CRL_SOURCE" "$CRL_TEMP"
chmod 644 "$CRL_TEMP"

openssl crl -in "$CRL_TEMP" -noout >/dev/null

mv -f "$CRL_TEMP" "$CRL_TARGET"

trap - EXIT

echo "[SUCCESS] CRL refreshed: $CRL_TARGET"
