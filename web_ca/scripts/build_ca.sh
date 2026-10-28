#!/bin/bash
set -Eeuo pipefail

CA_DIR="/ca"
CONFIG_FILE="$CA_DIR/config/ca.env"
EASYRSA_SRC="/usr/share/easy-rsa"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_SCRIPT="$SCRIPT_DIR/server_export.sh"

log() {
    echo "[ INFO ] $1"
}

ok() {
    echo "[  OK  ] $1"
}

fail() {
    echo "[ERROR ] $1" >&2
    exit 1
}

# --------------------------------------------------
# Generate and publish CRL
# --------------------------------------------------

generate_crl() {
    log "Generating certificate revocation list"

    cd "$CA_DIR"

    EASYRSA_BATCH=1 ./easyrsa gen-crl \
        || fail "CRL generation failed"

    [[ -s "$CA_DIR/pki/crl.pem" ]] \
        || fail "Generated CRL is missing or empty"

    log "Publishing CRL"

    mkdir -p /crl

    local tmp_crl
    tmp_crl="$(mktemp /crl/.crl.pem.XXXXXX)" \
        || fail "Cannot create temporary CRL file"

    cp "$CA_DIR/pki/crl.pem" "$tmp_crl" \
        || fail "Cannot copy CRL"

    chmod 644 "$tmp_crl" \
        || fail "Cannot set CRL permissions"

    openssl crl -in "$tmp_crl" -noout \
        || fail "Generated CRL is invalid"

    mv -f "$tmp_crl" /crl/crl.pem \
        || fail "Cannot publish CRL"

    ok "CRL published to /crl/crl.pem"
}

# --------------------------------------------------
# Start
# --------------------------------------------------

echo
echo "--------------------------------------------------"
echo " OpenVPN Certificate Authority Setup"
echo "--------------------------------------------------"
echo

log "Checking CA state"

# --------------------------------------------------
# Existing CA
# --------------------------------------------------

if [[ -f "$CA_DIR/pki/ca.crt" ]]; then
    ok "Certificate Authority already initialized"

    generate_crl

    echo
    echo "--------------------------------------------------"
    echo " CA READY (existing CA, CRL updated)"
    echo "--------------------------------------------------"
    echo

    exit 0
fi

# --------------------------------------------------
# Check requirements
# --------------------------------------------------

[[ -f "$CONFIG_FILE" ]] \
    || fail "Configuration file not found: $CONFIG_FILE"

[[ -f "$EXPORT_SCRIPT" ]] \
    || fail "Server export script not found: $EXPORT_SCRIPT"

source "$CONFIG_FILE"

ok "Configuration loaded"

# --------------------------------------------------
# Prepare EasyRSA workspace
# --------------------------------------------------

log "Preparing EasyRSA workspace"

mkdir -p "$CA_DIR"

cp -r "$EASYRSA_SRC"/* "$CA_DIR/"

cd "$CA_DIR"

ok "Workspace ready"

# --------------------------------------------------
# Write EasyRSA configuration
# --------------------------------------------------

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

ok "Configuration written"

# --------------------------------------------------
# Set EasyRSA environment
# --------------------------------------------------

export EASYRSA="$CA_DIR"
export EASYRSA_PKI="$CA_DIR/pki"

# --------------------------------------------------
# Initialize PKI
# --------------------------------------------------

log "Initializing PKI"

EASYRSA_BATCH=1 ./easyrsa init-pki \
    >/dev/null 2>&1 \
    || fail "PKI initialization failed"

ok "PKI initialized"

# --------------------------------------------------
# Generate Certificate Authority
# --------------------------------------------------

log "Generating Certificate Authority"

EASYRSA_BATCH=1 ./easyrsa \
    --req-cn="$CA_CN" \
    build-ca nopass \
    >/dev/null 2>&1 \
    || fail "CA generation failed"

ok "CA certificate created"

# --------------------------------------------------
# Generate server certificate
# --------------------------------------------------

log "Generating OpenVPN server certificate"

EASYRSA_BATCH=1 ./easyrsa \
    build-server-full server nopass \
    >/dev/null 2>&1 \
    || fail "Server certificate generation failed"

ok "Server certificate created"

# --------------------------------------------------
# Generate initial CRL
# --------------------------------------------------

generate_crl

# --------------------------------------------------
# Generate tls-crypt key
# --------------------------------------------------

log "Generating tls-crypt key"

openvpn --genkey secret "$CA_DIR/tls-crypt.key" \
    >/dev/null 2>&1 \
    || fail "tls-crypt key generation failed"

ok "tls-crypt key created"

# --------------------------------------------------
# Generate Diffie-Hellman parameters
# --------------------------------------------------

log "Generating Diffie-Hellman parameters"
log "This can take several minutes"

openssl dhparam \
    -out "$CA_DIR/dh.pem" \
    "${CA_DH_SIZE:-2048}" \
    || fail "DH parameter generation failed"

ok "DH parameters created"

# --------------------------------------------------
# Prepare client directory
# --------------------------------------------------

mkdir -p "$CA_DIR/clients"

# --------------------------------------------------
# Export server files
# --------------------------------------------------

log "Automatically exporting OpenVPN server files"

bash "$EXPORT_SCRIPT" \
    || fail "Server export failed"

ok "Server export completed"

# --------------------------------------------------
# Finished
# --------------------------------------------------

echo
echo "--------------------------------------------------"
echo " CA READY (server files and CRL exported)"
echo "--------------------------------------------------"
echo
