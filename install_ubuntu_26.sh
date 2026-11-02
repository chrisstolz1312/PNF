#!/usr/bin/env bash
# PNF installer for Ubuntu Server 26.04
# Installs host dependencies, starts the Web CA, validates its export,
# then deploys OpenWrt gateways, Unbound, IPVS and the Dozzle dashboard.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run with sudo: sudo ./install.sh' >&2; exit 1; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/pnf-install.log

# Preserve terminal colors while writing an ANSI-free log file.
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C_RESET=$'\033[0m'; C_CYAN=$'\033[1;36m'; C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_BOLD=$'\033[1m'
else
    C_RESET=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''
fi
exec > >(tee >(sed -u $'s/\033\\[[0-9;]*[[:alpha:]]//g' >> "$LOG")) 2>&1

STEP=0
stage() {
    ((STEP += 1))
    printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_CYAN" "$C_RESET"
    printf '%s  [%02d] %s%s\n' "$C_CYAN" "$STEP" "$1" "$C_RESET"
    printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_CYAN" "$C_RESET"
}
info() { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
on_error() { local rc=$?; printf '%s[ERROR]%s Line %s: %s (exit code %s)\n' "$C_RED" "$C_RESET" "$1" "$2" "$rc" >&2; }
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

source /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 26.04 ]] || fail 'Requires Ubuntu Server 26.04'
command -v apt-get >/dev/null
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

printf '\n%s%sPNF INSTALLER · Ubuntu Server 26.04%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
info "Installation directory: $ROOT"
info "Log file: $LOG"

stage 'Update system'
# Restore the system clock from the hardware clock after a VM snapshot rollback.
hwclock --hctosys --utc
apt-get update
apt-get -y full-upgrade
if [[ -f /var/run/reboot-required ]] || {
    [[ -e /boot/vmlinuz ]] &&
    [[ "$(readlink -f /boot/vmlinuz)" != "/boot/vmlinuz-$(uname -r)" ]]
}; then
    warn 'Reboot required. Run sudo ./install.sh again after reboot.'
    exit 20
fi
ok 'System update completed'

stage 'Enable Ubuntu Universe'
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update
ok 'Ubuntu Universe enabled'

stage 'Install dependencies'
apt-get install -y \
    ca-certificates curl git jq tar gzip unzip tree \
    build-essential dkms "linux-headers-$(uname -r)" \
    ipvsadm iproute2 iptables nftables conntrack kmod \
    openvpn openssl jool-dkms jool-tools \
    docker.io docker-compose-v2
ok 'Dependencies installed'

# Configure persistent module loading and filter unavailable optional modules.
stage 'Verify Docker and host'
systemctl enable --now docker
docker info >/dev/null
docker compose version
ipvsadm -Ln >/dev/null
modinfo jool >/dev/null
if [[ ! -c /dev/net/tun ]]; then
    modprobe tun
    mkdir -p /dev/net
    [[ -c /dev/net/tun ]] || mknod /dev/net/tun c 10 200
fi
# Docker group membership becomes effective after the user logs in again.
if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
    groupadd -f docker
    usermod -aG docker "$SUDO_USER"
    ok "Docker group configured for $SUDO_USER (login required for membership to take effect)"
fi
ok 'Host verification completed'

# ============================================================
# PNF Host-Setup: required scripts, executed in filename order
# ============================================================
stage 'Configure PNF kernel modules and NAT66'
POST_INSTALL_DIR="$ROOT/scripts"
[[ -d "$POST_INSTALL_DIR" ]] || fail "Missing scripts directory: $POST_INSTALL_DIR"
for required_script in 10_install_kmods.sh 20_configure_nat66.sh; do
    [[ -f "$POST_INSTALL_DIR/$required_script" ]] || \
        fail "Missing required script: $POST_INSTALL_DIR/$required_script"
done

scripts=()
while IFS= read -r -d '' script; do
    scripts+=("$script")
