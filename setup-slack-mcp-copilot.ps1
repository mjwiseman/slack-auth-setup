<#
.SYNOPSIS
Authorizes a Slack MCP app for the current Windows user and optionally configures MCP clients.

.DESCRIPTION
This script performs a Slack OAuth user-token flow using a confidential-client exchange. It requires
the Slack client secret. The returned user token is stored in SLACK_MCP_TOKEN so MCP clients can
reference it from their configuration.

.EXAMPLE
.\setup-slack-mcp-copilot.ps1 -ClientId "1234567890.1234567890123" -ClientSecret "abc123"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [int]$RedirectPort = 53682,

    [Parameter(Mandatory = $false)]
    [string[]]$Scopes = @(
        "search:read.public",
        "search:read.private",
        "search:read.mpim",
        "search:read.im",
        "channels:history",
        "groups:history",
        "mpim:history",
        "im:history"
    ),

    [Parameter(Mandatory = $false)]
    [string]$ServerName = "slack"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Base64UrlRandomString {
    param([int]$ByteCount = 32)

    $bytes = New-Object byte[] $ByteCount
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    }
    finally {
        $random.Dispose()
    }

    return ConvertTo-Base64Url -Bytes $bytes
}

function ConvertTo-Base64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function ConvertTo-QueryString {
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)

    $pairs = foreach ($key in $Parameters.Keys) {
        $encodedKey = [System.Uri]::EscapeDataString([string]$key)
        $encodedValue = [System.Uri]::EscapeDataString([string]$Parameters[$key])
        "$encodedKey=$encodedValue"
    }

    return ($pairs -join "&")
}

function Write-BrowserResponse {
    param(
        [Parameter(Mandatory = $true)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [int]$StatusCode = 200
    )

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>$Title</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 48px; line-height: 1.5; color: #1f2328; }
    main { max-width: 680px; }
    code { background: #f6f8fa; padding: 2px 5px; border-radius: 4px; }
  </style>
</head>
<body>
  <main>
    <h1>$Title</h1>
    <p>$Message</p>
    <p>You can close this browser tab and return to PowerShell.</p>
  </main>
</body>
</html>
"@

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "text/html; charset=utf-8"
    $Context.Response.ContentLength64 = $buffer.Length
    $Context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Context.Response.OutputStream.Close()
}

function Backup-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.bak-$timestamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function Read-JsonFileOrDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$DefaultValue
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $DefaultValue
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $DefaultValue
    }

    try {
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Could not parse existing MCP config at '$Path'. A backup has been created. Fix or remove this file, then rerun the script. Parse error: $($_.Exception.Message)"
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $property.Value = $Value
    }
}

function Update-CopilotMcpConfig {
    param([Parameter(Mandatory = $true)][string]$ConfiguredServerName)

    $copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
        Join-Path $HOME ".copilot"
    }
    else {
        $env:COPILOT_HOME
    }

    if (-not (Test-Path -LiteralPath $copilotHome)) {
        New-Item -ItemType Directory -Path $copilotHome -Force | Out-Null
    }

    $configPath = Join-Path $copilotHome "mcp-config.json"
    $backupPath = Backup-File -Path $configPath

    $config = Read-JsonFileOrDefault -Path $configPath -DefaultValue ([pscustomobject]@{})
    if ($null -eq $config.PSObject.Properties["mcpServers"]) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([pscustomobject]@{})
    }

    $serverConfig = [pscustomobject]@{
        type = "http"
        url = "https://mcp.slack.com/mcp"
        headers = [pscustomobject]@{
            Authorization = 'Bearer ${SLACK_MCP_TOKEN}'
        }
        tools = @("*")
    }

    Set-JsonProperty -Object $config.mcpServers -Name $ConfiguredServerName -Value $serverConfig

    $json = $config | ConvertTo-Json -Depth 100
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, $utf8NoBom)

    return [pscustomobject]@{
        ConfigPath = $configPath
        BackupPath = $backupPath
    }
}

