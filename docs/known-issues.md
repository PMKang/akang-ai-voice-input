# 已知问题

## Fn / Globe 单键快捷键无法在所有 Mac 上完全拦截

状态：开放问题，第一版推荐使用 `Control + Option`。

### 表现

- Fn 能触发语音输入，但部分 macOS 设备仍会同时切换系统输入法。
- 长按和短按的系统行为可能不同。
- 问题与当前输入框、键盘设备和 macOS 会话状态有关。

### 已验证

- 已获得辅助功能和输入监控权限。
- 使用原生 `CGEventTap`、`headInsertEventTap` 和 `defaultTap`。
- 已尝试 HID 与 Session 两种 tap 位置。
- 已同时监听 `keyDown`、`keyUp` 和 `flagsChanged`，覆盖 Fn 的按下、抬起与修饰键状态变化。
- 已处理 `tapDisabledByTimeout`、`tapDisabledByUserInput`、健康检查和睡眠唤醒刷新。
- 修改 `AppleFnUsageType`、重启输入源服务和事后恢复输入法均不能在所有环境下稳定消除系统切换浮层。

### 当前决策

- 默认快捷键使用 `Control + Option`，保证跨应用启停可靠。
- 保留 Fn 选项作为实验能力，不作为第一版默认方案。
- 后续可在 GitHub Issue 中公开最小复现、系统版本、键盘型号和事件日志，邀请熟悉 Quartz Event Services、IOHID 或 DriverKit 的开发者协助。

### 安全边界

优先使用 macOS 公开 API，不引入内核扩展，不复制第三方专有代码。
