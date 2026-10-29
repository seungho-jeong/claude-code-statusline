# Claude Code Statusline — Windows installer (PowerShell 5.1+).
#
# Usage:
#   .\install.ps1                    # install statusline.js (Node)
#   .\install.ps1 -Source <path>     # install from a local file instead of HTTP
#   .\install.ps1 -DryRun            # backup + plan only; no download or settings edit
#
# Pre-existing files in $env:USERPROFILE\.claude (statusline.{sh,js},
# settings.json) are backed up to *.bak.<yyyyMMdd-HHmmss> before any change.
# Backup paths are printed on exit.

[CmdletBinding()]
param(
    [string]$Source = "",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$RepoRaw   = "https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main"
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$Settings  = Join-Path $ClaudeDir "settings.json"

$Dest = Join-Path $ClaudeDir "statusline.js"
$Src  = "statusline.js"
$Cmd  = "node `"$Dest`""

# Node version gate.
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw "node v18+ required but not found on PATH."
}
$version = (& node -e "process.stdout.write(String(process.versions.node.split('.')[0]))" 2>$null)
if ([int]$version -lt 18) {
    throw "node v18+ required (found v$version)."
}

# Ensure ~/.claude exists.
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
}

# Timestamped backup of any pre-existing assets (including a legacy
# statusline.sh from releases before 0.3.0). Bail on first failure.
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$backups = @()
foreach ($f in @(
    (Join-Path $ClaudeDir "statusline.sh"),
    (Join-Path $ClaudeDir "statusline.js"),
    $Settings
)) {
    if (Test-Path $f) {
        $bak = "$f.bak.$ts"
        Copy-Item -Path $f -Destination $bak -ErrorAction Stop
        $backups += $bak
    }
}

if ($DryRun) {
    Write-Host "dry-run: backups created (no download or settings edit)."
    if ($backups.Count -gt 0) {
        Write-Host "backups:"
        foreach ($b in $backups) { Write-Host "  $b" }
    }
    exit 0
}

# Atomic download: write to tmp, then Move-Item -Force onto destination.
$tmp = New-TemporaryFile
try {
    if ($Source -ne "") {
        Copy-Item -Path $Source -Destination $tmp.FullName -Force
    } else {
        Invoke-WebRequest -Uri "$RepoRaw/$Src" -OutFile $tmp.FullName -UseBasicParsing
    }
    Move-Item -Path $tmp.FullName -Destination $Dest -Force
} catch {
    Remove-Item -Path $tmp.FullName -ErrorAction SilentlyContinue
    throw
}

# Update settings.json. ConvertFrom-Json + ConvertTo-Json round-trip preserves
# unrelated keys; -Depth 10 covers nested hook/permission objects.
$line = [PSCustomObject]@{
    type                 = "command"
    command              = $Cmd
    padding              = 0
    refreshInterval      = 30
}

if (Test-Path $Settings) {
    $raw = Get-Content -Raw -Path $Settings
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $obj = [PSCustomObject]@{}
    } else {
        $obj = $raw | ConvertFrom-Json
    }
    if ($obj.PSObject.Properties.Name -contains "statusLine") {
        $obj.statusLine = $line
    } else {
        Add-Member -InputObject $obj -MemberType NoteProperty -Name "statusLine" -Value $line
    }
    $tmpJson = New-TemporaryFile
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $tmpJson.FullName -Encoding UTF8
    Move-Item -Path $tmpJson.FullName -Destination $Settings -Force
} else {
    $obj = [PSCustomObject]@{ statusLine = $line }
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $Settings -Encoding UTF8
}

Write-Host "installed. restart Claude Code to apply."
if ($backups.Count -gt 0) {
    Write-Host "backups:"
    foreach ($b in $backups) { Write-Host "  $b" }
}
