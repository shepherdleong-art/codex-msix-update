$ErrorActionPreference = 'Stop'

$icon = Join-Path $PSScriptRoot 'CodexUpdater.ico'
if (-not (Test-Path -LiteralPath $icon)) {
    throw "Icon file not found: $icon"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$candidateNames = @(
    'Codex 一键更新器.lnk',
    'Codex MSIX Updater.lnk'
)

$shortcuts = foreach ($name in $candidateNames) {
    $path = Join-Path $desktop $name
    if (Test-Path -LiteralPath $path) {
        $path
    }
}

if (-not $shortcuts) {
    $shortcuts = Get-ChildItem -LiteralPath $desktop -Filter '*Codex*.lnk' -File |
        Select-Object -ExpandProperty FullName
}

if (-not $shortcuts) {
    throw "No Codex shortcut was found on the desktop."
}

$shell = New-Object -ComObject WScript.Shell
foreach ($shortcutPath in $shortcuts) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.IconLocation = $icon
    $shortcut.Save()
    Write-Host "Updated icon: $shortcutPath"
}

Write-Host "Done. If the old icon is still visible, right-click the desktop and choose Refresh."
