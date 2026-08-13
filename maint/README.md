# Maintainer notes

Users install via GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/revytechinc/ollama-agent-config/main/install.sh | sh
```

They do not need nginx.

Optional local static publish (us only):

```sh
make dist
sh maint/publish.sh
```

Snippet: `maint/nginx-install-scripts.conf`
