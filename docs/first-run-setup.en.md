# First-run setup guide

Noboard · 自在说 uses Alibaba Cloud Model Studio's Beijing-region realtime models. First use requires your own API Key. **A Workspace ID and App ID are not required.**

## 1. Create an API Key

1. Open the [Alibaba Cloud Model Studio API Key console](https://bailian.console.aliyun.com/?tab=model#/api-key), then select **China North 2 (Beijing)**.
2. Create an API Key in the workspace you plan to use. For personal testing, the default workspace is fine.
3. Give it a recognizable description such as `Noboard Voice Input`.
4. For testing, you may grant broad permissions. For long-term use, restrict permissions to the models you need.
5. Copy or download the complete key immediately. The clear-text value is displayed only once.

The console may also show API Host, OpenAI-compatible, and DashScope addresses. Do not enter them in Noboard; it uses the supported public DashScope endpoint with your API Key.

| Console value | Enter in Noboard? | Purpose |
| --- | --- | --- |
| API Key | Yes | Request authentication; saved in macOS Keychain |
| Workspace ID | No | Not required for normal setup |
| API Host | No | Resolved by the app |
| OpenAI-compatible URL | No | Not used by this Realtime WebSocket client |
| DashScope URL | No | Used internally by the app; do not paste it |
| App ID | No | The app does not call a Model Studio application |

## 2. Save credentials in the app

1. Open **Settings**.
2. Open **Voice Model Configuration** and paste the API Key under **Alibaba Cloud Model Studio**.
3. Select **Save**.
4. Choose a currently available model.
5. Select **Test Connection** and wait for **Connection Succeeded** before recording.

Credentials stay in the current Mac’s Keychain and are not written to source, history, or diagnostic reports.

## 3. Grant macOS permissions

1. In **Settings > Permissions & Status**, allow microphone access.
2. Next to **Accessibility**, select **Open Accessibility Settings**. This permission is required to write results into the active field in WeChat, browsers, and other apps; without it, results are copied safely to the clipboard.
3. On macOS 13 and later, enable `Noboard · 自在说` in **System Settings > Privacy & Security > Accessibility**. On macOS 12, go to **System Preferences > Security & Privacy > Privacy > Accessibility**, unlock the pane, and enable the app. If it is missing, use **+** to add it from Applications.
4. Return to the app and select **Recheck**. After replacing, moving, or reinstalling the app, quit it completely, reopen it, and check the permission again.
5. Press `Option + Command` to start recording, then press it again to stop and generate text.

## Troubleshooting

### Connection test fails

- Check that the API Key is from China North 2 (Beijing).
- Confirm that the key has permission to invoke `qwen3.5-omni-flash-realtime` and that billing is available.
- Do not paste an App ID or API Host into the API Key field.

### A key was exposed

Delete or disable the old key in the Model Studio console immediately and create a new one. Never share keys through screenshots, chat history, or Git repositories.

## Official references

- [Get an API Key](https://help.aliyun.com/zh/model-studio/get-api-key/)
- [API Key console](https://bailian.console.aliyun.com/?tab=model#/api-key)
- [Regions and Base URLs](https://help.aliyun.com/zh/model-studio/base-url)
