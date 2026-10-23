#!/usr/bin/env bash
# PNF installer for Ubuntu Server 26.04
# Installs host dependencies, starts the Web CA, validates its export,
# then deploys OpenWrt gateways, Unbound, IPVS and the Dozzle dashboard.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run with sudo: sudo ./install.sh' >&2; exit 1; }
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG=/var/log/pnf-install.log

# Keep the terminal colourful while storing a plain-text log.
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
on_error() { local rc=$?; printf '%s[ERROR]%s Zeile %s: %s (Exit %s)\n' "$C_RED" "$C_RESET" "$1" "$2" "$rc" >&2; }
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

source /etc/os-release
[[ ${ID:-} == ubuntu && ${VERSION_ID:-} == 26.04 ]] || fail 'Requires Ubuntu Server 26.04'
command -v apt-get >/dev/null
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

printf '\n%s%sPNF INSTALLER · Ubuntu Server 26.04%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
info "Installationsverzeichnis: $ROOT"
info "Protokoll: $LOG"

stage 'System aktualisieren'
# A restored VM snapshot can leave the system clock behind the RTC.
hwclock --hctosys --utc
apt-get update
apt-get -y full-upgrade
if [[ -f /var/run/reboot-required ]] || {
  [[ -e /boot/vmlinuz ]] &&
  [[ "$(readlink -f /boot/vmlinuz)" != "/boot/vmlinuz-$(uname -r)" ]]
}; then
  warn 'Neustart erforderlich. Danach sudo ./install.sh erneut ausführen.'
  exit 20
fi
ok 'Systemaktualisierung abgeschlossen'

stage 'Ubuntu Universe aktivieren'
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update
ok 'Universe aktiviert'

stage 'Abhängigkeiten installieren'
apt-get install -y \
  ca-certificates curl git jq tar gzip unzip tree \
  build-essential dkms "linux-headers-$(uname -r)" \
  ipvsadm iproute2 iptables nftables conntrack kmod \
  openvpn openssl jool-dkms jool-tools \
  docker.io docker-compose-v2
ok 'Pakete installiert'

stage 'Kernelmodule konfigurieren'
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/pnf-ipvs.conf <<'MOD'
ip_vs
ip_vs_lc
ip_vs_rr
ip_vs_wrr
nf_conntrack
MOD
cat > /etc/modules-load.d/pnf-jool.conf <<'MOD'
jool
MOD
cat > /etc/modules-load.d/pnf-nat.conf <<'MOD'
nf_nat
nf_conntrack
nf_tables
nft_chain_nat
nft_masq
ip6_tables
ip6table_nat
ip_tables
xt_nat
xt_MASQUERADE
MOD

# Retain only loadable modules; the three essential modules must exist.
for conf in /etc/modules-load.d/pnf-*.conf; do
  tmp=$(mktemp)
  while IFS= read -r module; do
    [[ -z $module ]] && continue
    if modprobe "$module" 2>/dev/null; then
      echo "$module" >> "$tmp"
    elif [[ $module == jool || $module == ip_vs || $module == nf_conntrack ]]; then
      rm -f "$tmp"
      fail "Erforderliches Kernelmodul fehlt: $module"
    else
      warn "Optionales Kernelmodul nicht verfügbar: $module"
    fi
  done < "$conf"
  cat "$tmp" > "$conf"
  rm -f "$tmp"
done
ok 'Kernelmodule geprüft'

stage 'Docker und Host prüfen'
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
# Docker group membership takes effect at the next login.
if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
  groupadd -f docker
  usermod -aG docker "$SUDO_USER"
  ok "Docker-Gruppe für $SUDO_USER eingerichtet (Neuanmeldung erforderlich)"
fi
ok 'Hostprüfung erfolgreich'

