#!/usr/bin/env bash
# vpncheck.sh — ProtonVPN (NetShield ON) leak & blocking audit (Arch-safe)

set -eo pipefail
trap 'echo "❌ vpncheck.sh failed at line $LINENO" >&2' ERR

# ---------- Pretty output ----------
GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; BOLD="\e[1m"; RESET="\e[0m"
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}!${RESET} $*"; }
info(){ echo -e "${BLUE}i${RESET} $*"; }
headline(){ echo -e "\n${BOLD}===== $* =====${RESET}"; }
ts(){ date +"%Y-%m-%d %H:%M:%S %Z"; }

# ---------- Requirements ----------
need_cmds=(curl dig ip ping nc awk sed)
missing=()
for c in "${need_cmds[@]}"; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  echo "Missing commands: ${missing[*]}"
  exit 1
fi

# ---------- Reports ----------
OUTDIR="${FUETEM_LOG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fuetem/logs}"
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
REPORT="$OUTDIR/vpn_audit_${STAMP}.txt"
CSV="$OUTDIR/adblock_results_${STAMP}.csv"
TMPCSV="$CSV.tmp"
: > "$REPORT"
: > "$TMPCSV"
log(){ echo "$*" | tee -a "$REPORT" >/dev/null; }

# ---------- Config ----------
TIMEOUT=${TIMEOUT:-2}
MAXJOBS=${MAXJOBS:-10}

# Proton sinkholes
SINKHOLES=("0.0.0.0" "10.10.10.1" "::" "0.0.0.17")

EXPECTED_ALLOW=(phishing.army malware-filter.gitlab.io)

TEST_DOMAINS=(
  doubleclick.net ad.doubleclick.net googleadservices.com
  pagead2.googlesyndication.com g.doubleclick.net
  securepubads.g.doubleclick.net s.youtube.com
  www.googletagmanager.com www.google-analytics.com
  connect.facebook.net pixel.facebook.com graph.facebook.com
  telemetry.microsoft.com ads.msn.com adnxs.com
  business-api.tiktok.com ads-api.tiktok.com
  log.byteoversea.com hotjar.com events.hotjar.io
  browser.sentry-cdn.com api.bugsnag.com
  cdn.optimizely.com scorecardresearch.com
  quantserve.com criteo.com taboola.com
  outbrain.com rubiconproject.com openx.net
  pubmatic.com phishing.army malware-filter.gitlab.io
)

# ---------- Environment ----------
headline "Environment"
log "$(ts)"

if systemctl is-active --quiet systemd-networkd; then
  networkctl status --no-pager || true
elif command -v nmcli >/dev/null 2>&1; then
  nmcli connection show --active || true
elif command -v resolvectl >/dev/null 2>&1; then
  resolvectl status || true
else
  warn "No known network manager detected"
fi

# ---------- Routes & tunnel ----------
headline "Default routes & tunnel"
ip route show default | sed 's/^/  /' | tee -a "$REPORT" >/dev/null || true

tuns=$(ip link show | awk -F: '/tun|wg|proton/ {print $2}' | tr -d ' ')
[[ -n "$tuns" ]] && ok "Tunnel interfaces: $tuns" || warn "No tun/wg/proton interfaces detected"