function Update-VsCodeMcpConfig {
    param([Parameter(Mandatory = $true)][string]$ConfiguredServerName)

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "APPDATA is not set, so the VS Code user MCP config path could not be resolved."
    }

    $vsCodeUserHome = Join-Path $env:APPDATA "Code\User"
    if (-not (Test-Path -LiteralPath $vsCodeUserHome)) {
        New-Item -ItemType Directory -Path $vsCodeUserHome -Force | Out-Null
    }

    $configPath = Join-Path $vsCodeUserHome "mcp.json"
    $backupPath = Backup-File -Path $configPath

    $config = Read-JsonFileOrDefault -Path $configPath -DefaultValue ([pscustomobject]@{})
    if ($null -eq $config.PSObject.Properties["servers"]) {
        $config | Add-Member -MemberType NoteProperty -Name "servers" -Value ([pscustomobject]@{})
    }

    $serverConfig = [pscustomobject]@{
        type = "http"
        url = "https://mcp.slack.com/mcp"
        headers = [pscustomobject]@{
            Authorization = 'Bearer ${env:SLACK_MCP_TOKEN}'
        }
    }

    Set-JsonProperty -Object $config.servers -Name $ConfiguredServerName -Value $serverConfig

    $json = $config | ConvertTo-Json -Depth 100
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($configPath, $json + [Environment]::NewLine, $utf8NoBom)

    return [pscustomobject]@{
        ConfigPath = $configPath
        BackupPath = $backupPath
    }
}

function Test-SlackToken {
    param([Parameter(Mandatory = $true)][string]$AccessToken)

    try {
        return Invoke-RestMethod `
            -Method Post `
            -Uri "https://slack.com/api/auth.test" `
            -Headers @{ Authorization = "Bearer $AccessToken" }
    }
    catch {
        Write-Warning "Could not verify the Slack token with auth.test. Continuing setup. Error: $($_.Exception.Message)"
        return $null
    }
}

function Confirm-SetupStep {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    $answer = Read-Host "$Prompt [Y/n]"
    return [string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant().StartsWith("y")
}

if ([string]::IsNullOrWhiteSpace($ClientId)) {
    throw "Slack Client ID is required. Run: .\setup-slack-mcp-copilot.ps1 -ClientId `"YOUR_SLACK_CLIENT_ID`""
}

if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    throw "Slack Client Secret is required for this confidential-client flow. Run: .\setup-slack-mcp-copilot.ps1 -ClientId `"YOUR_SLACK_CLIENT_ID`" -ClientSecret `"YOUR_SLACK_CLIENT_SECRET`""
}

if ($Scopes.Count -eq 0) {
    throw "At least one Slack user scope is required."
}

$redirectUri = "http://localhost:$RedirectPort/slack/oauth/callback"
$listenerPrefix = "http://localhost:$RedirectPort/"
$state = New-Base64UrlRandomString -ByteCount 32

$authorizeQuery = ConvertTo-QueryString -Parameters @{
    client_id = $ClientId
    scope = ($Scopes -join ",")
    redirect_uri = $redirectUri
    state = $state
}
$authorizeUrl = "https://slack.com/oauth/v2_user/authorize?$authorizeQuery"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($listenerPrefix)