done < <(find "$POST_INSTALL_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)

for script in "${scripts[@]}"; do
    info "Running host setup: $(basename "$script")"
    if bash "$script"; then
        ok "$(basename "$script") completed"
    else
        fail "Host setup failed: $(basename "$script")"
    fi
done
ok 'PNF host setup completed'


stage 'Start Web CA'
WEB_CA_DIR="$ROOT/web_ca"
[[ -f "$WEB_CA_DIR/build.sh" ]] || fail "Missing: $WEB_CA_DIR/build.sh"
if [[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" != true ]]; then
    # Guard against older build scripts that remove existing CA export files.
    if grep -Eq '^[[:space:]]*rm[[:space:]]+-f[[:space:]]+.*server_export' "$WEB_CA_DIR/build.sh" \
        && [[ -d "$WEB_CA_DIR/server_export" ]] \
        && find "$WEB_CA_DIR/server_export" -maxdepth 1 -type f -print -quit | grep -q .; then
        fail 'web_ca/build.sh would delete existing server export files.'
    fi
    (cd "$WEB_CA_DIR" && bash ./build.sh)
fi
[[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" == true ]] || \
    fail 'Web CA container ca-web is not running.'
(cd "$WEB_CA_DIR" && docker compose ps)
ok 'Web CA started: http://<SERVER-IP>:8080'

# Wait for an interactive CA export and validate the certificate/key pair.
stage 'Validate CA export'
EXPORT="$WEB_CA_DIR/server_export"
info 'Create the CA in the web interface; the server export will then be validated.'
[[ -t 0 ]] || fail 'An interactive terminal is required to configure the CA.'
while :; do
    missing=()
    for f in ca.crt server.crt server.key dh.pem tls-crypt.key; do
        [[ -s "$EXPORT/$f" ]] || missing+=("$f")
    done
    if (( ${#missing[@]} == 0 )); then
        if openssl x509 -in "$EXPORT/ca.crt" -noout -checkend 0 >/dev/null 2>&1 && \
       openssl x509 -in "$EXPORT/server.crt" -noout -checkend 0 >/dev/null 2>&1 && \
       openssl pkey -in "$EXPORT/server.key" -noout >/dev/null 2>&1 && \
       [[ "$(openssl x509 -in "$EXPORT/server.crt" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)" == \
                    "$(openssl pkey -in "$EXPORT/server.key" -pubout -outform DER | sha256sum | cut -d' ' -f1)" ]]; then
            ok 'CA export complete; certificates and keys validated'
            break
        fi
        warn 'Export exists, but certificates or keys are invalid or do not match.'
    else
        info "Still missing: ${missing[*]}"
    fi
    read -r -p 'CA created and server exported? CA login [port 8080]: [Enter = check, q = quit]: ' answer
    [[ $answer != q && $answer != Q ]] || { info 'Setup interrupted. The CA remains running.'; exit 0; }
done

stage 'Configure IPVS-only mode'
PNF_CONFIG="$ROOT/config/pnf.conf"
IPVS_DIR="$ROOT/openwrt_gw/ipvs"
[[ -d "$IPVS_DIR" ]] || fail 'IPVS directory is missing.'
mkdir -p "$ROOT/config"
if [[ -f "$PNF_CONFIG" ]]; then
    cp -a "$PNF_CONFIG" "$PNF_CONFIG.bak-ipvs-only"
fi
printf 'PNF_CONFIG_VERSION=1\nTCP_BALANCER=ipvs\nUDP_BALANCER=ipvs\n' > "$PNF_CONFIG"
printf '# Managed by PNF installer. IPVS handles TCP and UDP.\nIGNORE_TCP=0\n' > "$IPVS_DIR/state.conf"
ok 'TCP=IPVS, UDP=IPVS; IGNORE_TCP=0'

stage 'Install OpenWrt / Unbound / IPVS'
OPENWRT_DIR="$ROOT/openwrt_gw"
[[ -f "$OPENWRT_DIR/build.sh" ]] || fail 'OpenWrt build.sh is missing.'
[[ -s "$OPENWRT_DIR/image/openwrt-x86-64-generic-rootfs.tar.gz" ]] || \
    fail 'OpenWrt RootFS is missing.'
(cd "$OPENWRT_DIR" && bash ./build.sh)
ok 'OpenWrt / Unbound / IPVS installation completed'

stage 'Start Dozzle dashboard'
DOZZLE_DIR="$ROOT/dozzle"
[[ -f "$DOZZLE_DIR/docker-compose.yml" ]] || fail 'Dozzle docker-compose.yml is missing.'
if [[ -f "$DOZZLE_DIR/build.sh" ]]; then
    (cd "$DOZZLE_DIR" && bash ./build.sh)
else
    info 'No Dozzle build.sh found; starting with Docker Compose.'
    (cd "$DOZZLE_DIR" && docker compose pull && docker compose up -d)
fi
(cd "$DOZZLE_DIR" && docker compose ps)
ok 'Dozzle started: http://<SERVER-IP>:8081'

# ddclient operates independently of the VPN stack; preserve user configuration.
stage 'Start ddclient (DynDNS)'
DDCLIENT_DIR="$ROOT/ddclient"
if [[ -f "$DDCLIENT_DIR/docker-compose.yml" ]]; then
    if [[ -f "$DDCLIENT_DIR/build.sh" ]]; then
        (cd "$DDCLIENT_DIR" && bash ./build.sh)
    else
        (cd "$DDCLIENT_DIR" && docker compose up -d)
    fi
    (cd "$DDCLIENT_DIR" && docker compose ps)
    ok 'ddclient container started (configuration unchanged)'
    info 'DynDNS updates require enabled credentials.'
else
    warn 'ddclient/docker-compose.yml is missing; skipping optional module.'
fi

printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_GREEN" "$C_RESET"
printf '%s  PNF INSTALLATION COMPLETED%s\n' "$C_GREEN" "$C_RESET"
printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_GREEN" "$C_RESET"
info "Log file: $LOG"
