#!/usr/bin/env bash
# ponytail: assert-based check for the CONNECT proxy. Builds the image, then runs
# itself inside it against a fake GitHub and a fake OpenShift API on loopback, so
# no real cluster, token, or GitHub API call is involved.
set -uo pipefail

if [ -z "${IN_CONTAINER:-}" ]; then
  set -e
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  podman build -q -t oc-runner:test "${HERE}" >/dev/null
  exec podman run --rm --cpus=2 --memory=1g --user root -e IN_CONTAINER=1 \
    -v "${HERE}/proxy_test.sh:/proxy_test.sh:ro,z" \
    --entrypoint bash oc-runner:test /proxy_test.sh
fi

fail() { echo "FAIL: $*" >&2; exit 1; }

dnf install -y python3 openssl >/dev/null 2>&1
echo "127.0.0.1 fake-api.test fake-other.test fake-github.test" >> /etc/hosts

mkdir -p /etc/squid/tls
openssl req -x509 -newkey rsa:2048 -keyout /etc/squid/tls/tls.key \
  -out /etc/squid/tls/tls.crt -days 1 -nodes -subj "/CN=localhost" >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -keyout /api.key -out /api.crt \
  -days 1 -nodes -subj "/CN=fake-api.test" >/dev/null 2>&1

# Fake GitHub, faithful on the point that matters: /repos/<anything> succeeds for
# ANY valid token, because public repositories are readable by everyone. Only
# /installation/repositories ties a token to its own repository.
python3 - <<'PY' &
import http.server, json
TOKENS = {
    "goodtoken":   "bcgov/action-oc-runner",
    "bcgovctoken": "bcgov-c/something",
    "eviltoken":   "attacker/evil",
}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = (self.headers.get("Authorization") or "").removeprefix("Bearer ")
        if auth not in TOKENS:
            self.send_response(401); self.send_header("Content-Length", "0")
            self.end_headers(); return
        if self.path.startswith("/installation/repositories"):
            body = json.dumps({"repositories": [{"full_name": TOKENS[auth]}]}).encode()
        elif self.path.startswith("/repos/"):
            body = b'{"private":false}'
        else:
            self.send_response(404); self.send_header("Content-Length", "0")
            self.end_headers(); return
        self.send_response(200); self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8080), H).serve_forever()
PY

# Fake OpenShift API on the real API port
python3 - <<'PY' &
import http.server, ssl
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = b'{"major":"1"}'
        self.send_response(200); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain("/api.crt", "/api.key")
s = http.server.HTTPServer(("127.0.0.1", 6443), H)
s.socket = c.wrap_socket(s.socket, server_side=True); s.serve_forever()
PY

# Run squid unprivileged, as it does in OpenShift; as root it drops privileges
# partway through startup and can no longer write its own logs.
chmod 0644 /etc/squid/tls/tls.crt /etc/squid/tls/tls.key
# squid logs to /dev/stdout, which here resolves to this file, so it must own it
install -o squid -m 0644 /dev/null /squid.log
runuser -u squid -- env \
  GITHUB_API="http://fake-github.test:8080" \
  OWNER_REGEX='^bcgov(-c)?/' \
  API_HOSTS="fake-api.test" \
  /usr/local/bin/entrypoint.sh >/squid.log 2>&1 &

for _ in $(seq 1 50); do
  (exec 3<>/dev/tcp/127.0.0.1/3129) 2>/dev/null && break
  sleep 0.2
done
(exec 3<>/dev/tcp/127.0.0.1/3129) 2>/dev/null || { cat /squid.log; fail "squid did not start"; }

# Returns the HTTP code the client saw, or 000 when the tunnel was refused
try() { # user pass target
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 -k \
    --proxy "https://${1}:${2}@localhost:3129" \
    --proxy-cacert /etc/squid/tls/tls.crt \
    "https://${3}/version" 2>/dev/null
}

