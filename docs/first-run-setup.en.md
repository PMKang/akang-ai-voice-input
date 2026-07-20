# First-run setup guide

Noboard · 自在说 uses Alibaba Cloud Model Studio’s Beijing-region `qwen3.5-omni-flash-realtime` service. First use requires your own API Key and Workspace ID. **An App ID is not required.**

## 1. Create an API Key

1. Open the [Alibaba Cloud Model Studio API Key console](https://bailian.console.aliyun.com/?tab=model#/api-key), then select **China North 2 (Beijing)**.
2. Create an API Key in the workspace you plan to use. For personal testing, the default workspace is fine.
3. Give it a recognizable description such as `Noboard Voice Input`.
4. For testing, you may grant broad permissions. For long-term use, restrict permissions to the models you need.
5. Copy or download the complete key immediately. The clear-text value is displayed only once.

The console may also show API Host, OpenAI-compatible, and DashScope addresses. Do not enter them in Noboard; the app derives the Realtime WebSocket address from the Beijing Workspace ID.

## 2. Find the Workspace ID

1. Open Alibaba Cloud’s [Workspace ID guide](https://help.aliyun.com/zh/model-studio/obtain-the-app-id-and-workspace-id).
2. Keep the console region set to **China North 2 (Beijing)**.
3. Open the current workspace information at the top right of the console and copy its Workspace ID.
4. Confirm that it belongs to the same workspace as the API Key.

The generated API Host usually looks like this:

```text
<Workspace ID>.cn-beijing.maas.aliyuncs.com
```

Use the console copy button when possible. This app directly calls the Realtime API, so it needs only the API Key and Workspace ID—not an App ID.

| Console value | Enter in Noboard? | Purpose |
| --- | --- | --- |
| API Key | Yes | Request authentication; saved in macOS Keychain |
| Workspace ID | Yes | Resolves the Beijing Realtime service address |
| API Host | No | Derived automatically from Workspace ID |
| OpenAI-compatible URL | No | Not used by this Realtime WebSocket client |
| DashScope URL | No | Not used by this Realtime WebSocket client |
| App ID | No | The app does not call a Model Studio application |

## 3. Save credentials in the app

1. Open **Settings**.
2. Under **Model & Keys**, select **Set Key**.
3. Paste the API Key and Workspace ID.
4. Select **Save Securely**.
5. Select **Test Connection** and wait for **Connection Succeeded** before recording.

Credentials stay in the current Mac’s Keychain and are not written to source, history, or diagnostic reports.

## 4. Grant macOS permissions

1. In **Settings > Permissions & Status**, allow microphone access.
2. Allow Accessibility access so results can be inserted into the focused text field.
3. Press `Option + Command` to start recording, then press it again to stop and generate text.

## Troubleshooting

### Connection test fails

- Check that the API Key and Workspace ID belong to the same China North 2 (Beijing) workspace.
- Confirm that the key has permission to invoke `qwen3.5-omni-flash-realtime` and that billing is available.
- Do not paste an App ID into the Workspace ID field.

### A key was exposed

Delete or disable the old key in the Model Studio console immediately and create a new one. Never share keys through screenshots, chat history, or Git repositories.

## Official references

- [Get an API Key](https://help.aliyun.com/zh/model-studio/get-api-key/)
- [API Key console](https://bailian.console.aliyun.com/?tab=model#/api-key)
- [Find a Workspace ID](https://help.aliyun.com/zh/model-studio/obtain-the-app-id-and-workspace-id)
- [Regions and Base URLs](https://help.aliyun.com/zh/model-studio/base-url)
