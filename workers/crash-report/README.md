# Noboard 崩溃上报 Worker

这个 Worker 是 macOS 客户端与飞书群机器人之间的安全边界：

```text
Noboard（用户主动开启） → Cloudflare Worker → D1 去重/留样 → 飞书群机器人
```

客户端不会包含飞书 Webhook。入口另有一枚独立上报令牌，Worker 会在读取正文前校验，用来拦截没有令牌的请求；随后再次校验和脱敏正文。它只在以下情况推送飞书：

- 第一次出现的新问题；
- D1 中状态已被标记为 `resolved` 后再次出现；
- 开发者选项主动发送的链路测试。

同一指纹的普通重复报告只增加 `occurrence_count`，不会反复刷群。发送失败的通知由每 5 分钟运行一次的 Cron 重试，最多 10 次。

## 本地验证

```bash
npm install
npm run types
npm run typecheck
npm test
npm run deploy:dry
```

测试使用本地 Workers Runtime 和本地 D1，不会调用真实飞书 Webhook。

## 首次部署

1. 登录 Cloudflare，并创建 D1：

   ```bash
   npx wrangler login
   npx wrangler d1 create noboard-crash-reports
   ```

2. 将命令返回的 `database_id` 写入 `wrangler.jsonc`，替换全零占位值。
3. 应用远端迁移：

   ```bash
   npx wrangler d1 migrations apply noboard-crash-reports --remote
   ```

4. 生成至少 32 位随机上报令牌，并把它保存为 Worker Secret。构建客户端时也要注入同一枚令牌：

   ```bash
   openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
   npx wrangler secret put REPORT_INGEST_TOKEN
   ```

   第二条命令会提示输入值，请粘贴第一条命令生成的令牌。构建客户端时通过 `NOBOARD_CRASH_REPORT_TOKEN` 注入同一枚令牌；普通用户无需填写任何令牌。

5. 在飞书群添加“自定义机器人”，然后把完整 Webhook 作为 Worker Secret 输入：

   ```bash
   npx wrangler secret put FEISHU_WEBHOOK_URL
   ```

   Webhook 只允许 `https://open.feishu.cn/open-apis/bot/v2/hook/...` 或 Lark 对应域名；不要把它写入代码、`.env`、截图或提交记录。

6. 部署：

   ```bash
   npm run deploy
   ```

7. 用最终地址构建客户端（必须包含完整上报路径）：

   ```bash
   NOBOARD_CRASH_REPORT_ENDPOINT="https://<worker>.workers.dev/v1/report" \
     ./script/build_and_run.sh --build-only
   ```

8. 打开 Noboard 设置的开发者模式，开启“自动发送脱敏崩溃报告”，再点“发送测试告警”。只有同时看到应用显示 Worker 已接收、D1 新增测试记录、飞书收到“链路测试”，才算端到端验证通过。

## 处理已解决问题

D1 暂未提供管理后台。确认修复后，可在 Cloudflare D1 Console 中按指纹执行：

```sql
UPDATE crash_groups
SET status = 'resolved', resolved_at = datetime('now')
WHERE fingerprint = '<完整指纹>';
```

该指纹下次出现时会转回 `open`，并生成一次“已解决问题再次出现”告警。

## 数据边界

- 请求体上限 48 KiB，并要求明确的 `Content-Length`。
- 每个 Cloudflare 客户端 IP 每分钟最多 20 次。IP 只作为 Cloudflare Rate Limiting key，不写入 D1。
- D1 保存脱敏后的错误摘要、应用栈、最多 40 条脱敏 breadcrumb 和版本环境信息。
- 飞书消息不包含完整栈或 breadcrumb，只包含定位所需摘要。
- 客户端不上传原始 `.ips`、音频、转写正文、API Key 或 Workspace ID。
- 客户端只生成一个随机安装 ID，用于联合限流和重复来源识别；它不是网卡、蓝牙或硬件序列号，也不用于跨应用追踪。

按 IP 限流存在共享出口误伤的可能，因此当前阈值刻意设得较宽；如果以后有账号或安装标识，应改为不含个人信息的服务端身份键。

上报令牌会随受控版本构建进入 App，目的是让用户下载后直接可用；它不是设备证明，也不是不可提取的秘密。泄露后最坏影响是伪造报告、消耗 Worker/D1 配额或触发飞书骚扰，不能直接得到飞书 Webhook。当前实现依靠服务端限流、字段校验、去重和可轮换 Secret 控制风险；公开发行前应升级为每安装注册、可撤销和可轮换的凭证体系。
