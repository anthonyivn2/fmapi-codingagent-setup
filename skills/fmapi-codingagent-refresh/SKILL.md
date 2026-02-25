---
name: fmapi-codingagent-refresh
description: Rotate the FMAPI PAT token — revoke old tokens and create a fresh one without re-running full setup
user_invocable: true
---

# FMAPI Token Refresh

Rotate your Databricks FMAPI Personal Access Token (PAT) without re-running the full setup.

## Instructions

1. Determine the install path of this plugin. This SKILL.md file is located at `<install-path>/skills/fmapi-codingagent-refresh/SKILL.md`, so the setup script is two directories up at `<install-path>/setup-fmapi-claudecode.sh`.

2. Run the refresh command:

```bash
bash "<install-path>/setup-fmapi-claudecode.sh" --refresh
```

3. This command is non-interactive and zero-prompt. It will:
   - Discover the existing FMAPI configuration
   - Check the OAuth session
   - Revoke old FMAPI PATs
   - Create a new PAT with the same lifetime as the original
   - Update the cache file atomically
   - Print a one-line success message with the new expiry

4. If the OAuth session has expired, the command will print instructions for the user to re-authenticate manually:

```bash
databricks auth login --host <workspace-url> --profile <profile>
```

After re-authenticating, the user can run `/fmapi-codingagent-refresh` again.

5. If no existing FMAPI configuration is found, inform the user they need to run `/fmapi-codingagent-setup` first.
