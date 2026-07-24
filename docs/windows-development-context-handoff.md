# Noboard Windows 版开发上下文交接

> 证据范围：Windows 端 Codex 对话、本机 Git 全历史、仓库源码/文档/测试/构建脚本，以及 GitHub PR、Actions 和 Release。本文供 Mac 端 Codex撰写公众号文章使用，不是最终文章。无法确认之处均明确标注。

## 1. 200 字以内的故事摘要

阿康先在 macOS 上完成语音输入产品，又拿一台 Windows 10 电脑，让另一台 Codex 以 macOS v1.5.0 为产品基线重做 Windows 版。第一版很快实现录音、实时识别和自动写入，却先后踩中 `*.app` 忽略规则、Win32 输入结构、剪贴板、UIPI、WPF 视觉、版本分裂和更新文件锁等问题。阿康持续真机验收，Codex根据反馈返工，最终两个系统使用同一版本号、同一个 GitHub Release 发布。

## 2. 项目背景和最初目标

阿康最早在 Windows 端对话中明确提出：

> “那如果我们开始搞windows的语音输入法开发工作，就按我当前系统win10作为最低版本支持，你看看需要哪些准备”

随后又说：

> “我准备上班去 电脑开着 你看需要我先做啥”  
> “你伴我执行吧”

开发前的交接材料进一步规定：

- Windows 10 x64 为最低支持目标。
- 第一阶段使用云端实时识别，不在普通办公电脑上部署本地大模型。
- 用户聚焦输入框后，用全局快捷键开始/结束录音。
- 录音期间实时显示识别结果，停止后生成最终文本。
- 优先写入原输入框；写入失败时至少保留在剪贴板。
- 第一阶段不做完整 Windows TSF/IME。
- Windows 代码放在 `windows/`，避免破坏现有 Swift 项目。
- 技术方案已经明确为 C#、.NET 10 和 WPF。

初始目标是先证明：

```text
全局快捷键 → PCM 麦克风采集 → Qwen Realtime WebSocket
→ 实时预览 → 最终文本 → 写入原输入框或剪贴板
```

现有证据没有显示团队曾正式比较 Electron、Tauri、Avalonia、MAUI 等框架。WPF适合大量 Windows 原生能力和平台隔离，是根据代码可以作出的合理推断；是否正式讨论并否决过其他框架，仍需阿康补充。

## 3. 按时间排序的完整开发时间线

