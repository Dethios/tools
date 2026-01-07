$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $env:WORKSPACE_ROOT
if (-not $root) {
    $root = Resolve-Path (Join-Path $scriptDir '..')
}

if ($args.Count -ge 2 -and $args[0] -eq '--root') {
    $root = $args[1]
    if ($args.Count -gt 2) {
        $args = $args[2..($args.Count - 1)]
    } else {
        $args = @()
    }
}
$root = Resolve-Path $root

# Config
$defaultMsg = "Auto-commit: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'"))"
try {
    $branch = (git -C $root rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if (-not $branch) { $branch = 'main' }
} catch {
    $branch = 'main'
}

$configPath = $env:SETTINGS_CONFIG
if (-not $configPath) {
    $configPath = Join-Path $root 'settings_sources.json'
}

# Keep settings_master in sync before staging/commit (if config exists)
if (Test-Path $configPath) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 (Join-Path $scriptDir 'settings_manager.py') --config $configPath merge
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        & python3 (Join-Path $scriptDir 'settings_manager.py') --config $configPath merge
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python (Join-Path $scriptDir 'settings_manager.py') --config $configPath merge
    } else {
        Write-Warning 'settings merge skipped: python not found'
        exit 1
    }
}

# Guardrails: block obvious secret-like paths
$blockPatterns = @(
    '\.env'
    'id_rsa|id_ed25519|_key$'
    'token|apikey|secret'
)

# 1) Refuse if patterns present in staged or untracked
$changedFiles = git -C $root ls-files -o -m --exclude-standard
$combinedPattern = ($blockPatterns -join '|')
if ($changedFiles | Where-Object { $_ -match $combinedPattern }) {
    Write-Warning 'Potential secret-like files changed. Review before pushing.'
    $changedFiles | Where-Object { $_ -match $combinedPattern } | ForEach-Object { Write-Host $_ }
    exit 1
}

# 2) Stage & skip if nothing
git -C $root add -A
git -C $root diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to commit in $root."
    exit 0
}

# 3) Commit with message (arg or default)
$msg = if ($args.Count -gt 0) { $args[0] } else { $defaultMsg }
git -C $root commit -m $msg

# 4) Ensure upstream once
git -C $root rev-parse --symbolic-full-name --verify '@{u}' *> $null
if ($LASTEXITCODE -ne 0) {
    git -C $root push -u origin $branch
} else {
    git -C $root push
}

Write-Host "Pushed to $(git -C $root remote get-url origin) on branch $branch"
