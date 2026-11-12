#!/bin/sh

# Wait until both VPN interfaces are ready
ip -4 addr show dev tun0 2>/dev/null | grep -Fq '172.31.254.1/25' || exit 0
ip -4 addr show dev tun1 2>/dev/null | grep -Fq '172.31.254.129/25' || exit 0

# Check DNS on both VPN addresses
if ! nslookup openwrt.org 172.31.254.1 >/dev/null 2>&1 ||
   ! nslookup openwrt.org 172.31.254.129 >/dev/null 2>&1; then

    logger -t vpn-dns-check "DNS check failed, restarting dnsmasq"
    /etc/init.d/dnsmasq restart
fi
