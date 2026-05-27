# Slack MCP Auth for GitHub Copilot CLI on Windows

## Summary

This branch tests an alternative per-user authorization flow for GitHub Copilot CLI using Slack's confidential-client OAuth exchange. Each user runs a Windows PowerShell helper, approves the internal Slack MCP app in their browser, and receives a Slack user token that reflects only their own Slack permissions.

The implementation requires the Slack client secret. The token is stored as `SLACK_MCP_TOKEN`, and the helper can optionally configure VS Code and GitHub Copilot CLI to reference that environment variable.

## Current State

The working manual setup uses Slack's hosted MCP endpoint:

```toml
[mcp_servers.slack]
url = "https://mcp.slack.com/mcp"
bearer_token_env_var = "SLACK_MCP_TOKEN"
```

For GitHub Copilot CLI, the equivalent user-level configuration lives at:

```text
%USERPROFILE%\.copilot\mcp-config.json
```

Copilot CLI supports remote HTTP MCP servers and HTTP headers. The target configuration is:

```json
{
  "mcpServers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "headers": {
        "Authorization": "Bearer ${env:SLACK_MCP_TOKEN}"
      },
      "tools": ["*"]
    }
  }
}
```

VS Code uses a different top-level key:

```json
{
  "servers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "headers": {
        "Authorization": "Bearer ${env:SLACK_MCP_TOKEN}"
      }
    }
  }
}
```

## Slack App Prerequisites

The internal Slack app must be configured before users run the helper:

- The app is internal and approved for Slack MCP use.
- Slack MCP is enabled under **Agents & AI Apps**.
- PKCE is not enabled. This branch is intended to test whether a non-PKCE localhost confidential-client flow returns long-lived user tokens when token rotation is disabled.
- Token rotation is disabled for v1.
- Redirect URL is added exactly as:

```text
http://localhost:53682/slack/oauth/callback
```

- Required scopes are added under **User Token Scopes**:

```text
search:read.public
search:read.private
search:read.mpim
search:read.im
channels:history
groups:history
mpim:history
im:history
```

Optional scopes can be added later if the team wants write, file, canvas, reaction, or profile capabilities.

## Implementation

The main deliverable is `setup-slack-mcp-copilot.ps1`.

The script:

- Accepts the Slack `ClientId` and `ClientSecret` as parameters.
- Uses `http://localhost:53682/slack/oauth/callback` by default.
- Generates a random OAuth `state`.
- Opens the Slack OAuth URL at `https://slack.com/oauth/v2_user/authorize`.
- Starts a temporary local callback listener.
- Validates the returned `state`.
- Exchanges the authorization code through `https://slack.com/api/oauth.v2.user.access`.
- Verifies the returned token with Slack `auth.test` and prints the Slack user/workspace IDs without printing the token.
- Stores the returned token in the current user's `SLACK_MCP_TOKEN` environment variable.
- Asks whether to update VS Code user MCP config.
- Asks whether to update GitHub Copilot CLI MCP config.
- Updates `%APPDATA%\Code\User\mcp.json` for VS Code when selected.
- Updates `%USERPROFILE%\.copilot\mcp-config.json`, or `$env:COPILOT_HOME\mcp-config.json`, for Copilot CLI when selected.
- Creates a timestamped backup before changing an existing MCP config.
- Replaces only the `servers.slack` or `mcpServers.slack` entry and preserves other MCP servers.
- Never prints the Slack token.

## Failure Handling

The helper should fail with clear messages for:

- Missing or placeholder Slack client ID.
- Port unavailable or local listener startup failure.
- User cancellation or denial from Slack.
- OAuth state mismatch.
- Missing authorization code.
- Slack `bad_redirect_uri`.
- Slack `bad_client_secret`, which means the client secret is wrong or does not match the client ID.
- Slack `invalid_arguments`, which may mean the Slack app has PKCE enabled and is rejecting this confidential-client localhost flow.
- Slack token response without `access_token`.
- Existing invalid `mcp-config.json`.
- Windows PowerShell 5.1 compatibility issues, especially JSON parsing without `ConvertFrom-Json -Depth`.

When the existing MCP config is invalid JSON, the script creates a backup before failing so the user or support engineer can recover the previous contents.

## Test Plan

Manual happy path on Windows:

1. Run:

```powershell
.\setup-slack-mcp-copilot.ps1 -ClientId "YOUR_SLACK_CLIENT_ID" -ClientSecret "YOUR_SLACK_CLIENT_SECRET"
```

2. Approve Slack permissions in the browser.
3. Select VS Code and/or Copilot CLI config when prompted.
4. Confirm the token exists:

```powershell
echo $env:SLACK_MCP_TOKEN
```

5. If selected, confirm config files contain a `slack` entry:

```powershell
Get-Content "$HOME\.copilot\mcp-config.json"
```

6. Do not share or paste the bearer token.

Copilot CLI validation:

1. Run:

```powershell
gh copilot
```

2. In Copilot CLI, run:

```text
/mcp show slack
```

3. Ask:

```text
Use Slack MCP to search for recent messages mentioning actuals sync and summarise the results.
```

4. Approve the Slack MCP tool permission when prompted.

Negative tests:

- Run the helper while port `53682` is already in use.
- Remove the redirect URL from the Slack app and confirm `bad_redirect_uri` guidance.
- Cancel the Slack consent screen and confirm `access_denied` guidance.
- Put invalid JSON in `mcp-config.json` and confirm the script preserves a backup and exits.
- Add another MCP server, run setup, and confirm the other server remains unchanged.

## Rollout

Recommended rollout:

1. Test with two or three engineers using the internal Slack app.
2. Confirm each engineer can see only Slack content available to their own Slack account.
3. Replace the current Keeper entry containing the shared Slack MCP token with a link to this setup folder and the Slack client ID.
4. Ask existing users of the shared token to run the helper and remove any local shared-token configuration.
5. Keep the shared token temporarily available only for rollback, then revoke it once adoption is complete.

## Future Improvements

- Package the PowerShell helper as a signed Windows executable.
- Add support for Slack token rotation by storing refresh tokens in Windows Credential Manager and refreshing automatically.
- Add optional scopes for Slack message sending, files, canvases, reactions, or user profile lookup.
- Add a `-Verify` mode that checks Copilot CLI config without running OAuth.
- Add a `-Remove` mode that deletes the Slack MCP config entry and clears `SLACK_MCP_TOKEN`.
- Add a `-VerifyOnly` mode that reads the configured token and runs Slack `auth.test`.
