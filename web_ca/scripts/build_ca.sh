#!/bin/bash
set -Eeuo pipefail

CA_DIR="/ca"
CONFIG_FILE="$CA_DIR/config/ca.env"
EASYRSA_SRC="/usr/share/easy-rsa"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/server_export.sh"

log() { echo "[ INFO ] $1"; }
ok() { echo "[  OK  ] $1"; }
fail() { echo "[ERROR ] $1" >&2; exit 1; }

echo
printf '%s\n' '--------------------------------------------------' ' OpenVPN Certificate Authority Setup' '--------------------------------------------------'
echo

log "Checking CA state"
if [[ -f "$CA_DIR/pki/ca.crt" ]]; then
    ok "Certificate Authority already initialized"
    exit 0
fi

[[ -f "$CONFIG_FILE" ]] || fail "Missing configuration: $CONFIG_FILE"
[[ -f "$EXPORT_SCRIPT" ]] || fail "Missing server export script: $EXPORT_SCRIPT"

# shellcheck disable=SC1090
source "$CONFIG_FILE"
ok "Configuration loaded"

log "Preparing EasyRSA workspace"
mkdir -p "$CA_DIR"
cp -r "$EASYRSA_SRC"/* "$CA_DIR/"
cd "$CA_DIR"
ok "Workspace ready"

log "Writing CA configuration"
cat > vars <<VARS
set_var EASYRSA_REQ_COUNTRY "$CA_COUNTRY"
set_var EASYRSA_REQ_PROVINCE "$CA_PROVINCE"
set_var EASYRSA_REQ_CITY "$CA_CITY"
set_var EASYRSA_REQ_ORG "$CA_ORG"
set_var EASYRSA_REQ_EMAIL "$CA_EMAIL"
set_var EASYRSA_REQ_OU "$CA_OU"

set_var EASYRSA_ALGO "$CA_ALGO"
set_var EASYRSA_DIGEST "$CA_DIGEST"
VARS

export EASYRSA="$CA_DIR"
export EASYRSA_PKI="$CA_DIR/pki"
ok "Configuration written"

log "Initializing PKI"
EASYRSA_BATCH=1 ./easyrsa init-pki >/dev/null 2>&1
ok "PKI initialized"

log "Generating Certificate Authority"
EASYRSA_BATCH=1 ./easyrsa --req-cn="$CA_CN" build-ca nopass >/dev/null 2>&1
ok "CA certificate created"

log "Generating OpenVPN server certificate"
EASYRSA_BATCH=1 ./easyrsa build-server-full server nopass >/dev/null 2>&1
ok "Server certificate created"

log "Generating tls-crypt key"
openvpn --genkey secret "$CA_DIR/tls-crypt.key" >/dev/null 2>&1
ok "tls-crypt key created"

echo
log "Generating Diffie-Hellman parameters"
log "This can take several minutes"
# No pipeline: openssl failure must not be hidden by fold.
openssl dhparam -out "$CA_DIR/dh.pem" "${CA_DH_SIZE:-2048}" 2>&1
ok "DH parameters created"

mkdir -p "$CA_DIR/clients"

log "Automatically exporting OpenVPN server files"
if bash "$EXPORT_SCRIPT"; then
    ok "Server export completed"
else
    fail "CA created, but automatic server export failed. Use Server-Export in the web UI to retry."
fi

echo
printf '%s\n' '--------------------------------------------------' ' CA READY (server files exported)' '--------------------------------------------------'
echo
