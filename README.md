# ollama-agent-config

POSIX installer that discovers whatever models an Ollama-compatible endpoint currently serves, then writes and validates configs for **Claude Code**, **Junie**, and **Grok Build** on FreeBSD.

Repository: [revytechinc/ollama-agent-config](https://github.com/revytechinc/ollama-agent-config)

Published (after `make publish`) at:

`https://freedev007.cloudbsd.org/install-ollama-agent-config.sh`

## Safe install

```sh
curl -fsSL https://freedev007.cloudbsd.org/install-ollama-agent-config.sh -o install-ollama-agent-config.sh
curl -fsSL https://freedev007.cloudbsd.org/install-ollama-agent-config.sh.sha256 -o install-ollama-agent-config.sh.sha256
sha256sum -c install-ollama-agent-config.sh.sha256
sh ./install-ollama-agent-config.sh
```

Convenience (no checksum):

```sh
curl -fsSL https://freedev007.cloudbsd.org/install-ollama-agent-config.sh | sh
```

Dry run:

```sh
curl -fsSL https://freedev007.cloudbsd.org/install-ollama-agent-config.sh | sh -s -- --dry-run
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

Requires `python3` (3.11+), `curl`. No `jq`, no bash.

## JetBrains IDE

GoLand / WebStorm: Settings → Tools → AI Assistant → Ollama at `http://127.0.0.1:11434`. This installer does not write IDE XML.
