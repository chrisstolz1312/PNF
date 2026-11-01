#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# PNF Web CA - Client Certificate Revocation
# -----------------------------------------------------------------------------
# Revoke an existing client certificate using EasyRSA, regenerate the
# certificate revocation list (CRL), and publish the validated CRL atomically.
# Existing client profiles, certificates, and private keys are not deleted.
#
# Usage: ./revoke_client.sh CLIENT_NAME
# -----------------------------------------------------------------------------
set -euo pipefail

# Configure the EasyRSA working directory and PKI location.
export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki

CLIENT="${1:-}"

# Require a client name and restrict it to supported common-name characters.
if [[ -z "$CLIENT" ]]; then
    echo "[ERROR] Client name is required." >&2
    exit 1
fi

if [[ ! "$CLIENT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "[ERROR] Invalid client name." >&2
    exit 1
fi

cd /ca

# Confirm that the client certificate exists before attempting revocation.
if [[ ! -f "/ca/pki/issued/${CLIENT}.crt" ]]; then
    echo "[ERROR] Certificate for '${CLIENT}' was not found." >&2
    exit 1
fi

# Revoke the certificate without deleting any associated client files.
EASYRSA_BATCH=1 ./easyrsa revoke "$CLIENT"

# Regenerate the CRL to include the revoked certificate.
EASYRSA_BATCH=1 ./easyrsa gen-crl

CRL_SOURCE="/ca/pki/crl.pem"
CRL_TARGET_DIR="/crl"
CRL_TARGET="${CRL_TARGET_DIR}/crl.pem"

# Do not publish an absent or empty CRL.
if [[ ! -s "$CRL_SOURCE" ]]; then
    echo "[ERROR] CRL was not generated." >&2
    exit 1
fi

mkdir -p "$CRL_TARGET_DIR"

# Create a temporary file on the target filesystem for atomic replacement.
CRL_TEMP="$(mktemp "${CRL_TARGET_DIR}/.crl.pem.XXXXXX")"
trap 'rm -f "$CRL_TEMP"' EXIT

cp "$CRL_SOURCE" "$CRL_TEMP"
chmod 644 "$CRL_TEMP"

# Validate the CRL format before making it available to other components.
openssl crl -in "$CRL_TEMP" -noout >/dev/null

# Atomically replace the published CRL with the validated version.
mv -f "$CRL_TEMP" "$CRL_TARGET"

trap - EXIT

# Remove generated OpenVPN profiles after successful CRL publication.
CLIENT_OVPN_DIR="/ca/clients/${CLIENT}/ovpn"

if [[ -d "$CLIENT_OVPN_DIR" && ! -L "$CLIENT_OVPN_DIR" ]]; then
    rm -rf -- "$CLIENT_OVPN_DIR"
    echo "[SUCCESS] Client OpenVPN profiles removed: ${CLIENT_OVPN_DIR}"
elif [[ -L "$CLIENT_OVPN_DIR" ]]; then
    echo "[ERROR] Refusing to remove a symbolic link: ${CLIENT_OVPN_DIR}" >&2
    exit 1
else
    echo "[INFO] No OpenVPN profiles found for: ${CLIENT}"
fi

echo "[SUCCESS] CRL updated: ${CRL_TARGET}"
echo "[SUCCESS] Client revoked: ${CLIENT}"

exit 0
