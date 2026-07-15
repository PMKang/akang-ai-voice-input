# 本地测试包

阿康的 AI 语音输入法当前可以生成便于本机或受信任测试者验证的 ZIP，但它仍是本地临时签名构建，不是正式发布版本。

## 生成

```bash
./script/package_local.sh
```

脚本会：

1. 使用 `build_and_run.sh --build-only` 重新构建 App Bundle，不启动应用。
2. 执行 `codesign --verify --deep --strict`。
3. 使用 `ditto` 创建保留 macOS 资源属性的 ZIP。
4. 使用 `unzip -t` 检查压缩包完整性。
5. 生成 SHA-256 校验文件。
6. 生成不含凭证和本地数据的测试包清单。

产物位于 `release/`，该目录已加入 `.gitignore`：

```text
AkangVoiceInput-v<版本>-macos-<架构>-local.zip
AkangVoiceInput-v<版本>-macos-<架构>-local.zip.sha256
AkangVoiceInput-v<版本>-macos-<架构>-local-manifest.txt
```

## 校验

接收者可以在 ZIP 所在目录执行：

```bash
shasum -a 256 -c AkangVoiceInput-v<版本>-macos-arm64-local.zip.sha256
```

显示 `OK` 代表文件与生成时一致。

## 包中不包含

- API Key
- Workspace ID
- Keychain 数据
- 历史记录
- 个人词典
- 原始音频
- 当前运行诊断

所有凭证都需要接收者在自己的 Mac 上首次运行后配置。

## 当前限制

- App 使用本地临时签名。
- 没有 Developer ID TeamIdentifier。
- 没有启用 Hardened Runtime。
- 没有完成 Apple 公证。
- 其他 Mac 可能显示无法验证开发者的 Gatekeeper 提示。

不要把本地测试 ZIP 描述为已经公证或可直接公开分发的正式安装包。

## 正式发布前

1. 确定 Bundle ID 与版本策略。
2. 配置 Developer ID Application 证书。
3. 明确麦克风、辅助功能、网络和 Keychain 所需的签名与权限。
4. 启用 Hardened Runtime 并检查 entitlements。
5. 使用 `notarytool` 提交公证。
6. 使用 `stapler` 附加公证票据。
7. 在全新用户环境验证 Gatekeeper、首次授权、升级和卸载流程。
