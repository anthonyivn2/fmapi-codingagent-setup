# CLAUDE.md

## Project Overview

This repo contains a single bash setup script (`setup_fmapi_cc.sh`) that configures Claude Code to use Anthropic models served through Databricks Foundation Model API (FMAPI). There is no application code — just the script and documentation.

## Repository Structure

```
setup_fmapi_cc.sh   # Main setup script (bash)
README.md           # User-facing documentation
CLAUDE.md           # This file
.gitignore          # Ignores .claude/settings.json and Python artifacts
```

## Key Concepts

- **`setup_fmapi_cc.sh`** — Interactive bash script that installs dependencies (Claude Code, Databricks CLI), authenticates via OAuth, writes `.claude/settings.json`, and adds a `dbx-fmapi-claude` shell wrapper to the user's RC file.
- **`dbx-fmapi-claude`** — A shell function injected into `~/.zshrc` or `~/.bashrc` that wraps the `claude` command with automatic Databricks OAuth token refresh.
- **`.claude/settings.json`** — Claude Code configuration file containing environment variables (`ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, etc.) that route requests through Databricks FMAPI.

## Development Guidelines

- This is a **bash-only** project. No Python, no package manager, no build step.
- The script must remain **idempotent** — re-running it updates existing config rather than duplicating entries.
- The shell wrapper block in the RC file is delimited by `# >>> dbx-fmapi-claude wrapper >>>` and `# <<< dbx-fmapi-claude wrapper <<<` markers. Always preserve this convention.
- The script uses `set -euo pipefail` for strict error handling. Any new code must work under these constraints.
- **Dependencies**: `brew`, `jq`, `curl`, `databricks` CLI. Do not introduce additional dependencies without good reason.
- **Never commit** `.claude/settings.json` — it contains OAuth tokens.
- Use [ShellCheck](https://www.shellcheck.net/) conventions when editing the script.

## Testing Changes

There are no automated tests. To verify changes:

1. Run `bash setup_fmapi_cc.sh` end-to-end with a real Databricks workspace.
2. Confirm `.claude/settings.json` is written correctly with `jq . .claude/settings.json`.
3. Open a new terminal and run `dbx-fmapi-claude` to verify the wrapper works.
4. Run the script a second time to confirm idempotency (wrapper is replaced, settings are merged).

## Abbreviations

FMAPI: Foundational Model API