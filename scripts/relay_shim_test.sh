#!/usr/bin/env bash
# ponytail: assert-based check for relay_shim.py. Stands up a throwaway TLS
# listener standing in for the relay and asserts the shim stamps identity on.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"; kill %1 %2 2>/dev/null || true' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" \
  -days 1 -nodes -subj "/CN=localhost" >/dev/null 2>&1

printf 'ghs_exampletoken' > "${WORK}/token"

# Stand-in relay: records the request headers it receives, then replies
python3 - "${WORK}" <<'PY' &
import http.server, ssl, sys, threading
work = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(f"{work}/seen.txt", "w", encoding="utf-8") as fh:
            for key, value in self.headers.items():
                fh.write(f"{key}: {value}\n")
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(f"{work}/cert.pem", f"{work}/key.pem")
srv = http.server.HTTPServer(("127.0.0.1", 18443), Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY

# The shim verifies TLS, so trust the throwaway certificate
export SSL_CERT_FILE="${WORK}/cert.pem"
python3 "${ROOT}/scripts/relay_shim.py" \
  --relay https://localhost:18443 \
  --repository bcgov/action-oc-runner \
  --token-file "${WORK}/token" \
  --listen-port 17443 >"${WORK}/shim.log" 2>&1 &

for _ in $(seq 1 50); do
  (exec 3<>/dev/tcp/127.0.0.1/17443) 2>/dev/null && break
  sleep 0.2
done

# A client that spoofs identity headers, to prove the shim overwrites them
curl -sS --max-time 10 -o /dev/null \
  -H "X-Action-Repository: attacker/evil" \
  -H "X-Action-Token: stolen" \
  http://127.0.0.1:17443/version

grep -qi "^X-Action-Repository: bcgov/action-oc-runner$" "${WORK}/seen.txt" \
  || { echo "FAIL: shim must stamp the real repository"; cat "${WORK}/seen.txt"; exit 1; }
grep -qi "^X-Action-Token: ghs_exampletoken$" "${WORK}/seen.txt" \
  || { echo "FAIL: shim must stamp the real token"; exit 1; }
grep -qi "attacker/evil" "${WORK}/seen.txt" \
  && { echo "FAIL: client-supplied identity headers must be dropped"; exit 1; }

echo "relay_shim_test.sh: ok"
