#!/usr/bin/env bash
# Level-3 network diagnostics for the platform: DNS, TCP reachability, TLS and HTTP checks
# for the OpenShift API and an application Route, plus cluster health when `oc` is logged in.
#
#   tools/netcheck.sh api.ocp.example.com subscriber-api-dev.apps.ocp.example.com
#
# Exit code is the number of failed checks, so it can be used from a pipeline or a ticket.
set -uo pipefail

API_HOST="${1:?usage: netcheck.sh <api-host> [route-host]}"
ROUTE_HOST="${2:-}"
FAILED=0

ok()   { printf '  [OK]   %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; FAILED=$((FAILED + 1)); }
info() { printf '  [INFO] %s\n' "$*"; }

resolve() {
  local host="$1"
  local ip
  if command -v dig >/dev/null; then
    ip="$(dig +short "$host" | tail -n1)"
  else
    ip="$(getent hosts "$host" | awk '{print $1}' | head -n1)"
  fi
  [[ -n "$ip" ]] && { ok "DNS ${host} -> ${ip}"; return 0; }
  fail "DNS ${host} does not resolve"; return 1
}

tcp_check() {
  local host="$1" port="$2"
  if timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; then
    ok "TCP ${host}:${port} reachable"
  else
    fail "TCP ${host}:${port} unreachable (firewall / load balancer / routing)"
  fi
}

tls_check() {
  local host="$1" port="$2"
  local out
  if ! out="$(echo | timeout 10 openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null)"; then
    fail "TLS handshake with ${host}:${port}"; return
  fi
  local not_after
  not_after="$(printf '%s' "$out" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
  local issuer
  issuer="$(printf '%s' "$out" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer=//')"
  ok "TLS ${host}:${port} certificate expires ${not_after:-?} (issuer: ${issuer:-?})"
}

http_check() {
  local url="$1" expected="$2" extra="${3:-}"
  local code
  # shellcheck disable=SC2086
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 $extra "$url" || true)"
  if [[ "$code" == "$expected" ]]; then
    ok "HTTP ${url} -> ${code}"
  else
    fail "HTTP ${url} -> ${code:-no response} (expected ${expected})"
  fi
}

echo "== OpenShift API (${API_HOST})"
resolve "$API_HOST" && tcp_check "$API_HOST" 6443 && tls_check "$API_HOST" 6443
http_check "https://${API_HOST}:6443/healthz" 200
http_check "https://${API_HOST}:6443/api/v1/namespaces" 403

if [[ -n "$ROUTE_HOST" ]]; then
  echo "== Application Route (${ROUTE_HOST})"
  resolve "$ROUTE_HOST" && tcp_check "$ROUTE_HOST" 443 && tls_check "$ROUTE_HOST" 443
  tcp_check "$ROUTE_HOST" 80
  http_check "http://${ROUTE_HOST}/healthz" 302
  http_check "https://${ROUTE_HOST}/healthz" 200
  http_check "https://${ROUTE_HOST}/api/v1/info" 200
fi

echo "== Path"
if command -v mtr >/dev/null; then
  mtr -rwc 5 "$API_HOST" | sed 's/^/  /'
elif command -v traceroute >/dev/null; then
  traceroute -m 15 -w 2 "$API_HOST" 2>/dev/null | sed 's/^/  /'
else
  info "mtr/traceroute not installed; skipping path analysis"
fi

if command -v oc >/dev/null && oc whoami >/dev/null 2>&1; then
  echo "== Cluster health (oc whoami: $(oc whoami))"
  degraded="$(oc get clusteroperators -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Degraded" and .status=="True")) | .metadata.name' 2>/dev/null)"
  [[ -z "$degraded" ]] && ok "no degraded cluster operator" || fail "degraded cluster operators: ${degraded//$'\n'/, }"
  not_ready="$(oc get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}')"
  [[ -z "$not_ready" ]] && ok "all nodes Ready" || fail "nodes not Ready: ${not_ready//$'\n'/, }"
  routers="$(oc -n openshift-ingress get pods -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default --no-headers 2>/dev/null | grep -c Running || true)"
  [[ "${routers:-0}" -ge 1 ]] && ok "${routers} router pod(s) running" || fail "no running router pod"
else
  info "oc not logged in; skipping cluster checks"
fi

echo
echo "${FAILED} check(s) failed"
exit "$FAILED"
