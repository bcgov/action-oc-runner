#!/usr/bin/env bash
# ponytail: assert-based check for apply_proxy_env.sh; no framework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="${ROOT}/scripts/apply_proxy_env.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy NO_PROXY no_proxy ACTION_HTTPS_PROXY
# shellcheck source=scripts/apply_proxy_env.sh
source "${APPLY}"
[ -z "${HTTPS_PROXY:-}" ] || fail "empty ACTION_HTTPS_PROXY must not set HTTPS_PROXY"

ACTION_HTTPS_PROXY="http://127.0.0.1:8888"
# shellcheck source=scripts/apply_proxy_env.sh
source "${APPLY}"
[ "${HTTPS_PROXY}" = "http://127.0.0.1:8888" ] || fail "expected HTTPS_PROXY to match input"
[ "${HTTP_PROXY}" = "http://127.0.0.1:8888" ] || fail "expected HTTP_PROXY to match input"
[[ "${NO_PROXY}" == *github.com* ]] || fail "NO_PROXY must include github.com"
[[ "${NO_PROXY}" == *mirror.openshift.com* ]] || fail "NO_PROXY must include mirror.openshift.com"

ENV_FILE="$(mktemp)"
trap 'rm -f "${ENV_FILE}"' EXIT
GITHUB_ENV="${ENV_FILE}"
ACTION_HTTPS_PROXY="http://127.0.0.1:8888"
# shellcheck source=scripts/apply_proxy_env.sh
source "${APPLY}"
grep -qx "HTTPS_PROXY=http://127.0.0.1:8888" "${ENV_FILE}" || fail "GITHUB_ENV must carry HTTPS_PROXY to later steps"
grep -q "^NO_PROXY=.*mirror.openshift.com" "${ENV_FILE}" || fail "GITHUB_ENV must carry NO_PROXY to later steps"
unset GITHUB_ENV

ACTION_HTTPS_PROXY="http://user:pass@evil:3128"
if source "${APPLY}"; then
  fail "proxy with credentials must be rejected"
fi

ACTION_HTTPS_PROXY="http://proxy.example:3128/extra"
if source "${APPLY}"; then
  fail "proxy with a path must be rejected"
fi

echo "apply_proxy_env_test.sh: ok"
