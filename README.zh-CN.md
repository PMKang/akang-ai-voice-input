# Noboard · 自在说

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/LANG-English-4C8BF5?style=flat-square&labelColor=555555" alt="English README" /></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/LANG-%E4%B8%AD%E6%96%87-EA4C46?style=flat-square&labelColor=555555" alt="中文 README" /></a>
</p>

> Talk free. Write naturally. 一款用 Codex 从零打造的 macOS AI 语音输入工具。

Noboard · 自在说是一款本地优先的语音输入工具：在任意应用中说话，将结果整理为自然文字并写入当前输入框。模型凭据、历史记录、词典和表达方式都保留在用户自己的设备上。

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

默认使用阿里云百炼的 `qwen3.5-omni-flash-realtime`。一次 Realtime WebSocket 会话即可完成语音理解、提示词注入和文字输出；架构并不绑定单一供应商，后续可继续扩展模型适配。

## 下载与首次使用

1. 打开[最新版本下载页](https://github.com/PMKang/akang-ai-voice-input/releases/latest)。
2. 下载名称包含 `macos.zip` 的安装包。
3. 解压后将 `Noboard · 自在说.app` 拖入“应用程序”。
4. 如果首次打开被 macOS 拦截，按住 `Control` 点击 App，选择“打开”，再确认一次。
5. 在“设置”中填写自己的阿里云百炼 API Key 和 Workspace ID，测试连接后按提示授权。

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

- 需要自行开通并配置同地域的阿里云百炼 API Key 与 Workspace ID。
- Token 和费用按接口用量及公开单价在本地估算；点击“预估费用”可打开当前模型服务的官方费用与额度页面。
- 当前配置无法通过 API Key 查询账户余额，因此应用会显示“账户余额：暂不支持”。实际账单、免费额度和活动价格以供应商控制台为准。
- 音频实时发送到用户配置的模型服务；应用不保存本地录音。
- 诊断报告不包含密钥、Workspace ID、音频或转写正文。

更多信息见：[隐私与安全说明（中文）](docs/privacy-and-security.md)。

## 参与改进

欢迎通过 Issue 或 Pull Request 参与：更多实时模型、macOS 输入法兼容性、复杂控件写入、表达方式与方言体验都是值得改进的方向。项目采用 [MIT License](LICENSE)。

## 关注作者

扫码关注微信公众号“**阿康AI探索号**”，获取 AI 工具、产品实测、开发记录与踩坑复盘。

<img src="Resources/OfficialAccountQR.jpg" width="160" alt="阿康AI探索号二维码" />

## 已知限制

- `Fn` 可能与 macOS 输入法切换冲突，建议优先使用可配置的组合快捷键。
- 部分自绘输入控件不支持 Accessibility 直接写入，结果会自动复制到剪贴板。
- 当前默认适配阿里云百炼华北 2（北京）的 Realtime 服务。