| 时间 | 阶段 | 阿康提出的目标 | Codex 完成的工作 | 关键结果 | Commit/PR 证据 |
|---|---|---|---|---|---|
| 2026-07-22 22:36 | macOS 基线 | 已有 Mac 产品，要扩展到 Windows | Mac 侧完成豆包流式 ASR v1.5.0 | Windows 从 macOS v1.5.0 产品状态出发 | `b87f16b22d19a65cada3354bfecdb555262d2531` — `feat: add doubao streaming asr v1.5.0` |
| 2026-07-23 开发前 | 交接与范围 | Win10 最低版本，先跑通云端语音输入 | 约定 Windows 代码进入 `windows/`，MVP 不做 TSF | 通过 Git 和文档跨电脑接力 | `AGENTS.md`、`docs/platform-parity.md` |
| 2026-07-23 13:10 | Windows MVP | 快捷键录音、实时识别、自动输入 | 实现 Core、NAudio、Qwen Realtime、Credential Manager、目标窗口、剪贴板/Ctrl+V、测试和打包 | 核心链路进入提交，但 WPF App 被误忽略 | `e077a3254ad23ade554a836e3e509a4302d27d70` — `Add Windows voice input MVP` |
| 2026-07-23 13:15–13:33 | MVP 合并 | 发布主分支且不影响 Mac | PR #5 合并基础能力并记录真机修复 | 主分支取得 Windows MVP | PR #5；`6ee68eb647c68872b8c1d661f028efec1563845c` — `Add Windows voice input MVP` |
| 2026-07-23 真机验收 | 闭环调试 | 验证 API、识别和写入 | 修正 x64 INPUT 布局、窗口激活、剪贴板恢复延迟和失败提示 | 识别成功，但暴露粘贴、提示和写入延迟 | PR #5 描述、当前对话 |
| 2026-07-23 14:35 | 补回 EXE 项目 | “如何启动”“不应该是exe文件吗” | 修复 `.gitignore`；提交 WPF App、七页壳层、托盘、悬浮窗和本地数据 | 仓库终于包含可构建 EXE | `790afc26a2da31b78a88f7769ea775eb26c5303a` — `feat(windows): add macOS feature parity shell and local data` |
| 2026-07-23 23:51 | 视觉对齐 | “和 MAC 完全不一样”“这么丑” | 引入 Mac 对齐主题、波形、热力图并重做 XAML | 从工程壳层转向产品界面 | `265668bb90a18c5ee8750f61eb746221b5ba341c` — `feat(windows): match macOS app visual design` |
| 2026-07-24 00:41 | 仪表盘和模型 | 折线图、指标、豆包/阿里筛选、模型选择、二维码、窗口观感 | 增加识别趋势、模型目录、豆包路由、Qwen Plus/FunASR 和原生窗口框架 | 功能和 Mac 信息架构基本对齐 | `4496ca3cc80ed30625bb3eb1d8a81aa8d2bf52a9` — `feat(windows): complete dashboard models and native chrome` |
| 2026-07-24 00:48–00:49 | 文档与合并 | README 同时说明 macOS/Windows | 更新 README 和版本说明，合并 parity PR | Windows 进入功能基本对齐阶段 | `e4c36ba7acb5395a6525593a797ec4d141e0f0de` — `docs: document macOS and Windows versions`；PR #6；merge `109fb824258c2718dd73c6e2e77feeb5426c76aa` |
| 2026-07-24 09:11–09:18 | 统一版本 | 解决 Latest 可能只有一端、版本号不同 | 新增根 `VERSION`、统一发布文档和双平台 workflow | v1.6.0 同一 Release 包含 Mac/Windows | `a87e4045252d8dd22b0f4a8e620d888acd509dee` — `release: unify macOS and Windows versioning`；PR #7；merge `0308779977c002fa4cc931ab57a711bc9ba4d407` |
| 2026-07-24 12:35–12:36 | 更新与 UI polish | 检查更新、下载安装；继续修边框、二维码、卡片和滚动条 | 实现 Release 检查、ZIP、SHA256、替换、回滚、重启和 UI 改进 | v1.6.1 具备应用内更新基础 | `a42fd450633bf0a6804e77856d38eb1cd99e8fa2` — `feat(windows): add verified in-app updates and polish UI`；PR #8；merge `614d3aa213c570025b64f6e572f328ce1a21ac30` |
| 2026-07-24 12:37 | Release CI 失败 | 发布 v1.6.1 | Hosted Windows 清理临时 `Noboard.exe` 时遇到文件锁 | 32 通过、1 失败，发布停止 | Actions run 30067257856 |
| 2026-07-24 12:43–12:44 | 文件锁修复 | 重试发布 | 测试清理增加最长约 5 秒重试 | CI 恢复 | `99bee78f565d4a16db27fcfeb1dff94364799c04` — `test(windows): tolerate relaunch file-lock cleanup`；PR #9；merge `e73b2dfb8c8ac8d3752006f88e7c4dfdab891523` |
| 2026-07-24 12:47–12:49 | v1.6.1 Release | 两个平台同版发布 | 两个平台均成功后才发布 | 同一 Release 含 Mac/Windows 安装资产 | Actions run 30067694741；Release v1.6.1 |
| 2026-07-24 当前 WIP | 单键快捷键 | 三键不方便；右 Alt 太远；Caps Lock 会亮灯；选择默认左 Alt | 试验单独按下/松开左 Alt 触发，Alt+Tab/Alt+F4 放行，并迁移旧配置 | 34 项本地测试通过，但未提交、未发布 | 分支 `agent/windows-single-key-shortcut`，基点 `e73b2df...` |

## 4. 从 macOS 到 Windows：复用了什么，重写了什么

