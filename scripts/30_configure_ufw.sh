#!/usr/bin/env bash
set -Eeuo pipefail

echo "[INFO] Configuring UFW for PNF"

# Host-Verkehr unverändert erlauben
ufw default allow incoming
ufw default allow outgoing
ufw default allow routed

# Container dürfen keine Host-Dienste erreichen
ufw deny in on br-openvpn

# Firewall aktivieren
ufw --force enable

echo "[OK] PNF host isolation configured"
ufw status verbose
