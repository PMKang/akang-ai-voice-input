import { env } from "cloudflare:workers";
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { computeFingerprint, parseCrashReport, sanitizeText } from "../src/index";

const feishuFetch = vi.fn<typeof fetch>();

beforeEach(() => {
  feishuFetch.mockResolvedValue(Response.json({ code: 0, msg: "success" }));
  vi.stubGlobal("fetch", feishuFetch);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

function report(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schemaVersion: 1,
    reportID: crypto.randomUUID(),
    product: "noboard",
    kind: "crash",
    source: "macos.ips",
    label: "EXC_BAD_ACCESS",
    version: "1.8.0",
    build: "2026081201",
    osVersion: "macOS 15.6",
    architecture: "arm64",
    errorType: "EXC_BAD_ACCESS",
    errorMessage: "SIGSEGV",
    stack: "AkangVoiceInput · FloatingPanel.update + 42",
    topFrame: "AkangVoiceInput · FloatingPanel.update + 42",
    fingerprintHint: "EXC_BAD_ACCESS|SIGSEGV|FloatingPanel.update + 42",
    occurredAt: "2026-08-12T14:00:00Z",
    incidentID: crypto.randomUUID(),
    breadcrumbs: [
      {
        occurredAt: "2026-08-12T13:59:59Z",
        category: "应用",
        message: "悬浮窗更新",
      },
    ],
    ...overrides,
  };
}

function reportRequest(payload: Record<string, unknown>, ipSuffix = 1): Request {
  const body = JSON.stringify(payload);
  return new Request("https://crash.example.test/v1/report", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": String(new TextEncoder().encode(body).byteLength),
      "CF-Connecting-IP": `203.0.113.${ipSuffix}`,
      "Authorization": "Bearer test-ingest-token-0000000000000001",
    },
    body,
  });
}

