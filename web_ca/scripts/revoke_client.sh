
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

# Revoke the certificate and regenerate the CRL.
# Do not delete the client profile, certificate, private key, or other files.
EASYRSA_BATCH=1 ./easyrsa revoke "$CLIENT"
EASYRSA_BATCH=1 ./easyrsa gen-crl

echo "CLIENT REVOKED: ${CLIENT}"
exit 0