| 能力 | macOS 实现 | Windows 实现 | 是否复用代码 | 迁移难点 |
|---|---|---|---|---|
| 产品信息架构 | SwiftUI 页面、仪表盘、历史、词典、表达、模型、设置、关于 | WPF 七页导航和本地状态 | 复用设计，不复用 Swift UI | 第一版功能壳与品牌视觉差距大 |
| 识别规则 | Swift 中的 prompt、语言保持、口语清理、`[EMPTY]` | `VoiceInputPrompt.cs` | 语义复用，C# 重写 | 保证双平台输出风格一致 |
| 麦克风 | macOS 音频 API | NAudio，16 kHz/16-bit/mono PCM | 不复用 | 缓冲、峰值波形和生命周期 |
| Qwen Realtime | Swift WebSocket | `QwenRealtimeService.cs`、`QwenRealtimeProtocol.cs` | 协议语义复用，代码重写 | 分片、预览/最终结果和超时 |
| 多模型 | Qwen、豆包等 | `VoiceModelCatalog.cs`、Provider router | 产品目录复用，服务重写 | 鉴权和协议不同 |
| 快捷键 | macOS 全局键盘监听 | RegisterHotKey；当前 WIP 为低级 hook | 不复用 | 单键 Alt 与系统组合键 |
| 输入目标 | macOS Accessibility/焦点 | GetForegroundWindow 保存句柄 | 不复用 | 录音期间焦点变化 |
| 自动写入 | macOS 辅助功能/粘贴 | Clipboard + SendInput(Ctrl+V) | 不复用 | x64 结构、焦点和 UIPI |
| 密钥 | Keychain | Windows Credential Manager | 不复用 | 不能写普通 JSON |
| 托盘/单实例 | 菜单栏生命周期 | NotifyIcon + 命名 EventWaitHandle | 不复用 | 第二次启动需唤醒现有实例 |
| UI | SwiftUI/AppKit | MacParityTheme、WindowChrome、WPF | 不复用 UI 源码 | 默认 WPF 风格陈旧 |
| 品牌资源 | 根 Resources | WPF 项目链接根图标/二维码 | 实际复用文件 | 资源路径、缩放和裁剪 |
| 打包/更新 | DMG/ZIP、Mac updater | self-contained ZIP、SHA256、PowerShell updater | 发布约定复用，脚本重写 | EXE 不能覆盖自己、文件锁 |
| 版本 | 曾可能独立推进 | 根 VERSION + 单 tag + 双平台 workflow | 根层共享 | GitHub 只有一个 Latest |
| TSF/IME | 非本阶段目标 | 未实现 | 无 | MVP 明确延期 |

真正共享的是产品定义、提示词语义、模型目录、品牌资源、版本和发布约定；Swift、音频、窗口、凭据、托盘、自动写入等平台代码基本全部重写。

## 5. 五个最值得写进文章的难题

### 5.1 代码提交了，EXE 却不见了

- **目标**：提交可启动的 Windows MVP。
- **现象**：solution 引用了 `AkangVoiceInput.App`，文档也说有 WPF，但 Git tree 没有应用项目。
- **根因**：macOS 的 `*.app` 忽略规则在 Windows 大小写不敏感环境中吞掉 `AkangVoiceInput.App/`。
- **方案**：显式放行该目录，只继续忽略 bin/obj。
- **证据**：`.gitignore`、`windows/AkangVoiceInput.slnx`、`e077a325...`、`790afc26...`、PR #6。
- **启发**：跨平台仓库必须验证干净 clone 的真实文件树，不能只看本机 build。

### 5.2 识别成功，不代表文字进了输入框

- **现象**：识别和快捷键正常，但自动粘贴失败；“正在写入”约 1 秒；非输入框录音后剪贴板仍是旧内容。
- **根因**：前台窗口变化、x64 INPUT union 布局、剪贴板占用、窗口激活、非可编辑控件和 UIPI 叠加。
- **尝试**：恢复窗口、发送 Ctrl+V、恢复旧剪贴板；同步恢复剪贴板造成卡顿。
- **方案**：先无条件更新剪贴板；仅在窗口变化时激活；短暂等待后 SendInput；不恢复旧剪贴板；失败时保留可手动粘贴的结果；不绕过 UIPI。
- **证据**：`WindowsTextInsertionService.cs`、`app.manifest`、对应测试和 PR #5。
- **启发**：先保证文字不丢，再追求自动化。

### 5.3 PCM 与 Qwen Realtime 的实时/最终结果

- **目标**：边说边显示，停止后取得可正式写入的结果。
- **难点**：持续发送 PCM base64、WebSocket 分片、预览快照、最终 delta、commit、response.done 和超时。
- **产品反馈**：“key是不是只要输一个就行 不需要worksapceID 我mac版本就是这样”。
- **方案**：16k PCM16 mono、约 100ms 缓冲；workspace 可选；预览与最终结果分开；30 秒 final timeout；`[EMPTY]` 不写入。
- **证据**：`NAudioCaptureService.cs`、`QwenRealtimeProtocol.cs`、`QwenRealtimeService.cs`、`VoiceInputCoordinator.cs`。
- **启发**：普通用户配置应只暴露最低必要字段。

