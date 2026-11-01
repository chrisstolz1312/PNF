#!/usr/bin/env bash
# Generate an OpenVPN client profile using the Web CA credentials.
# Existing client certificates and private keys are reused when available.
set -euo pipefail

export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki
# Load server connection settings used in the generated profile.
CONFIG_FILE="/ca/config/ca.env"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: Configuration file is missing: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

CLIENT=""
MODE="tcp"

usage() {
  echo "Usage: $0 --name CLIENT --mode tcp|udp|connect"
}

while (($#)); do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      CLIENT="$2"
      shift 2
      ;;
    --mode)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CLIENT" || ! "$CLIENT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: A valid client name must be provided with --name." >&2
  exit 2
fi

# Select transport-specific OpenVPN settings.
case "$MODE" in
  tcp)
    PROTO_LINE="proto tcp-client"
    TUN_MTU=1500
    MSSFIX=1400
    ;;
  udp)
    PROTO_LINE="proto udp"
    TUN_MTU=1280
    MSSFIX=1200
    ;;
  connect)
    PROTO_LINE=""
    TUN_MTU=1280
    MSSFIX=1200
    ;;
  *)
    echo "ERROR: Mode must be tcp, udp, or connect." >&2
    exit 2
    ;;
esac

# Resolve the client certificate, key, and output profile paths.
cd /ca

CERT="/ca/pki/issued/$CLIENT.crt"
KEY="/ca/pki/private/$CLIENT.key"
PROFILE_DIR="/ca/clients/$CLIENT/ovpn"
PROFILE="$PROFILE_DIR/${MODE}_${CLIENT}.ovpn"

# Reuse existing client credentials; create them only if both files are absent.
if [[ -f "$CERT" && -f "$KEY" ]]; then
  echo "INFO: Reusing existing certificate: $CLIENT"
elif [[ ! -e "$CERT" && ! -e "$KEY" ]]; then
  EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT" nopass
else
  echo "ERROR: Certificate and private key are incomplete. Check their state." >&2
  exit 1
fi

# Verify that all files needed for an embedded-credential profile are readable.
for f in "$CERT" "$KEY" /ca/pki/ca.crt /ca/tls-crypt.key; do
  [[ -r "$f" ]] || { echo "ERROR: Required file is missing: $f" >&2; exit 1; }
done

# Write the OpenVPN profile with embedded CA, client certificate, key,
# and tls-crypt material. Preserve the original protocol and tunnel settings.
mkdir -p "$PROFILE_DIR"

{
  cat <<EOF
client
dev tun1312
EOF

  [[ -z "$PROTO_LINE" ]] || printf '%s\n' "$PROTO_LINE"

  cat <<EOF
remote ${SERVER_HOST} ${SERVER_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
tun-mtu ${TUN_MTU}
mssfix ${MSSFIX}
cipher CHACHA20-POLY1305
verb 3

<ca>
$(cat /ca/pki/ca.crt)
</ca>

<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$p' "$CERT")
</cert>

<key>
$(cat "$KEY")
</key>

<tls-crypt>
$(cat /ca/tls-crypt.key)
</tls-crypt>
EOF
} > "$PROFILE"

# Preserve the original profile permissions (0644).
chmod 0644 "$PROFILE"

echo "READY: $PROFILE (mode=$MODE, tun-mtu=$TUN_MTU, mssfix=$MSSFIX)"
