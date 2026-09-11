#!/usr/bin/env bash
# Install and start Tor on the runner, giving OpenShift API traffic an exit IP that
# is not the runner's. Free, public, and needs no infrastructure of your own.
# Prints the SOCKS proxy URL on success.
set -euo pipefail

SOCKS_PORT="${TOR_SOCKS_PORT:-9050}"

if ! command -v tor >/dev/null 2>&1; then
  echo "Installing Tor..." >&2
  sudo apt-get update -qq >&2
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tor >&2
fi

# The packaged service may already own the port; only start one if nothing listens
if ! (exec 3<>"/dev/tcp/127.0.0.1/${SOCKS_PORT}") 2>/dev/null; then
  sudo tor --SocksPort "${SOCKS_PORT}" --RunAsDaemon 1 >&2
fi

# Tor accepts connections before it has a usable circuit, so poll a real request
for _ in $(seq 1 60); do
  if curl -sS --socks5-hostname "127.0.0.1:${SOCKS_PORT}" --max-time 10 \
      -o /dev/null https://check.torproject.org/api/ip 2>/dev/null; then
    echo "socks5://127.0.0.1:${SOCKS_PORT}"
    exit 0
  fi
  sleep 2
done

echo "::error::Tor did not build a usable circuit within 120s." >&2
exit 1
