#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo '[ERROR] Run as root' >&2; exit 1; }

mkdir -p /etc/modules-load.d

# Mandatory for the PNF stack.
mandatory=(ip_vs nf_conntrack jool)
# Optional: some kernels have these built in or omit individual helpers.
optional=(ip_vs_lc ip_vs_rr ip_vs_wrr nf_nat nf_tables nft_chain_nat nft_masq ip6_tables ip6table_nat ip_tables xt_nat xt_MASQUERADE sch_cake ifb act_mirred cls_u32 sch_ingress sch_fq_codel)

# Load mandatory modules first. Never silently continue if one is missing.
for module in "${mandatory[@]}"; do
    modprobe "$module" || { echo "[ERROR] Required module unavailable: $module" >&2; exit 1; }
done

# Use one authoritative configuration, removing obsolete split files from prior PNF installs.
conf=/etc/modules-load.d/pnf-kmods.conf
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "${mandatory[@]}" > "$tmp"
for module in "${optional[@]}"; do
    if modprobe "$module" 2>/dev/null; then
        printf '%s\n' "$module" >> "$tmp"
        echo "[OK] $module"
    else
        echo "[WARN] Optional module unavailable: $module" >&2
    fi
done
install -m 0644 "$tmp" "$conf"
# Prevent old PNF configurations from trying to load unavailable modules.
rm -f /etc/modules-load.d/pnf-ipvs.conf \
      /etc/modules-load.d/pnf-jool.conf \
      /etc/modules-load.d/pnf-nat.conf \
      /etc/modules-load.d/pnf-sqm.conf \
      /etc/modules-load.d/pnf-nat66.conf

echo '[OK] PNF kernel modules configured and persisted'
