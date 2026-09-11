#!/usr/bin/env python3
"""Loopback shim that stamps GitHub identity onto OpenShift API traffic.

'oc' has no flag for custom headers, so it cannot prove which repository it is
running from. It talks plain HTTP to this shim on 127.0.0.1 instead; the shim
adds the identity headers and forwards to the relay over TLS, letting the relay
reject anything that is not a workflow in the expected organization.
"""

from __future__ import annotations

import argparse
import select
import socket
import ssl
import sys
import threading
from urllib.parse import urlsplit

# Injected per request; the relay validates the token against the GitHub API.
REPO_HEADER = "X-Action-Repository"
TOKEN_HEADER = "X-Action-Token"


def _pipe(a: socket.socket, b: socket.socket) -> None:
    socks = [a, b]
    try:
        while True:
            readable, _, _ = select.select(socks, [], [], 300)
            if not readable:
                return
            for src in readable:
                data = src.recv(65536)
                if not data:
                    return
                (b if src is a else a).sendall(data)
    except OSError:
        return
    finally:
        a.close()
        b.close()


def _rewrite(headers: bytes, host: str, repository: str, token: str) -> bytes:
    lines = headers.split(b"\r\n")
    out = [lines[0]]
    for line in lines[1:]:
        name = line.split(b":", 1)[0].strip().lower()
        # Drop hop-by-hop and spoofed identity headers from the client
        if name in (b"host", b"connection", b"proxy-connection",
                    REPO_HEADER.lower().encode(), TOKEN_HEADER.lower().encode()):
            continue
        out.append(line)
    out.append(f"Host: {host}".encode())
    out.append(f"{REPO_HEADER}: {repository}".encode())
    out.append(f"{TOKEN_HEADER}: {token}".encode())
    # One request per upstream connection keeps every request stamped
    out.append(b"Connection: close")
    return b"\r\n".join(out) + b"\r\n\r\n"


def _handle(client: socket.socket, args: argparse.Namespace, token: str) -> None:
    upstream = None
    try:
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                return
            buf += chunk
            if len(buf) > 65536:
                client.sendall(b"HTTP/1.1 431 Request Header Fields Too Large\r\n\r\n")
                return
        headers, _, body = buf.partition(b"\r\n\r\n")

        relay = urlsplit(args.relay)
        port = relay.port or 443
        raw = socket.create_connection((relay.hostname, port), timeout=30)
        upstream = ssl.create_default_context().wrap_socket(
            raw, server_hostname=relay.hostname
        )
        upstream.sendall(_rewrite(headers, relay.hostname, args.repository, token))
        if body:
            upstream.sendall(body)
        _pipe(client, upstream)
    except (OSError, ValueError) as err:
        print(f"relay_shim: {err}", file=sys.stderr, flush=True)
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
        except OSError:
            pass
    finally:
        client.close()
        if upstream is not None:
            upstream.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--relay", required=True, help="https://relay-host")
    parser.add_argument("--repository", required=True, help="owner/repo")
    parser.add_argument("--token-file", required=True, help="file holding the GitHub token")
    parser.add_argument("--listen-port", type=int, default=7443)
    args = parser.parse_args()

    if urlsplit(args.relay).scheme != "https":
        sys.exit("relay_shim: --relay must be https://")
    with open(args.token_file, encoding="utf-8") as handle:
        token = handle.read().strip()
    if not token:
        sys.exit("relay_shim: token file is empty")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", args.listen_port))
    server.listen(32)
    print(f"relay_shim: 127.0.0.1:{args.listen_port} -> {args.relay}", flush=True)
    while True:
        client, _ = server.accept()
        threading.Thread(target=_handle, args=(client, args, token), daemon=True).start()


if __name__ == "__main__":
    main()
