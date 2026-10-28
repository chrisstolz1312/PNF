#!/bin/bash
set -euo pipefail

export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki

CLIENT="${1:-}"

if [[ -z "$CLIENT" ]]; then
    echo "ERROR: Clientname fehlt." >&2
    exit 1
fi

# Allow only simple client common names.
if [[ ! "$CLIENT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: Ungültiger Clientname." >&2
    exit 1
fi

cd /ca

if [[ ! -f "/ca/pki/issued/${CLIENT}.crt" ]]; then
    echo "ERROR: Zertifikat für '${CLIENT}' nicht gefunden." >&2
    exit 1
fi

# Revoke certificate.
# Do not delete client profile, certificate, private key, or other files.
EASYRSA_BATCH=1 ./easyrsa revoke "$CLIENT"

# Generate updated CRL.
EASYRSA_BATCH=1 ./easyrsa gen-crl

# Publish CRL atomically to shared directory.
CRL_SOURCE="/ca/pki/crl.pem"
CRL_TARGET_DIR="/crl"
CRL_TARGET="${CRL_TARGET_DIR}/crl.pem"

if [[ ! -s "$CRL_SOURCE" ]]; then
    echo "ERROR: CRL wurde nicht generiert." >&2
    exit 1
fi

mkdir -p "$CRL_TARGET_DIR"

# Temporary file in the same filesystem for atomic rename.
CRL_TEMP="$(mktemp "${CRL_TARGET_DIR}/.crl.pem.XXXXXX")"
trap 'rm -f "$CRL_TEMP"' EXIT

cp "$CRL_SOURCE" "$CRL_TEMP"
chmod 644 "$CRL_TEMP"

# Verify the generated CRL before publishing.
openssl crl -in "$CRL_TEMP" -noout >/dev/null

mv -f "$CRL_TEMP" "$CRL_TARGET"

trap - EXIT

echo "CRL UPDATED: ${CRL_TARGET}"
echo "CLIENT REVOKED: ${CLIENT}"

exit 0
