<#
.SYNOPSIS
Authorizes the Dayshape Slack MCP app for the current Windows user and configures GitHub Copilot CLI.

.DESCRIPTION
This script performs a Slack OAuth user-token flow using PKCE. It does not use or require the Slack
client secret. The returned user token is stored in the current user's SLACK_MCP_TOKEN environment
variable, and GitHub Copilot CLI is configured to use Slack's hosted MCP endpoint.

.EXAMPLE
.\setup-slack-mcp-copilot.ps1 -ClientId "1234567890.1234567890123"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ClientId = "<REPLACE_WITH_SLACK_CLIENT_ID>",

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
        return $raw | ConvertFrom-Json -Depth 100
    }
    catch {
        throw "Could not parse existing Copilot MCP config at '$Path'. A backup has been created. Fix or remove this file, then rerun the script. Parse error: $($_.Exception.Message)"
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

if ([string]::IsNullOrWhiteSpace($ClientId) -or $ClientId -eq "<REPLACE_WITH_SLACK_CLIENT_ID>") {
    throw "Slack Client ID is required. Run: .\setup-slack-mcp-copilot.ps1 -ClientId `"YOUR_SLACK_CLIENT_ID`""
}

if ($Scopes.Count -eq 0) {
    throw "At least one Slack user scope is required."
}

$redirectUri = "http://localhost:$RedirectPort/slack/oauth/callback"
$listenerPrefix = "http://localhost:$RedirectPort/"
$codeVerifier = New-Base64UrlRandomString -ByteCount 64
$state = New-Base64UrlRandomString -ByteCount 32
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($codeVerifier))
}
finally {
    $sha256.Dispose()
}
$codeChallenge = ConvertTo-Base64Url -Bytes $challengeBytes

$authorizeQuery = ConvertTo-QueryString -Parameters @{
    client_id = $ClientId
    scope = ($Scopes -join ",")
    redirect_uri = $redirectUri
    state = $state
    code_challenge = $codeChallenge
    code_challenge_method = "S256"
}
$authorizeUrl = "https://slack.com/oauth/v2_user/authorize?$authorizeQuery"

$listener = [System.Net.HttpListener]::new()
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

    Write-BrowserResponse -Context $context -Title "Slack authorization complete" -Message "Slack authorization succeeded. The setup helper is finishing your local Copilot CLI configuration."

    $tokenBody = @{
        client_id = $ClientId
        code = $code
        redirect_uri = $redirectUri
        code_verifier = $codeVerifier
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

        throw "Slack token exchange failed: $slackError"
    }

    if (-not $tokenResponse.PSObject.Properties["access_token"] -or [string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
        throw "Slack token exchange succeeded but did not return an access_token. Check the Slack app OAuth settings and requested user scopes."
    }

    $accessToken = [string]$tokenResponse.access_token
    if (-not $accessToken.StartsWith("xoxp-")) {
        Write-Warning "Slack returned a token that does not start with xoxp-. Continuing, but confirm this is a user token if MCP access fails."
    }

    [Environment]::SetEnvironmentVariable("SLACK_MCP_TOKEN", $accessToken, "User")
    $env:SLACK_MCP_TOKEN = $accessToken

    $configResult = Update-CopilotMcpConfig -ConfiguredServerName $ServerName

    Write-Host ""
    Write-Host "Slack MCP setup complete."
    Write-Host "Configured Copilot MCP file: $($configResult.ConfigPath)"
    if ($null -ne $configResult.BackupPath) {
        Write-Host "Backup of previous config: $($configResult.BackupPath)"
    }
    Write-Host ""
    Write-Host "Open a new terminal before running GitHub Copilot CLI so it can read the new SLACK_MCP_TOKEN environment variable."
    Write-Host "Then run gh copilot and use /mcp show $ServerName to verify the Slack MCP server."
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