stage 'Web CA starten'
WEB_CA_DIR="$ROOT/web_ca"
[[ -f "$WEB_CA_DIR/build.sh" ]] || fail "Fehlt: $WEB_CA_DIR/build.sh"
if [[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" != true ]]; then
  # Protect existing exports from an old, destructive build script.
  if grep -Eq '^[[:space:]]*rm[[:space:]]+-f[[:space:]]+.*server_export' "$WEB_CA_DIR/build.sh" \
    && [[ -d "$WEB_CA_DIR/server_export" ]] \
    && find "$WEB_CA_DIR/server_export" -maxdepth 1 -type f -print -quit | grep -q .; then
    fail 'web_ca/build.sh würde vorhandene Server-Exportdateien löschen.'
  fi
  (cd "$WEB_CA_DIR" && bash ./build.sh)
fi
[[ "$(docker inspect -f '{{.State.Running}}' ca-web 2>/dev/null || true)" == true ]] || \
  fail 'Web-CA-Container ca-web läuft nicht.'
(cd "$WEB_CA_DIR" && docker compose ps)
ok 'Web CA gestartet: http://<SERVER-IP>:8080'

stage 'CA-Export prüfen'
EXPORT="$WEB_CA_DIR/server_export"
info 'CA im Webinterface erstellen; der Server-Export wird anschließend geprüft.'
[[ -t 0 ]] || fail 'Für die CA-Einrichtung wird ein interaktives Terminal benötigt.'
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
      ok 'CA-Export vollständig; Zertifikate und Schlüssel geprüft'
      break
    fi
    warn 'Export vorhanden, aber Zertifikate/Schlüssel sind ungültig oder passen nicht zusammen.'
  else
    info "Noch fehlend: ${missing[*]}"
  fi
  read -r -p 'CA erstellt und Server exportiert? [Enter = prüfen, q = beenden]: ' answer
  [[ $answer != q && $answer != Q ]] || { info 'Einrichtung unterbrochen. CA bleibt gestartet.'; exit 0; }
done

stage 'IPVS-only konfigurieren'
PNF_CONFIG="$ROOT/config/pnf.conf"
IPVS_DIR="$ROOT/openwrt_gw/ipvs"
[[ -d "$IPVS_DIR" ]] || fail 'IPVS-Verzeichnis fehlt.'
mkdir -p "$ROOT/config"
if [[ -f "$PNF_CONFIG" ]]; then
  cp -a "$PNF_CONFIG" "$PNF_CONFIG.bak-ipvs-only"
fi
printf 'PNF_CONFIG_VERSION=1\nTCP_BALANCER=ipvs\nUDP_BALANCER=ipvs\n' > "$PNF_CONFIG"
printf '# Managed by PNF installer. IPVS handles TCP and UDP.\nIGNORE_TCP=0\n' > "$IPVS_DIR/state.conf"
ok 'TCP=IPVS, UDP=IPVS; IGNORE_TCP=0'

stage 'OpenWrt / Unbound / IPVS installieren'
OPENWRT_DIR="$ROOT/openwrt_gw"
[[ -f "$OPENWRT_DIR/build.sh" ]] || fail 'OpenWrt build.sh fehlt.'
[[ -s "$OPENWRT_DIR/image/openwrt-x86-64-generic-rootfs.tar.gz" ]] || \
  fail 'OpenWrt RootFS fehlt.'
(cd "$OPENWRT_DIR" && bash ./build.sh)
ok 'OpenWrt / Unbound / IPVS abgeschlossen'

stage 'Dozzle-Dashboard starten'
DOZZLE_DIR="$ROOT/dozzle"
[[ -f "$DOZZLE_DIR/docker-compose.yml" ]] || fail 'Dozzle docker-compose.yml fehlt.'
if [[ -f "$DOZZLE_DIR/build.sh" ]]; then
  (cd "$DOZZLE_DIR" && bash ./build.sh)
else
  info 'Kein Dozzle build.sh vorhanden; starte über Docker Compose.'
  (cd "$DOZZLE_DIR" && docker compose pull && docker compose up -d)
fi
(cd "$DOZZLE_DIR" && docker compose ps)
ok 'Dozzle gestartet: http://<SERVER-IP>:8081'

# ddclient is independent of the VPN stack. Keep user configuration untouched.
stage 'ddclient (DynDNS) starten'
DDCLIENT_DIR="$ROOT/ddclient"
if [[ -f "$DDCLIENT_DIR/docker-compose.yml" ]]; then
  if [[ -f "$DDCLIENT_DIR/build.sh" ]]; then
    (cd "$DDCLIENT_DIR" && bash ./build.sh)
  else
    (cd "$DDCLIENT_DIR" && docker compose up -d)
  fi
  (cd "$DDCLIENT_DIR" && docker compose ps)
  ok 'ddclient-Container gestartet (Konfiguration bleibt unverändert)'
  info 'Ohne aktivierte DynDNS-Zugangsdaten erfolgt keine erfolgreiche Aktualisierung.'
else
  warn 'ddclient/docker-compose.yml fehlt – optionales Modul übersprungen.'
fi

printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_GREEN" "$C_RESET"
printf '%s  PNF INSTALLATION ABGESCHLOSSEN%s\n' "$C_GREEN" "$C_RESET"
printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$C_GREEN" "$C_RESET"
info "Protokoll: $LOG"
