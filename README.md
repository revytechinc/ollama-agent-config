# ollama-agent-config

Configures **Claude Code**, **Junie**, and **Grok Build** to use your Ollama models.

```sh
curl -fsSL https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/install.sh | sh
```

## What it does

- Discovers installed agents (Claude, Junie, Grok) unless you pass `--tools=`
- Reads `GET $OLLAMA_HOST/api/tags` (default `http://127.0.0.1:11434`)
- Skips embedding models
- Configures **every remaining model** in Claude, Junie, and Grok
- Backs up existing files first; `--prune` is opt-in

## Flags

```
--dry-run
--validate-only
--tools=claude,junie,grok
--ollama-host=http://127.0.0.1:11434
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
