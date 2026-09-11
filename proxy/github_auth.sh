#!/usr/bin/env bash
# Squid basic auth helper. The username is owner/repo and the password is that
# workflow's GITHUB_TOKEN.
#
# The repository is derived from the token rather than taken on trust. Asking
# GET /repos/<claimed> would prove nothing, because any valid token reads any
# public repository; that check would admit anyone with a GitHub account. An
# installation token instead reports the repositories it is scoped to, so the
# claim is only accepted when the token itself grants that repository.
#
# This requires the workflow's own GITHUB_TOKEN. A personal access token is not
# an installation token and is refused.
#
# Squid's helper protocol is one "username password" line in, one OK/ERR out.
set -uo pipefail

API="${GITHUB_API:-https://api.github.com}"
BODY="$(mktemp)"
trap 'rm -f "${BODY}"' EXIT

# Squid URL-encodes both fields. Repository names cannot contain '%' or '\',
# so rejecting anything outside the allowed shape keeps this decode safe.
decode() { printf '%b' "${1//%/\\x}"; }

while read -r user pass; do
  repo="$(decode "${user:-}")"
  token="$(decode "${pass:-}")"

  if [[ ! "${repo}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "ERR message=malformed-repository"
    continue
  fi

  code="$(curl -sS -o "${BODY}" -w '%{http_code}' --max-time 10 \
    --header "Authorization: Bearer ${token}" \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: action-oc-runner-proxy" \
    "${API}/installation/repositories?per_page=100" 2>/dev/null)" || code="000"

  if [ "${code}" != "200" ]; then
    echo "ERR message=not-a-workflow-token-${code}"
    continue
  fi

  if jq -e --arg repo "${repo}" \
      '[.repositories[]?.full_name] | index($repo) != null' "${BODY}" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "ERR message=token-does-not-grant-${repo}"
  fi
done
