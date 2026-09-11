#!/usr/bin/env bash
# ponytail: assert-based check for resolve_server.sh; no framework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVE="${ROOT}/scripts/resolve_server.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

got="$(OC_SERVER=https://api.gold.devops.gov.bc.ca:6443 OC_RELAY= bash "${RESOLVE}")"
[ "${got}" = "https://api.gold.devops.gov.bc.ca:6443" ] || fail "empty relay must pass oc_server through, got '${got}'"

got="$(OC_SERVER=https://api.gold.devops.gov.bc.ca:6443 OC_RELAY='https://oc-relay.apps.{cluster}.devops.gov.bc.ca' bash "${RESOLVE}")"
[ "${got}" = "https://oc-relay.apps.gold.devops.gov.bc.ca" ] || fail "expected gold relay, got '${got}'"

got="$(OC_SERVER=https://api.silver.devops.gov.bc.ca:6443 OC_RELAY='https://oc-relay.apps.{cluster}.devops.gov.bc.ca' bash "${RESOLVE}")"
[ "${got}" = "https://oc-relay.apps.silver.devops.gov.bc.ca" ] || fail "expected silver relay, got '${got}'"

got="$(OC_SERVER=https://api.emerald.devops.gov.bc.ca:6443 OC_RELAY='https://oc-relay.apps.{cluster}.devops.gov.bc.ca' bash "${RESOLVE}")"
[ "${got}" = "https://oc-relay.apps.emerald.devops.gov.bc.ca" ] || fail "expected emerald relay, got '${got}'"

got="$(OC_SERVER=https://api.dev.example.org:6443 OC_RELAY='https://oc-relay.apps.{cluster}.example.org' bash "${RESOLVE}")"
[ "${got}" = "https://oc-relay.apps.dev.example.org" ] || fail "cluster name must not be tied to devops.gov.bc.ca, got '${got}'"

# {domain} makes one relay string portable across orgs and clusters
for pair in \
  "https://api.silver.devops.gov.bc.ca:6443|https://oc-relay.apps.silver.devops.gov.bc.ca" \
  "https://api.gold.devops.gov.bc.ca:6443|https://oc-relay.apps.gold.devops.gov.bc.ca" \
  "https://api.emerald.devops.gov.bc.ca:6443|https://oc-relay.apps.emerald.devops.gov.bc.ca" \
  "https://api.ocp4.example.com:6443|https://oc-relay.apps.ocp4.example.com" ; do
  server="${pair%%|*}"
  want="${pair##*|}"
  got="$(OC_SERVER="${server}" OC_RELAY='https://oc-relay.apps.{domain}' bash "${RESOLVE}")"
  [ "${got}" = "${want}" ] || fail "{domain} for ${server} expected '${want}', got '${got}'"
done

got="$(OC_SERVER=https://api.gold.devops.gov.bc.ca:6443 OC_RELAY='https://fixed-relay.example.ca' bash "${RESOLVE}")"
[ "${got}" = "https://fixed-relay.example.ca" ] || fail "relay without {cluster} must be used verbatim, got '${got}'"

if OC_SERVER=https://console.example.com:6443 OC_RELAY='https://oc-relay.apps.{cluster}.devops.gov.bc.ca' bash "${RESOLVE}" 2>/dev/null; then
  fail "{cluster} with an oc_server that has no api.<cluster>. prefix must fail fast"
fi

if OC_SERVER=https://api.gold.devops.gov.bc.ca:6443 OC_RELAY='http://oc-relay.example' bash "${RESOLVE}" 2>/dev/null; then
  fail "non-https relay must be rejected"
fi

echo "resolve_server_test.sh: ok"