# ---------- Public IP ----------
headline "Public IP & ASN"
v4_ip=$(curl -4s --max-time 8 https://ifconfig.me || true)
[[ -n "$v4_ip" ]] && ok "IPv4 public: $v4_ip" || warn "No IPv4 public IP"

v4_info=$(curl -4s --max-time 8 https://ipinfo.io/json || true)
if [[ -n "$v4_info" ]]; then
  org=$(sed -n 's/.*"org": *"\([^"]*\)".*/\1/p' <<<"$v4_info")
  city=$(sed -n 's/.*"city": *"\([^"]*\)".*/\1/p' <<<"$v4_info")
  ctry=$(sed -n 's/.*"country": *"\([^"]*\)".*/\1/p' <<<"$v4_info")
  [[ -n "$org" ]] && info "Org/ASN: $org (${city:-?}, ${ctry:-?})"
fi

# ---------- IPv6 ----------
headline "IPv6 exposure check"
v6=false
{ dig -6 +time=2 +tries=1 google.com >/dev/null 2>&1; } && v6=true || true
ping -6 -c1 -W2 google.com >/dev/null 2>&1 && v6=true || true
curl -6s --max-time 5 https://ipv6.icanhazip.com >/dev/null 2>&1 && v6=true || true
$v6 && warn "IPv6 reachable — ensure VPN blocks it" || ok "No IPv6 connectivity detected"

# ---------- DNS ----------
headline "DNS configuration"
nameservers=()
if command -v resolvectl >/dev/null 2>&1; then
  resolvectl status | tee -a "$REPORT" >/dev/null || true
  mapfile -t nameservers < <(resolvectl status | awk '/DNS Servers/ {print $3}')
else
  mapfile -t nameservers < <(awk '/^nameserver/ {print $2}' /etc/resolv.conf)
fi
log "System nameservers: ${nameservers[*]:-none}"

# ---------- DNS leak ----------
headline "DNS leak check"
odns=$(dig +short myip.opendns.com @resolver1.opendns.com -4 2>/dev/null || true)
[[ -n "$odns" ]] && ok "OpenDNS sees egress IP: $odns" || warn "OpenDNS check failed"

# ---------- STUN ----------
headline "STUN / WebRTC"
nc -u -z -w2 stun.l.google.com 19302 >/dev/null 2>&1
[[ $? -eq 0 ]] && info "STUN reachable (normal)" || ok "STUN blocked/unreachable"

# ---------- Ad / Tracker ----------
headline "Ad / Tracker scorecard"
echo "domain,blocked,a_records,aaaa_records,status_v4,status_v6" > "$TMPCSV"

check_one() {
  local d="$1" av4 av6 st4 st6 verdict sink=false expect=false

  av4=$(dig +short A "$d" 2>/dev/null | tr '\n' ' ')
  av6=$(dig +short AAAA "$d" 2>/dev/null | tr '\n' ' ')
  st4=$(dig "$d" 2>/dev/null | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)
  st6=$(dig AAAA "$d" 2>/dev/null | sed -n 's/.*status: \([A-Z]*\).*/\1/p' | head -1)

  for e in "${EXPECTED_ALLOW[@]}"; do [[ "$d" == "$e" ]] && expect=true; done
  for ip in $av4 $av6; do [[ " ${SINKHOLES[*]} " == *" $ip "* ]] && sink=true; done

  if $expect; then
    ok "EXPECTED → $d"
    verdict="expected"
  elif $sink || [[ -z "$av4$av6" ]] || [[ "$st4$st6" =~ (NXDOMAIN|SERVFAIL) ]]; then
    ok "BLOCKED → $d"
    verdict="yes"
  else
    warn "ALLOWED → $d  A:$av4 AAAA:$av6"
    verdict="no"
  fi

  echo "$d,$verdict,\"$av4\",\"$av6\",${st4:-NA},${st6:-NA}" >> "$TMPCSV"
}

for d in "${TEST_DOMAINS[@]}"; do
  check_one "$d" &
  while (( $(jobs -p | wc -l) >= MAXJOBS )); do sleep 0.1; done
done
wait
mv "$TMPCSV" "$CSV"

# ---------- Summary ----------
headline "Summary"
total=$(($(wc -l < "$CSV") - 1))
blocked=$(awk -F, '$2=="yes"{c++} END{print c+0}' "$CSV")
expected=$(awk -F, '$2=="expected"{c++} END{print c+0}' "$CSV")
effective=$(( total - expected ))
pct=$(( effective > 0 ? blocked*100/effective : 100 ))

ok "Ad/Tracker block rate: $blocked / $effective (${pct}%)"
ok "CSV report: $CSV"
ok "Text report: $REPORT"

exit 0
