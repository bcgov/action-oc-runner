#!/usr/bin/env bash
# Squid basic auth helper. The username is owner/repo and the password is that
# workflow's GITHUB_TOKEN. A GITHUB_TOKEN only authenticates for its own
# repository, so a 200 from the repos endpoint proves the caller really is a
# workflow running in that repository.
#
# Squid's helper protocol is one "username password" line in, one OK/ERR out.
set -uo pipefail

API="${GITHUB_API:-https://api.github.com}"

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

  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
    --header "Authorization: Bearer ${token}" \
    --header "Accept: application/vnd.github+json" \
    --header "User-Agent: action-oc-runner-proxy" \
    "${API}/repos/${repo}" 2>/dev/null)" || code="000"

  if [ "${code}" = "200" ]; then
    echo "OK"
  else
    echo "ERR message=github-rejected-${code}"
  fi
done
