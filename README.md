# ollama-agent-config

POSIX installer that discovers whatever models an Ollama-compatible endpoint currently serves, then writes and validates configs for **Claude Code**, **Junie**, and **Grok Build** on FreeBSD.

Repository: [revytechinc/ollama-agent-config](https://github.com/revytechinc/ollama-agent-config)

The published artifact lives in `dist/` on this repo. A dedicated download host can replace the `BASE` URL later.

## Install

One line: download the script and its checksum, verify, then run. There is no unverified `curl | sh`.

```sh
BASE=https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/dist; curl -fsSL "$BASE/install-ollama-agent-config.sh" -o install-ollama-agent-config.sh && curl -fsSL "$BASE/install-ollama-agent-config.sh.sha256" | sha256sum -c && sh ./install-ollama-agent-config.sh
```

Dry run:

```sh
BASE=https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/dist; curl -fsSL "$BASE/install-ollama-agent-config.sh" -o install-ollama-agent-config.sh && curl -fsSL "$BASE/install-ollama-agent-config.sh.sha256" | sha256sum -c && sh ./install-ollama-agent-config.sh --dry-run
```

From a clone:

```sh
git clone git@github.com:revytechinc/ollama-agent-config.git
cd ollama-agent-config
sh install.sh --dry-run
```

## What it does

- Reads `GET $OLLAMA_HOST/api/tags` (default `http://127.0.0.1:11434`)
- Drops embeddings
- Upserts Claude `~/.claude/settings.json` (Anthropic Messages base URL **without** `/v1`)
- Rewrites Junie `~/.junie/models/*.json` (OpenAI Chat Completions **full** `/v1/chat/completions`)
- Surgically upserts only `[model.ollama-direct-*]` in `~/.grok/config.toml` (OpenAI `/v1`)
- Always backups first. `--prune` is opt-in and runs only after every selected adapter succeeded.

On this host, `:11434` is nginx in front of a remote Ollama. The script never reads `/usr/local/etc/nginx/conf.d/ollama.conf`.

## Common flags

```
--dry-run
--validate-only
--tools=claude,junie,grok
--ollama-host=http://127.0.0.1:11434
--prefer-cloud
--prefer-local
--prune
--live-probe
```

## Develop

```sh
make test
make dist
```

The installer itself needs `python3` (3.11+). It does not call `curl`. The one-liner above uses `curl` only to download the published script and checksum.

## JetBrains IDE

GoLand / WebStorm: Settings → Tools → AI Assistant → Ollama at `http://127.0.0.1:11434`. This installer does not write IDE XML.

## License

[BSD 3-Clause](LICENSE). Copyright (c) 2026 REVYTECH, Inc.
