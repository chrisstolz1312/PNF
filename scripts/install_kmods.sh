cd ~/PNF

cat > scripts/10_install_kmods.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== PNF Kernelmodule ==="

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

cat > /etc/modules-load.d/pnf-sqm.conf <<'MOD'
sch_cake
ifb
act_mirred
cls_u32
sch_ingress
sch_fq_codel
MOD

for conf in \
    /etc/modules-load.d/pnf-ipvs.conf \
    /etc/modules-load.d/pnf-jool.conf \
    /etc/modules-load.d/pnf-nat.conf \
    /etc/modules-load.d/pnf-sqm.conf
do
    tmp=$(mktemp)

    while IFS= read -r module; do
        [[ -z "$module" ]] && continue

        if modprobe "$module" 2>/dev/null; then
            echo "[OK] $module"
            echo "$module" >> "$tmp"

        elif [[ "$module" == jool ||
                "$module" == ip_vs ||
                "$module" == nf_conntrack ]]; then
            rm -f "$tmp"
            echo "[ERROR] Required kernel module missing: $module" >&2
            exit 1

        else
            echo "[WARN] Optional kernel module unavailable: $module"
        fi
    done < "$conf"

    cat "$tmp" > "$conf"
    rm -f "$tmp"
done

echo "[OK] PNF kernel modules configured"
EOF

chmod +x scripts/10_install_kmods.sh
