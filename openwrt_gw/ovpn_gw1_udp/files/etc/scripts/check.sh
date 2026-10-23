#!/bin/sh

#
# Enable colors only when running in a terminal
#
if [ -t 1 ]; then
    GREEN="$(printf '\033[1;32m')"
    RED="$(printf '\033[1;31m')"
    BLUE="$(printf '\033[1;34m')"
    NC="$(printf '\033[0m')"
else
    GREEN=""
    RED=""
    BLUE=""
    NC=""
fi

ok() {
    printf "%b[ OK ]%b %s\n" "$GREEN" "$NC" "$1"
}

fail() {
    printf "%b[FAIL]%b %s\n" "$RED" "$NC" "$1"
}

info() {
    printf "%b==>%b %s\n" "$BLUE" "$NC" "$1"
}

echo
echo "========================================="
echo "   OpenWrt Gateway Connectivity Check"
echo "========================================="
echo

#
# IPv4
#
info "IPv4 Address"
ip -4 addr show eth0 | awk '/inet / {print "  "$2}'
echo

#
# IPv6
#
info "IPv6 Address"
ip -6 addr show eth0 | awk '/scope global/ {print "  "$2}'
echo

#
# Default Routes
#
info "Default Routes"

echo "IPv4:"
ip -4 route | grep default || echo "  none"

echo
echo "IPv6:"
ip -6 route | grep default || echo "  none"
echo

#
# Gateway Tests
#
info "Ping IPv4 Gateway"

if ping -c2 -W2 172.31.255.1 >/dev/null 2>&1; then
    ok "IPv4 Gateway reachable"
else
    fail "IPv4 Gateway unreachable"
fi

info "Ping IPv6 Gateway"

if ping6 -c2 -W2 fdff:ffff:dc59:1312::1 >/dev/null 2>&1; then
    ok "IPv6 Gateway reachable"
else
    fail "IPv6 Gateway unreachable"
fi

echo

#
# DNS
#
info "DNS"

if nslookup google.de >/dev/null 2>&1; then
    ok "DNS resolves google.de"
else
    fail "DNS resolution failed"
fi

echo

#
# Internet IPv4
#
info "Internet IPv4"

if ping -c2 -W2 google.de >/dev/null 2>&1; then
    ok "IPv4 Internet reachable"
else
    fail "IPv4 Internet unreachable"
fi

#
# Internet IPv6
#
info "Internet IPv6"

if ping6 -c2 -W2 google.de >/dev/null 2>&1; then
    ok "IPv6 Internet reachable"
else
    fail "IPv6 Internet unreachable"
fi

echo

#
# Interface Status
#
info "OpenWrt Interface Status"

echo
echo "--- WAN ---"
ifstatus wan 2>/dev/null || true

echo
echo "--- WAN6 ---"
ifstatus wan6 2>/dev/null || true

echo
echo "--- VPN ---"
ifstatus vpn 2>/dev/null || true

echo
echo "========================================="
echo "            Check finished"
echo "========================================="
