$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
    [string]$Root
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = $env:WORKSPACE_ROOT }
if (-not $Root) { $Root = Join-Path $scriptDir '..' }
$root = Resolve-Path $Root

function Get-WorkspaceRepos($basePath) {
    $gitPaths = Get-ChildItem -Path $basePath -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' }
    $repos = $gitPaths | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique
    return @($repos)
}

function Get-TargetBranch($path) {
    git -C $path show-ref --verify --quiet 'refs/remotes/origin/main'
    if ($LASTEXITCODE -eq 0) { return 'main' }
    git -C $path show-ref --verify --quiet 'refs/remotes/origin/master'
    if ($LASTEXITCODE -eq 0) { return 'master' }
    return (git -C $path branch --show-current 2>$null).Trim()
}

foreach ($repo in (Get-WorkspaceRepos $root)) {
    if ([string]::IsNullOrWhiteSpace($repo)) { continue }

    if (-not (git -C $repo rev-parse --git-dir *> $null)) {
        Write-Host "Skipping $repo (not a git repo)"
        continue
    }

    git -C $repo remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Skipping $repo (no origin remote)"
        continue
    }

    $branch = Get-TargetBranch $repo
    if ($branch -eq 'master') {
        Write-Host "Skipping push in $repo (origin/master repos are pull-only)"
        continue
    }

    & (Join-Path $scriptDir 'push.ps1') --root $repo
}
