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
    return $null
}

function Checkout-TargetBranch($path, $branch) {
    $current = (git -C $path branch --show-current 2>$null).Trim()
    if ($current -eq $branch) { return }

    git -C $path show-ref --verify --quiet "refs/heads/$branch"
    if ($LASTEXITCODE -eq 0) {
        git -C $path checkout $branch
    } else {
        git -C $path checkout -b $branch --track "origin/$branch"
    }
}

function Update-Repo($path) {
    if (-not (git -C $path rev-parse --git-dir *> $null)) {
        Write-Host "Skipping $path (not a git repo)"
        return
    }

    git -C $path remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Skipping $path (no origin remote)"
        return
    }

    if (-not (Test-CleanRepo $path)) {
        Write-Host "Skipping pull in $path (dirty working tree)"
        return
    }

    git -C $path fetch origin --prune
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Fetch failed in $path"
        return
    }

    $branch = Get-TargetBranch $path
    if (-not $branch) {
        Write-Host "Skipping $path (no origin/main or origin/master)"
        return
    }

    Checkout-TargetBranch $path $branch
    git -C $path pull --no-rebase origin $branch
}

if (-not (git -C $root rev-parse --git-dir *> $null)) {
    Write-Host "No git repo at $root"
    exit 0
}

foreach ($repo in (Get-WorkspaceRepos $root)) {
    if (-not [string]::IsNullOrWhiteSpace($repo)) {
        Update-Repo $repo
    }
}
