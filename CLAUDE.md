# CLAUDE.md

## Project Overview

This repo contains setup scripts and a Claude Code plugin that configure coding agents to use foundation models served through Databricks Foundation Model API (FMAPI). Currently only Claude Code is supported, with OpenAI Codex and Gemini CLI planned. The repo includes a setup script, plugin manifest, and skill definitions — no application code.

## Repository Structure

```
setup-fmapi-claudecode.sh                  # Claude Code setup script (bash)
.claude-plugin/plugin.json                 # Claude Code plugin manifest
skills/fmapi-codingagent-status/SKILL.md   # /fmapi-codingagent-status skill
skills/fmapi-codingagent-reauth/SKILL.md   # /fmapi-codingagent-reauth skill
skills/fmapi-codingagent-setup/SKILL.md    # /fmapi-codingagent-setup skill
README.md                                  # User-facing documentation
CLAUDE.md                                  # This file
.gitignore                                 # Ignores generated files and Python artifacts
```

## Supported Coding Agents

| Agent | Script | Status |
|---|---|---|
| Claude Code | `setup-fmapi-claudecode.sh` | Implemented |
| OpenAI Codex | — | Planned |
| Gemini CLI | — | Planned |

## Plugin Skills

The repo is a Claude Code plugin providing three slash-command skills:

| Skill | Description |
|---|---|
| `/fmapi-codingagent-status` | Show FMAPI configuration health dashboard (OAuth health, model config) |
| `/fmapi-codingagent-reauth` | Re-authenticate Databricks OAuth session |
| `/fmapi-codingagent-setup` | Run full FMAPI setup (interactive or non-interactive with CLI flags) |

The plugin is automatically registered in `~/.claude/plugins/installed_plugins.json` when the setup script runs. It is deregistered on `--uninstall`.

## Key Concepts

- **`setup-fmapi-claudecode.sh`** — Bash script that installs dependencies (Claude Code, Databricks CLI), authenticates via OAuth, writes `.claude/settings.json`, and generates `fmapi-key-helper.sh`. Supports `--status`, `--reauth`, `--uninstall`, and CLI flags for non-interactive setup. Passing `--host` enables non-interactive mode where all other flags auto-default (profile defaults to `fmapi-claudecode-profile`).
- **`.claude-plugin/plugin.json`** — Plugin manifest that registers the repo as a Claude Code plugin with the `skills/` directory.
- **`skills/*/SKILL.md`** — Skill definitions that instruct Claude how to invoke the setup script with the appropriate flags.
- **`fmapi-key-helper.sh`** — A POSIX `/bin/sh` script generated alongside `settings.json` that Claude Code invokes automatically via the `apiKeyHelper` setting to obtain OAuth access tokens on demand. The Databricks CLI handles token refresh transparently.
- **`.claude/settings.json`** — Claude Code configuration file containing `apiKeyHelper` (path to helper script) and environment variables that route requests through Databricks FMAPI.

## CLI Flags

| Flag | Description |
|---|---|
| `--status` | Show configuration health dashboard |
| `--reauth` | Re-authenticate Databricks OAuth session |
| `--uninstall` | Remove all FMAPI artifacts and plugin registration |
| `-h`, `--help` | Show help |
| `--host URL` | Databricks workspace URL (enables non-interactive mode) |
| `--profile NAME` | Databricks CLI profile name (default: `fmapi-claudecode-profile`) |
| `--model MODEL` | Primary model (default: `databricks-claude-opus-4-6`) |
| `--opus MODEL` | Opus model (default: `databricks-claude-opus-4-6`) |
| `--sonnet MODEL` | Sonnet model (default: `databricks-claude-sonnet-4-6`) |
| `--haiku MODEL` | Haiku model (default: `databricks-claude-haiku-4-5`) |
| `--ttl MINUTES` | Token refresh interval in minutes (default: `30`, max: `60`) |
| `--settings-location PATH` | Settings location: `home`, `cwd`, or custom path (default: `home`) |

## Development Guidelines

- This is a **bash-only** project. No Python, no package manager, no build step.
- Each coding agent should have its own setup script following the naming convention `setup-fmapi-<agent>.sh`.
- Scripts must remain **idempotent** — re-running updates existing config rather than duplicating entries.
- The helper script (`fmapi-key-helper.sh`) must be POSIX `/bin/sh` compatible with `set -eu`. Do not use bash-specific features in the helper.
- Scripts use `set -euo pipefail` for strict error handling. Any new code must work under these constraints.
- All generated files must have owner-only permissions. Never store tokens in world-readable files.
- **Dependencies**: `brew`, `jq`, `curl`, `tput`, `databricks` CLI. Do not introduce additional dependencies without good reason.
- **Never commit** `.claude/settings.json`, `fmapi-key-helper.sh`, or other files containing tokens.
- Use [ShellCheck](https://www.shellcheck.net/) conventions when editing scripts.

## Testing Changes

There are no automated tests. To verify changes:

1. Run `bash setup-fmapi-claudecode.sh --help` and verify all flags documented.
2. Run `bash setup-fmapi-claudecode.sh --status` — should show "no config found" or current dashboard.
3. Run `bash setup-fmapi-claudecode.sh` end-to-end with a real Databricks workspace.
4. Confirm `.claude/settings.json` is written correctly with `apiKeyHelper` and env vars.
5. Verify the helper script exists with owner-only permissions.
6. Run `bash setup-fmapi-claudecode.sh --status` — confirm dashboard shows correct config.
7. Run `bash setup-fmapi-claudecode.sh --reauth` — confirm OAuth re-authentication works.
8. Re-run the setup script to confirm idempotency (defaults pre-populated).
9. Confirm `~/.claude/plugins/installed_plugins.json` has `fmapi-codingagent` entry.
10. Run `claude` and confirm it works with FMAPI.
11. Run `bash setup-fmapi-claudecode.sh --uninstall` and confirm cleanup (including plugin deregistration).

## Abbreviations

FMAPI: Foundation Model API
