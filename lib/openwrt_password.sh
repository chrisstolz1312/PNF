#!/usr/bin/env bash
# Sourced by PNF installers. Never print the password or its hash.
set -euo pipefail
PNF_PASSWORD_FILE="$ROOT/config/secrets/openwrt-root.hash"

if [[ -s "$PNF_PASSWORD_FILE" ]]; then
    printf '[INFO] Existing OpenWrt root password configuration found.\n'
    while :; do
        read -r -p 'Keep existing password? [Y/n]: ' keep_answer </dev/tty
        case "$keep_answer" in
            ''|[Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) break ;;
            *) printf 'Please answer y or n.\n' ;;
        esac
    done
fi

[[ -r /dev/tty && -w /dev/tty ]] || { echo 'Interactive terminal required for OpenWrt root password.' >&2; return 1; }
command -v openssl >/dev/null || { echo 'openssl is required.' >&2; return 1; }
pnf_password='' pnf_confirm='' pnf_hash=''
while :; do
    IFS= read -r -s -p 'New OpenWrt root password (all 8 gateways): ' pnf_password </dev/tty
    printf '\n' >/dev/tty
    if (( ${#pnf_password} < 12 )); then
        echo 'Password must contain at least 12 characters.' >&2
        continue
    fi
    IFS= read -r -s -p 'Confirm OpenWrt root password: ' pnf_confirm </dev/tty
    printf '\n' >/dev/tty
    if [[ "$pnf_password" != "$pnf_confirm" ]]; then
        echo 'Passwords do not match.' >&2
        continue
    fi
    break
done
# -stdin avoids exposing the password in process arguments.
pnf_hash="$(printf '%s\n' "$pnf_password" | openssl passwd -6 -stdin)"
unset pnf_password pnf_confirm
[[ "$pnf_hash" == '$6$'* ]] || { echo 'SHA-512 password hashing failed.' >&2; return 1; }
( umask 077
  mkdir -p "$ROOT/config/secrets"
  chmod 700 "$ROOT/config/secrets"
  tmp="$(mktemp "$ROOT/config/secrets/.openwrt-root.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' "$pnf_hash" > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$PNF_PASSWORD_FILE"
)
unset pnf_hash
printf '[OK] OpenWrt root password configured.\n'
