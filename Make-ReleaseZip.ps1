$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$version = Get-Date -Format 'yyyyMMdd-HHmm'
$zipPath = Join-Path $root "CodexUpdater-$version.zip"

$items = @(
    'CodexUpdater.ps1',
    'Start-CodexUpdater.vbs',
    'CodexUpdater.ico',
    'Create-DesktopShortcut.ps1',
    'Fix-DesktopIcon.ps1',
    'README.md',
    'NOTICE.md'
)

$missing = $items | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) }
if ($missing) {
    throw "Missing required files: $($missing -join ', ')"
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("CodexUpdater-release-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null

try {
    foreach ($item in $items) {
        Copy-Item -LiteralPath (Join-Path $root $item) -Destination (Join-Path $temp $item)
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zipPath -Force
    Write-Host "Created: $zipPath"
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
