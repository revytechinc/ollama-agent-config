#!/usr/bin/env python3
"""Classify an Ollama /api/tags document and assign Claude/Junie roles."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SKIP_NEEDLES = (
    "nomic-embed",
    "qwen3-embedding",
    "bge-m3",
    "mxbai-embed",
    "all-minilm",
    "-embed",
    "embed-",
    ":embed",
)
CODER_NEEDLES = (
    "coder",
    "code",
    "devstral",
    "muse-glimmer",
    "opencoder",
    "wizardcoder",
    "north-mini-code",
)
KIMI_CODE = re.compile(r"kimi-k2.*-code", re.I)
FAST_TAGS = (":1b", ":3b", ":7b", ":8b")
FAST_NAMES = {
    "granite4.1:8b",
    "granite4.1:3b",
    "qwen2.5-coder:latest",
    "llama3.2:1b",
    "llama3.2:latest",
}
ALIASES = ("sonnet", "haiku", "opus", "fable")


def grok_slug(name: str) -> str:
    s = name.lower()
    for ch in ":/._":
        s = s.replace(ch, "-")
    return "ollama-direct-" + s


def junie_slug(name: str) -> str:
    return name.replace(":", "_")


def parse_b(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        n = float(value)
        if n >= 1_000_000:
            return n / 1_000_000_000.0
        return n
    s = str(value).strip().lower().replace(",", "")
    if not s:
        return None
    m = re.match(r"^([0-9]*\.?[0-9]+)\s*([a-z]+)?$", s)
    if not m:
        if s.isdigit():
            n = float(s)
            return n / 1_000_000_000.0 if n >= 1_000_000 else n
        return None
    n = float(m.group(1))
    unit = (m.group(2) or "").lower()
    if unit in ("t", "tb"):
        return n * 1000.0
    if unit in ("b", "bn"):
        return n
    if unit in ("m", "mb"):
        return n / 1000.0
    if unit in ("k", "kb"):
        return n / 1_000_000.0
    if not unit and n >= 1_000_000:
        return n / 1_000_000_000.0
    return n


def is_cloud(name: str) -> bool:
    return ":cloud" in name or name.endswith("-cloud")


def is_coder(name: str) -> bool:
    low = name.lower()
    if KIMI_CODE.search(low):
        return True
    return any(n in low for n in CODER_NEEDLES)


def is_skip(name: str, capabilities: list[str]) -> bool:
    caps = {c.lower() for c in capabilities}
    if "embedding" in caps or "rerank" in caps:
        return True
    low = name.lower()
    return any(n in low for n in SKIP_NEEDLES)


def is_fast(name: str, details: dict[str, Any], capabilities: list[str]) -> bool:
    if is_cloud(name):
        return False
    if name in FAST_NAMES:
        return True
    low = name.lower()
    if any(t in low for t in FAST_TAGS):
        return True
    pb = parse_b((details or {}).get("parameter_size"))
    return pb is not None and pb <= 9.0


def name_rank(name: str) -> tuple:
    """Lower is better when the user has no existing name to keep."""
    tag = name.rsplit(":", 1)[-1]
    latest = 0 if tag == "latest" else 1
    return (latest, len(name), name)


def _group_key(m: dict[str, Any]) -> tuple:
    digest = (m.get("digest") or "").strip()
    if digest:
        return ("d", digest)
    return ("n", m["name"])


def dedupe_models(
    models: list[dict[str, Any]],
    preferred: list[str] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    """One row per digest (or exact name). Keep a name the user already uses."""
    preferred = [n for n in (preferred or []) if n]
    groups: dict[tuple, list[dict[str, Any]]] = {}
    order: list[tuple] = []
    for m in models:
        key = _group_key(m)
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(m)

    out: list[dict[str, Any]] = []
    aliases: dict[str, str] = {}
    for key in order:
        group = groups[key]
        names = [x["name"] for x in group]
        winner_name = None
        for p in preferred:
            if p in names:
                winner_name = p
                break
        if winner_name is None:
            winner_name = min(names, key=name_rank)
        winner = next(x for x in group if x["name"] == winner_name)
        out.append(winner)
        for n in names:
            if n != winner_name:
                aliases[n] = winner_name
    return out, aliases


def load_models(
    tags: dict[str, Any],
    preferred: list[str] | None = None,
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    out = []
    for m in tags.get("models") or []:
        name = m.get("name") or m.get("model") or m.get("id")
        if not name:
            continue
        caps = list(m.get("capabilities") or [])
        details = m.get("details") or {}
        digest = m.get("digest") or m.get("id") or ""
        if isinstance(digest, str) and digest.startswith("sha256:"):
            digest = digest[len("sha256:") :]
        out.append(
            {
                "name": name,
                "digest": digest if isinstance(digest, str) else "",
                "capabilities": caps,
                "details": details,
                "size": m.get("size") or 0,
                "modified_at": m.get("modified_at") or "",
                "skip": is_skip(name, caps),
                "cloud": is_cloud(name),
                "coder": is_coder(name),
                "fast": is_fast(name, details, caps),
                "parse_b": parse_b(details.get("parameter_size")),
                "tools": "tools" in {c.lower() for c in caps},
            }
        )
    return dedupe_models(out, preferred)


def completion_models(models: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [m for m in models if not m["skip"]]


def haiku_score(m: dict[str, Any]) -> tuple:
    return (
        50 if m["tools"] else 0,
        20 if m["coder"] else 0,
        -(m["parse_b"] if m["parse_b"] is not None else 999),
    )


def pick_haiku(comp: list[dict[str, Any]]) -> str | None:
    locals_fast = [m for m in comp if m["fast"] and not m["cloud"]]
    for m in locals_fast:
        if m["name"] == "granite4.1:8b":
            return m["name"]
    if not locals_fast:
        locals_fast = [m for m in comp if not m["cloud"]]
    if not locals_fast:
        return comp[0]["name"] if comp else None
    return max(locals_fast, key=haiku_score)["name"]


def pick_sonnet(comp: list[dict[str, Any]], prefer_cloud: bool) -> str | None:
    names = {m["name"] for m in comp}
    if prefer_cloud:
        cloud = [m for m in comp if m["cloud"]]
        for m in cloud:
            if KIMI_CODE.search(m["name"]):
                return m["name"]
        cloud_coders = [m for m in cloud if m["coder"]]
        if cloud_coders:
            return cloud_coders[0]["name"]
        if cloud:
            return cloud[0]["name"]
    if "qwen2.5-coder:14b" in names:
        return "qwen2.5-coder:14b"
    local_coders = [
        m
        for m in comp
        if not m["cloud"]
        and m["coder"]
        and m["tools"]
        and m["parse_b"] is not None
        and 10 <= m["parse_b"] <= 35
    ]
    if local_coders:
        return max(local_coders, key=lambda m: m["parse_b"] or 0)["name"]
    local_coders = [m for m in comp if not m["cloud"] and m["coder"]]
    if local_coders:
        return max(local_coders, key=lambda m: m["parse_b"] or 0)["name"]
    local_tools = [m for m in comp if not m["cloud"] and m["tools"]]
    if local_tools:
        return max(local_tools, key=lambda m: m["parse_b"] or 0)["name"]
    local_all = [m for m in comp if not m["cloud"]]
    if local_all:
        return local_all[0]["name"]
    return comp[0]["name"] if comp else None


def pick_opus(comp: list[dict[str, Any]]) -> str | None:
    local_coders = [m for m in comp if not m["cloud"] and m["coder"] and m["tools"]]
    if local_coders:
        def key(m):
            pb = m["parse_b"] or 0
            latest = 1 if m["name"].endswith(":latest") else 0
            return (pb, latest)

        return max(local_coders, key=key)["name"]
    local_tools = [m for m in comp if not m["cloud"] and m["tools"]]
    if local_tools:
        return max(local_tools, key=lambda m: m["parse_b"] or 0)["name"]
    local_all = [m for m in comp if not m["cloud"]]
    return local_all[0]["name"] if local_all else (comp[0]["name"] if comp else None)


def pick_fable(comp: list[dict[str, Any]]) -> str | None:
    cands = [
        m
        for m in comp
        if not m["cloud"] and m["tools"] and m["parse_b"] is not None and m["parse_b"] >= 20
    ]
    if cands:
        return max(cands, key=lambda m: m["modified_at"] or "")["name"]
    cands = [m for m in comp if not m["cloud"] and m["tools"]]
    if cands:
        return max(cands, key=lambda m: m["modified_at"] or "")["name"]
    local_all = [m for m in comp if not m["cloud"]]
    return local_all[0]["name"] if local_all else (comp[0]["name"] if comp else None)


def pick_cloud_coder(comp: list[dict[str, Any]]) -> str | None:
    cloud = [m for m in comp if m["cloud"]]
    for m in cloud:
        if KIMI_CODE.search(m["name"]):
            return m["name"]
    cloud_coders = [m for m in cloud if m["coder"]]
    if cloud_coders:
        return cloud_coders[0]["name"]
    return cloud[0]["name"] if cloud else None


def faster_for_profile(profile_id: str, haiku: str, comp: list[dict[str, Any]]) -> str:
    names = {m["name"] for m in comp}
    if profile_id != haiku:
        return haiku
    if "granite4.1:3b" in names and "granite4.1:3b" != profile_id:
        return "granite4.1:3b"
    if "qwen2.5-coder:latest" in names and "qwen2.5-coder:latest" != profile_id:
        return "qwen2.5-coder:latest"
    others = [m for m in comp if m["name"] != profile_id and m["fast"] and not m["cloud"]]
    if others:
        return max(others, key=haiku_score)["name"]
    others = [m for m in comp if m["name"] != profile_id]
    return others[0]["name"] if others else profile_id


def assign_roles(
    models: list[dict[str, Any]],
    *,
    prefer_cloud: bool = False,
    prefer_local: bool = False,
    overrides: dict[str, str] | None = None,
) -> dict[str, str]:
    comp = completion_models(models)
    overrides = overrides or {}
    haiku = overrides.get("haiku") or pick_haiku(comp)
    sonnet = overrides.get("sonnet") or pick_sonnet(comp, prefer_cloud)
    opus = overrides.get("opus") or pick_opus(comp)
    fable = overrides.get("fable") or pick_fable(comp)
    roles = {
        "haiku": haiku or "",
        "sonnet": sonnet or "",
        "opus": opus or "",
        "fable": fable or "",
    }
    return roles


def classify_payload(
    tags: dict[str, Any],
    *,
    prefer_cloud: bool = False,
    prefer_local: bool = False,
    overrides: dict[str, str] | None = None,
    junie_primary: str | None = None,
    default_model: str | None = None,
    preferred: list[str] | None = None,
) -> dict[str, Any]:
    models, aliases = load_models(tags, preferred)
    comp = completion_models(models)
    ov = dict(overrides or {})
    if default_model and "sonnet" not in ov:
        ov["sonnet"] = default_model
    roles = assign_roles(models, prefer_cloud=prefer_cloud, prefer_local=prefer_local, overrides=ov)

    primary = None
    if junie_primary == "cloud":
        primary = pick_cloud_coder(comp) or roles["sonnet"]
    elif junie_primary == "local":
        primary = roles["opus"] if roles["opus"] and not is_cloud(roles["opus"]) else roles["sonnet"]
    elif junie_primary:
        primary = junie_primary
    elif default_model:
        primary = default_model
    elif prefer_local:
        primary = roles["opus"] if roles["opus"] and not is_cloud(roles["opus"]) else roles["sonnet"]
    else:
        primary = pick_cloud_coder(comp) or roles["sonnet"]

    return {
        "total": len(models),
        "completion": [m["name"] for m in comp],
        "skip": [m["name"] for m in models if m["skip"]],
        "aliases": aliases,
        "roles": roles,
        "junie_primary": primary or "",
        "junie_local": roles["opus"] or roles["sonnet"],
        "models": models,
    }


def gather_prefer_names(
    claude: str | None = None,
    junie_dir: str | None = None,
    grok: str | None = None,
) -> list[str]:
    names: list[str] = []
    if claude and Path(claude).is_file():
        try:
            am = json.loads(Path(claude).read_text(encoding="utf-8")).get("availableModels") or []
        except (OSError, json.JSONDecodeError):
            am = []
        names.extend(n for n in am if isinstance(n, str))
    if junie_dir and Path(junie_dir).is_dir():
        for p in sorted(Path(junie_dir).glob("*.json")):
            try:
                mid = json.loads(p.read_text(encoding="utf-8")).get("id")
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(mid, str):
                names.append(mid)
    if grok and Path(grok).is_file():
        try:
            text = Path(grok).read_text(encoding="utf-8")
        except OSError:
            text = ""
        for m in re.finditer(r'^\s*model\s*=\s*"([^"]+)"', text, re.M):
            names.append(m.group(1))
    return names


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="catalog.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("classify")
    c.add_argument("--tags", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--prefer-cloud", action="store_true")
    c.add_argument("--prefer-local", action="store_true")
    c.add_argument("--haiku-model")
    c.add_argument("--sonnet-model")
    c.add_argument("--opus-model")
    c.add_argument("--fable-model")
    c.add_argument("--default-model")
    c.add_argument("--junie-primary")
    c.add_argument("--prefer-names", help="JSON list of names already in the user's config")
    g = sub.add_parser("gather-names")
    g.add_argument("--claude")
    g.add_argument("--junie-dir")
    g.add_argument("--grok")
    g.add_argument("--out", required=True)
    args = p.parse_args(argv)
    if args.cmd == "gather-names":
        names = gather_prefer_names(args.claude, args.junie_dir, args.grok)
        Path(args.out).write_text(json.dumps(names) + "\n", encoding="utf-8")
        return 0
    if args.cmd == "classify":
        tags = json.loads(open(args.tags, encoding="utf-8").read())
        ov = {}
        if args.haiku_model:
            ov["haiku"] = args.haiku_model
        if args.sonnet_model:
            ov["sonnet"] = args.sonnet_model
        if args.opus_model:
            ov["opus"] = args.opus_model
        if args.fable_model:
            ov["fable"] = args.fable_model
        preferred = None
        if args.prefer_names:
            preferred = json.loads(open(args.prefer_names, encoding="utf-8").read())
        payload = classify_payload(
            tags,
            prefer_cloud=args.prefer_cloud,
            prefer_local=args.prefer_local,
            overrides=ov,
            junie_primary=args.junie_primary,
            default_model=args.default_model,
            preferred=preferred,
        )
        slim = {
            "total": payload["total"],
            "completion": payload["completion"],
            "skip": payload["skip"],
            "aliases": payload["aliases"],
            "roles": payload["roles"],
            "junie_primary": payload["junie_primary"],
            "junie_local": payload["junie_local"],
        }
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(slim, f, indent=2)
            f.write("\n")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
