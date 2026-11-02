cd ~/PNF

cat > install_pnf_nat66.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SUBNET="fdff:ffff:dc59:1312::/64"
BRIDGE="br-openvpn"

echo "=== PNF Debian 13 NAT66 Setup ==="

# Benötigte Kernelmodule dauerhaft laden.
cat > /etc/modules-load.d/pnf-nat66.conf <<'MODULES'
nf_conntrack
nf_nat
nf_tables
nft_nat
nft_masq
ip6table_nat
xt_MASQUERADE
MODULES

echo "[INFO] Lade NAT66-Kernelmodule ..."

while read -r module; do
    modprobe "$module"
done < /etc/modules-load.d/pnf-nat66.conf

# NAT66-Regel als separates Boot-Skript.
cat > /usr/local/sbin/pnf-nat66.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

SUBNET="fdff:ffff:dc59:1312::/64"
BRIDGE="br-openvpn"

# NAT66-Regel idempotent einrichten.
if ! ip6tables -t nat -C POSTROUTING \
    -s "$SUBNET" ! -o "$BRIDGE" \
    -j MASQUERADE 2>/dev/null; then

    ip6tables -t nat -A POSTROUTING \
        -s "$SUBNET" ! -o "$BRIDGE" \
        -j MASQUERADE
fi

echo "[OK] PNF NAT66 aktiv"
SCRIPT

chmod 755 /usr/local/sbin/pnf-nat66.sh

# systemd-Dienst.
cat > /etc/systemd/system/pnf-nat66.service <<'SERVICE'
[Unit]
Description=PNF Docker IPv6 NAT66 Masquerading
Requires=docker.service
After=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pnf-nat66.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now pnf-nat66.service

echo
echo "=== NAT66 STATUS ==="
systemctl --no-pager --full status pnf-nat66.service
ip6tables -t nat -S POSTROUTING

echo
echo "[OK] PNF NAT66 Setup abgeschlossen."
EOF

chmod +x install_pnf_nat66.sh
