const MAX_BODY_BYTES = 48 * 1024;
const MAX_PENDING_NOTIFICATIONS_PER_RUN = 20;
const NOTIFICATION_LEASE_SECONDS = 60;
const MAX_NOTIFICATION_ATTEMPTS = 10;
const GITHUB_REPOSITORY = "PMKang/akang-ai-voice-input";

const textEncoder = new TextEncoder();

type CrashKind = "crash" | "exception" | "test";
type NotificationReason = "new" | "regression" | "test";

interface CrashBreadcrumb {
  occurredAt: string;
  category: string;
  message: string;
}

interface CrashReport {
  schemaVersion: 1;
  reportID: string;
  installID: string;
  product: "noboard";
  kind: CrashKind;
  source: string;
  label: string;
  version: string;
  build: string;
  osVersion: string;
  architecture: string;
  errorType: string;
  errorMessage: string;
  stack: string;
  topFrame: string;
  fingerprintHint: string;
  occurredAt: string;
  incidentID: string;
  breadcrumbs: CrashBreadcrumb[];
}

interface NotificationRow {
  notification_key: string;
  fingerprint: string;
  report_id: string;
  reason: NotificationReason;
}

interface NotificationDetailRow extends NotificationRow {
  product: string;
  kind: CrashKind;
  source: string;
  label: string;
  version: string;
  build: string;
  os_version: string;
  architecture: string;
  error_type: string;
  error_message: string;
  stack: string;
  top_frame: string;
  occurred_at: string;
  received_at: string;
  occurrence_count: number;
}

interface GitHubIssueResponse {
  number: number;
  html_url: string;
}

class RequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const sensitiveReplacements: ReadonlyArray<readonly [RegExp, string]> = [
  [/(?:\/Users\/|\/home\/)[^/\\:\s"']+/gi, "[redacted-user]"],
  [/[A-Z]:\\Users\\[^/\\:\s"']+/gi, "[redacted-user]"],
  [/\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b/g, "[redacted-email]"],
  [/Bearer\s+[A-Za-z0-9._~+\-/]+=*/gi, "Bearer [redacted]"],
  [/(api[_ -]?key\s*[:=]\s*)\S+/gi, "$1[redacted]"],
  [/(workspace[_ -]?id\s*[:=]\s*)\S+/gi, "$1[redacted]"],
  [/(authorization|password|secret|token)(\s*[:=]\s*)\S+/gi, "$1$2[redacted]"],
  [/\b(?:sk|ark|rk)-(?:proj-)?[A-Za-z0-9._-]{8,}\b/gi, "[redacted-key]"],
  [/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[redacted-token]"],
  [/wss:\/\/[^/\s]+/gi, "wss://[redacted-host]"],
];

export function sanitizeText(value: string): string {
  return sensitiveReplacements.reduce(
    (result, [pattern, replacement]) => result.replace(pattern, replacement),
    value,
  );
}

function clipUTF8(value: string, maximumBytes: number): string {
  if (textEncoder.encode(value).byteLength <= maximumBytes) return value;
  let result = "";
  let bytes = 0;
  for (const character of value) {
    const characterBytes = textEncoder.encode(character).byteLength;
    if (bytes + characterBytes > maximumBytes) break;
    result += character;
    bytes += characterBytes;
  }
  return result;
}

function normalizedFingerprintPart(value: string): string {
  return value
    .toLowerCase()
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi, "<uuid>")
    .replace(/0x[0-9a-f]+/gi, "<hex>")
    .replace(/\b\d+\b/g, "<n>")
    .replace(/\s+/g, " ")
    .trim();
}

export async function computeFingerprint(report: CrashReport): Promise<string> {
  const hint = report.fingerprintHint.trim();
  const material = hint.length > 0
    ? [report.product, report.kind, report.source, hint]
    : [report.product, report.kind, report.source, report.label, report.errorType, report.topFrame];
  const normalized = material.map(normalizedFingerprintPart).join("|");
  const digest = await crypto.subtle.digest("SHA-256", textEncoder.encode(normalized));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireString(
  record: Record<string, unknown>,
  key: string,
  maximumBytes: number,
  allowEmpty = true,
): string {
  const value = record[key];
  if (typeof value !== "string") {
    throw new RequestError(400, "invalid_payload", `${key} must be a string`);
  }
  const sanitized = clipUTF8(sanitizeText(value), maximumBytes);
  if (!allowEmpty && sanitized.trim().length === 0) {
    throw new RequestError(400, "invalid_payload", `${key} must not be empty`);
  }
  return sanitized;
}

function parseBreadcrumbs(value: unknown): CrashBreadcrumb[] {
  if (!Array.isArray(value) || value.length > 40) {
    throw new RequestError(400, "invalid_payload", "breadcrumbs must be an array with at most 40 items");
  }
  return value.map((candidate) => {
    if (!isRecord(candidate)) {
      throw new RequestError(400, "invalid_payload", "each breadcrumb must be an object");
    }
    return {
      occurredAt: requireString(candidate, "occurredAt", 96),
      category: requireString(candidate, "category", 64),
      message: requireString(candidate, "message", 240),
    };
  });
}

function parseInstallID(value: unknown): string {
  if (value === undefined) return "unknown";
  const installID = requireString({ installID: value }, "installID", 64, false).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(installID)) {
    throw new RequestError(400, "invalid_payload", "installID must be a UUID");
  }
  return installID;
}

export function parseCrashReport(value: unknown): CrashReport {
  if (!isRecord(value)) {
    throw new RequestError(400, "invalid_payload", "payload must be an object");
  }
  if (value.schemaVersion !== 1) {
    throw new RequestError(400, "unsupported_schema", "schemaVersion must be 1");
  }

  const reportID = requireString(value, "reportID", 64, false).toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(reportID)) {
    throw new RequestError(400, "invalid_payload", "reportID must be a UUID");
  }

  const product = requireString(value, "product", 32, false);
  if (product !== "noboard") {
    throw new RequestError(400, "invalid_product", "product is not accepted");
  }

  const kind = requireString(value, "kind", 24, false);
  if (kind !== "crash" && kind !== "exception" && kind !== "test") {
    throw new RequestError(400, "invalid_payload", "kind is not accepted");
  }

  const source = requireString(value, "source", 96, false);
  if (!/^[A-Za-z0-9._-]+$/.test(source)) {
    throw new RequestError(400, "invalid_payload", "source contains unsupported characters");
  }

  const occurredAt = requireString(value, "occurredAt", 96, false);
  if (!Number.isFinite(Date.parse(occurredAt))) {
    throw new RequestError(400, "invalid_payload", "occurredAt must be an ISO timestamp");
  }

  return {
    schemaVersion: 1,
    reportID,
    installID: parseInstallID(value.installID),
    product: "noboard",
    kind,
    source,
    label: requireString(value, "label", 160),
    version: requireString(value, "version", 64),
    build: requireString(value, "build", 64),
    osVersion: requireString(value, "osVersion", 160),
    architecture: requireString(value, "architecture", 32),
    errorType: requireString(value, "errorType", 160),
    errorMessage: requireString(value, "errorMessage", 1_500),
    stack: requireString(value, "stack", 12_000),
    topFrame: requireString(value, "topFrame", 500),
    fingerprintHint: requireString(value, "fingerprintHint", 700),
    occurredAt,
    incidentID: requireString(value, "incidentID", 128),
    breadcrumbs: parseBreadcrumbs(value.breadcrumbs),
  };
}

async function readRequestPayload(request: Request): Promise<unknown> {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0]?.trim().toLowerCase();
  if (contentType !== "application/json") {
    throw new RequestError(415, "unsupported_media_type", "Content-Type must be application/json");
  }
  if (request.headers.has("content-encoding")) {
    throw new RequestError(415, "unsupported_encoding", "compressed request bodies are not accepted");
  }
  const contentLengthValue = request.headers.get("content-length");
  if (contentLengthValue === null || !/^\d+$/.test(contentLengthValue)) {
    throw new RequestError(411, "length_required", "Content-Length is required");
  }
  const contentLength = Number(contentLengthValue);
  if (contentLength <= 0 || contentLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "payload_too_large", "payload exceeds the allowed size");
  }

  const bytes = await request.arrayBuffer();
  if (bytes.byteLength <= 0 || bytes.byteLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "payload_too_large", "payload exceeds the allowed size");
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new RequestError(400, "invalid_json", "request body is not valid JSON");
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

async function insertReport(env: Env, report: CrashReport, fingerprint: string, receivedAt: string): Promise<boolean> {
  const result = await env.DB.prepare(`
    INSERT OR IGNORE INTO crash_reports (
      report_id,
      install_id,
      fingerprint,
      product,
      kind,
      source,
      label,
      version,
      build,
      os_version,
      architecture,
      error_type,
      error_message,
      stack,
      top_frame,
      occurred_at,
      incident_id,
      breadcrumbs_json,
      received_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    report.reportID,
    report.installID,
    fingerprint,
    report.product,
    report.kind,
    report.source,
    report.label,
    report.version,
    report.build,
    report.osVersion,
    report.architecture,
    report.errorType,
    report.errorMessage,
    report.stack,
    report.topFrame,
    report.occurredAt,
    report.incidentID,
    JSON.stringify(report.breadcrumbs),
    receivedAt,
  ).run();
  return (result.meta.changes ?? 0) > 0;
}

async function pendingNotificationForReport(env: Env, reportID: string): Promise<NotificationRow | null> {
  return env.DB.prepare(`
    SELECT notification_key, fingerprint, report_id, reason
    FROM crash_notifications
    WHERE report_id = ? AND sent_at IS NULL
    LIMIT 1
  `).bind(reportID).first<NotificationRow>();
}

async function claimNotification(env: Env, notificationKey: string): Promise<NotificationRow | null> {
  const now = new Date();
  const leaseUntil = new Date(now.getTime() + NOTIFICATION_LEASE_SECONDS * 1_000).toISOString();
  return env.DB.prepare(`
    UPDATE crash_notifications
    SET lease_until = ?, attempt_count = attempt_count + 1
    WHERE notification_key = ?
      AND sent_at IS NULL
      AND attempt_count < ?
      AND (lease_until IS NULL OR lease_until < ?)
    RETURNING notification_key, fingerprint, report_id, reason
  `).bind(
    leaseUntil,
    notificationKey,
    MAX_NOTIFICATION_ATTEMPTS,
    now.toISOString(),
  ).first<NotificationRow>();
}

async function notificationDetails(env: Env, notificationKey: string): Promise<NotificationDetailRow | null> {
  return env.DB.prepare(`
    SELECT
      n.notification_key,
      n.fingerprint,
      n.report_id,
      n.reason,
      r.product,
      r.kind,
      r.source,
      r.label,
      r.version,
      r.build,
      r.os_version,
      r.architecture,
      r.error_type,
      r.error_message,
      r.top_frame,
      r.occurred_at,
      r.received_at,
      g.occurrence_count
    FROM crash_notifications n
    JOIN crash_reports r ON r.report_id = n.report_id
    JOIN crash_groups g ON g.fingerprint = n.fingerprint
    WHERE n.notification_key = ?
    LIMIT 1
  `).bind(notificationKey).first<NotificationDetailRow>();
}

function validatedFeishuWebhook(rawValue: string): URL {
  let url: URL;
  try {
    url = new URL(rawValue);
  } catch {
    throw new Error("FEISHU_WEBHOOK_URL is invalid");
  }
  const allowedHost = url.hostname === "open.feishu.cn" || url.hostname === "open.larksuite.com";
  if (url.protocol !== "https:" || !allowedHost || !url.pathname.startsWith("/open-apis/bot/v2/hook/")) {
    throw new Error("FEISHU_WEBHOOK_URL is not an allowed Feishu bot URL");
  }
  return url;
}

function notificationReasonLabel(row: NotificationDetailRow): string {
  if (row.notification_key.startsWith("occurrence:")) return "问题再次发生";
  const reason = row.reason;
  switch (reason) {
    case "new": return "发现新问题";
    case "regression": return "已解决问题再次出现";
    case "test": return "链路测试";
  }
}

function feishuMessage(row: NotificationDetailRow): string {
  const title = row.label.trim() || row.error_type.trim() || "未命名崩溃";
  const details = [
    `【Noboard · 自在说】${notificationReasonLabel(row)}`,
    `问题：${clipUTF8(title, 180)}`,
    `版本：${row.version || "未知"} (${row.build || "未知"})`,
    `系统：${row.os_version || "未知"} · ${row.architecture || "未知"}`,
    `类型：${row.error_type || row.kind}`,
    `摘要：${clipUTF8(row.error_message || "无", 500)}`,
    `位置：${clipUTF8(row.top_frame || "未提取到应用栈", 500)}`,
    `累计：${row.occurrence_count} 次`,
    `指纹：${row.fingerprint.slice(0, 16)}`,
    `发生：${row.occurred_at}`,
  ];
  if (row.reason === "test") {
    details.push("说明：这是从应用开发者选项主动触发的测试，不是真实崩溃。");
  }
  return details.join("\n");
}

async function postFeishu(env: Env, row: NotificationDetailRow): Promise<void> {
  const webhook = validatedFeishuWebhook(env.FEISHU_WEBHOOK_URL);
  const response = await fetch(webhook, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({
      msg_type: "text",
      content: { text: feishuMessage(row) },
    }),
    signal: AbortSignal.timeout(8_000),
  });
  const responseText = clipUTF8(await response.text(), 2_048);
  if (!response.ok) {
    throw new Error(`Feishu returned HTTP ${response.status}`);
  }
  let result: Record<string, unknown>;
  try {
    const parsed = JSON.parse(responseText) as unknown;
    result = isRecord(parsed) ? parsed : {};
  } catch {
    throw new Error("Feishu returned invalid JSON");
  }
  const code = result.code ?? result.StatusCode;
  if (code !== 0) {
    throw new Error(`Feishu rejected the message with code ${String(code ?? "unknown")}`);
  }
}

async function completeNotification(env: Env, notificationKey: string): Promise<void> {
  await env.DB.prepare(`
    UPDATE crash_notifications
    SET sent_at = ?, lease_until = NULL, last_error = NULL
    WHERE notification_key = ?
  `).bind(new Date().toISOString(), notificationKey).run();
}

async function releaseNotification(env: Env, notificationKey: string, error: unknown): Promise<void> {
  const message = error instanceof Error ? error.message : String(error);
  await env.DB.prepare(`
    UPDATE crash_notifications
    SET lease_until = NULL, last_error = ?
    WHERE notification_key = ? AND sent_at IS NULL
  `).bind(clipUTF8(sanitizeText(message), 500), notificationKey).run();
}

async function deliverNotification(env: Env, notificationKey: string): Promise<void> {
  const claimed = await claimNotification(env, notificationKey);
  if (claimed === null) return;
  try {
    const detail = await notificationDetails(env, notificationKey);
    if (detail === null) throw new Error("notification detail is missing");
    await postFeishu(env, detail);
    await completeNotification(env, notificationKey);
    console.log(JSON.stringify({
      event: "crash_notification_sent",
      reason: detail.reason,
      fingerprint: detail.fingerprint.slice(0, 16),
    }));
  } catch (error) {
    await releaseNotification(env, notificationKey, error);
    console.error(JSON.stringify({
      event: "crash_notification_failed",
      notificationKey,
      error: clipUTF8(sanitizeText(error instanceof Error ? error.message : String(error)), 300),
    }));
  }
}

async function handleReport(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const rateLimitKey = request.headers.get("CF-Connecting-IP") ?? "missing-cf-client-ip";
  const rateLimit = await env.REPORT_RATE_LIMITER.limit({ key: rateLimitKey });
  if (!rateLimit.success) {
    return jsonResponse({ ok: false, error: "rate_limited" }, 429);
  }
  const report = parseCrashReport(await readRequestPayload(request));
  if (report.installID !== "unknown") {
    const installRateLimit = await env.REPORT_RATE_LIMITER.limit({
      key: `install:${report.installID}`,
    });
    if (!installRateLimit.success) {
      return jsonResponse({ ok: false, error: "rate_limited" }, 429);
    }
  }
  const fingerprint = await computeFingerprint(report);
  const receivedAt = new Date().toISOString();
  const existingGroup = report.kind !== "test"
    ? await env.DB.prepare(`
        SELECT status FROM crash_groups WHERE fingerprint = ? LIMIT 1
      `).bind(fingerprint).first<{ status: string }>()
    : null;
  const inserted = await insertReport(env, report, fingerprint, receivedAt);
  if (inserted && report.kind !== "test" && existingGroup?.status === "open") {
    // Every accepted repeat occurrence gets its own notification. The
    // report_id-based key keeps retries idempotent and the existing rate
    // limiter still protects the webhook from abuse.
    await env.DB.prepare(`
      INSERT OR IGNORE INTO crash_notifications (
        notification_key, fingerprint, report_id, reason, created_at
      ) VALUES (?, ?, ?, 'new', ?)
    `).bind(
      `occurrence:${report.reportID}`,
      fingerprint,
      report.reportID,
      receivedAt,
    ).run();
  }
  const notification = inserted
    ? await pendingNotificationForReport(env, report.reportID)
    : null;
  if (notification !== null) {
    ctx.waitUntil(deliverNotification(env, notification.notification_key));
  }
  if (inserted) {
    ctx.waitUntil(syncGitHubIssue(env, fingerprint, report.reportID));
  }

  console.log(JSON.stringify({
    event: "crash_report_accepted",
    reportID: report.reportID,
    kind: report.kind,
    fingerprint: fingerprint.slice(0, 16),
    duplicate: !inserted,
    notificationScheduled: notification !== null,
  }));
  return jsonResponse({
    ok: true,
    accepted: inserted,
    duplicate: !inserted,
    fingerprint: fingerprint.slice(0, 16),
    notificationScheduled: notification !== null,
  }, 202);
}

function githubHeaders(env: Env): HeadersInit {
  return {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${env.GITHUB_TOKEN}`,
    "X-GitHub-Api-Version": "2022-11-28",
    "Content-Type": "application/json",
    "User-Agent": "noboard-crash-report-worker",
  };
}

function githubIssueBody(report: NotificationDetailRow, occurrenceCount: number): string {
  return [
    report.kind === "test" ? "## 自动崩溃测试报告" : "## 自动崩溃报告",
    "",
    `- 指纹：\`${report.fingerprint}\``,
    `- 首次/累计：${occurrenceCount} 次`,
    `- 版本：${report.version || "未知"} (${report.build || "未知"})`,
    `- 系统：${report.os_version || "未知"} · ${report.architecture || "未知"}`,
    `- 类型：${report.error_type || report.kind}`,
    `- 发生时间：${report.occurred_at}`,
    `- Incident ID：${report.report_id}`,
    "",
    `### 摘要\n${report.error_message || "无"}`,
    `### 崩溃位置\n\`${report.top_frame || "未提取到应用栈"}\``,
    `### 调用栈\n\`\`\`text\n${report.stack || "未提取到调用栈"}\n\`\`\``,
    "",
    "> 此 Issue 由 Noboard 崩溃上报 Worker 自动创建；内容已脱敏。",
  ].join("\n");
}

async function syncGitHubIssue(env: Env, fingerprint: string, reportID: string): Promise<void> {
  if (!env.GITHUB_TOKEN) return;
  try {
    const row = await env.DB.prepare(`
      SELECT r.report_id, r.version, r.build, r.os_version, r.architecture,
             r.kind, r.error_type, r.error_message, r.top_frame, r.stack,
             r.occurred_at, r.fingerprint, g.occurrence_count,
             g.github_issue_number
      FROM crash_reports r
      JOIN crash_groups g ON g.fingerprint = r.fingerprint
      WHERE r.report_id = ? AND r.fingerprint = ?
      LIMIT 1
    `).bind(reportID, fingerprint).first<NotificationDetailRow & {
      github_issue_number: number | null;
    }>();
    if (!row) return;

    const baseURL = `https://api.github.com/repos/${GITHUB_REPOSITORY}`;
    const issueNumber = row.github_issue_number;
    if (issueNumber === null || issueNumber === undefined) {
      const response = await fetch(`${baseURL}/issues`, {
        method: "POST",
        headers: githubHeaders(env),
        body: JSON.stringify({
          title: `[${row.kind === "test" ? "Test Crash" : "Crash"}] ${row.error_type || "未知崩溃"} · ${row.top_frame || row.fingerprint.slice(0, 12)}`,
          body: githubIssueBody(row, row.occurrence_count),
        }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`GitHub issue creation failed: HTTP ${response.status}`);
      const issue = await response.json() as GitHubIssueResponse;
      await env.DB.prepare(`
        UPDATE crash_groups SET github_issue_number = ? WHERE fingerprint = ?
      `).bind(issue.number, fingerprint).run();
      console.log(JSON.stringify({ event: "github_issue_created", issue: issue.number, fingerprint: fingerprint.slice(0, 16) }));
      return;
    }

    const response = await fetch(`${baseURL}/issues/${issueNumber}/comments`, {
      method: "POST",
      headers: githubHeaders(env),
      body: JSON.stringify({ body: `### 崩溃再次发生\n\n${githubIssueBody(row, row.occurrence_count)}` }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`GitHub issue comment failed: HTTP ${response.status}`);
    console.log(JSON.stringify({ event: "github_issue_commented", issue: issueNumber, fingerprint: fingerprint.slice(0, 16) }));
  } catch (error) {
    console.error(JSON.stringify({
      event: "github_issue_sync_failed",
      error: clipUTF8(sanitizeText(error instanceof Error ? error.message : String(error)), 300),
      fingerprint: fingerprint.slice(0, 16),
    }));
  }
}

async function handleFetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") {
    return jsonResponse({ ok: true, service: "noboard-crash-report" });
  }
  if (url.pathname !== "/v1/report") {
    return jsonResponse({ ok: false, error: "not_found" }, 404);
  }
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }
  return handleReport(request, env, ctx);
}

async function retryPendingNotifications(env: Env): Promise<void> {
  const now = new Date().toISOString();
  const pending = await env.DB.prepare(`
    SELECT notification_key, fingerprint, report_id, reason
    FROM crash_notifications
    WHERE sent_at IS NULL
      AND attempt_count < ?
      AND (lease_until IS NULL OR lease_until < ?)
    ORDER BY created_at ASC
    LIMIT ?
  `).bind(
    MAX_NOTIFICATION_ATTEMPTS,
    now,
    MAX_PENDING_NOTIFICATIONS_PER_RUN,
  ).all<NotificationRow>();
  await Promise.all(pending.results.map((row) => deliverNotification(env, row.notification_key)));
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      return await handleFetch(request, env, ctx);
    } catch (error) {
      if (error instanceof RequestError) {
        return jsonResponse({ ok: false, error: error.code }, error.status);
      }
      console.error(JSON.stringify({
        event: "crash_report_request_failed",
        error: clipUTF8(sanitizeText(error instanceof Error ? error.message : String(error)), 300),
      }));
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }
  },

  scheduled(
    _controller: ScheduledController,
    env: Env,
    ctx: ExecutionContext,
  ): void {
    ctx.waitUntil(retryPendingNotifications(env));
  },
} satisfies ExportedHandler<Env>;
