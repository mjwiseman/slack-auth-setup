# Slack MCP User Setup Guide

This guide shows how to connect Slack MCP using your own Slack account in VS Code or GitHub Copilot CLI.

You do not need a shared Slack token. You do not need the Slack app Client Secret. You only need the Slack app Client ID from the app admin.

## What This Gives You

After setup, Copilot can use Slack MCP to search and read Slack conversations that your Slack account can access.

Example prompts:

```text
Use Slack MCP to search recent messages about the actuals sync issue and summarise the results.
```

```text
Use Slack MCP to find the latest thread discussing the ODL decision.
```

## Before You Start

You need:

- Access to the Slack workspace.
- The Slack app Client ID from the app admin.
- Either VS Code with Copilot, GitHub Copilot CLI, or both.

The Slack app must already have:

- Slack MCP enabled.
- PKCE enabled.
- Redirect URL `http://127.0.0.1`.
- The required user scopes.

## VS Code Setup

Open your VS Code user MCP config.

In VS Code:

1. Open the Command Palette.
2. Run `MCP: Open User Configuration`.
3. Add this config, replacing `YOUR_SLACK_CLIENT_ID`:

```json
{
  "servers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "oauth": {
        "clientId": "YOUR_SLACK_CLIENT_ID"
      }
    }
  }
}
```

If you already have other MCP servers, add only the `slack` entry inside the existing `servers` object.

### VS Code Config File Locations

Likely user config paths:

| OS | Path |
| --- | --- |
| macOS | `~/Library/Application Support/Code/User/mcp.json` |
| Windows | `%APPDATA%\Code\User\mcp.json` |
| Windows expanded | `C:\Users\<YourUsername>\AppData\Roaming\Code\User\mcp.json` |

For VS Code Insiders, replace `Code` with `Code - Insiders`.

### First VS Code Login

After saving the config:

1. Fully restart VS Code.
2. Use Copilot Chat or start the Slack MCP server from VS Code's MCP controls.
3. VS Code should open your browser.
4. Sign into Slack as your own Slack user.
5. Approve the app permissions.
6. Return to VS Code and try a Slack MCP prompt.

## GitHub Copilot CLI Setup

Open or create your Copilot MCP config file.

Add this config, replacing `YOUR_SLACK_CLIENT_ID`:

```json
{
  "mcpServers": {
    "slack": {
      "type": "http",
      "url": "https://mcp.slack.com/mcp",
      "oauthClientId": "YOUR_SLACK_CLIENT_ID",
      "tools": ["*"]
    }
  }
}
```

If you already have other MCP servers, add only the `slack` entry inside the existing `mcpServers` object.

### Copilot CLI Config File Locations

Likely user config paths:

| OS | Path |
| --- | --- |
| macOS | `~/.copilot/mcp-config.json` |
| Windows | `%USERPROFILE%\.copilot\mcp-config.json` |
| Windows expanded | `C:\Users\<YourUsername>\.copilot\mcp-config.json` |

If `COPILOT_HOME` is set, Copilot CLI uses:

| OS | Path |
| --- | --- |
| macOS | `$COPILOT_HOME/mcp-config.json` |
| Windows | `%COPILOT_HOME%\mcp-config.json` |

### First Copilot CLI Login

Start Copilot CLI:

```bash
gh copilot
```

Inside Copilot CLI, check the server:

```text
/mcp show slack
```

If it says authentication is needed, run:

```text
/mcp auth slack
```

Copilot CLI should open your browser. Sign into Slack as your own Slack user, approve the app permissions, then return to Copilot CLI.

Try a Slack query:

```text
Use Slack MCP to search recent Slack messages mentioning actuals sync and summarise the results.
```

## Troubleshooting

### Slack Opens But The MCP Client Still Says Missing Token

Check that the Slack app has PKCE enabled and has this redirect URL:

```text
http://127.0.0.1
```

Also check that your config uses OAuth, not a stale bearer-token header.

VS Code should use:

```json
"oauth": {
  "clientId": "YOUR_SLACK_CLIENT_ID"
}
```

Copilot CLI should use:

```json
"oauthClientId": "YOUR_SLACK_CLIENT_ID"
```

### It Authenticated As The Wrong Slack User

Your browser was probably signed into the wrong Slack account.

Sign out of Slack in the browser, use a private browser window, or switch browser profiles. Then re-authenticate:

```text
/mcp auth slack
```

For VS Code, remove/re-authenticate the Slack MCP connection from VS Code's MCP controls, then try again.

### Copilot Still Uses An Old Token

Reload the MCP server:

```text
/mcp reload slack
```

If it still looks stale, start a new Copilot CLI session and run:

```text
/mcp auth slack
```

### Slack Says The App Is Not Enabled For MCP

Ask the app admin to enable Slack MCP for the Slack app.

### Slack Says The App Needs Approval

Ask a Slack workspace admin to approve or install the app.

### Private Channels Are Missing

Slack MCP uses your Slack account permissions. You can only search private channels and DMs that your Slack account can access.

## Notes

- This setup does not require `SLACK_MCP_TOKEN`.
- This setup does not require the Slack Client Secret.
- VS Code and Copilot CLI handle OAuth themselves.
- The Slack app Client ID is not secret.
- Do not paste Slack OAuth tokens into config files unless an admin specifically asks you to use the older bearer-token setup.

## References

- [VS Code MCP configuration](https://code.visualstudio.com/docs/copilot/reference/mcp-configuration)
- [GitHub Copilot CLI command reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- [Slack MCP server docs](https://docs.slack.dev/ai/slack-mcp-server/)
- [Slack PKCE docs](https://docs.slack.dev/authentication/using-pkce/)
