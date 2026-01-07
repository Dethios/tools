#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Root) {
    $Root = $env:WORKSPACE_ROOT
}
if (-not $Root) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$root = Resolve-Path $Root

$patterns = @(
    '*SAVE-ERROR*',
    '*.tmp',
    '*.temp',
    '*.lock',
    '*.lck',
    '*.auxlock',
    '*.synctex(busy)',
    '*.synctex.gz(busy)'
)

$files = Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\.git\\' } |
    Where-Object {
        $name = $_.Name
        foreach ($pattern in $patterns) {
            if ($name -like $pattern) { return $true }
        }
        return $false
    }

if ($DryRun) {
    $files | ForEach-Object { Write-Output $_.FullName }
} else {
    $files | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
}
