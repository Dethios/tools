$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
    [string]$Root
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = $env:WORKSPACE_ROOT }
if (-not $Root) { $Root = Join-Path $scriptDir '..' }
$root = Resolve-Path $Root

$configPath = $env:SETTINGS_CONFIG
if (-not $configPath) {
    $configPath = Join-Path $root 'settings_sources.json'
}

# Sync VS Code settings if config exists
if (Test-Path $configPath) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 (Join-Path $scriptDir 'settings_manager.py') --config $configPath sync
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        & python3 (Join-Path $scriptDir 'settings_manager.py') --config $configPath sync
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        & python (Join-Path $scriptDir 'settings_manager.py') --config $configPath sync
    } else {
        Write-Warning 'settings sync skipped: python not found'
    }
}

& (Join-Path $scriptDir 'workspace-pull.ps1') -Root $root

if (-not $IsWindows) {
    if (Get-Command apt-get -ErrorAction SilentlyContinue) {
        sudo /usr/bin/apt-get update
        sudo /usr/bin/apt-get -y upgrade
    }

    $tlmgr = (Get-Command tlmgr -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $tlmgr) {
        Get-ChildItem -Path /usr/local/texlive/*/bin/*/tlmgr -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $tlmgr -and $_.FullName) { $tlmgr = $_.FullName }
        }
    }
    if ($tlmgr) {
        sudo $tlmgr update --self --all
    }

    if (Get-Command brew -ErrorAction SilentlyContinue) {
        brew update
        brew upgrade
    }
} else {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget upgrade --all --accept-source-agreements --accept-package-agreements
    }
}

if (Get-Command corepack -ErrorAction SilentlyContinue) {
    corepack enable
    corepack prepare pnpm@latest --activate
    corepack prepare yarn@stable --activate
}
if (Get-Command npm -ErrorAction SilentlyContinue) {
    npm -g update
}
if ((Get-Command pnpm -ErrorAction SilentlyContinue) -and -not (Get-Command corepack -ErrorAction SilentlyContinue)) {
    pnpm -g add pnpm@latest
}

if (Get-Command pipx -ErrorAction SilentlyContinue) {
    pipx upgrade-all
}
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    rustup update
}

& (Join-Path $scriptDir 'scrub.ps1') -Root $root
