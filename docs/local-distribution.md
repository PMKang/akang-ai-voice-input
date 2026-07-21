# 本地测试与安装包

项目可以同时生成两种 Universal macOS 产物：

- DMG：面向首次安装，包含应用图标、`Applications` 快捷方式和拖拽引导。
- ZIP：供现有应用内自动更新器下载和解压，也可用于手动安装。

两种产物都包含 Intel 与 Apple 芯片代码。当前仍使用本地临时签名，不代表已经完成 Developer ID 签名或 Apple 公证。

## 仅生成安装包

```bash
./script/package_local.sh --package-only
```

脚本会：

1. 以 Release 配置构建 Universal App，不启动应用。
2. 使用本地临时签名生成 App Bundle。
3. 使用 `ditto` 生成保留 macOS 资源属性的 ZIP。
4. 使用原生 `hdiutil` 生成压缩 DMG。
5. 通过 Finder 写入 DMG 图标位置、背景图和拖拽安装布局。
6. 检查临时签名、当前版本号、Universal 架构、ZIP 完整性和 DMG 校验和。

产物位于已被 `.gitignore` 忽略的 `release/`：

```text
AkangVoiceInput-v<版本>-<构建时间>-macos.dmg
AkangVoiceInput-v<版本>-<构建时间>-macos.zip
```

## 打包后安装到本机

```bash
./script/package_local.sh --install
```

除生成上述两个安装包外，该模式还会替换 `/Applications/Noboard · 自在说.app` 并启动新版本。执行前请确认没有需要保留的同名 App 副本。

## 发布约定

GitHub Release 必须同时上传 DMG 与 ZIP：

- README 将用户引导到 DMG，降低首次安装门槛。
- 应用内更新器继续选择名称包含 `macos` 的 ZIP；不能只发布 DMG。

## 包中不包含

- API Key 或 Workspace ID
- Keychain 数据
- 历史记录或个人词典
- 原始音频或当前运行诊断

所有凭证都由接收者在自己的 Mac 上首次运行后配置。

## 当前签名限制

- App 使用本地临时签名。
- 没有 Developer ID TeamIdentifier。
- 没有启用 Hardened Runtime。
- 没有完成 Apple 公证。
- 其他 Mac 可能显示无法验证开发者的 Gatekeeper 提示。

不要把本地测试 DMG 或 ZIP 描述为已经公证的正式安装包。

## 正式发布前

1. 配置 Developer ID Application 证书。
2. 明确麦克风、辅助功能、网络和 Keychain 所需的签名与权限。
3. 启用 Hardened Runtime 并检查 entitlements。
4. 使用 `notarytool` 提交公证。
5. 使用 `stapler` 将公证票据附加到 DMG。
6. 在全新用户环境验证 Gatekeeper、首次授权、升级和卸载流程。
