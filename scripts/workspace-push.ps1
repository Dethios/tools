$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
    [string]$Root
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = $env:WORKSPACE_ROOT }
if (-not $Root) { $Root = Join-Path $scriptDir '..' }
$root = Resolve-Path $Root

& (Join-Path $scriptDir 'push.ps1') --root $root

$submoduleLines = git -C $root submodule status --recursive 2>$null
foreach ($line in $submoduleLines) {
    $parts = $line.Trim() -split '\s+'
    if ($parts.Count -lt 2) { continue }
    $path = $parts[1]
    $subPath = Join-Path $root $path
    if (-not (Test-Path $subPath)) { continue }
    & (Join-Path $scriptDir 'push.ps1') --root $subPath
}
