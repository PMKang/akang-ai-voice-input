# 参与开发

## 开发流程

1. Fork 仓库，并从最新的 `main` 创建功能分支。
2. 修改前阅读根目录 README 和相关代码。
3. 保持功能真实可用，不添加无法生效的开关或虚构统计。
4. 为协议、状态和数据边界增加可重复测试。
5. 使用统一脚本构建和启动。

```bash
swift test
./script/verify_mock_realtime.sh
./script/build_and_run.sh --verify
```

## 代码原则

- 优先使用 SwiftUI、AppKit 和 macOS 原生框架。
- API Key 只进入 Keychain，不写入源码或配置文件。
- 不保存原始音频。
- 输入框写入失败时不得覆盖完整字段内容。
- 诊断只记录阶段和指标，不记录转写正文。
- Realtime 协议改动必须同时更新编码器测试和官方依据。
- “规划中”的功能不得在产品文案中描述为已经支持。

## 提交前检查

```bash
git diff --check
swift test
./script/verify_mock_realtime.sh
./script/build_and_run.sh --verify
git status --short
git remote -v
```

人工确认：

- 没有 API Key、Bearer 请求头或 Workspace ID。
- 没有私人聊天截图、账户信息或未经处理的音频。
- 文档中的命令和路径与当前代码一致。
- 新增 UI 在常见窗口尺寸下没有重叠、截断或无效控件。

## 提交信息

使用简短、可验证的提交信息，例如：

```text
feat: add microphone permission flow
fix: prevent empty audio submission
test: verify realtime client events
docs: document local privacy boundaries
```
