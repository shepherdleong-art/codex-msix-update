param(
    [string]$SaveDir = "$env:USERPROFILE\Downloads\codex-msix"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

$script:ProductId = '9PLM9XGG6VKS'
$script:ApiUrl = 'https://store.rg-adguard.net/api/GetFiles'
$script:PackageName = 'OpenAI.Codex'
$script:PackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0'
$script:Latest = $null
$script:LastDownloadedPath = $null

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-ControlFont([float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
    return New-Object System.Drawing.Font('Microsoft YaHei UI', $size, $style)
}

function Set-ButtonStyle($button, [System.Drawing.Color]$backColor, [System.Drawing.Color]$foreColor) {
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $backColor
    $button.ForeColor = $foreColor
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
}

function Append-Log([string]$message) {
    $time = Get-Date -Format 'HH:mm:ss'
    $logBox.AppendText("[$time] $message`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-State([string]$message, [int]$percent) {
    $statusLabel.Text = $message
    if ($percent -lt 0) { $percent = 0 }
    if ($percent -gt 100) { $percent = 100 }
    $progressBar.Value = $percent
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool]$busy) {
    $btnUpdate.Enabled = -not $busy
    $btnLocal.Enabled = -not $busy
    $btnOpen.Enabled = -not $busy
    $btnShortcut.Enabled = -not $busy
    $btnAdmin.Enabled = -not $busy
    $ringBox.Enabled = -not $busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-InstalledCodexPackage {
    return Get-AppxPackage -Name $script:PackageName -ErrorAction SilentlyContinue
}

function Refresh-InstalledState {
    $pkg = Get-InstalledCodexPackage
    if ($pkg) {
        $currentValue.Text = "$($pkg.Version) ($($pkg.Status))"
    } else {
        $currentValue.Text = '未安装'
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Resolve-LatestMsix([string]$ring) {
    Set-State "正在查找最新版 Codex 安装包..." 10
    Append-Log "正在通过 Microsoft Store 产品 ID 查询包列表：$script:ProductId，通道=$ring"

    $headers = @{
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        'Referer' = 'https://store.rg-adguard.net/'
    }
    $body = "type=ProductId&url=$script:ProductId&ring=$ring&lang=zh-CN"

    $resp = Invoke-WebRequest -Uri $script:ApiUrl -Method POST `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 60

    $pattern = '<a href="(?<url>http[^"]+)"[^>]*>(?<name>OpenAI\.Codex_(?<ver>\d+\.\d+\.\d+\.\d+)_x64__[^<]+\.msix)</a>'
    $matches = [regex]::Matches($resp.Content, $pattern)

    if ($matches.Count -eq 0) {
        throw "没有找到 OpenAI.Codex x64 MSIX 包。请先打开 TUN/全局代理，或切换更新通道后重试。"
    }

    $packages = foreach ($m in $matches) {
        [PSCustomObject]@{
            Name = $m.Groups['name'].Value
            Url = $m.Groups['url'].Value
            Version = [version]$m.Groups['ver'].Value
        }
    }

    $latest = $packages | Sort-Object Version -Descending | Select-Object -First 1
    Append-Log "找到最新版安装包：$($latest.Name)"
    $latestValue.Text = "$($latest.Version)"
    Set-State "已找到 $($latest.Name)" 20
    return $latest
}

function Confirm-MsixSignature([string]$path) {
    Set-State "正在校验微软数字签名..." 75
    Append-Log "正在校验数字签名：$path"

    if (-not (Test-Path -LiteralPath $path)) {
        throw "安装包文件不存在：$path"
    }

    $size = (Get-Item -LiteralPath $path).Length
    if ($size -lt 100MB) {
        throw "这个安装包太小，不像完整的 Codex MSIX，可能下载不完整。"
    }

    $sig = Get-AuthenticodeSignature -LiteralPath $path
    if ($sig.Status -ne 'Valid') {
        throw "安装包数字签名无效：$($sig.Status)"
    }

    $issuer = ''
    if ($sig.SignerCertificate) {
        $issuer = $sig.SignerCertificate.Issuer
    }
    if ($issuer -notmatch 'Microsoft') {
        throw "安装包虽然有签名，但签发者不是 Microsoft：$issuer"
    }

    Append-Log "签名通过：$issuer"
}

function Download-Msix($package) {
    if (-not (Test-Path -LiteralPath $SaveDir)) {
        New-Item -ItemType Directory -Path $SaveDir | Out-Null
    }

    $dest = Join-Path $SaveDir $package.Name
    if (Test-Path -LiteralPath $dest) {
        Append-Log "发现本地已有安装包，直接复用：$dest"
        Confirm-MsixSignature $dest
        $script:LastDownloadedPath = $dest
        return $dest
    }

    $temp = "$dest.download"
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force
    }

    Set-State "正在下载 Codex MSIX..." 30
    Append-Log "下载保存到：$dest"
    Append-Log "网络提示：国内环境建议先打开 Clash 的 TUN/全局代理。"

    $request = [System.Net.HttpWebRequest]::Create($package.Url)
    $request.AllowAutoRedirect = $true
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $response = $request.GetResponse()

    try {
        $total = $response.ContentLength
        $inputStream = $response.GetResponseStream()
        $outputStream = [System.IO.File]::Open($temp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $buffer = New-Object byte[] (1024 * 1024)
            $readTotal = 0L
            $lastReport = Get-Date
            while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $read)
                $readTotal += $read
                if (((Get-Date) - $lastReport).TotalMilliseconds -gt 300) {
                    if ($total -gt 0) {
                        $downloadPercent = [int](30 + (($readTotal / $total) * 40))
                        $mbDone = [math]::Round($readTotal / 1MB, 1)
                        $mbTotal = [math]::Round($total / 1MB, 1)
                        Set-State "正在下载... $mbDone MB / $mbTotal MB" $downloadPercent
                    } else {
                        $mbDone = [math]::Round($readTotal / 1MB, 1)
                        Set-State "正在下载... $mbDone MB" 45
                    }
                    $lastReport = Get-Date
                }
            }
        } finally {
            $outputStream.Close()
            $inputStream.Close()
        }
    } finally {
        $response.Close()
    }

    Move-Item -LiteralPath $temp -Destination $dest -Force
    Append-Log "下载完成。"
    Confirm-MsixSignature $dest
    $script:LastDownloadedPath = $dest
    return $dest
}

function Install-Msix([string]$path, [bool]$skipVersionCheck) {
    Confirm-MsixSignature $path

    $current = Get-InstalledCodexPackage
    $targetVersion = $null
    if ((Split-Path -Leaf $path) -match 'OpenAI\.Codex_(?<ver>\d+\.\d+\.\d+\.\d+)_x64__') {
        $targetVersion = [version]$Matches['ver']
    }

    if (-not $skipVersionCheck -and $current -and $targetVersion) {
        $currentVersion = [version]$current.Version
        if ($targetVersion -le $currentVersion) {
            Append-Log "当前已安装版本是 $currentVersion，目标安装包版本是 $targetVersion。"
            Set-State "Codex 已经是最新版本。" 100
            [System.Windows.Forms.MessageBox]::Show(
                "Codex 当前已是 $currentVersion。`r`n不需要更新。",
                "已经是最新版本",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }
    }

    Set-State "正在安装 MSIX 包..." 85
    Append-Log "正在调用 Windows 原生安装流程。Codex 可能会被自动关闭。"

    try {
        Add-AppxPackage -Path $path -ForceApplicationShutdown -ErrorAction Stop
    } catch {
        $message = $_.Exception.Message
        if ($message -match 'Access is denied|0x80070005') {
            throw "Windows 拒绝了安装权限。请关闭 Codex，然后点击[管理员模式]重新打开本工具。原始错误：$message"
        }
        throw
    }

    Refresh-InstalledState
    $pkg = Get-InstalledCodexPackage
    if (-not $pkg) {
        throw "安装流程结束了，但系统里没有检测到 OpenAI.Codex。"
    }

    Set-State "安装完成。Codex 版本：$($pkg.Version)" 100
    Append-Log "安装完成。当前版本：$($pkg.Version)，状态：$($pkg.Status)"
    [System.Windows.Forms.MessageBox]::Show(
        "Codex 已更新成功。`r`n当前版本：$($pkg.Version)",
        "更新完成",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Invoke-UpdateFlow {
    Set-Busy $true
    try {
        Refresh-InstalledState
        Set-State "开始检查并更新..." 5
        $ring = [string]$ringBox.SelectedItem
        $script:Latest = Resolve-LatestMsix $ring
        $pkgPath = Download-Msix $script:Latest
        Install-Msix $pkgPath $false
    } catch {
        Set-State "更新失败。" 0
        Append-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "更新失败",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        Set-Busy $false
    }
}

function Invoke-InstallLocalFlow {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = '选择 Codex MSIX 安装包'
    $dialog.Filter = 'MSIX 安装包 (*.msix)|*.msix|所有文件 (*.*)|*.*'
    $dialog.InitialDirectory = $SaveDir

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    Set-Busy $true
    try {
        Install-Msix $dialog.FileName $true
    } catch {
        Set-State "本地安装失败。" 0
        Append-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "本地安装失败",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        Set-Busy $false
    }
}

function Open-Codex {
    try {
        Start-Process "shell:AppsFolder\$script:PackageFamilyName!App"
        Append-Log "已请求启动 Codex。"
    } catch {
        Append-Log "ERROR: 无法启动 Codex。$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "无法从 AppsFolder 启动 Codex。`r`n可以先从开始菜单手动打开。",
            "启动失败",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

function Create-DesktopShortcut {
    try {
        $launcher = Join-Path $PSScriptRoot 'Start-CodexUpdater.vbs'
        if (-not (Test-Path -LiteralPath $launcher)) {
            throw "Launcher file not found: $launcher"
        }

        $desktop = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktop 'Codex 一键更新器.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $launcher
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.IconLocation = (Join-Path $PSScriptRoot 'CodexUpdater.ico')
        $shortcut.Description = '通过微软签名 MSIX 更新 Codex'
        $shortcut.Save()

        Append-Log "桌面快捷方式已创建：$shortcutPath"
        [System.Windows.Forms.MessageBox]::Show(
            "桌面快捷方式已创建。",
            "快捷方式",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        Append-Log "ERROR: 无法创建快捷方式。$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "创建快捷方式失败",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Restart-AsAdministrator {
    try {
        $args = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden',
            '-File', "`"$PSCommandPath`"",
            '-SaveDir', "`"$SaveDir`""
        )
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs
        Append-Log "正在以管理员权限重新打开..."
        $form.Close()
    } catch {
        Append-Log "ERROR: 无法以管理员权限重启。$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "管理员模式启动失败",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex 一键更新器'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(780, 620)
$form.MinimumSize = New-Object System.Drawing.Size(720, 560)
$form.BackColor = [System.Drawing.Color]::FromArgb(250, 248, 244)
$form.Font = New-ControlFont 9

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 92
$header.BackColor = [System.Drawing.Color]::FromArgb(19, 31, 43)
$form.Controls.Add($header)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = 'Codex 一键更新器'
$titleLabel.Font = New-ControlFont 20 ([System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(24, 18)
$header.Controls.Add($titleLabel)

$subLabel = New-Object System.Windows.Forms.Label
$subLabel.Text = '自动查找最新版安装包，校验微软签名，然后替你完成更新。'
$subLabel.Font = New-ControlFont 9
$subLabel.ForeColor = [System.Drawing.Color]::FromArgb(207, 216, 226)
$subLabel.AutoSize = $true
$subLabel.Location = New-Object System.Drawing.Point(27, 56)
$header.Controls.Add($subLabel)

$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.Padding = New-Object System.Windows.Forms.Padding(24)
$content.BackColor = $form.BackColor
$form.Controls.Add($content)
$header.BringToFront()

$currentCaption = New-Object System.Windows.Forms.Label
$currentCaption.Text = '当前版本'
$currentCaption.Font = New-ControlFont 9 ([System.Drawing.FontStyle]::Bold)
$currentCaption.Location = New-Object System.Drawing.Point(24, 24)
$currentCaption.Size = New-Object System.Drawing.Size(130, 22)
$content.Controls.Add($currentCaption)

$currentValue = New-Object System.Windows.Forms.Label
$currentValue.Text = '正在检测...'
$currentValue.Location = New-Object System.Drawing.Point(160, 24)
$currentValue.Size = New-Object System.Drawing.Size(250, 22)
$content.Controls.Add($currentValue)

$latestCaption = New-Object System.Windows.Forms.Label
$latestCaption.Text = '发现版本'
$latestCaption.Font = New-ControlFont 9 ([System.Drawing.FontStyle]::Bold)
$latestCaption.Location = New-Object System.Drawing.Point(430, 24)
$latestCaption.Size = New-Object System.Drawing.Size(95, 22)
$content.Controls.Add($latestCaption)

$latestValue = New-Object System.Windows.Forms.Label
$latestValue.Text = '尚未检查'
$latestValue.Location = New-Object System.Drawing.Point(530, 24)
$latestValue.Size = New-Object System.Drawing.Size(180, 22)
$content.Controls.Add($latestValue)

$ringLabel = New-Object System.Windows.Forms.Label
$ringLabel.Text = '更新通道'
$ringLabel.Font = New-ControlFont 9 ([System.Drawing.FontStyle]::Bold)
$ringLabel.Location = New-Object System.Drawing.Point(24, 58)
$ringLabel.Size = New-Object System.Drawing.Size(130, 24)
$content.Controls.Add($ringLabel)

$ringBox = New-Object System.Windows.Forms.ComboBox
$ringBox.DropDownStyle = 'DropDownList'
$ringBox.Items.Add('RP') | Out-Null
$ringBox.Items.Add('Retail') | Out-Null
$ringBox.SelectedIndex = 0
$ringBox.Location = New-Object System.Drawing.Point(160, 55)
$ringBox.Size = New-Object System.Drawing.Size(120, 26)
$content.Controls.Add($ringBox)

$proxyNote = New-Object System.Windows.Forms.Label
$proxyNote.Text = '提示：如果商店/微软下载不稳定，先打开 Clash 的 TUN 或全局代理。'
$proxyNote.ForeColor = [System.Drawing.Color]::FromArgb(90, 99, 112)
$proxyNote.Location = New-Object System.Drawing.Point(300, 58)
$proxyNote.Size = New-Object System.Drawing.Size(430, 24)
$content.Controls.Add($proxyNote)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text = '检查并更新'
$btnUpdate.Font = New-ControlFont 10 ([System.Drawing.FontStyle]::Bold)
$btnUpdate.Location = New-Object System.Drawing.Point(24, 104)
$btnUpdate.Size = New-Object System.Drawing.Size(155, 42)
$content.Controls.Add($btnUpdate)
Set-ButtonStyle $btnUpdate ([System.Drawing.Color]::FromArgb(34, 104, 80)) ([System.Drawing.Color]::White)

$btnLocal = New-Object System.Windows.Forms.Button
$btnLocal.Text = '安装本地包'
$btnLocal.Location = New-Object System.Drawing.Point(191, 104)
$btnLocal.Size = New-Object System.Drawing.Size(135, 42)
$content.Controls.Add($btnLocal)
Set-ButtonStyle $btnLocal ([System.Drawing.Color]::FromArgb(232, 226, 216)) ([System.Drawing.Color]::FromArgb(31, 41, 55))

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = '打开 Codex'
$btnOpen.Location = New-Object System.Drawing.Point(338, 104)
$btnOpen.Size = New-Object System.Drawing.Size(105, 42)
$content.Controls.Add($btnOpen)
Set-ButtonStyle $btnOpen ([System.Drawing.Color]::FromArgb(232, 226, 216)) ([System.Drawing.Color]::FromArgb(31, 41, 55))

$btnShortcut = New-Object System.Windows.Forms.Button
$btnShortcut.Text = '创建桌面图标'
$btnShortcut.Location = New-Object System.Drawing.Point(455, 104)
$btnShortcut.Size = New-Object System.Drawing.Size(120, 42)
$content.Controls.Add($btnShortcut)
Set-ButtonStyle $btnShortcut ([System.Drawing.Color]::FromArgb(232, 226, 216)) ([System.Drawing.Color]::FromArgb(31, 41, 55))

$btnAdmin = New-Object System.Windows.Forms.Button
$btnAdmin.Text = '管理员模式'
$btnAdmin.Location = New-Object System.Drawing.Point(587, 104)
$btnAdmin.Size = New-Object System.Drawing.Size(135, 42)
$content.Controls.Add($btnAdmin)
Set-ButtonStyle $btnAdmin ([System.Drawing.Color]::FromArgb(55, 65, 81)) ([System.Drawing.Color]::White)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = '准备好了。'
$statusLabel.Font = New-ControlFont 10
$statusLabel.Location = New-Object System.Drawing.Point(24, 166)
$statusLabel.Size = New-Object System.Drawing.Size(700, 26)
$content.Controls.Add($statusLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(24, 196)
$progressBar.Size = New-Object System.Drawing.Size(700, 22)
$progressBar.Style = 'Continuous'
$content.Controls.Add($progressBar)

$logCaption = New-Object System.Windows.Forms.Label
$logCaption.Text = '详细日志'
$logCaption.Font = New-ControlFont 9 ([System.Drawing.FontStyle]::Bold)
$logCaption.Location = New-Object System.Drawing.Point(24, 240)
$logCaption.Size = New-Object System.Drawing.Size(120, 22)
$content.Controls.Add($logCaption)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.WordWrap = $false
$logBox.Font = New-ControlFont 9
$logBox.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 249)
$logBox.Location = New-Object System.Drawing.Point(24, 266)
$logBox.Size = New-Object System.Drawing.Size(700, 226)
$logBox.Anchor = 'Top,Bottom,Left,Right'
$content.Controls.Add($logBox)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = '安全规则：只有微软签名有效的安装包才会被安装；签名失败会直接停止。'
$footer.ForeColor = [System.Drawing.Color]::FromArgb(90, 99, 112)
$footer.Location = New-Object System.Drawing.Point(24, 506)
$footer.Size = New-Object System.Drawing.Size(700, 28)
$footer.Anchor = 'Bottom,Left,Right'
$content.Controls.Add($footer)

$btnUpdate.Add_Click({ Invoke-UpdateFlow })
$btnLocal.Add_Click({ Invoke-InstallLocalFlow })
$btnOpen.Add_Click({ Open-Codex })
$btnShortcut.Add_Click({ Create-DesktopShortcut })
$btnAdmin.Add_Click({ Restart-AsAdministrator })

$form.Add_Shown({
    Refresh-InstalledState
    Append-Log "准备好了。下载目录：$SaveDir"
    if (Test-IsAdministrator) {
        Append-Log "当前是管理员权限。"
    } else {
        Append-Log "当前是普通权限。如果安装被拒绝，请点[管理员模式]。"
    }
})

[void][System.Windows.Forms.Application]::Run($form)
