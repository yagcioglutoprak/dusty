<div align="center">

<img src="../../Dusty/Dusty/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" height="96" alt="">

# Dusty

**释放 Mac 磁盘空间，删除前每个文件都一目了然。**

一款常驻菜单栏的免费开源 CleanMyMac 替代品。

[![Release](https://img.shields.io/github/v/release/yagcioglutoprak/dusty?color=3b82f6&label=Release)](https://github.com/yagcioglutoprak/dusty/releases/latest)
[![CI](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml/badge.svg)](https://github.com/yagcioglutoprak/dusty/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/github/license/yagcioglutoprak/dusty?color=6366f1)](../../LICENSE)
[![Stars](https://img.shields.io/github/stars/yagcioglutoprak/dusty?label=Stars&color=38bdf8)](https://github.com/yagcioglutoprak/dusty/stargazers)

[English](../../README.md) · **简体中文** · [日本語](README.ja.md) · [Español](README.es.md) · [Français](README.fr.md) · [Русский](README.ru.md)

[**下载**](https://github.com/yagcioglutoprak/dusty/releases/latest) ·
[安装](#安装) ·
[清理范围](#清理范围) ·
[为什么安全](#为什么值得信任) ·
[命令行](#命令行与快捷指令) ·
[常见问题](#常见问题)

<br>

<img src="../screenshots/demo.gif?v=4" width="480" alt="Dusty 的首次启动欢迎页、进行中的扫描、按级别统计的可释放空间、一次带撤销倒计时的安全级别清理，以及逐项列出的开发者级别">

<sub>如果 Dusty 帮你省出了空间，在 GitHub 上点个 Star，就能让更多 Mac 用户找到一款更安全的清理工具。</sub>

</div>

> 本页为译文。[英文 README](../../README.md) 始终是最新版本。

## 概览

- **一切都看得见。** 在删除任何内容之前，每个路径及其大小都会显示在屏幕上。扫描本身从不删除任何东西。
- **只会碰垃圾文件。** 删除范围限定在一份固定、可查阅的白名单内，其中只有缓存和残留文件。你的文稿、照片和邮件在设计上就不在它的触及范围内。
- **每次清理都能撤销。** 清理的项目会先经过废纸篓，几秒内都可以点按“撤销”按钮恢复，每一次删除也都会写入日志。
- **认得开发者的垃圾文件。** 它能识别 Xcode DerivedData 和模拟器，npm、Cargo、pip 的缓存，还有你早已忘在一边的项目里的 `node_modules`。
- **速度快。** 在一台日常使用的开发机上（M3，866 个路径，共约 18 GB），完整扫描大约只需 5 秒。
- **不打扰你。** 可用空间显示在菜单栏中，后台扫描让“待清理”数值随时保持最新，应用也会自行更新。
- **不花一分钱。** 免费，采用 MIT 许可证，无需账户，不收集遥测数据。

## 安装

```bash
brew install --cask yagcioglutoprak/tap/dusty
```

也可以从[最新版本](https://github.com/yagcioglutoprak/dusty/releases/latest)下载 `Dusty.dmg`，将它拖到“应用程序”文件夹后打开。两种方式得到的应用都已签名，并经过 Apple 公证。

Dusty 会以磁盘图标的形式出现在菜单栏中，旁边显示当前的可用空间。它需要 macOS 13 Ventura 或更高版本，并会自动保持更新（可以在设置中关闭）。

Dusty 的面板目前提供英语、法语、西班牙语和俄语版本。简体中文面板欢迎贡献者参与，详见 [#34](https://github.com/yagcioglutoprak/dusty/issues/34)。

## 工作方式

1. **扫描。** 点按磁盘图标并开始扫描。Dusty 会测量每个清理目标的大小，把找到的内容分为三个级别，并按从大到小排列。
2. **查看。** 一键即可清理安全（Safe）级别。你也可以打开任意级别，逐项取消勾选想保留的内容。底部的信息栏会始终显示本次清理将移除多少内容。
3. **清理，并留有退路。** 确认界面会列出每个路径，以及清理前后的可用空间。清理完成后，你有几秒钟可以改变主意：按下“撤销”（或 ⌘Z），清理掉的项目就会回到原来的位置。

<p align="center">
<img src="../screenshots/overview.png" alt="Dusty 的面板：带有存储空间条和一键安全清理的主界面、逐项列出的开发者级别、确认界面，以及设置">
</p>

## 清理范围

三个级别，从“随时都可以清”到“动手前先看清楚”。

| 级别 | 清理内容 | 为什么安全 |
| --- | --- | --- |
| 🟢 **安全（Safe）** | 用户缓存、应用日志、废纸篓、浏览器缓存（Safari、Chrome、Firefox、Edge、Brave、Arc），以及应用缓存（Slack、Discord、Notion、Spotify、VS Code、Cursor、Signal、Obsidian、Microsoft Teams、Zoom 更新安装包、Telegram 媒体缓存） | 会自动重新生成，不影响任何功能 |
| 🟣 **开发者（Developer）** | Xcode DerivedData、旧的 DeviceSupport、不可用的模拟器、包管理器缓存（npm、yarn、pnpm、pip、uv、Bun、Deno、Cargo、Go、Homebrew、Composer、Gradle、CocoaPods、SwiftPM、Dart/Flutter pub）、Cypress 二进制缓存、`~/.cache` 中的开发工具缓存、JetBrains 和 Unity 缓存、Maven 本地仓库（需手动启用）、可选的 `docker system prune` | 下次需要时会重新构建或重新下载 |
| 🟠 **深度（Deep）** | “下载”文件夹中旧的 `.dmg` / `.pkg` 安装包、Xcode 归档、未使用的模拟器、本地时间机器快照、陈旧的诊断日志、Ollama 模型（需手动启用）、闲置项目的构建产物 | 在你勾选之前，任何项目都不会被选中 |

**被遗忘的项目。** 深度级别还会检查你的项目。它会找出一个月没有动过的项目中的 `node_modules`、Cargo `target` 文件夹或 virtualenv。对应工具的清单文件必须与构建产物位于同一目录，项目是否活跃以你自己的文件和 git 历史为准；如果你在扫描和清理之间改动了某个项目，Dusty 会拒绝清理它的构建产物。

**洞察（Insights）。** 扫描完成后，Dusty 会指出人工检查时会注意到的情况：Xcode 已经卸载，却还留着 12 GB 的 DerivedData；某个缓存从春天起就再没被写入过；照现在的速度，磁盘三周后就会被占满。洞察只负责提示，从不选中或删除任何内容。

**省心模式。** 后台扫描（默认开启，每 4 小时一次）会让菜单栏中的数值保持最新，并且从不删除任何内容。自动清理（默认关闭）会按计划运行，或在可用空间低于你设定的阈值时运行，遵循与面板相同的规则。

## 为什么值得信任

“Mac 清理工具”通常意味着“一个会删除你看不到的东西的应用”。Dusty 的做法正好相反。删除逻辑放在一个独立、经过完整测试且不含界面的 Swift 包（`CleanerEngine`）中，能够批准删除的只有 `SafetyValidator` 这一个组件。它会强制执行以下规则：

- **仅限白名单。** 只有位于 [`CleanupTargetRegistry`](../../CleanerEngine/Sources/CleanerEngine/CleanupTargetRegistry.swift) 中某个明确目标之下的路径才能被删除。整个代码库中没有任何“除……之外全部删除”的逻辑。
- **受保护的文件夹不可触碰。** 文稿、桌面、图片、“照片”图库、音乐、影片、邮件、iCloud 云盘、钥匙串和 Application Support 一律拒绝，以它们为前缀的路径也不例外（已登记目标中指定的缓存子文件夹除外）。
- **不会借符号链接越界。** Dusty 从不跟随符号链接，父文件夹本身是符号链接时也是如此。
- **不使用 root 权限。** Dusty 从不以 root 身份运行，也不使用 `sudo`，不会触碰任何受 SIP 保护的内容。
- **每个级别都能撤销。** 清理时会先把项目暂存到废纸篓，恢复操作与删除操作接受同样的检查。
- **试运行。** 打开一个开关后，每次清理都只报告将会删除的内容，而不实际删除任何东西。
- **留有记录。** 每个操作（时间、路径、字节数）都会追加写入 `~/Library/Application Support/Dusty/deletion-log.jsonl`。

更详细的设计说明（附代码）：[Dusty 如何从设计上避免删错东西](https://toprak.sh/dusty/safety/)（英文）。如果你发现了让它删除白名单之外内容的方法，请通过私密渠道报告：参见 [SECURITY.md](../../.github/SECURITY.md)。

## 内存

内存就显示在主屏幕的磁盘信息下方：已用多少、内存压力如何；当闲置应用占着内存时，还会出现 **Free up** 按钮，确认后一键拿回。打开卡片即可查看完整详情。

- **真实的情况。** 按活动监视器的方式拆分已用内存（应用、系统、压缩、缓存的文件），显示交换空间、最近一小时的曲线，以及真正说明 Mac 是否缺内存的“内存压力”。
- **按应用，而不是按进程。** 每个应用的合计包含为它工作的所有进程：Chrome 的辅助进程、Safari 的网页、从终端启动的工具。
- **闲置应用已预先勾选。** 会建议退出一小时未使用的大应用。终端、虚拟机、通话中的应用以及正在播放或录制声音的应用永远不会被建议。
- **可以撤回的释放。** 确认列表后一键退出建议的应用。它们会像按 ⌘Q 一样退出，有未保存工作的应用会先询问你。几秒内可用 **重新打开**（或 ⌘Z）全部恢复。
- **发现内存泄漏。** 持续增长的应用会被标出，**重新启动** 按钮可让它的内存回到初始状态。

Dusty 从不强制退出、从不结束进程，也不运行 `purge`：它需要 root 权限，而且只会清掉 macOS 本来就会按需归还的文件缓存。

## 命令行与快捷指令

同样的引擎、白名单和安全规则，也可以通过脚本调用。`dusty` 命令行工具内置在应用中，通过 Homebrew cask 安装时会自动把它加入 `PATH`：

```bash
dusty scan                                    # 测量全部三个级别，不删除任何内容
dusty scan --json                             # 同上，输出机器可读的格式
dusty clean                                   # 打印安全级别的删除计划
dusty clean --yes                             # 实际执行删除
dusty clean --level developer --trash --yes   # 把开发者缓存暂存到废纸篓
dusty targets                                 # 打印完整的白名单
dusty memory                                  # 内存用量、压力和占用最多的应用（只读）
```

不加 `--yes` 时，`clean` 不会改动任何内容；它只删除应用自己默认会选中的项目，并跳过对应应用正在运行的目标。借助 **Clean Safe Items**（清理安全项目）和 **Get Reclaimable Space**（获取可释放空间）这两个快捷指令操作，你可以在任何 macOS 自动化流程中使用 Dusty。

## 常见问题

**真的免费吗？**
是的。MIT 许可证，没有试用期，没有付费升级推销，也不需要账户。

**它会删除我的项目或文稿吗？**
不会。在触碰任何内容之前，验证器就会拒绝这些文件夹，而且只有白名单中的缓存和构建产物路径才会被纳入处理范围。即使是被遗忘的项目，Dusty 也只会提供它的构建产物，绝不会动你的代码。

**如果清理掉了需要的东西怎么办？**
在清理后的几秒内按下“撤销”（或 ⌘Z），这些项目就会回到原来的位置。唯一的例外是清倒废纸篓，这一步和在访达中一样无法撤销。

**为什么不上架 Mac App Store？**
App Store 要求应用运行在沙盒中，而沙盒应用无法访问 Dusty 需要清理的那些缓存。

更多解答（完全磁盘访问权限、更新、从源码构建）请参阅[英文 README](../../README.md)。

## 参与贡献

欢迎提交 Pull Request，尤其是新的清理目标和翻译。请参阅 [CONTRIBUTING.md](../../CONTRIBUTING.md) 和[翻译相关的 issue](https://github.com/yagcioglutoprak/dusty/issues/33)。

## 许可证

MIT。详见 [LICENSE](../../LICENSE)。

---

<div align="center">
由 <a href="https://toprak.sh">toprak.sh</a> 制作
</div>
