#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo '[ERROR] Run as root' >&2; exit 1; }
command -v ip6tables >/dev/null || { echo '[ERROR] ip6tables missing' >&2; exit 1; }
command -v systemctl >/dev/null || { echo '[ERROR] systemctl missing' >&2; exit 1; }

install -d -m 0755 /usr/local/sbin
cat > /usr/local/sbin/pnf-nat66.sh <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
SUBNET='fdff:ffff:dc59:1312::/64'
BRIDGE='br-openvpn'
# The Docker bridge need not exist yet for the ip6tables interface exclusion.
if ! ip6tables -t nat -C POSTROUTING -s "$SUBNET" ! -o "$BRIDGE" -j MASQUERADE 2>/dev/null; then
    ip6tables -t nat -A POSTROUTING -s "$SUBNET" ! -o "$BRIDGE" -j MASQUERADE
fi
SCRIPT
chmod 0755 /usr/local/sbin/pnf-nat66.sh

cat > /etc/systemd/system/pnf-nat66.service <<'SERVICE'
[Unit]
Description=PNF IPv6 NAT66 masquerading for OpenWrt Docker network
Requires=docker.service
After=docker.service
PartOf=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pnf-nat66.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target docker.service
SERVICE

systemctl daemon-reload
systemctl enable pnf-nat66.service
systemctl restart pnf-nat66.service
ip6tables -t nat -C POSTROUTING -s fdff:ffff:dc59:1312::/64 ! -o br-openvpn -j MASQUERADE

echo '[OK] NAT66 rule and systemd service configured'
