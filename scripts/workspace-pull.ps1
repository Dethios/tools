$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
    [string]$Root
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = $env:WORKSPACE_ROOT }
if (-not $Root) { $Root = Join-Path $scriptDir '..' }
$root = Resolve-Path $Root

function Test-CleanRepo($path) {
    git -C $path diff --quiet
    if ($LASTEXITCODE -ne 0) { return $false }
    git -C $path diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { return $false }
    $dirty = git -C $path ls-files -o -m --exclude-standard
    return [string]::IsNullOrWhiteSpace(($dirty -join '').Trim())
}

if (-not (git -C $root rev-parse --git-dir *> $null)) {
    Write-Host "No git repo at $root"
    exit 0
}

if (Test-CleanRepo $root) {
    git -C $root pull --ff-only
} else {
    Write-Host "Skipping pull in $root (dirty working tree)"
}

git -C $root submodule update --init --recursive | Out-Null

$submoduleLines = git -C $root submodule status --recursive 2>$null
foreach ($line in $submoduleLines) {
    $parts = $line.Trim() -split '\s+'
    if ($parts.Count -lt 2) { continue }
    $path = $parts[1]
    $subPath = Join-Path $root $path
    if (-not (Test-Path $subPath)) { continue }
    if (Test-CleanRepo $subPath) {
        git -C $subPath pull --ff-only
    } else {
        Write-Host "Skipping $path (dirty working tree)"
    }
}
