---
name: fmapi-codingagent-doctor
description: Run comprehensive FMAPI diagnostics — dependencies, configuration, profile, auth, connectivity, and model validation
user_invocable: true
---

# FMAPI Doctor

Run comprehensive diagnostics to identify issues with your Databricks Foundation Model API (FMAPI) configuration.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-doctor/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the doctor command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --doctor
```

3. Present the output to the user. The doctor runs six diagnostic categories:

   - **Dependencies** — Checks that jq, databricks, claude, and curl are installed; reports versions
   - **Configuration** — Verifies settings file is valid JSON, all required FMAPI keys are present, and helper script exists and is executable
   - **Profile** — Confirms the Databricks CLI profile exists in `~/.databrickscfg`
   - **Auth** — Tests whether the OAuth token is valid
   - **Connectivity** — Tests HTTP reachability to the Databricks serving endpoints API
   - **Models** — Validates all four configured model names exist and are ready

4. Each check shows **PASS**, **FAIL**, **WARN**, or **SKIP** with an actionable fix suggestion for failures.

5. If the command exits with code 1, some checks failed. Guide the user through fixing the reported issues. Common fixes:
   - Missing dependencies: install via the suggested command
   - Auth failures: suggest `/fmapi-codingagent-reauth`
   - Missing config: suggest `/fmapi-codingagent-setup`
   - Model issues: suggest `/fmapi-codingagent-list-models` to discover available endpoints
