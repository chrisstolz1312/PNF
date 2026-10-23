#!/bin/bash
set -euo pipefail

PKI="/ca/pki"
CLIENTS_DIR="/ca/clients"
INDEX="$PKI/index.txt"

json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# BusyBox date on Alpine needs an explicit input format for OpenSSL dates.
parse_openssl_date() {
  local raw="$1" output_format="$2"
  date -u -D "%b %e %H:%M:%S %Y GMT" -d "$raw" "+$output_format" 2>/dev/null
}

# EasyRSA index expiry format: YYMMDDHHMMSSZ.
parse_index_expiry() {
  local raw="$1" yy mm dd hh mi ss yyyy iso
  [[ "$raw" =~ ^[0-9]{12}Z$ ]] || return 1
  yy="${raw:0:2}"; mm="${raw:2:2}"; dd="${raw:4:2}"
  hh="${raw:6:2}"; mi="${raw:8:2}"; ss="${raw:10:2}"
  if (( 10#$yy >= 50 )); then yyyy="19$yy"; else yyyy="20$yy"; fi
  iso="$yyyy-$mm-$dd $hh:$mi:$ss"
  date -u -D "%Y-%m-%d %H:%M:%S" -d "$iso" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
}

declare -A seen=()
declare -A db_status=()
declare -A db_expiry=()

if [[ -r "$INDEX" ]]; then
  while IFS= read -r line; do
    # EasyRSA index rows: status expiry revocation serial filename subject
    read -r st expiry revocation serial filename subject <<< "$line"
    [[ -n "${st:-}" && -n "${subject:-}" ]] || continue
    name="${subject##*/CN=}"
    [[ "$name" != "$subject" ]] || continue
    [[ "$name" != server ]] || continue
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || continue
    # Prefer R over V if historical/duplicate CN rows exist.
    if [[ "$st" == R || -z "${db_status[$name]:-}" ]]; then
      db_status[$name]="$st"
      db_expiry[$name]="$expiry"
    fi
    seen[$name]=1
  done < "$INDEX"
fi

# Include clients represented by exported profile directories.
if [[ -d "$CLIENTS_DIR" ]]; then
  for dir in "$CLIENTS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    name=${dir##*/}
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || continue
    seen[$name]=1
  done
fi

# Include issued certificates even if the profile directory is missing.
if [[ -d "$PKI/issued" ]]; then
  for cert in "$PKI"/issued/*.crt; do
    [[ -f "$cert" ]] || continue
    name=${cert##*/}; name=${name%.crt}
    [[ "$name" != server && "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || continue
    seen[$name]=1
  done
fi

printf '{"success":true,"clients":['
first=1
valid=0; expiring=0; expired=0; revoked=0; missing_cert=0; missing_profile=0; unknown=0

for name in "${!seen[@]}"; do
  cert="$PKI/issued/$name.crt"
  profile="$CLIENTS_DIR/$name/ovpn/$name.ovpn"
  has_cert=false; has_profile=false; expires=""; days_remaining=null
  [[ -f "$cert" ]] && has_cert=true
  [[ -f "$profile" ]] && has_profile=true
  st="${db_status[$name]:-}"

  # Revocation in index.txt takes precedence, even if EasyRSA removed the cert.
  if [[ "$st" == R ]]; then
    status=REVOKED; revoked=$((revoked + 1))
    expiry_raw="${db_expiry[$name]:-}"
    if [[ -n "$expiry_raw" ]]; then
      expires=$(parse_index_expiry "$expiry_raw" || true)
    fi
  elif [[ ! -f "$cert" ]]; then
    status=MISSING_CERT; missing_cert=$((missing_cert + 1))
  else
    enddate=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2- || true)
    if [[ -n "$enddate" ]]; then
      expires=$(parse_openssl_date "$enddate" '%Y-%m-%dT%H:%M:%SZ' || true)
      exp_epoch=$(parse_openssl_date "$enddate" '%s' || true)
      now_epoch=$(date -u '+%s')
      # Parsing failure must not turn a valid certificate into EXPIRED.
      if [[ "$exp_epoch" =~ ^[0-9]+$ ]]; then
        days_remaining=$(( (exp_epoch - now_epoch) / 86400 ))
        if (( exp_epoch <= now_epoch )); then
          status=EXPIRED; expired=$((expired + 1))
        elif (( days_remaining <= 30 )); then
          status=EXPIRING; expiring=$((expiring + 1))
        else
          status=VALID; valid=$((valid + 1))
        fi
      else
        status=UNKNOWN; unknown=$((unknown + 1)); days_remaining=null
      fi
    else
      status=UNKNOWN; unknown=$((unknown + 1))
    fi
  fi

  # Missing profile is reported separately; never override REVOKED.
  if [[ "$has_profile" == false && "$status" != REVOKED ]]; then
    if [[ "$status" == VALID || "$status" == EXPIRING || "$status" == EXPIRED ]]; then
      status=MISSING_PROFILE; missing_profile=$((missing_profile + 1))
    fi
  fi

  [[ $first -eq 1 ]] || printf ','
  first=0
  printf '{"name":"%s","status":"%s","profile":%s,"certificate":%s,"expires":"%s","days_remaining":%s}' \
    "$(json_escape "$name")" "$status" "$has_profile" "$has_cert" \
    "$(json_escape "$expires")" "$days_remaining"
done

count=${#seen[@]}
printf '],"count":%s,"summary":{"valid":%s,"expiring":%s,"expired":%s,"revoked":%s,"missing_cert":%s,"missing_profile":%s,"unknown":%s}}\n' \
  "$count" "$valid" "$expiring" "$expired" "$revoked" "$missing_cert" "$missing_profile" "$unknown"
