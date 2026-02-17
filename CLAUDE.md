# CLAUDE.md

## Project Overview

This repo contains setup scripts that configure coding agents to use foundation models served through Databricks Foundation Model API (FMAPI). Currently only Claude Code is supported, with OpenAI Codex and Gemini CLI planned. There is no application code — just setup scripts and documentation.

## Repository Structure

```
setup-fmapi-claudecode.sh   # Claude Code setup script (bash)
README.md                    # User-facing documentation
CLAUDE.md                    # This file
.gitignore                   # Ignores .claude/settings.json and Python artifacts
```

## Supported Coding Agents

| Agent | Script | Status |
|---|---|---|
| Claude Code | `setup-fmapi-claudecode.sh` | Implemented |
| OpenAI Codex | — | Planned |
| Gemini CLI | — | Planned |

## Key Concepts

- **`setup-fmapi-claudecode.sh`** — Interactive bash script that installs dependencies (Claude Code, Databricks CLI), authenticates via OAuth, writes `.claude/settings.json`, and adds a shell wrapper to the user's RC file. Uses an interactive arrow-key selector for multi-choice prompts (command name, settings location).
- **`fmapi-claude`** — The default shell function name injected into `~/.zshrc` or `~/.bashrc` that wraps the `claude` command with automatic Databricks OAuth token refresh. Users can choose to override `claude` directly or use a custom command name during setup.
- **`.claude/settings.json`** — Claude Code configuration file containing environment variables (`ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, etc.) that route requests through Databricks FMAPI.

## Development Guidelines

- This is a **bash-only** project. No Python, no package manager, no build step.
- Each coding agent should have its own setup script following the naming convention `setup-fmapi-<agent>.sh`.
- Scripts must remain **idempotent** — re-running updates existing config rather than duplicating entries.
- The shell wrapper block in the RC file is delimited by `# >>> <cmd-name> wrapper >>>` and `# <<< <cmd-name> wrapper <<<` markers (where `<cmd-name>` is the user's chosen command name, e.g. `fmapi-claude`). Always preserve this convention.
- The `select_option` function provides an interactive arrow-key selector for multi-choice prompts. It uses ANSI escape codes to redraw options in place and collapses to the selected item on confirmation. Reuse this pattern in future setup scripts.
- Scripts use `set -euo pipefail` for strict error handling. Any new code must work under these constraints.
- **Dependencies**: `brew`, `jq`, `curl`, `tput`, `databricks` CLI. Do not introduce additional dependencies without good reason.
- **Never commit** `.claude/settings.json` or other files containing OAuth tokens.
- Use [ShellCheck](https://www.shellcheck.net/) conventions when editing scripts.

## Testing Changes

There are no automated tests. To verify changes:

1. Run `bash setup-fmapi-claudecode.sh` end-to-end with a real Databricks workspace.
2. Confirm `.claude/settings.json` is written correctly with `jq . .claude/settings.json`.
3. Open a new terminal and run `fmapi-claude` (or your chosen command name) to verify the wrapper works.
4. Run the script a second time to confirm idempotency (wrapper is replaced, settings are merged).
5. Re-run the script with a different command name and verify the old wrapper is removed from the RC file.

## Abbreviations

FMAPI: Foundation Model API
