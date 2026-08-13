#!/usr/bin/env python3
"""Thin urllib GET for catalog fetch and endpoint probes."""
from __future__ import annotations

import argparse
import sys
import urllib.error
import urllib.request


def get(url: str, out: str | None, bearer: str | None, timeout: float) -> int:
    req = urllib.request.Request(url, method="GET")
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = resp.read()
            if resp.status >= 400:
                return 1
            if out:
                with open(out, "wb") as f:
                    f.write(data)
            return 0
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError):
        return 1


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="fetch.py")
    p.add_argument("cmd", choices=("get", "check"))
    p.add_argument("url")
    p.add_argument("--out")
    p.add_argument("--bearer")
    p.add_argument("--timeout", type=float, default=15.0)
    args = p.parse_args(argv)
    if args.cmd == "get":
        if not args.out:
            print("fetch.py get requires --out", file=sys.stderr)
            return 2
        return get(args.url, args.out, args.bearer, args.timeout)
    if args.cmd == "check":
        return get(args.url, None, args.bearer, args.timeout)
    return 2


if __name__ == "__main__":
    sys.exit(main())
