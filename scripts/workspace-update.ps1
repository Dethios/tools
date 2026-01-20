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

try {
    & (Join-Path $scriptDir 'workspace-pull.ps1') -Root $root
} catch {
    Write-Warning "workspace-pull failed: $($_.Exception.Message)"
}

$isWindowsOS = $IsWindows -or ($env:OS -eq 'Windows_NT')
if (-not $isWindowsOS) {
    if ((Get-Command apt-get -ErrorAction SilentlyContinue) -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
        try {
            sudo /usr/bin/apt-get update
            sudo /usr/bin/apt-get -y upgrade
        } catch {
            Write-Warning "apt-get update failed: $($_.Exception.Message)"
        }
    }

    $tlmgr = (Get-Command tlmgr -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $tlmgr) {
        Get-ChildItem -Path /usr/local/texlive/*/bin/*/tlmgr -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $tlmgr -and $_.FullName) { $tlmgr = $_.FullName }
        }
    }
    if ($tlmgr -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
        try {
            sudo $tlmgr update --self --all
        } catch {
            Write-Warning "tlmgr update failed: $($_.Exception.Message)"
        }
    }

    if (Get-Command brew -ErrorAction SilentlyContinue) {
        try {
            brew update
            brew upgrade
        } catch {
            Write-Warning "brew update failed: $($_.Exception.Message)"
        }
    }
} else {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget upgrade --all --accept-source-agreements --accept-package-agreements
        } catch {
            Write-Warning "winget upgrade failed: $($_.Exception.Message)"
        }
    }
}

if (Get-Command corepack -ErrorAction SilentlyContinue) {
    try {
        corepack enable
        corepack prepare pnpm@latest --activate
        corepack prepare yarn@stable --activate
    } catch {
        Write-Warning "corepack update failed: $($_.Exception.Message)"
    }
}
if (Get-Command npm -ErrorAction SilentlyContinue) {
    try {
        npm -g update
    } catch {
        Write-Warning "npm update failed: $($_.Exception.Message)"
    }
}
if ((Get-Command pnpm -ErrorAction SilentlyContinue) -and -not (Get-Command corepack -ErrorAction SilentlyContinue)) {
    try {
        pnpm -g add pnpm@latest
    } catch {
        Write-Warning "pnpm update failed: $($_.Exception.Message)"
    }
}

pnpm -g add @openai/codex
pnpm -g add @google/gemini-cli
pnpm -g add gh
pnpm -g update

if (Get-Command go -ErrorAction SilentlyContinue) {
    try {
        go install mvdan.cc/sh/v3/cmd/shfmt@latest
    } catch {
        Write-Warning "shfmt update failed: $($_.Exception.Message)"
    }
}

if (Get-Command pipx -ErrorAction SilentlyContinue) {
    try {
        pipx upgrade-all
    } catch {
        Write-Warning "pipx update failed: $($_.Exception.Message)"
    }
}
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    try {
        rustup update
    } catch {
        Write-Warning "rustup update failed: $($_.Exception.Message)"
    }
}

try {
    & (Join-Path $scriptDir 'scrub.ps1') -Root $root
} catch {
    Write-Warning "scrub failed: $($_.Exception.Message)"
}
