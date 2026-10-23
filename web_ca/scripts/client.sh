#!/bin/bash
set -euo pipefail

export EASYRSA=/ca
export EASYRSA_PKI=/ca/pki
CONFIG_FILE="/ca/config/ca.env"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "ERROR: Konfiguration fehlt: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

CLIENT=""
MODE="tcp"

usage() {
  echo "Verwendung: $0 --name CLIENT --mode tcp|udp|connect"
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
      echo "ERROR: Unbekannter Parameter: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CLIENT" || ! "$CLIENT" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: Gültiger Clientname über --name erforderlich." >&2
  exit 2
fi

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
    echo "ERROR: Modus muss tcp, udp oder connect sein." >&2
    exit 2
    ;;
esac

cd /ca

CERT="/ca/pki/issued/$CLIENT.crt"
KEY="/ca/pki/private/$CLIENT.key"
PROFILE_DIR="/ca/clients/$CLIENT/ovpn"
PROFILE="$PROFILE_DIR/${MODE}_${CLIENT}.ovpn"

# Vorhandene Zugangsdaten wiederverwenden.
if [[ -f "$CERT" && -f "$KEY" ]]; then
  echo "INFO: Vorhandenes Zertifikat wird wiederverwendet: $CLIENT"
elif [[ ! -e "$CERT" && ! -e "$KEY" ]]; then
  EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT" nopass
else
  echo "ERROR: Zertifikat und Schlüssel sind unvollständig. Bitte Zustand prüfen." >&2
  exit 1
fi

for f in "$CERT" "$KEY" /ca/pki/ca.crt /ca/tls-crypt.key; do
  [[ -r "$f" ]] || { echo "ERROR: Datei fehlt: $f" >&2; exit 1; }
done

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

chmod 0644 "$PROFILE"

echo "READY: $PROFILE (mode=$MODE, tun-mtu=$TUN_MTU, mssfix=$MSSFIX)"