try {
    try {
        $listener.Start()
    }
    catch {
        throw "Could not start the local callback listener on $listenerPrefix. If the port is already in use, rerun with -RedirectPort 53683 and add the matching redirect URL to the Slack app. Original error: $($_.Exception.Message)"
    }

    Write-Host "Opening Slack authorization in your browser..."
    Write-Host "Waiting for Slack to redirect back to $redirectUri"
    Start-Process $authorizeUrl

    $context = $listener.GetContext()
    $requestPath = $context.Request.Url.AbsolutePath

    if ($requestPath -ne "/slack/oauth/callback") {
        Write-BrowserResponse -Context $context -Title "Unexpected callback path" -Message "The setup helper received a request for <code>$requestPath</code>, but expected <code>/slack/oauth/callback</code>." -StatusCode 404
        throw "Received an unexpected callback path: $requestPath"
    }

    $returnedState = $context.Request.QueryString["state"]
    $code = $context.Request.QueryString["code"]
    $errorCode = $context.Request.QueryString["error"]

    if (-not [string]::IsNullOrWhiteSpace($errorCode)) {
        Write-BrowserResponse -Context $context -Title "Slack authorization was not completed" -Message "Slack returned <code>$errorCode</code>. If you cancelled or denied the request, rerun the setup script when ready." -StatusCode 400
        throw "Slack authorization failed: $errorCode"
    }

    if ($returnedState -ne $state) {
        Write-BrowserResponse -Context $context -Title "Authorization state mismatch" -Message "The OAuth state value did not match. The setup helper stopped to protect your account." -StatusCode 400
        throw "OAuth state mismatch. Rerun the setup script."
    }

    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-BrowserResponse -Context $context -Title "Missing authorization code" -Message "Slack did not return an authorization code. Rerun the setup script and approve the requested permissions." -StatusCode 400
        throw "Slack did not return an authorization code."
    }

    Write-BrowserResponse -Context $context -Title "Slack authorization complete" -Message "Slack authorization succeeded. The setup helper is finishing your local MCP setup."

    $tokenBody = @{
        client_id = $ClientId
        client_secret = $ClientSecret
        code = $code
        redirect_uri = $redirectUri
        grant_type = "authorization_code"
    }

    Write-Host "Exchanging authorization code for a Slack user token..."
    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "https://slack.com/api/oauth.v2.user.access" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody

    if ($true -ne $tokenResponse.ok) {
        $slackError = if ($tokenResponse.PSObject.Properties["error"]) { $tokenResponse.error } else { "unknown_error" }
        if ($slackError -eq "bad_redirect_uri") {
            throw "Slack returned bad_redirect_uri. Ask an app admin to add exactly this redirect URL to the Slack app: $redirectUri"
        }

        if ($slackError -eq "bad_client_secret") {
            throw "Slack returned bad_client_secret. Confirm the Slack client secret is correct and belongs to the same app as the client ID."
        }

        if ($slackError -eq "invalid_code") {
            throw "Slack returned invalid_code. The authorization code may have expired or may have been generated for a different redirect URL. Rerun setup and complete the browser approval promptly."
        }

        if ($slackError -eq "invalid_arguments") {
            throw "Slack returned invalid_arguments. If this Slack app has PKCE enabled, Slack may reject a confidential-client exchange for a localhost redirect. Use an app that has not opted into PKCE for this alternative flow."
        }

        throw "Slack token exchange failed: $slackError"
    }

    if (-not $tokenResponse.PSObject.Properties["access_token"] -or [string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
        throw "Slack token exchange succeeded but did not return an access_token. Check the Slack app OAuth settings and requested user scopes."
    }

    $accessToken = [string]$tokenResponse.access_token
    if ($accessToken.StartsWith("xoxe.xoxp-")) {
        Write-Warning "Slack returned an expiring user token. This alternative flow was expected to produce a long-lived user token when token rotation is disabled. Check whether the Slack app has PKCE or token rotation enabled."
    }
    elseif (-not ($accessToken.StartsWith("xoxp-") -or $accessToken.StartsWith("xoxe.xoxp-"))) {
        Write-Warning "Slack returned a token format this helper does not recognize. Continuing, but confirm this token can access Slack MCP if setup fails."
    }

    $authTest = Test-SlackToken -AccessToken $accessToken
    if ($null -ne $authTest) {
        if ($true -eq $authTest.ok) {
            Write-Host "Slack token verified for user '$($authTest.user)' ($($authTest.user_id)) in workspace '$($authTest.team)' ($($authTest.team_id))."
        }
        else {
            $authError = if ($authTest.PSObject.Properties["error"]) { $authTest.error } else { "unknown_error" }
            Write-Warning "Slack auth.test did not accept the returned token: $authError"
        }
    }

    [Environment]::SetEnvironmentVariable("SLACK_MCP_TOKEN", $accessToken, "User")
    $env:SLACK_MCP_TOKEN = $accessToken

    $vsCodeResult = $null
    if (Confirm-SetupStep -Prompt "Add Slack MCP to Visual Studio Code user configuration?") {
        $vsCodeResult = Update-VsCodeMcpConfig -ConfiguredServerName $ServerName
    }

    $copilotResult = $null
    if (Confirm-SetupStep -Prompt "Add Slack MCP to GitHub Copilot CLI configuration?") {
        $copilotResult = Update-CopilotMcpConfig -ConfiguredServerName $ServerName
    }

    Write-Host ""
    Write-Host "Slack MCP setup complete."
    Write-Host "Saved SLACK_MCP_TOKEN as a Windows user environment variable."
    if ($null -ne $vsCodeResult) {
        Write-Host "Configured VS Code MCP file: $($vsCodeResult.ConfigPath)"
        if ($null -ne $vsCodeResult.BackupPath) {
            Write-Host "Backup of previous VS Code config: $($vsCodeResult.BackupPath)"
        }
    }
    if ($null -ne $copilotResult) {
        Write-Host "Configured Copilot CLI MCP file: $($copilotResult.ConfigPath)"
        if ($null -ne $copilotResult.BackupPath) {
            Write-Host "Backup of previous Copilot config: $($copilotResult.BackupPath)"
        }
    }
    Write-Host ""
    Write-Host "Open a new terminal before running shell-based tools so they can read the new SLACK_MCP_TOKEN environment variable."
    Write-Host "Fully restart VS Code before using the Slack MCP server there."
    Write-Host "In Copilot CLI, run gh copilot and use /mcp show $ServerName to verify the Slack MCP server."
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