### 5.4 功能有了，但不像同一个产品

阿康原话：

> “天呐，这是什么鬼东西啊？这么丑的。”  
> “我说的是 MAC 的语音输入法，和你这个完全不一样啊 UI 风格。”

返工包括托盘 Logo、折线图、数据指标、模型筛选、月度热力图、豆包/Qwen 模型、二维码、窗口边框、自定义滚动条、卡片等宽和标题栏按钮。

- **证据**：`265668bb...`、`4496ca3...`、`a42fd450...`、`MacParityTheme.xaml` 和多轮本机截图。
- **启发**：迁移已有产品时，“能运行”只是工程里程碑，不是产品完成。

### 5.5 同一 Release 与会更新自己的 Windows 应用

- **现象**：Mac/Windows 版本独立，Latest 可能只有一端；更新器 CI 又因退出后的 EXE 短暂文件锁失败。
- **阿康原话**：“比如找到最新的 Mac，发现没有 Windows。”
- **方案**：根 VERSION；两个平台成功后才发布；Windows 精确选择 ZIP/SHA256；校验、等待旧 PID、备份、替换、回滚和重启；测试清理容忍短暂文件锁。
- **证据**：`VERSION`、`.github/workflows/release.yml`、`WindowsUpdateService.cs`、PR #7/#8/#9、失败/成功 Actions。
- **启发**：多平台版本应代表一次面向用户的产品发布，而不是某台电脑的一次构建。

## 6. Codex 与阿康的协作过程

### 阿康作出的产品判断

- Win10 为最低版本。
- 第一阶段先做云端闭环，不先做 TSF。
- Qwen 普通配置只需 API Key，workspace 不应强制。
- Windows/Mac 代码要清楚分区。
- Windows 视觉必须属于同一个 Noboard 产品。
- 首页需要趋势、指标、热力图和模型筛选。
- 豆包/Qwen 不仅展示，还要允许真实选择。
- 二维码、边框、滚动条和托盘 Logo 属于产品质量。
- 两个平台使用同一版本号和同一 Release。
- Windows 需要应用内更新。
- 当前快捷键方向由真实手势判断：右 Alt 太远、Caps Lock 会亮灯，正在选择左 Alt。

### Codex 完成的工程实现

- Windows 分层工程、NAudio、Qwen Realtime 和多提供商路由。
- Credential Manager、前台窗口、Clipboard/SendInput 和 UIPI 降级。
- 托盘、单实例、悬浮状态和开机启动。
- 七页 WPF、本地历史/词典/表达/统计/模型。
- self-contained ZIP、SHA256 和统一 workflow。
- 检查更新、替换、回滚和重启。
- 根据阿康真机反馈和 CI 日志连续修复。

### 阿康的真机验证

阿康实际验证了 API、麦克风、快捷键、自动写入、非输入框剪贴板兜底、写入延迟、提示关闭、托盘、首页/模型/设置/关于、二维码、窗口边框、滚动条、Release 和更新入口。

### 跨电脑接力

两台 Codex不共享本机隐式记忆，只能通过 Git 分支、Commit、PR 描述、README、docs、Release、截图和交接文档传递状态。Mac 构建必须由 Mac 或 macOS runner 完成；WPF、Win32、SendInput、托盘和管理员窗口限制必须在 Windows 真机验证。

## 7. 开发中的失败、返工和意外

1. GitHub 设备授权曾卡住：“没打开啊”“没有这个码”。
2. 首次 MVP 被 `*.app` 规则吞掉整个 WPF App。
3. 第一版识别成功但自动粘贴失败。
4. 恢复旧剪贴板造成明显“正在写入”卡顿，最终删除该行为。
5. 非输入框录音时剪贴板兜底最初失效。
6. 第一版 UI 被整体否定，经历多轮返工。
7. 模型提供商最初只是展示不够，后来加入真实路由和选择。
8. Mac/Windows 独立版本导致 Latest 语义混乱。
9. v1.6.0 没有更新器，用户需要手动安装 v1.6.1 一次。
10. v1.6.1 首次 Release 因 `Noboard.exe` 文件锁失败。
11. 当前左 Alt 方案仍是未提交 WIP。
12. 快捷键测试期间曾启动 framework-dependent Debug EXE，系统提示安装 .NET；正式 v1.6.1 ZIP 是 self-contained，不需要用户另装 .NET。

