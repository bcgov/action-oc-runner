#!/usr/bin/env bash
# Live checks against an oc-runner Route. Used by the PR e2e job to prove
# oc-runner-<pr> actually tunnels allowed API calls and refuses everything else.
#
# Required: PROXY_HOST, TOKEN, GITHUB_REPOSITORY
# PROXY_INSECURE=1 (default) for the throwaway PR certificate.
set -euo pipefail

: "${PROXY_HOST:?PROXY_HOST is required}"
: "${TOKEN:?TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

SILVER="https://api.silver.devops.gov.bc.ca:6443/version"
GOLD="https://api.gold.devops.gov.bc.ca:6443/version"
CURL_PROXY=(--max-time 25)
if [ "${PROXY_INSECURE:-1}" = "1" ]; then
  CURL_PROXY+=(--proxy-insecure)
fi

fail() { echo "FAIL: $*" >&2; exit 1; }

code_via() { # proxy_url target
  curl -sS -o /tmp/pr_e2e.body -w '%{http_code}' "${CURL_PROXY[@]}" --proxy "$1" "$2" || echo 000
}

wait_up() {
  local code="" i
  for i in $(seq 1 30); do
    code="$(code_via "https://${PROXY_HOST}" "${SILVER}")"
    if [ "${code}" != "000" ]; then
      echo "proxy reachable (${code}) after ${i} probe(s)"
      return 0
    fi
    sleep 5
  done
  fail "proxy at ${PROXY_HOST} never answered"
}

echo "== DNS =="
getent hosts "${PROXY_HOST}" | awk '{print "  " $1, $2}' \
  || fail "${PROXY_HOST} does not resolve"

echo "== wait =="
wait_up

REPO_ENC="${GITHUB_REPOSITORY//\//%2F}"
GOOD="https://${REPO_ENC}:${TOKEN}@${PROXY_HOST}"
NONE="https://${PROXY_HOST}"
BAD="https://${REPO_ENC}:not-a-token@${PROXY_HOST}"
SPOOF="https://attacker%2Fevil:${TOKEN}@${PROXY_HOST}"
echo "::add-mask::${GOOD}"

echo "== refuse =="
code="$(code_via "${NONE}" "${SILVER}")"
[ "${code}" != "200" ] || fail "unauthenticated request must not tunnel, got ${code}"
echo "  no credentials              -> ${code}"

code="$(code_via "${BAD}" "${SILVER}")"
[ "${code}" != "200" ] || fail "invalid token must not tunnel, got ${code}"
echo "  invalid token               -> ${code}"

code="$(code_via "${SPOOF}" "${SILVER}")"
[ "${code}" != "200" ] || fail "token must not be usable as another repository, got ${code}"
echo "  this token as attacker/evil -> ${code}"

code="$(code_via "${GOOD}" "https://example.com:6443/")"
[ "${code}" != "200" ] || fail "undeclared host must not tunnel, got ${code}"
echo "  allowed caller, example.com -> ${code}"

code="$(code_via "${GOOD}" "https://api.silver.devops.gov.bc.ca/")"
[ "${code}" != "200" ] || fail "port 443 must not tunnel, got ${code}"
echo "  allowed caller, silver :443 -> ${code}"

echo "== allow =="
code="$(code_via "${GOOD}" "${SILVER}")"
[ "${code}" = "200" ] || fail "silver API through the proxy, got ${code}"
grep -q '"gitVersion"' /tmp/pr_e2e.body || fail "silver /version was not a kube version document"
echo "  silver :6443 /version       -> ${code} $(jq -r .gitVersion /tmp/pr_e2e.body)"

code="$(code_via "${GOOD}" "${GOLD}")"
[ "${code}" = "200" ] || fail "gold API through the proxy, got ${code}"
grep -q '"gitVersion"' /tmp/pr_e2e.body || fail "gold /version was not a kube version document"
echo "  gold :6443 /version         -> ${code} $(jq -r .gitVersion /tmp/pr_e2e.body)"

echo "pr_e2e.sh: ok"