describe("Noboard crash report worker", () => {
  it("reports health without touching storage", async () => {
    const ctx = createExecutionContext();
    const response = await worker.fetch(
      new Request("https://crash.example.test/health"),
      env,
      ctx,
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ ok: true });
  });

  it("stores once, groups repeats, and only schedules the first alert", async () => {
    const first = report();
    const firstParsed = parseCrashReport(first);
    const fingerprint = await computeFingerprint(firstParsed);
    const firstContext = createExecutionContext();
    const firstResponse = await worker.fetch(reportRequest(first, 2), env, firstContext);
    expect(firstResponse.status).toBe(202);
    await expect(firstResponse.json()).resolves.toMatchObject({
      accepted: true,
      duplicate: false,
      notificationScheduled: true,
    });
    await waitOnExecutionContext(firstContext);

    const duplicateContext = createExecutionContext();
    const duplicateResponse = await worker.fetch(reportRequest(first, 3), env, duplicateContext);
    await expect(duplicateResponse.json()).resolves.toMatchObject({
      accepted: false,
      duplicate: true,
      notificationScheduled: false,
    });

    const repeat = report({ incidentID: crypto.randomUUID() });
    const repeatContext = createExecutionContext();
    const repeatResponse = await worker.fetch(reportRequest(repeat, 4), env, repeatContext);
    await expect(repeatResponse.json()).resolves.toMatchObject({
      accepted: true,
      duplicate: false,
      notificationScheduled: false,
    });

    const group = await env.DB.prepare(`
      SELECT occurrence_count FROM crash_groups WHERE fingerprint = ?
    `).bind(fingerprint).first<{ occurrence_count: number }>();
    const reportCount = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM crash_reports WHERE fingerprint = ?
    `).bind(fingerprint).first<{ count: number }>();
    const notificationCount = await env.DB.prepare(`
      SELECT COUNT(*) AS count FROM crash_notifications WHERE fingerprint = ?
    `).bind(fingerprint).first<{ count: number }>();
    const notification = await env.DB.prepare(`
      SELECT sent_at, attempt_count, last_error
      FROM crash_notifications
      WHERE fingerprint = ?
    `).bind(fingerprint).first<{
      sent_at: string | null;
      attempt_count: number;
      last_error: string | null;
    }>();
    expect(group?.occurrence_count).toBe(2);
    expect(reportCount?.count).toBe(2);
    expect(notificationCount?.count).toBe(1);
    expect(notification?.sent_at).not.toBeNull();
    expect(notification).toMatchObject({ attempt_count: 1, last_error: null });
    expect(feishuFetch).toHaveBeenCalledTimes(1);

    const [webhook, init] = feishuFetch.mock.calls[0]!;
    expect(String(webhook)).toBe("https://open.feishu.cn/open-apis/bot/v2/hook/test-webhook-id");
    expect(init?.method).toBe("POST");
    const feishuBody = JSON.parse(String(init?.body)) as {
      msg_type: string;
      content: { text: string };
    };
    expect(feishuBody.msg_type).toBe("text");
    expect(feishuBody.content.text).toContain("发现新问题");
    expect(feishuBody.content.text).not.toContain("悬浮窗更新");
  });

  it("sanitizes sensitive values again before D1 persistence", async () => {
    const sensitive = report({
      fingerprintHint: "sensitive-report-test",
      errorMessage: "api_key=sk-test-super-secret alice@example.com",
      stack: "/Users/alice/Projects/Noboard/main.swift",
      breadcrumbs: [
        {
          occurredAt: "2026-08-12T13:59:59Z",
          category: "token",
          message: "Bearer abcdefghijklmnop /home/alice/private",
        },
      ],
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(reportRequest(sensitive, 5), env, ctx);
    expect(response.status).toBe(202);
    await waitOnExecutionContext(ctx);

    const stored = await env.DB.prepare(`
      SELECT error_message, stack, breadcrumbs_json
      FROM crash_reports
      WHERE report_id = ?
    `).bind(sensitive.reportID).first<{
      error_message: string;
      stack: string;
      breadcrumbs_json: string;
    }>();
    const combined = `${stored?.error_message}\n${stored?.stack}\n${stored?.breadcrumbs_json}`;
    expect(combined).not.toContain("sk-test-super-secret");
    expect(combined).not.toContain("alice@example.com");
    expect(combined).not.toContain("/Users/alice");
    expect(combined).not.toContain("/home/alice");
    expect(combined).not.toContain("abcdefghijklmnop");
    expect(combined).toContain("[redacted");
  });

  it("creates an independent notification for every explicit test report", async () => {
    const reportIDs: string[] = [];
    for (const suffix of [6, 7]) {
      const payload = report({ kind: "test", source: "macos.manual-test" });
      reportIDs.push(payload.reportID as string);
      const ctx = createExecutionContext();
      const response = await worker.fetch(
        reportRequest(payload, suffix),
        env,
        ctx,
      );
      await expect(response.json()).resolves.toMatchObject({ notificationScheduled: true });
      await waitOnExecutionContext(ctx);
    }
    const rows = await env.DB.prepare(`
      SELECT reason
      FROM crash_notifications
      WHERE report_id IN (?, ?)
      ORDER BY created_at
    `).bind(...reportIDs).all<{ reason: string }>();
    expect(rows.results.map((row) => row.reason)).toEqual(["test", "test"]);
  });

  it("alerts once when a resolved fingerprint regresses", async () => {
    const initial = report({ fingerprintHint: "regression-test" });
    const initialParsed = parseCrashReport(initial);
    const fingerprint = await computeFingerprint(initialParsed);
    const initialContext = createExecutionContext();
    await worker.fetch(reportRequest(initial, 11), env, initialContext);
    await waitOnExecutionContext(initialContext);

    const resolvedAt = "2026-08-12T14:05:00Z";
    await env.DB.prepare(`
      UPDATE crash_groups SET status = 'resolved', resolved_at = ? WHERE fingerprint = ?
    `).bind(resolvedAt, fingerprint).run();

    const regression = report({ fingerprintHint: "regression-test" });
    const regressionContext = createExecutionContext();
    const response = await worker.fetch(reportRequest(regression, 12), env, regressionContext);
    await expect(response.json()).resolves.toMatchObject({ notificationScheduled: true });
    await waitOnExecutionContext(regressionContext);

    const row = await env.DB.prepare(`
      SELECT reason FROM crash_notifications
      WHERE notification_key = ?
    `).bind(`regression:${fingerprint}:${resolvedAt}`).first<{ reason: string }>();
    const group = await env.DB.prepare(`
      SELECT status, occurrence_count, regressed_at
      FROM crash_groups
      WHERE fingerprint = ?
    `).bind(fingerprint).first<{
      status: string;
      occurrence_count: number;
      regressed_at: string | null;
    }>();
    expect(row?.reason).toBe("regression");
    expect(group).toMatchObject({ status: "open", occurrence_count: 2 });
    expect(group?.regressed_at).not.toBeNull();
  });

  it("rejects missing length, oversized bodies, and malformed payloads", async () => {
    const missingLength = new Request("https://crash.example.test/v1/report", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "CF-Connecting-IP": "203.0.113.8",
        "Authorization": "Bearer test-ingest-token-0000000000000001",
      },
      body: "{}",
    });
    const missingContext = createExecutionContext();
    expect((await worker.fetch(missingLength, env, missingContext)).status).toBe(411);

    const oversized = reportRequest(report(), 9);
    oversized.headers.set("Content-Length", String(49 * 1024));
    const oversizedContext = createExecutionContext();
    expect((await worker.fetch(oversized, env, oversizedContext)).status).toBe(413);

    const malformed = reportRequest(report({ product: "another-app" }), 10);
    const malformedContext = createExecutionContext();
    expect((await worker.fetch(malformed, env, malformedContext)).status).toBe(400);
  });

  it("rejects a report without the ingest token before reading its body", async () => {
    const request = reportRequest(report(), 13);
    request.headers.delete("Authorization");
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({ error: "unauthorized" });
  });

  it("normalizes volatile numbers when computing a fingerprint", async () => {
    const first = parseCrashReport(report({
      fingerprintHint: "EXC_BAD_ACCESS|offset 42|0x1234",
    }));
    const second = parseCrashReport(report({
      fingerprintHint: "EXC_BAD_ACCESS|offset 99|0xfeed",
    }));
    expect(await computeFingerprint(first)).toBe(await computeFingerprint(second));
    expect(sanitizeText("/Users/alice/a sk-test-super-secret")).not.toContain("alice");
  });
});
