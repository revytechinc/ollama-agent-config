#!/usr/bin/env python3
"""Frozen JSON merge/check CLI for Claude and Junie configs."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Import sibling catalog when running from a real file path.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))
from catalog import (  # noqa: E402
    ALIASES,
    faster_for_profile,
    grok_slug,
    is_skip,
    junie_slug,
    load_models,
)

CLAUDE_ENV_KEYS = [
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION",
    "ANTHROPIC_DEFAULT_FABLE_MODEL",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY",
    "API_TIMEOUT_MS",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
    "DISABLE_TELEMETRY",
    "DISABLE_ERROR_REPORTING",
    "DISABLE_PROMPT_CACHING",
]

JUNIE_PROFILE_KEYS = ("baseUrl", "id", "apiType", "apiKey", "temperature", "fasterModel")


def _atomic_write(path: Path, data: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    if tmp.exists():
        tmp.unlink()
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
        os.replace(str(tmp), str(path))
    except Exception:
        try:
            os.unlink(str(tmp))
        except OSError:
            pass
        raise


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _dump(obj: object) -> str:
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def stable_merge_available(existing: list, completion: list[str], skip: list[str]) -> list[str]:
    alias_set = set(ALIASES)
    skip_set = set(skip)
    completion_set = set(completion)
    out: list[str] = list(ALIASES)
    seen = set(out)
    for name in existing:
        if not isinstance(name, str):
            continue
        if name in alias_set:
            continue
        if name in skip_set or is_skip(name, []):
            continue
        if name in completion_set or name not in skip_set:
            if name not in seen:
                out.append(name)
                seen.add(name)
    for name in completion:
        if name not in seen and name not in alias_set:
            out.append(name)
            seen.add(name)
    return out


def merge_claude(existing: dict, env_updates: dict, models: dict) -> dict:
    out = dict(existing) if isinstance(existing, dict) else {}
    env = dict(out.get("env") or {})
    for k, v in env_updates.items():
        env[k] = v
    out["env"] = env
    prev = out.get("availableModels") or []
    if not isinstance(prev, list):
        prev = []
    out["availableModels"] = stable_merge_available(
        prev, models.get("completion") or [], models.get("skip") or []
    )
    return out


def merge_junie_profile(existing: dict, model_id: str, base_url: str, faster: str) -> dict:
    return {
        "baseUrl": base_url,
        "id": model_id,
        "apiType": "OpenAICompletion",
        "apiKey": "ollama",
        "temperature": 0.6,
        "fasterModel": {"id": faster},
    }


def merge_junie_config(existing: dict, model: str) -> dict:
    out = dict(existing) if isinstance(existing, dict) else {}
    cur = out.get("model")
    if cur is None or (isinstance(cur, str) and cur.startswith("custom:ollama")):
        out["model"] = model
    if "model-default-locations" not in out:
        out["model-default-locations"] = True
    if "auto-update" not in out:
        out["auto-update"] = True
    return out


def check_claude(path: Path) -> int:
    data = _load_json(path)
    env = data.get("env") or {}
    base = env.get("ANTHROPIC_BASE_URL") or ""
    if base.rstrip("/").endswith("/v1"):
        print("ANTHROPIC_BASE_URL must not end with /v1", file=sys.stderr)
        return 1
    if not env.get("ANTHROPIC_AUTH_TOKEN"):
        print("ANTHROPIC_AUTH_TOKEN missing", file=sys.stderr)
        return 1
    models = data.get("availableModels") or []
    if models[:4] != list(ALIASES):
        print("availableModels must start with sonnet,haiku,opus,fable", file=sys.stderr)
        return 1
    if len(models) != len(set(models)):
        print("availableModels has duplicates", file=sys.stderr)
        return 1
    return 0


def check_junie_profile(path: Path) -> int:
    data = _load_json(path)
    for k in ("baseUrl", "id", "apiType"):
        if k not in data:
            print(f"missing {k}", file=sys.stderr)
            return 1
    if data.get("apiType") != "OpenAICompletion":
        print("apiType must be OpenAICompletion", file=sys.stderr)
        return 1
    if not str(data.get("baseUrl", "")).endswith("/v1/chat/completions"):
        print("baseUrl must end with /v1/chat/completions", file=sys.stderr)
        return 1
    return 0


def check_junie_config(path: Path) -> int:
    data = _load_json(path)
    model = data.get("model")
    if not isinstance(model, str) or not model.startswith("custom:ollama"):
        print("model must be custom:ollama*", file=sys.stderr)
        return 1
    return 0


def cmd_merge_claude(args) -> int:
    existing = _load_json(Path(args.file))
    env_updates = json.loads(Path(args.env_json).read_text(encoding="utf-8"))
    models = json.loads(Path(args.models_json).read_text(encoding="utf-8"))
    out = merge_claude(existing, env_updates, models)
    dest = Path(args.out or args.file)
    _atomic_write(dest, _dump(out), 0o644)
    return 0


def cmd_merge_junie_profile(args) -> int:
    existing = _load_json(Path(args.file)) if Path(args.file).exists() else {}
    out = merge_junie_profile(existing, args.id, args.base_url, args.faster)
    dest = Path(args.out or args.file)
    _atomic_write(dest, _dump(out), 0o644)
    return 0


def cmd_merge_junie_config(args) -> int:
    existing = _load_json(Path(args.file))
    out = merge_junie_config(existing, args.model)
    dest = Path(args.out or args.file)
    _atomic_write(dest, _dump(out), 0o644)
    return 0


def cmd_write_junie_all(args) -> int:
    tags = json.loads(Path(args.tags).read_text(encoding="utf-8"))
    cls = json.loads(Path(args.models_json).read_text(encoding="utf-8"))
    models = load_models(tags)
    from catalog import completion_models

    comp = completion_models(models)
    dest = Path(args.models_dir)
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    for name in cls.get("completion") or []:
        faster = faster_for_profile(name, args.haiku, comp)
        merge_path = dest / (junie_slug(name) + ".json")
        _atomic_write(
            merge_path,
            _dump(merge_junie_profile({}, name, args.base_url, faster)),
            0o644,
        )
        written += 1
    for fname, mid in (("ollama.json", args.primary), ("ollama-local.json", args.local)):
        faster = faster_for_profile(mid, args.haiku, comp)
        _atomic_write(
            dest / fname,
            _dump(merge_junie_profile({}, mid, args.base_url, faster)),
            0o644,
        )
        written += 1
    print(f"junie: rewrite {written} managed profiles")
    return 0


def cmd_check(args) -> int:
    path = Path(args.file)
    if args.schema == "claude":
        return check_claude(path)
    if args.schema == "junie-profile":
        return check_junie_profile(path)
    if args.schema == "junie-config":
        return check_junie_config(path)
    return 2


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="json_util.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("merge-claude")
    c.add_argument("--file", required=True)
    c.add_argument("--env-json", required=True)
    c.add_argument("--models-json", required=True)
    c.add_argument("--out")

    j = sub.add_parser("merge-junie-profile")
    j.add_argument("--file", required=True)
    j.add_argument("--id", required=True)
    j.add_argument("--base-url", required=True)
    j.add_argument("--faster", required=True)
    j.add_argument("--out")

    jc = sub.add_parser("merge-junie-config")
    jc.add_argument("--file", required=True)
    jc.add_argument("--model", required=True)
    jc.add_argument("--out")

    wj = sub.add_parser("write-junie-all")
    wj.add_argument("--models-dir", required=True)
    wj.add_argument("--tags", required=True)
    wj.add_argument("--models-json", required=True)
    wj.add_argument("--haiku", required=True)
    wj.add_argument("--primary", required=True)
    wj.add_argument("--local", required=True)
    wj.add_argument("--base-url", required=True)

    ch = sub.add_parser("check")
    ch.add_argument("--file", required=True)
    ch.add_argument("--schema", required=True, choices=("claude", "junie-profile", "junie-config"))

    args = p.parse_args(argv)
    try:
        if args.cmd == "merge-claude":
            return cmd_merge_claude(args)
        if args.cmd == "merge-junie-profile":
            return cmd_merge_junie_profile(args)
        if args.cmd == "merge-junie-config":
            return cmd_merge_junie_config(args)
        if args.cmd == "write-junie-all":
            return cmd_write_junie_all(args)
        if args.cmd == "check":
            return cmd_check(args)
    except json.JSONDecodeError as e:
        print(f"json parse error: {e}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
