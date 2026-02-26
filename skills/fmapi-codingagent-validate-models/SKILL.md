---
name: fmapi-codingagent-validate-models
description: Validate that configured FMAPI models exist and are ready in the workspace
user_invocable: true
---

# FMAPI Validate Models

Validate that all configured model names exist as serving endpoints in your Databricks workspace and are in a READY state.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-validate-models/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the validate-models command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --validate-models
```

3. Present the output to the user. The command checks each configured model (Model, Opus, Sonnet, Haiku) and reports:

   - **PASS** — Endpoint exists and is READY
   - **WARN** — Endpoint exists but is not in READY state
   - **FAIL** — Endpoint not found in the workspace
   - **SKIP** — Model not configured

4. If any models fail validation:
   - The command exits with code 1
   - Suggest running `/fmapi-codingagent-list-models` to discover available endpoint names
   - Suggest re-running `/fmapi-codingagent-setup` with correct model names

5. If the command fails before validation:
   - **No config found**: suggest `/fmapi-codingagent-setup` first
   - **OAuth expired**: suggest `/fmapi-codingagent-reauth`
