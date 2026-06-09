# Codex 一键更新器

一个给 Windows 用户使用的图形化 Codex MSIX 更新工具。

它的目标很简单：当 Microsoft Store 无法自动更新 Codex，或者 Codex 因更新器问题闪退时，用一个小窗口完成“查找最新版安装包、下载、校验微软签名、安装”的流程。

> 这是非官方工具，不隶属于 OpenAI 或 Microsoft。它只负责下载并安装 Microsoft 签名有效的 Codex MSIX 包。

## 功能

- 图形化界面，不需要盯着 PowerShell 黑框。
- 自动通过 Codex 的 Microsoft Store 产品 ID 查找最新版 x64 MSIX。
- 从微软 CDN 下载安装包。
- 安装前校验 Authenticode 数字签名，签发者必须包含 Microsoft。
- 支持安装本地 `.msix` 文件。
- 支持创建桌面图标。
- 支持一键切换到管理员模式。
- 支持单独检查当前版本是否已经是最新版。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `Start-CodexUpdater.vbs` | 双击启动图形界面，不显示 PowerShell 黑框 |
| `CodexUpdater.ps1` | 主程序 |
| `CodexUpdater.ico` | 桌面快捷方式图标 |
| `Create-DesktopShortcut.ps1` | 创建桌面快捷方式 |
| `Fix-DesktopIcon.ps1` | 修复旧快捷方式图标 |
| `README.md` | 使用说明 |

## 使用方法

1. 下载本仓库 ZIP，并解压到任意目录。
2. 建议先打开代理，最好使用 Clash 的 TUN / 全局模式。
3. 双击 `Start-CodexUpdater.vbs`。
4. 先点击 `检查版本`，确认当前版本是否已经是最新版。
5. 如果提示发现新版本，再点击 `检查并更新`。
6. 如果安装阶段被 Windows 拒绝权限，点击 `管理员模式`，在 UAC 弹窗里点“是”，然后再点 `检查并更新`。

## 按钮说明

- `检查版本`：只查询最新版并和当前安装版本对比，不下载、不安装。
- `检查并更新`：自动查找最新版 Codex MSIX，下载、验签、安装。
- `安装本地包`：选择已经下载好的 `.msix` 文件安装。
- `打开 Codex`：安装完成后启动 Codex。
- `创建图标`：在桌面创建启动器快捷方式。
- `管理员模式`：用管理员权限重新打开这个图形界面，用来解决安装权限被拒绝的问题。

## 网络说明

自动更新需要访问两类地址：

- `store.rg-adguard.net`：用于解析 Microsoft Store 包列表。
- `*.delivery.mp.microsoft.com`：微软 CDN，用于下载真实 MSIX 包。

国内网络环境下，这两段连接都可能不稳定。建议先开启 TUN / 全局代理，再运行更新。

## 安全说明

这个工具不会安装签名异常的安装包。安装前会检查：

- 文件存在且大小合理；
- Authenticode 签名状态为 `Valid`；
- 签发者包含 `Microsoft`。

如果签名校验失败，程序会停止安装。

## 常见问题

### 管理员模式是什么意思？

就是用管理员权限重新打开这个图形界面。底层等价于“以管理员身份运行 PowerShell”，但你不需要自己打开命令行。

### 为什么不直接用 Microsoft Store？

有些 Windows 环境里 Store 更新会卡住、报错，或者 Codex 的内置更新器触发闪退。这个工具绕开 Store 客户端，直接安装 Microsoft 签名的 MSIX 包。

### 会把 500MB 的 MSIX 包放进仓库吗？

不会。仓库只包含更新器本身。MSIX 包会在使用时下载到：

```text
%USERPROFILE%\Downloads\codex-msix
```
### Windows 提示脚本被阻止怎么办？

如果文件是从网上下载的，Windows 可能会阻止脚本。可以右键 ZIP 或脚本文件，打开“属性”，点击“解除锁定”。

## 致谢

本项目由 shepherdleong-art 制作。

开发与整理过程中使用了：

- OpenAI Codex
- Claude Code
