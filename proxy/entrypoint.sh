#!/usr/bin/env bash
# Render squid.conf from the environment, then hand off to squid.
set -euo pipefail

: "${OWNER_REGEX:=^bcgov(-c)?/}"
: "${API_HOSTS:=api.gold.devops.gov.bc.ca api.silver.devops.gov.bc.ca}"
: "${REALM:=action-oc-runner}"

for FILE in /etc/squid/tls/tls.crt /etc/squid/tls/tls.key; do
  if [ ! -r "${FILE}" ]; then
    echo "entrypoint: cannot read ${FILE}." >&2
    echo "entrypoint: the proxy must terminate TLS; basic auth over cleartext would expose GitHub tokens." >&2
    exit 1
  fi
done

export OWNER_REGEX API_HOSTS REALM
envsubst '${OWNER_REGEX} ${API_HOSTS} ${REALM}' \
  < /etc/squid/squid.conf.template > /tmp/squid.conf

# No -d1; cache_log already goes to stderr and the two together double every line
exec squid -f /tmp/squid.conf -N
