# 首次配置指南

阿康的 AI 语音输入法当前使用阿里云百炼北京地域的 `qwen3.5-omni-flash-realtime`。首次使用需要配置个人 API Key 和 Workspace ID，**不需要 App ID**。

## 1. 获取 API Key

1. 打开[阿里云百炼 API Key 控制台](https://bailian.console.aliyun.com/?tab=model#/api-key)。如需了解权限和地域规则，可查看[官方说明](https://help.aliyun.com/zh/model-studio/get-api-key/)。
2. 登录百炼控制台，地域选择“华北 2（北京）”。
3. 进入 API Key 管理页面，创建 API Key。
4. “归属业务空间”选择后续准备使用的工作空间。个人首次使用可直接选择“默认业务空间”。
5. “描述”是可选项，建议填写“阿康的 AI 语音输入法”，方便以后识别和撤销该 Key。
6. “权限”测试阶段可选“全部”；正式长期使用时建议改为自定义权限，只开放所需模型。
7. 创建后立即复制或下载完整 Key。新建 Key 的明文只展示一次。

创建完成后的页面还会显示 API Host、OpenAI 兼容地址和 DashScope 地址。当前应用不需要手工填写这三个地址，它会根据北京地域和 Workspace ID 自动生成 Realtime WebSocket 地址。

## 2. 获取 Workspace ID

1. 打开[Workspace ID 官方获取说明](https://help.aliyun.com/zh/model-studio/obtain-the-app-id-and-workspace-id)。
2. 在百炼控制台保持“华北 2（北京）”地域不变。
3. 点击控制台右上角的当前工作空间信息，复制 Workspace ID。
4. 确认它与创建 API Key 时选择的是同一个工作空间。

创建 Key 后显示的 API Host 通常形如：

```text
<Workspace ID>.cn-beijing.maas.aliyuncs.com
```

其中 `.cn-beijing.maas.aliyuncs.com` 前面的部分就是当前北京地域工作空间标识。优先使用控制台“工作空间信息”里提供的复制按钮，避免手工截取出错。

注意：文档同时介绍了 App ID，但本应用直接调用模型的 Realtime API，只需要 API Key 和 Workspace ID。

## 哪些内容需要填入应用

| 控制台内容 | 是否需要填写 | 说明 |
| --- | --- | --- |
| API Key | 需要 | 用于请求鉴权，保存在 macOS Keychain |
| Workspace ID | 需要 | 用于确定北京地域的专属 Realtime 服务地址 |
| API Host | 不需要 | 应用根据 Workspace ID 自动生成 |
| OpenAI 兼容地址 | 不需要 | 当前 Realtime WebSocket 调用不走该 HTTP 地址 |
| DashScope 地址 | 不需要 | 当前客户端使用工作空间专属 Realtime 地址 |
| App ID | 不需要 | 本应用直接调用模型，不调用百炼应用 |

## 3. 在应用中保存

1. 打开“设置”。
2. 在“模型与密钥”中点击“设置密钥”。
3. 粘贴 API Key 和 Workspace ID。
4. 点击“安全保存”。
5. 点击“测试连接”，看到“连接成功”后再开始录音。

凭证只保存在当前 Mac 的 Keychain 中，不会写入源码、历史记录或诊断报告。

## 4. 开通系统权限

1. 在“设置 > 权限与状态”中允许麦克风权限。
2. 在“辅助功能权限”右侧点击“打开辅助功能设置”。这是自动把文字写入微信、浏览器等输入框所必需的权限；未开启时，结果会安全地复制到剪贴板。
3. 在 macOS 13 及更高版本的“系统设置 > 隐私与安全性 > 辅助功能”中，打开 `Noboard · 自在说`；macOS 12 请前往“系统偏好设置 > 安全性与隐私 > 隐私 > 辅助功能”，解锁后勾选该 App。若列表没有它，请点“+”从“应用程序”中添加。
4. 回到 App 后点击“重新检测”。若刚替换、移动或重新安装过 App，请完全退出后重新打开，再检查一次权限。
5. 默认按下 `Control + Option` 开始录音，再按一次停止并生成文字。

## 常见问题

### 测试连接失败

- 检查 API Key 和 Workspace ID 是否同属华北 2（北京）。
- 检查 API Key 是否属于当前工作空间并有模型调用权限。
- 检查 `qwen3.5-omni-flash-realtime` 是否已开通且账户可正常计费。
- 不要把 App ID 填入 Workspace ID 输入框。

### Key 已泄露

立即在百炼控制台删除或禁用旧 Key，并创建新 Key。不要通过截图、聊天记录或 Git 仓库传递密钥。

## 官方参考

- [获取 API Key](https://help.aliyun.com/zh/model-studio/get-api-key/)
- [API Key 控制台直达地址](https://bailian.console.aliyun.com/?tab=model#/api-key)
- [获取 Workspace ID](https://help.aliyun.com/zh/model-studio/obtain-the-app-id-and-workspace-id)
- [地域与 Base URL](https://help.aliyun.com/zh/model-studio/base-url)