## 8. 可用于文章的细节、原话和场景

- 起点：“按我当前系统win10作为最低版本支持。”
- 第一次跑通：“我看到它能语音识别，也能验证通过。”
- 紧接着失败：“信息无法自动粘贴到输入框，且阻断提醒无法关闭。”
- 短暂肯定：“哎，好像挺好的。”
- 新场景暴露：“如果不在输入框里面识别，好像剪贴板不会更新。”
- UI 转折：“天呐，这是什么鬼东西啊？这么丑的。”
- 版本转折：“比如找到最新的 Mac，发现没有 Windows。”
- 最有折腾感的失败：代码、solution、README 都说有 WPF App，仓库里却没有 EXE 项目。
- 看似简单的 Windows 细节：把文字粘贴回“刚才那个输入框”，背后涉及窗口句柄、焦点、剪贴板锁、INPUT 内存结构、UIPI、失败兜底和提示时长。
- 同一 Release 的意义：v1.6.1 是一次 Noboard 产品发布，而不是一台电脑的一次构建。

不能确认阿康第一句成功识别的具体语音内容，不应补写。

## 9. 建议的文章结构

1. 已有 Mac 版，为什么还要在 Windows 上“重做一次”。
2. 两台电脑、两个 Codex 如何通过 Git 和交接文档接力。
3. 第一版很快识别成功，但离能用还很远。
4. 代码写完了，EXE 为什么被一条 macOS 规则吞掉。
5. Windows 最麻烦的不是 ASR，而是把文字送回原输入框。
6. 阿康否定第一版 UI：从工程壳层到同一个产品。
7. 从 Windows 分支变成双平台产品：一个版本、一个 Release。
8. 自动更新最后又撞上 Windows 文件锁。
9. 复盘：AI 完成工程，人负责范围、体验判断和拒绝不合格结果。
10. 以当前左 Alt 小细节收尾：发布不是结束。

建议标题：

- 《我让两台 Codex 接力，把一个 Mac 产品重新做到了 Windows》
- 《代码写完了，EXE 却不见了：一次真实的跨平台 AI 开发复盘》
- 《从 macOS 到 Windows：Noboard · 自在说的第二次诞生》

## 10. 素材清单

### 推荐截图

仓库中已有：

- `docs/images/app-overview.jpeg`：Mac 版参照。

本机未入 Git，撰文前应裁切隐私和桌面背景：

- `windows/artifacts/main-window.png`
- `windows/artifacts/mac-parity-home-v1.png`
- `windows/artifacts/mac-parity-home-v2-full.png`
- `windows/artifacts/feedback-home-v1.png`
- `windows/artifacts/feedback-models-v1.png`
- `windows/artifacts/feedback-models-final.png`
- `windows/artifacts/feedback-about-v1.png`
- `windows/artifacts/feedback-about-final.png`
- `windows/artifacts/feedback-settings-final.png`
- `windows/artifacts/feedback-tray-v1.png`
- 工作区截图：`noboard-ui-polish-home.png`、`noboard-ui-polish-models.png`、`noboard-ui-polish-about.png`、`noboard-v1.6.1-update-ui.png`。

### 相关文件

- `AGENTS.md`
- `README.md`
- `VERSION`
- `docs/platform-parity.md`
- `docs/repository-layout.md`
- `docs/releasing.md`
- `windows/src/AkangVoiceInput.Audio/NAudioCaptureService.cs`
- `windows/src/AkangVoiceInput.Transcription/QwenRealtimeProtocol.cs`
- `windows/src/AkangVoiceInput.Transcription/QwenRealtimeService.cs`
- `windows/src/AkangVoiceInput.Core/VoiceInputCoordinator.cs`
- `windows/src/AkangVoiceInput.Platform/WindowsTextInsertionService.cs`
- `windows/src/AkangVoiceInput.Platform/WindowsCredentialStore.cs`
- `windows/src/AkangVoiceInput.Platform/WindowsUpdateService.cs`
- `windows/src/AkangVoiceInput.App/App.xaml.cs`
- `windows/src/AkangVoiceInput.App/MainWindow.xaml`
- `windows/src/AkangVoiceInput.App/Themes/MacParityTheme.xaml`
- `windows/scripts/publish-win-x64.ps1`
- `windows/tests/AkangVoiceInput.Tests/`
- `.github/workflows/release.yml`
- `.gitignore`

