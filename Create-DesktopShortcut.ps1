$ErrorActionPreference = 'Stop'

$launcher = Join-Path $PSScriptRoot 'Start-CodexUpdater.vbs'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Launcher not found: $launcher"
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Codex MSIX Updater.lnk'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = (Join-Path $PSScriptRoot 'CodexUpdater.ico')
$shortcut.Description = 'Update Codex from Microsoft-signed MSIX package'
$shortcut.Save()

Write-Host "Created: $shortcutPath"
