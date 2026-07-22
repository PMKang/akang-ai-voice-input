# Noboard · 自在说

<h3 align="center">
  <a href="README.md">Read in English</a>
  &nbsp;&nbsp;·&nbsp;&nbsp;
  <a href="README.zh-CN.md">阅读简体中文版</a>
</h3>

> Talk free. Write naturally. 一款用 Codex 从零打造的 macOS AI 语音输入工具。

Noboard · 自在说是一款本地优先的语音输入工具：在任意应用中说话，将结果整理为自然文字并写入当前输入框。

## 看看实际效果

https://github.com/user-attachments/assets/1514c115-916f-4858-a3d6-d77244e5a1dd

## 为什么做 Noboard

前段时间，我重新体验了一圈语音输入工具。结果并不稳定：有的响应偏慢，有的会在一句话刚说完整时卡住，还有些订阅价格让我很难把它当成一个每天都能放心使用的工具。与此同时，我每天的 Codex 额度经常还没用完就重置了。于是我给自己出了一个很实际的题目：一个产品经理，能不能和 AI 一起，做出真正符合自己习惯的语音输入工具？

项目最初只是一个小实验，后来却变成了一次完整的产品实践：比较模型、验证实时音频链路、体验竞品、制作 UI 原型，处理 macOS 权限、全局快捷键，以及不同应用里的文字写入。真正困难的并不是做出一个看起来漂亮的窗口，而是尽量缩短“脑子里刚冒出一个想法”到“文字已经出现在正确输入框里”的距离，并让这个过程足够稳定。

于是有了 Noboard · 自在说。它采用本地优先的设计，使用用户自己的模型凭据，并把历史、词典和表达方式留在自己的设备上。我选择把它开源，不只是想交付一个可以下载的 App，也想把其中的选择、限制、踩坑和还没完成的部分公开出来——对正在尝试用 AI 做产品的人来说，这些过程往往比一个光鲜的结果更值得阅读。

## 产品概览

![Noboard · 自在说](docs/images/app-overview.jpeg)

## 功能

- 通过全局快捷键在任意应用中开始或停止语音输入。
- 在鼠标所在屏幕显示悬浮窗、动态声波和实时识别片段。
- 优先写入当前输入框；无法安全写入时自动复制到剪贴板。
- 按所选表达方式整理口头语、改口、标点、分段和编号。
- 支持粤语、上海话等中文方言，并转为自然的普通话书面表达。
- 本地保存历史、个人词典、表达方式、Token 用量、预估费用和输入概览。
- 内置晴空蓝、靛紫、珊瑚主题，并同步更新界面强调色和运行中的 Dock 图标。
- 可分别自定义中文与英文品牌名称，同步侧边栏、菜单栏、关于页和录音悬浮窗。

默认使用阿里云百炼的 `qwen3.5-omni-flash-realtime`。可在 Qwen 3.5 Omni Flash、Qwen 3.5 Omni Plus 与 Fun ASR 实时模型间切换；其中 Fun ASR 会自动将个人词典映射为供应商热词。一次 Realtime WebSocket 会话即可完成语音理解、提示词注入和文字输出；架构并不绑定单一供应商，后续可继续扩展模型适配。

## 下载与首次使用

1. 打开[最新版本下载页](https://github.com/PMKang/akang-ai-voice-input/releases/latest)。
2. 下载名称包含 `macos.zip` 的安装包。
3. 解压后将 `Noboard · 自在说.app` 拖入“应用程序”。
4. 如果首次打开被 macOS 拦截，按住 `Control` 点击 App，选择“打开”，再确认一次。
5. 在“设置”中填写自己的阿里云百炼 API Key，测试连接后按提示授权。

支持 macOS 12（Monterey）及更高版本，安装包同时支持 Apple 芯片与 Intel Mac。macOS 12 使用原生状态栏菜单；“开机启动”需要 macOS 13 或更高版本。

应用不会提供或内置共享密钥。API Key 保存在当前 Mac 的 Keychain 中，历史、词典和表达方式规则只存本机。

详细配置说明见：[首次配置指南（中文）](docs/first-run-setup.md)。

## 开发与自定义

```bash
git clone https://github.com/PMKang/akang-ai-voice-input.git
cd akang-ai-voice-input
swift test
./script/build_and_run.sh --verify
```

你可以将 `Sources/AkangVoiceInput/`、截图和具体目标交给 AI 编程助手，让它在现有结构上增加表达方式、模型适配或设置能力。提交 Pull Request 前，请运行相关测试，并检查隐私信息。

## 模型、费用与隐私

- 需要自行开通并配置北京地域的阿里云百炼 API Key；正常使用不需要填写 Workspace ID。
- Token 和费用按接口用量及公开单价在本地估算；点击“预估费用”可打开当前模型服务的官方费用与额度页面。
- 当前配置无法通过 API Key 查询账户余额，因此应用会显示“账户余额：暂不支持”。实际账单、免费额度和活动价格以供应商控制台为准。
- 音频实时发送到用户配置的模型服务；应用不保存本地录音。
- 诊断报告不包含密钥、Workspace ID、音频或转写正文。

更多信息见：[隐私与安全说明（中文）](docs/privacy-and-security.md)。

## 参与改进

欢迎通过 Issue 或 Pull Request 参与：更多实时模型、macOS 输入法兼容性、复杂控件写入、表达方式与方言体验都是值得改进的方向。项目采用 [MIT License](LICENSE)。

如果它确实帮你少打了一些字，欢迎给项目一个 Star。它能让我知道，这个由日常痛点和未用完的 Codex 额度开始的小实验，也对其他人有用。

## 关注作者

扫码关注微信公众号“**阿康AI探索号**”，获取 AI 工具、产品实测、开发记录与踩坑复盘。

<img src="Resources/OfficialAccountQR.jpg" width="160" alt="阿康AI探索号二维码" />

## 已知限制

- `Fn` 可能与 macOS 输入法切换冲突，建议优先使用可配置的组合快捷键。
- 部分自绘输入控件不支持 Accessibility 直接写入，结果会自动复制到剪贴板。
- 当前默认适配阿里云百炼华北 2（北京）的 Realtime 服务。

完整问题列表与技术说明见：[已知问题](docs/known-issues.md)。
