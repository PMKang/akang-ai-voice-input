# 隐私与安全

本文描述阿康的 AI 语音输入法当前版本的数据边界。它不是法律意义上的隐私政策，而是便于开发者审计实现的技术说明。

## 数据流

1. 麦克风音频由 AVAudioEngine 在本机采集。
2. 音频在内存中转换为 `16 kHz / 单声道 / PCM16`。
3. 音频片段通过加密 WebSocket 发送到用户自行配置的阿里云百炼 Workspace。
4. 模型返回最终文字后，应用尝试写入当前输入框。
5. 无法写入时，根据用户设置复制到系统剪贴板。

阿康的 AI 语音输入法不是离线识别工具。使用语音输入即表示音频需要发送到模型服务处理。

## 本地保存

### Keychain

以下内容保存在 macOS Keychain：

- 个人 API Key

Keychain 服务标识为 `com.akang.ai-voice-input`，可在设置页主动移除。

### Application Support

以下内容以 JSON 保存在 `~/Library/Application Support/AkangVoiceInput/app-data.json`：

- 最终文字历史记录
- 录音时长和处理耗时
- 使用的模型名称
- 手动个人词典

文件使用原子写入，减少中途退出造成损坏的概率。

### UserDefaults

以下偏好保存在 UserDefaults：

- Workspace ID
- 快捷键
- 默认语言
- 粤语转换开关
- 剪贴板回退开关

## 不保存的内容

- 原始音频文件
- Base64 音频片段
- 完整 WebSocket 请求与响应
- Authorization 请求头
- API Key 或 Workspace ID 明文日志
- 转写正文诊断日志

## 诊断报告

诊断事件只存在当前应用进程的内存中，最多保留 100 条。报告记录：

- 连接、录音、响应和输出阶段
- 权限状态
- 录音与处理耗时
- 最终文字长度
- Token 数量
- 错误摘要

复制报告前会脱敏 Bearer、常见密钥格式、Workspace ID 和 WebSocket 主机。退出应用后诊断自动清空。

## 系统权限

- 麦克风：采集用户主动开始的语音。
- 辅助功能：将最终文字写入当前焦点输入框。

若辅助功能未授权或目标输入控件不支持安全写入，应用不会覆盖控件全部内容，而是使用剪贴板回退。

## 开发安全检查

提交前至少执行：

```bash
git diff --check
swift test
git status --short
git remote -v
```

还应扫描常见密钥前缀、Bearer 请求头、私有主机和个人标识，并人工检查新增截图和文档。

## 当前发布状态

- 仅提供本地临时签名的开发构建。
- 尚未进行 Developer ID 签名、公证或 App Store 沙箱适配。
- 公开提交前需要执行敏感信息扫描，并人工检查新增截图与文档。
