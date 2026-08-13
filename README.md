# ollama-agent-config

Configures **Claude Code**, **Junie**, and **Grok Build** to use your Ollama models.

```sh
curl -fsSL https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/install.sh | sh
```

```sh
curl -fsSL https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/install.sh | sh -s -- --dry-run
```

The piped `install.sh` downloads the release script, checks its SHA-256, then runs it.

## From a clone

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

Requires `python3` (3.11+).

## JetBrains IDE

GoLand / WebStorm: Settings → Tools → AI Assistant → Ollama at `http://127.0.0.1:11434`. This installer does not write IDE XML.

## License

[BSD 3-Clause](LICENSE). Copyright (c) 2026 REVYTECH, Inc.