### 关键 PR、Actions 和 Release

- [PR #5 Add Windows voice input MVP](https://github.com/PMKang/akang-ai-voice-input/pull/5)
- [PR #6 macOS feature parity shell and local data](https://github.com/PMKang/akang-ai-voice-input/pull/6)
- [PR #7 unify macOS and Windows versioning](https://github.com/PMKang/akang-ai-voice-input/pull/7)
- [PR #8 verified in-app updates and UI polish](https://github.com/PMKang/akang-ai-voice-input/pull/8)
- [PR #9 tolerate relaunch file-lock cleanup](https://github.com/PMKang/akang-ai-voice-input/pull/9)
- [失败 Actions 30067257856](https://github.com/PMKang/akang-ai-voice-input/actions/runs/30067257856)
- [成功 Actions 30067694741](https://github.com/PMKang/akang-ai-voice-input/actions/runs/30067694741)
- [Release v1.6.0](https://github.com/PMKang/akang-ai-voice-input/releases/tag/v1.6.0)
- [Release v1.6.1](https://github.com/PMKang/akang-ai-voice-input/releases/tag/v1.6.1)

### 仍需阿康口述补充

1. 是否讨论过 Electron/Tauri/Avalonia/MAUI 等方案。
2. 第一版识别成功时具体说了什么。
3. UI 第一版最不能接受的核心原因。
4. 看到 v1.6.1 同时出现两个系统资产时的感受或原话。
5. 发布后是否已有真实外部用户反馈。
6. 默认左 Alt 是否最终定案。
7. Mac 侧是否还有未提交的聊天总结、截图或草稿。

## 11. 事实核查与不确定项

### 有 Git/代码证据确认

- Windows 从 macOS v1.5.0 的 `b87f16b...` 开始。
- 首个 Windows 提交是 `e077a325...`。
- 技术栈为 .NET 10/WPF/NAudio/Win32。
- `*.app` 确实导致 App 项目漏提交。
- 音频为 16k PCM16 mono；Qwen 使用 Realtime WebSocket。
- 自动写入采用目标窗口、剪贴板和 SendInput。
- manifest 不绕过 UIPI。
- 密钥保存使用 Credential Manager。
- 有托盘、单实例、自包含 ZIP、SHA256 和 updater。
- 根 VERSION 和 workflow 统一双平台发布。
- v1.6.1 首次 workflow 因文件锁失败，修复后成功。
- 当前左 Alt 改动未提交、未发布。

### 来自当前对话记忆

- Win10 最低版本。
- API Key 不应强制 workspace。
- 识别成功后仍有粘贴、提示、卡顿和剪贴板问题。
- 第一版 UI 被明确否定。
- 阿康要求趋势、指标、热力图、模型、二维码、边框和滚动条。
- 阿康主动提出统一版本和应用内更新。
- 阿康因右手使用鼠标而选择尝试左 Alt。

### 根据证据合理推断

- WPF 的选择与大量 Windows 原生集成、平台隔离有关。
- 初期优先验证“语音到输入框”，UI 只是壳层。
- PR 和 docs 承担了两台 Codex之间的结构化记忆。
- 同一 Release 标志着项目从两个构建转为一个跨平台产品版本。

### 暂时无法确认

- 是否正式评估并否决过具体跨平台框架。
- 最初准备环境的精确命令顺序。
- 第一句成功识别的语音内容。
- 每次协议试错的全部细节。
- Mac 侧 Codex完整对话和未提交工作。
- 阿康看到统一 Release 时是否留下原话。
- 当前左 Alt 是否会成为下一正式版本默认值。

## 给另一台 Codex 的交接摘要

Windows 版以 macOS v1.5.0 的 `b87f16b...` 为产品基线，从 `e077a325...` 开始，采用 .NET 10/WPF，隔离在 `windows/`。最重要的故事不是“AI 一次生成 Windows 版”，而是阿康用真机持续否定和修正：首个提交被 `*.app` 误伤而没有 EXE；识别成功却粘贴失败；剪贴板恢复导致卡顿；第一版 UI 被评价为完全不像 Mac；独立版本让 Latest 混乱；更新器又遇到 EXE 文件锁。最终 v1.6.1 在同一 Release 提供 Mac/Windows，并含 Windows SHA256 更新链路。当前默认左 Alt 仍是未提交 WIP，不要写成已发布功能。
