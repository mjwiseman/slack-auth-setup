# Slack MCP App Admin Guide

This guide is for the Slack app/workspace admin who prepares the shared Slack app that users will connect to from VS Code or GitHub Copilot CLI.

## Goal

Create one internal Slack app that is approved for Slack MCP, then let each user authorize that app as themselves.

This avoids sharing one person's Slack user token. Each user gets access through their own Slack permissions, so private channels and DMs follow the user's real Slack access.

## What The Admin Needs

- Permission to create or manage Slack apps for the workspace.
- Permission to install or request approval for the app.
- A Slack workspace that can use Slack MCP.

## Slack App Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps).
2. Create a new app, or reuse the internal app intended for Copilot/AI tooling.
3. In the app settings, enable Slack MCP access.
4. In **OAuth & Permissions**, enable **PKCE**.
5. In **OAuth & Permissions**, add this redirect URL:

```text
http://127.0.0.1
```

6. In **OAuth & Permissions**, add the required scopes under **User Token Scopes**.

For Slack search and thread/channel reading, use:

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

Do not add these as bot scopes for this setup. VS Code and Copilot CLI are authorizing the user.

7. Install the app to the workspace, or submit it for approval if your workspace requires app approval.
8. Copy the app **Client ID**.
9. Share the Client ID with users.

Do not share the Client Secret for this OAuth setup. The VS Code and Copilot CLI configs only need the Client ID.

## Optional Scopes

Only add more scopes if you want Slack MCP clients to perform more actions.

| Capability | User scopes |
| --- | --- |
| Search files | `search:read.files` |
| Read files | `files:read` |
| Search emoji | `emoji:read` |
| Search users | `search:read.users` |
| Send messages | `chat:write` |
| Create public channels | `channels:write` |
| Create private channels | `groups:write` |
| Create DMs | `im:write` |
| Create multi-party DMs | `mpim:write` |
| Add reactions | `reactions:write` |
| Read/write canvases | `canvases:read`, `canvases:write` |
| User profile/email | `users:read`, `users:read.email` |
| List channel members | `channels:read`, `groups:read`, `mpim:read` |

Keep scopes as narrow as practical. For the main "search Slack for context" workflow, the search/read scopes above are enough.

## Important Notes

- PKCE is the key setting that lets desktop clients authenticate without a client secret.
- Slack documents PKCE as a one-way app setting unless Slack support changes it.
- Users should not need a Slack token, a client secret, Keeper access, or the PowerShell/Python helper scripts for this flow.
- If a user signs into the wrong Slack account in the browser, the MCP client will connect as that wrong account. They should sign out or use a different browser profile and re-authenticate.

## Validation Checklist

Before rolling this out, test with two Slack users:

1. User A is in a private channel that User B is not in.
2. User B is in a different private channel that User A is not in.
3. Configure VS Code or Copilot CLI with only the Client ID.
4. Authenticate as each user.
5. Confirm each user can search only the Slack content their account can access.

## References

- [Slack MCP server docs](https://docs.slack.dev/ai/slack-mcp-server/)
- [Slack PKCE docs](https://docs.slack.dev/authentication/using-pkce/)
- [VS Code MCP configuration](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration)
- [GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
