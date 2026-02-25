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

- **`setup-fmapi-claudecode.sh`** — Interactive bash script that installs dependencies (Claude Code, Databricks CLI), authenticates via OAuth, creates a Personal Access Token (PAT), writes `.claude/settings.json` with an `apiKeyHelper` reference, and generates `fmapi-key-helper.sh` for automatic token management. Uses an interactive arrow-key selector for multi-choice prompts (settings location, PAT lifetime). Supports `--uninstall` to cleanly remove all FMAPI artifacts (helper scripts, cache files, settings keys, and optionally PATs).
- **`fmapi-key-helper.sh`** — A POSIX `/bin/sh` script generated alongside `settings.json` (`chmod 700`, owner-only) that Claude Code invokes automatically via the `apiKeyHelper` setting to obtain auth tokens. Uses `umask 077` and `trap`-based temp file cleanup. It reads a cached PAT from `.fmapi-pat-cache`, returning it if still valid (with a 5-minute buffer). On expiry, it checks the OAuth session, revokes old PATs, creates a new one via `jq -n`, and writes the cache atomically.
- **`.fmapi-pat-cache`** — JSON cache file (`chmod 600`) storing the current PAT token, expiry epoch, and lifetime. Written atomically via `mktemp` + `jq -n` + `mv` to prevent corruption and ensure proper JSON escaping.
- **`.claude/settings.json`** — Claude Code configuration file containing `apiKeyHelper` (path to helper script) and environment variables (`ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`, etc.) that route requests through Databricks FMAPI.

## Development Guidelines

- This is a **bash-only** project. No Python, no package manager, no build step.
- Each coding agent should have its own setup script following the naming convention `setup-fmapi-<agent>.sh`.
- Scripts must remain **idempotent** — re-running updates existing config rather than duplicating entries.
- The helper script (`fmapi-key-helper.sh`) must be POSIX `/bin/sh` compatible with `set -eu`. Do not use bash-specific features in the helper. It must use `chmod 700` (owner-only execute).
- Both scripts must start with `umask 077` after `set -e*` to ensure all newly created files default to owner-only permissions.
- Both scripts must use `trap`-based cleanup to remove orphaned temp files on exit or interrupt (Ctrl+C, `set -e` errors). The setup script uses a bash array (`_CLEANUP_FILES`); the helper uses a single POSIX variable (`_cleanup_tmp`).
- Cache files (`.fmapi-pat-cache`) must be written atomically (`mktemp` + `jq -n` + `chmod 600` + `mv`) and have `chmod 600` permissions. Never store tokens in world-readable files.
- Always use `jq -n` with `--arg`/`--argjson` to construct JSON containing token values. Never use `printf` for JSON — tokens may contain `"`, `\`, or `%` characters that break format strings silently.
- The `select_option` function provides an interactive arrow-key selector for multi-choice prompts. It uses ANSI escape codes to redraw options in place and collapses to the selected item on confirmation. Reuse this pattern in future setup scripts.
- Scripts use `set -euo pipefail` for strict error handling. Any new code must work under these constraints.
- **Dependencies**: `brew`, `jq`, `curl`, `tput`, `databricks` CLI. Do not introduce additional dependencies without good reason.
- **Never commit** `.claude/settings.json`, `fmapi-key-helper.sh`, `.fmapi-pat-cache`, or other files containing tokens (OAuth or PAT).
- Use [ShellCheck](https://www.shellcheck.net/) conventions when editing scripts.

## Testing Changes

There are no automated tests. To verify changes:

1. Run `bash setup-fmapi-claudecode.sh` end-to-end with a real Databricks workspace.
2. Confirm `.claude/settings.json` is written correctly: `jq . .claude/settings.json` should show `apiKeyHelper` and env vars, but no `ANTHROPIC_AUTH_TOKEN` or `_fmapi_meta`.
3. Verify the helper script exists with owner-only permissions: `ls -la ~/.claude/fmapi-key-helper.sh` (should be `-rwx------`, i.e. `700`).
4. Run the helper manually: `sh ~/.claude/fmapi-key-helper.sh` should output a PAT token.
5. Verify the cache file exists with correct permissions: `ls -la ~/.claude/.fmapi-pat-cache` (should be `-rw-------`, i.e. `600`).
6. Run `claude` and confirm it works with FMAPI.
7. Run the script a second time to confirm idempotency (helper overwritten, settings merged, no duplication).
8. **Migration test**: If upgrading from shell wrapper version, verify the old wrapper block is removed from `~/.zshrc` after re-running setup.
9. Run `bash setup-fmapi-claudecode.sh --uninstall` and confirm removal of helper script, cache file, and settings keys.
10. Verify cleanup: `ls ~/.claude/fmapi-key-helper.sh` should fail, `jq . ~/.claude/settings.json` should have no FMAPI keys (or the file should be deleted).
11. Re-run `--uninstall` to verify idempotent "Nothing to uninstall" message.
12. Run `bash setup-fmapi-claudecode.sh --help` and verify the usage text.
13. **Interrupt cleanup**: Kill the script mid-run (Ctrl+C) and verify no orphaned temp files remain: `ls ~/.claude/.fmapi-pat-cache.* ~/.claude/settings.json.* 2>/dev/null` should return nothing.

## Abbreviations

FMAPI: Foundation Model API
