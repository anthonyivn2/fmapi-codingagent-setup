# Coding Agents with Databricks Foundation Model API

Set up coding agents to run against models served through [Databricks Foundation Model API (FMAPI)](https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis). FMAPI provides a unified gateway for serving foundation models from your Databricks workspace, enabling coding agents to leverage enterprise-grade model serving with built-in governance, security, and observability.

## Supported Coding Agents

FMAPI supports various coding agents today. The table below breaks down the Coding Agents that Databricks Foundational Model API supports today, and the quickstart script you can use to set it up.

| Coding Agent | FMAPI Support | Setup Script |
|---|---|---|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Supported | `setup-fmapi-claudecode.sh` |
| [OpenAI Codex](https://openai.com/index/codex/) | Supported | Script not yet available |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Supported | Script not yet available |

## Claude Code

### Prerequisites

- **macOS** with `zsh` or `bash`
- [Homebrew](https://brew.sh/) (`brew`)
- [`jq`](https://jqlang.github.io/jq/) (install with `brew install jq`)
- A Databricks workspace with FMAPI enabled

### Quick Start

```bash
bash setup-fmapi-claudecode.sh
```

The script will prompt you for:

| Prompt | Type | Description |
|---|---|---|
| **Workspace URL** | Text input | Your Databricks workspace URL (e.g. `https://my-workspace.cloud.databricks.com`) |
| **CLI profile name** | Text input | Name for the Databricks CLI authentication profile (e.g. `my-profile`) |
| **Model** | Text input | The primary model to use. Defaults to `databricks-claude-opus-4-6` |
| **Opus model** | Text input | The Opus model for complex tasks. Defaults to `databricks-claude-opus-4-6` |
| **Sonnet model** | Text input | The Sonnet model for lighter tasks. Defaults to `databricks-claude-sonnet-4-6` |
| **Haiku model** | Text input | The Haiku model for fast, low-cost tasks. Defaults to `databricks-claude-haiku-4-5` |
| **Settings location** | Arrow-key selector | Where to write the `.claude/settings.json` file (home directory, current directory, or a custom path) |
| **PAT lifetime** | Arrow-key selector | How long the Personal Access Token should last (1 day, 3 days, 5 days, or 7 days) |

> The **Settings location** and **PAT lifetime** prompts use an interactive arrow-key selector &mdash; use the up/down arrow keys to navigate and Enter to confirm.

Once complete, run:

```bash
claude
```

### What the Script Does

#### 1. Installs dependencies

- **Claude Code** &mdash; installed via `curl -fsSL https://claude.ai/install.sh | bash` if not already present.
- **Databricks CLI** &mdash; installed via Homebrew (`brew tap databricks/tap && brew install databricks`) if not already present.

#### 2. Authenticates with Databricks

Establishes an OAuth session using `databricks auth token --profile <profile>`. If no valid session exists, it triggers `databricks auth login` to start the OAuth flow in your browser. Once authenticated, the script revokes any old FMAPI PATs and creates a new Personal Access Token (PAT) with the chosen lifetime.

#### 3. Writes `.claude/settings.json`

Creates or merges environment variables into your Claude Code settings file at the chosen location. The settings configure Claude Code to route API calls through your Databricks workspace:

| Setting | Location | Value |
|---|---|---|
| `apiKeyHelper` | Top-level | Path to `fmapi-key-helper.sh` (auto-generates auth tokens) |
| `ANTHROPIC_MODEL` | `env` | Selected model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_BASE_URL` | `env` | `<workspace-url>/serving-endpoints/anthropic` |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `env` | Selected Opus model (default: `databricks-claude-opus-4-6`) |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `env` | Selected Sonnet model (default: `databricks-claude-sonnet-4-6`) |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `env` | Selected Haiku model (default: `databricks-claude-haiku-4-5`) |
| `ANTHROPIC_CUSTOM_HEADERS` | `env` | `x-databricks-use-coding-agent-mode: true` |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | `env` | `1` |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | `env` | TTL for token caching (half of PAT lifetime, max 1 hour) |

If the settings file already exists, the script merges the new values into it without overwriting other settings. Old-style `ANTHROPIC_AUTH_TOKEN` and `_fmapi_meta` keys are removed during migration.

#### 4. Creates an API key helper script

Writes `fmapi-key-helper.sh` alongside `settings.json` with `chmod 700` (owner-only). This script is invoked automatically by Claude Code via the [`apiKeyHelper`](https://docs.anthropic.com/en/docs/claude-code/settings#available-settings) setting to obtain auth tokens on demand. The helper manages the full PAT lifecycle without requiring a shell wrapper.

#### 5. Seeds the PAT cache

The initial PAT created during setup is written atomically to `.fmapi-pat-cache` (via `mktemp` + `jq` + `mv`) so that the first `claude` invocation works immediately without needing to create a new token.

### Security

The script applies defense-in-depth to protect PAT tokens at rest:

- **`umask 077`** &mdash; Set at the top of both the setup script and the helper script. All newly created files default to owner-only permissions (`600` for files, `700` for directories), even if `chmod` never runs due to an interrupt.
- **Trap-based temp file cleanup** &mdash; Both scripts register cleanup handlers (`trap ... EXIT`) that remove orphaned temp files on exit, error, or interrupt (Ctrl+C). This prevents PAT tokens from being left in world-readable temp files if the script is killed mid-operation.
- **Atomic writes with `jq`** &mdash; All JSON files containing tokens are written using `mktemp` + `jq -n` + `chmod 600` + `mv`. This avoids both non-atomic writes (where another process could read a partial file) and `printf`-based JSON construction (where special characters in tokens could break the JSON silently).
- **Owner-only helper** &mdash; The helper script uses `chmod 700` instead of `755`, restricting read and execute access to the owning user only.

### How token management works

Claude Code uses the `apiKeyHelper` setting to automatically obtain auth tokens:

1. Claude Code invokes `fmapi-key-helper.sh` when it needs an API key.
2. The helper checks `.fmapi-pat-cache` for a cached token with at least 5 minutes of remaining validity.
3. If the cached token is still valid, it is returned immediately (no network call).
4. If expired, the helper ensures the OAuth session is still valid (prints re-auth instructions if needed).
5. Revokes any old FMAPI PATs from the workspace.
6. Creates a new PAT with the configured lifetime, writes it to the cache atomically, and returns it.

The `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` setting controls how often Claude Code re-invokes the helper (default: every hour or half the PAT lifetime, whichever is shorter).

### Available Models

Models available through FMAPI depend on what is enabled in your Databricks workspace. The setup script supports:

| Model ID | Description |
|---|---|
| `databricks-claude-opus-4-6` | Claude Opus 4.6 (default) |
| `databricks-claude-sonnet-4-6` | Claude Sonnet 4.6 (default Sonnet) |
| `databricks-claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `databricks-claude-haiku-4-5` | Claude Haiku 4.5 (default Haiku) |

### Uninstalling

To remove all FMAPI artifacts created by the setup script:

```bash
bash setup-fmapi-claudecode.sh --uninstall
```

The uninstall process:

1. **Discovers artifacts** &mdash; Finds helper scripts, cache files, and settings files with FMAPI keys. Also detects legacy shell wrappers in `~/.zshrc` and `~/.bashrc` from older versions.
2. **Deletes helper script and cache** &mdash; Removes `fmapi-key-helper.sh` and `.fmapi-pat-cache`.
3. **Cleans settings files** &mdash; Removes FMAPI-specific keys (`apiKeyHelper`, `ANTHROPIC_MODEL`, `ANTHROPIC_BASE_URL`, etc.) from `.claude/settings.json`. If no other settings remain, the file is deleted. Non-FMAPI settings are preserved.
4. **Removes legacy wrappers** &mdash; Cleans up any old-style shell wrapper blocks from RC files.
5. **Optionally revokes PATs** &mdash; With a separate confirmation prompt, revokes any Databricks PATs whose comment starts with "Claude Code FMAPI". If you decline, the tokens will expire on their own.

Re-running `--uninstall` when nothing is installed is safe and will print "Nothing to uninstall."

### Re-running the Script

You can safely re-run `setup-fmapi-claudecode.sh` at any time to:

- Update the workspace URL, profile, or models (Opus, Sonnet, Haiku)
- Refresh an expired token
- Repair a missing or corrupted settings file or helper script

The script will overwrite the existing helper script and merge settings without duplication.

### Upgrading from Shell Wrapper

If you previously used a version of this script that injected a shell wrapper into `~/.zshrc` or `~/.bashrc`, simply re-run the setup script:

```bash
bash setup-fmapi-claudecode.sh
```

The script will automatically:

1. Remove the old shell wrapper block from your RC file
2. Create the new `apiKeyHelper`-based setup
3. Migrate your settings (removing old `ANTHROPIC_AUTH_TOKEN` and `_fmapi_meta` keys)

You no longer need to `source ~/.zshrc` or use a custom command name &mdash; just run `claude` directly.

### Troubleshooting

**"Workspace URL must start with https://"**
Provide the full URL including the scheme, e.g. `https://my-workspace.cloud.databricks.com`.

**Token refresh fails silently**
Ensure the Databricks CLI profile name matches what you used during setup. Check with `databricks auth env --profile <profile>`.

**"apiKeyHelper failed" or authentication errors**
Run the helper script manually to diagnose: `sh ~/.claude/fmapi-key-helper.sh`. If it prints an OAuth error, re-authenticate with `databricks auth login --host <workspace-url> --profile <profile>`.

**Claude Code returns authentication errors**
Your PAT may have expired and the helper may need a valid OAuth session. Run `databricks auth login --host <workspace-url> --profile <profile>` to refresh the OAuth session, then retry `claude`.

## OpenAI Codex

FMAPI supports OpenAI Codex today. A setup script for this repo is not yet available &mdash; contributions welcome.

## Gemini CLI

FMAPI supports Gemini CLI today. A setup script for this repo is not yet available &mdash; contributions welcome.
