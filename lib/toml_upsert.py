#!/usr/bin/env python3
"""Byte-span upsert of [model.ollama-direct-*] tables. Never tomllib.dump."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tomllib
from pathlib import Path

HEADER_RE = re.compile(r"^\[\[?[^\]]+\]\]?\s*$")
MANAGED_RE = re.compile(r"^\[model\.ollama-direct-[A-Za-z0-9-]+\]\s*$")
KEY_RE = re.compile(r"^(\s*)(model|name|base_url|api_key)\s*=")
DEFAULT_RE = re.compile(r"^(\s*)default\s*=")


def grok_slug(name: str) -> str:
    s = name.lower()
    for ch in ":/._":
        s = s.replace(ch, "-")
    return "ollama-direct-" + s


def parse_spans(text: str) -> tuple[list[dict], list[str]]:
    if text and not text.endswith("\n"):
        text = text + "\n"
    lines = text.split("\n")
    # trailing split empty from final newline
    if lines and lines[-1] == "":
        lines = lines[:-1]
    headers = [i for i, line in enumerate(lines) if HEADER_RE.match(line)]
    spans = []
    for idx, start in enumerate(headers):
        end = headers[idx + 1] if idx + 1 < len(headers) else len(lines)
        spans.append(
            {
                "start": start,
                "end": end,
                "header": lines[start],
                "lines": lines[start:end],
            }
        )
    return spans, lines


def body_stripped(span_lines: list[str]) -> str:
    body = list(span_lines)
    while body and body[-1].strip() == "":
        body.pop()
    return "\n".join(body)


def foreign_identity(spans: list[dict]) -> list[tuple[str, int, str]]:
    counts: dict[str, int] = {}
    out = []
    for s in spans:
        h = s["header"]
        idx = counts.get(h, 0)
        counts[h] = idx + 1
        if not MANAGED_RE.match(h):
            out.append((h, idx, body_stripped(s["lines"])))
    return out


def managed_model_value(span_lines: list[str]) -> str | None:
    for line in span_lines[1:]:
        m = re.match(r'^\s*model\s*=\s*"([^"]*)"', line)
        if m:
            return m.group(1)
        m = re.match(r"^\s*model\s*=\s*'([^']*)'", line)
        if m:
            return m.group(1)
    return None


def rewrite_managed(span_lines: list[str], name: str, host: str) -> tuple[list[str], str | None]:
    """Return new lines and optional warning."""
    header = span_lines[0]
    rest = span_lines[1:]
    warn = None
    seen = {"model": False, "name": False, "base_url": False, "api_key": False, "env_key": False}
    new_rest: list[str] = []
    canon = {
        "model": f'model = "{name}"',
        "name": f'name = "{name} (Ollama direct)"',
        "base_url": f'base_url = "{host.rstrip("/")}/v1"',
    }
    for line in rest:
        if re.match(r"^\s*env_key\s*=", line):
            seen["env_key"] = True
            new_rest.append(line)
            continue
        km = KEY_RE.match(line)
        if not km:
            new_rest.append(line)
            continue
        indent, key = km.group(1), km.group(2)
        seen[key] = True
        if key == "api_key":
            val = ""
            qm = re.search(r'=\s*"([^"]*)"', line)
            if qm:
                val = qm.group(1)
            else:
                qm = re.search(r"=\s*'([^']*)'", line)
                val = qm.group(1) if qm else line.split("=", 1)[-1].strip()
            if val == "ollama":
                new_rest.append(line)
            else:
                warn = f"refusing to overwrite non-dummy api_key in {header}"
                new_rest.append(line)
            continue
        new_rest.append(f"{indent}{canon[key]}")
    insert_at = 0
    for key in ("model", "name", "base_url"):
        if not seen[key]:
            new_rest.insert(insert_at, canon[key])
            insert_at += 1
    if not seen["api_key"] and not seen["env_key"]:
        # after base_url if present
        placed = False
        out = []
        for line in new_rest:
            out.append(line)
            if re.match(r"^\s*base_url\s*=", line) and not placed:
                out.append('api_key = "ollama"')
                placed = True
        if not placed:
            out.append('api_key = "ollama"')
        new_rest = out
    # drop trailing blanks then one blank for separator handled by rebuild
    while new_rest and new_rest[-1].strip() == "":
        new_rest.pop()
    return [header] + new_rest, warn


def new_table(name: str, host: str) -> list[str]:
    base = host.rstrip("/") + "/v1"
    return [
        f"[model.{grok_slug(name)}]",
        f'model = "{name}"',
        f'name = "{name} (Ollama direct)"',
        f'base_url = "{base}"',
        'api_key = "ollama"',
    ]


def rewrite_models_default(span_lines: list[str], slug: str) -> list[str]:
    header = span_lines[0]
    rest = span_lines[1:]
    found = False
    out = []
    for line in rest:
        if DEFAULT_RE.match(line) and not found:
            indent = DEFAULT_RE.match(line).group(1)
            out.append(f'{indent}default = "{slug}"')
            found = True
        else:
            out.append(line)
    if not found:
        out = [f'default = "{slug}"'] + out
    while out and out[-1].strip() == "":
        out.pop()
    return [header] + out


def atomic_write(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    if tmp.exists():
        tmp.unlink()
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(str(tmp), str(path))
    except Exception:
        try:
            os.unlink(str(tmp))
        except OSError:
            pass
        raise


def rebuild(
    lines: list[str],
    spans: list[dict],
    replacements: dict[int, list[str]],
    inserts_before: int | None,
    new_spans: list[list[str]],
) -> str:
    """Rebuild file. replacements keyed by span index. new_spans inserted before inserts_before span index."""
    out: list[str] = []
    first = spans[0]["start"] if spans else len(lines)
    out.extend(lines[:first])
    for i, span in enumerate(spans):
        if inserts_before is not None and i == inserts_before:
            for ns in new_spans:
                if out and out[-1].strip() != "":
                    out.append("")
                out.extend(ns)
                out.append("")
        if i in replacements:
            block = replacements[i]
            while block and block[-1].strip() == "":
                block = block[:-1]
            out.extend(block)
            out.append("")
        else:
            out.extend(span["lines"])
    if inserts_before is None and new_spans:
        if out and out[-1].strip() != "":
            out.append("")
        for ns in new_spans:
            out.extend(ns)
            out.append("")
    # trim extra trailing blanks to a single trailing newline
    while out and out[-1] == "":
        out.pop()
    return "\n".join(out) + "\n"


def upsert(path: Path, catalog: list[dict], host: str, prune: bool, set_default: str | None) -> int:
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        print("file is not valid UTF-8", file=sys.stderr)
        return 1
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        print(f"toml parse error before edit: {e}", file=sys.stderr)
        return 1

    names = [c["name"] for c in catalog if c.get("name")]
    name_set = set(names)
    slugs = {grok_slug(n): n for n in names}

    spans, lines = parse_spans(text)
    before_id = foreign_identity(spans)

    replacements: dict[int, list[str]] = {}
    drop: set[int] = set()
    seen_slugs: set[str] = set()

    for i, span in enumerate(spans):
        h = span["header"]
        if not MANAGED_RE.match(h):
            continue
        slug = h[len("[model.") : -1].strip()
        if slug.endswith("]"):
            slug = slug[:-1]
        # header is [model.ollama-direct-foo]
        m = re.match(r"^\[model\.(ollama-direct-[A-Za-z0-9-]+)\]\s*$", h)
        if not m:
            continue
        slug = m.group(1)
        model_val = managed_model_value(span["lines"])
        if prune and (model_val is None or model_val not in name_set):
            drop.add(i)
            print(f"- [model.{slug}]")
            continue
        # rewrite if we know this slug or model
        target_name = slugs.get(slug) or (model_val if model_val in name_set else None)
        if target_name is None:
            continue
        seen_slugs.add(grok_slug(target_name))
        new_lines, warn = rewrite_managed(span["lines"], target_name, host)
        replacements[i] = new_lines
        print(f"~ [model.{slug}]")
        if warn:
            print(warn, file=sys.stderr)

    new_tables: list[list[str]] = []
    for n in names:
        slug = grok_slug(n)
        if slug in seen_slugs:
            continue
        # also skip if a span exists we didn't mark (shouldn't)
        already = any(
            re.match(rf"^\[model\.{re.escape(slug)}\]\s*$", s["header"])
            for s in spans
            if s not in []
        )
        if already and grok_slug(n) in seen_slugs:
            continue
        if any(re.match(rf"^\[model\.{re.escape(slug)}\]\s*$", s["header"]) for s in spans):
            continue
        new_tables.append(new_table(n, host))
        print(f"+ [model.{slug}]")

    models_idx = None
    for i, span in enumerate(spans):
        if span["header"].strip() == "[models]":
            models_idx = i
            break

    if set_default and models_idx is not None and models_idx not in drop:
        src = replacements.get(models_idx, spans[models_idx]["lines"])
        replacements[models_idx] = rewrite_models_default(src, set_default)

    # apply drops by skipping those span indices
    kept = []
    index_map = {}
    for i, span in enumerate(spans):
        if i in drop:
            continue
        index_map[i] = len(kept)
        kept.append(span)

    repl2 = {}
    for old_i, block in replacements.items():
        if old_i in drop:
            continue
        repl2[index_map[old_i]] = block

    insert_at = index_map[models_idx] if models_idx is not None and models_idx not in drop else None

    new_text = rebuild(lines, kept, repl2, insert_at, new_tables)

    try:
        tomllib.loads(new_text)
    except tomllib.TOMLDecodeError as e:
        print(f"toml parse error after edit: {e}", file=sys.stderr)
        return 1

    after_spans, _ = parse_spans(new_text)
    after_id = foreign_identity(after_spans)

    def normalize_expected(ident):
        if not set_default:
            return ident
        out = []
        for h, idx, body in ident:
            if h.strip() == "[models]":
                # re-apply default rewrite to expected body for comparison
                blines = body.split("\n")
                rewritten = rewrite_models_default(blines, set_default)
                out.append((h, idx, body_stripped(rewritten)))
            else:
                out.append((h, idx, body))
        return out

    expected = normalize_expected(before_id)
    # prune/drop of managed only — foreign list should match
    if expected != after_id:
        # allow [models] change only when set_default
        print("foreign-span identity check failed", file=sys.stderr)
        exp = {(h, i) for h, i, _ in expected}
        got = {(h, i) for h, i, _ in after_id}
        if exp != got:
            print(f"  headers expected {sorted(exp)} got {sorted(got)}", file=sys.stderr)
        else:
            for a, b in zip(expected, after_id):
                if a != b:
                    print(f"  body mismatch for {a[0]!r}#{a[1]}", file=sys.stderr)
                    break
        return 1

    atomic_write(path, new_text.encode("utf-8"))
    return 0


def check(path: Path, catalog: list[dict], host: str) -> int:
    text = path.read_text(encoding="utf-8")
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        print(f"toml parse error: {e}", file=sys.stderr)
        return 1
    spans, _ = parse_spans(text)
    names = [c["name"] for c in catalog if c.get("name")]
    have = {}
    for s in spans:
        m = re.match(r"^\[model\.(ollama-direct-[A-Za-z0-9-]+)\]\s*$", s["header"])
        if not m:
            continue
        have[managed_model_value(s["lines"])] = s
    missing = [n for n in names if n not in have]
    if missing:
        print("missing tables: " + ", ".join(missing[:8]), file=sys.stderr)
        return 1
    want_base = host.rstrip("/") + "/v1"
    for n, s in have.items():
        if n not in names:
            continue
        joined = "\n".join(s["lines"])
        if "/v1" not in joined:
            print(f"base_url missing /v1 in {s['header']}", file=sys.stderr)
            return 1
        if "api_key" not in joined and "env_key" not in joined:
            print(f"no api_key/env_key in {s['header']}", file=sys.stderr)
            return 1
    _ = want_base
    return 0


def load_catalog(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and "completion" in data:
        return [{"name": n} for n in data["completion"]]
    if isinstance(data, dict) and "models" in data:
        return [{"name": m.get("name")} for m in data["models"] if m.get("name")]
    raise SystemExit("catalog must be a list of {name} or classify JSON")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="toml_upsert.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    u = sub.add_parser("upsert")
    u.add_argument("--file", required=True)
    u.add_argument("--catalog", required=True)
    u.add_argument("--host", required=True)
    u.add_argument("--prune", action="store_true")
    u.add_argument("--set-default")
    c = sub.add_parser("check")
    c.add_argument("--file", required=True)
    c.add_argument("--catalog", required=True)
    c.add_argument("--host", required=True)
    args = p.parse_args(argv)
    catalog = load_catalog(Path(args.catalog))
    if args.cmd == "upsert":
        return upsert(Path(args.file), catalog, args.host, args.prune, args.set_default)
    if args.cmd == "check":
        return check(Path(args.file), catalog, args.host)
    return 2


if __name__ == "__main__":
    sys.exit(main())