echo "== allowed =="
code=$(try 'bcgov%2Faction-oc-runner' goodtoken 'fake-api.test:6443')
[ "${code}" = "200" ] || fail "bcgov repo with a valid token should tunnel, got '${code}'"
echo "  bcgov/action-oc-runner + valid token -> ${code}"

code=$(try 'bcgov-c%2Fsomething' bcgovctoken 'fake-api.test:6443')
[ "${code}" = "200" ] || fail "bcgov-c should be allowed too, got '${code}'"
echo "  bcgov-c/something + its own token   -> ${code}"

echo "== refused =="
code=$(try 'bcgov%2Faction-oc-runner' wrongtoken 'fake-api.test:6443')
[ "${code}" = "200" ] && fail "an invalid GitHub token must not tunnel"
echo "  valid repo + invalid token          -> ${code:-blocked}"

# The token works, but it belongs to attacker/evil. Trusting the claimed name
# would admit anyone with a GitHub account, since public repos read fine.
code=$(try 'bcgov%2Faction-oc-runner' eviltoken 'fake-api.test:6443')
[ "${code}" = "200" ] && fail "a valid token must not be usable to impersonate another repository"
echo "  someone else's token, bcgov claim   -> ${code:-blocked}"

code=$(try 'attacker%2Fevil' eviltoken 'fake-api.test:6443')
[ "${code}" = "200" ] && fail "a repo outside the allowed owners must not tunnel"
echo "  outside-org repo + its own token    -> ${code:-blocked}"

code=$(try 'bcgov%2Faction-oc-runner' goodtoken 'fake-other.test:6443')
[ "${code}" = "200" ] && fail "an undeclared destination host must not tunnel"
echo "  allowed caller, wrong host          -> ${code:-blocked}"

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -k \
  --proxy "https://localhost:3129" --proxy-cacert /etc/squid/tls/tls.crt \
  "https://fake-api.test:6443/version" 2>/dev/null)
[ "${code}" = "200" ] && fail "an unauthenticated caller must not tunnel"
echo "  no credentials at all               -> ${code:-blocked}"

code=$(try 'bcgov%2Faction-oc-runner' goodtoken 'fake-api.test:443')
[ "${code}" = "200" ] && fail "only port 6443 may be tunnelled to"
echo "  allowed caller, wrong port          -> ${code:-blocked}"

# Plain http:// through a proxy is a GET with an absolute URI, not a CONNECT.
# Allowing it would make this an open proxy for anyone inside the allowed owners.
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
  --proxy "https://bcgov%2Faction-oc-runner:goodtoken@localhost:3129" \
  --proxy-cacert /etc/squid/tls/tls.crt \
  "http://fake-github.test:8080/repos/bcgov/action-oc-runner" 2>/dev/null)
[ "${code}" = "200" ] && fail "a non-CONNECT request must be refused; this would be an open proxy"
echo "  allowed caller, plain GET (no CONNECT) -> ${code:-blocked}"

# A blocked request proves little on its own, so confirm squid refused for the
# stated reason.
echo "== reasons =="
grep -q "TCP_TUNNEL.*bcgov/action-oc-runner" /squid.log \
  || { grep TCP_ /squid.log >&2; fail "expected a tunnel logged for the allowed caller"; }
echo "  allowed caller logged as TCP_TUNNEL"

# eviltoken authenticates fine under its own name, so its failure under the
# bcgov claim can only come from the repository check, not from a bad token.
grep -q "TCP_DENIED.*attacker/evil" /squid.log \
  || { grep TCP_ /squid.log >&2; fail "outside-org caller authenticated but was not denied by the owner ACL"; }
echo "  same token authenticates as attacker/evil, then denied by owner ACL"

grep -q "TCP_DENIED/407" /squid.log \
  || { grep TCP_ /squid.log >&2; fail "expected an auth challenge for the invalid token"; }
echo "  invalid token challenged with 407"

echo "proxy_test.sh: ok"
