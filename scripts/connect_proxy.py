#!/usr/bin/env python3
"""Local HTTP CONNECT proxy for CI. Binds 127.0.0.1. Not a general-purpose proxy."""

from __future__ import annotations

import argparse
import select
import socket
import threading


def _tunnel(a: socket.socket, b: socket.socket) -> None:
    sockets = [a, b]
    try:
        while True:
            readable, _, _ = select.select(sockets, [], [], 30)
            if not readable:
                return
            for src in readable:
                data = src.recv(65536)
                if not data:
                    return
                dst = b if src is a else a
                dst.sendall(data)
    except OSError:
        return
    finally:
        a.close()
        b.close()


def _handle(client: socket.socket, log_path: str) -> None:
    try:
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = client.recv(4096)
            if not chunk:
                return
            buf += chunk
            if len(buf) > 8192:
                return
        request_line = buf.split(b"\r\n", 1)[0].decode("ascii", "replace")
        parts = request_line.split()
        if len(parts) < 2 or parts[0] != "CONNECT":
            client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n")
            return
        host, port_s = parts[1].rsplit(":", 1)
        port = int(port_s)
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(f"CONNECT {host}:{port}\n")
            log.flush()
        remote = socket.create_connection((host, port), timeout=20)
        client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        _tunnel(client, remote)
    except (OSError, ValueError):
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
        except OSError:
            pass
        client.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8888)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen, args.port))
    server.listen(16)
    with open(args.log, "a", encoding="utf-8") as log:
        log.write(f"listening {args.listen}:{args.port}\n")
    while True:
        client, _addr = server.accept()
        threading.Thread(target=_handle, args=(client, args.log), daemon=True).start()


if __name__ == "__main__":
    main()
