# CLAUDE.md

## Project Overview

This repo contains setup scripts that configure coding agents to use foundation models served through Databricks Foundation Model API (FMAPI). Currently only Claude Code is supported, with OpenAI Codex and Gemini CLI planned. There is no application code — just setup scripts and documentation.

## Repository Structure

```
setup-fmapi-claudecode.sh   # Claude Code setup script (bash)
README.md                    # User-facing documentation
CLAUDE.md                    # This file
.gitignore                   # Ignores .claude/settings.json, helper scripts, cache files, and Python artifacts
```

## Supported Coding Agents

| Agent | Script | Status |
|---|---|---|
| Claude Code | `setup-fmapi-claudecode.sh` | Implemented |
| OpenAI Codex | — | Planned |
| Gemini CLI | — | Planned |

## Key Concepts

- **`setup-fmapi-claudecode.sh`** — Interactive bash script that installs dependencies (Claude Code, Databricks CLI), authenticates via OAuth, creates a Personal Access Token (PAT), writes `.claude/settings.json` with an `apiKeyHelper` reference, and generates `fmapi-key-helper.sh` for automatic token management. Supports `--uninstall` to cleanly remove all FMAPI artifacts.
- **`fmapi-key-helper.sh`** — A POSIX `/bin/sh` script generated alongside `settings.json` that Claude Code invokes automatically via the `apiKeyHelper` setting to obtain and refresh auth tokens.
- **`.fmapi-pat-cache`** — Local cache file storing the current PAT token and expiry metadata.
- **`.claude/settings.json`** — Claude Code configuration file containing `apiKeyHelper` (path to helper script) and environment variables that route requests through Databricks FMAPI.

## Development Guidelines

- This is a **bash-only** project. No Python, no package manager, no build step.
- Each coding agent should have its own setup script following the naming convention `setup-fmapi-<agent>.sh`.
- Scripts must remain **idempotent** — re-running updates existing config rather than duplicating entries.
- The helper script (`fmapi-key-helper.sh`) must be POSIX `/bin/sh` compatible with `set -eu`. Do not use bash-specific features in the helper.
- Scripts use `set -euo pipefail` for strict error handling. Any new code must work under these constraints.
- All generated files containing tokens must have owner-only permissions. Never store tokens in world-readable files.
- **Dependencies**: `brew`, `jq`, `curl`, `tput`, `databricks` CLI. Do not introduce additional dependencies without good reason.
- **Never commit** `.claude/settings.json`, `fmapi-key-helper.sh`, `.fmapi-pat-cache`, or other files containing tokens (OAuth or PAT).
- Use [ShellCheck](https://www.shellcheck.net/) conventions when editing scripts.

## Testing Changes

There are no automated tests. To verify changes:

1. Run `bash setup-fmapi-claudecode.sh` end-to-end with a real Databricks workspace.
2. Confirm `.claude/settings.json` is written correctly with `apiKeyHelper` and env vars.
3. Verify the helper script and cache file exist with owner-only permissions.
4. Run `claude` and confirm it works with FMAPI.
5. Re-run the setup script to confirm idempotency.
6. Run `bash setup-fmapi-claudecode.sh --uninstall` and confirm cleanup.
7. Run `bash setup-fmapi-claudecode.sh --help` and verify the usage text.

## Abbreviations

FMAPI: Foundation Model API
