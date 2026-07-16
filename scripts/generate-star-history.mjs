import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const repository = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
const output = resolve(process.cwd(), "assets/star-history.svg");

if (!repository || !token) throw new Error("GITHUB_REPOSITORY and GITHUB_TOKEN are required.");

const headers = { Accept: "application/vnd.github.star+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2026-03-10", "User-Agent": "akang-star-history" };
const escapeXml = (value) => value.replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[character]);

async function fetchStars() {
  const stars = [];
  for (let page = 1; ; page += 1) {
    const response = await fetch(`https://api.github.com/repos/${repository}/stargazers?per_page=100&page=${page}`, { headers });
    if (!response.ok) throw new Error(`GitHub API returned ${response.status}: ${await response.text()}`);
    const batch = await response.json();
    stars.push(...batch.map((entry) => entry.starred_at).filter(Boolean));
    if (batch.length < 100) return stars;
  }
}

function buildSvg(starTimestamps) {
  const dates = starTimestamps.map((value) => new Date(value)).sort((a, b) => a - b);
  const today = new Date();
  const firstDate = dates[0] ?? today;
  const start = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const days = Math.max(1, Math.round((end - start) / 86_400_000));
  const width = 880, height = 300, left = 62, right = 46, top = 58, bottom = 54;
  const totalStars = dates.length;
  const chartWidth = width - left - right, chartHeight = height - top - bottom, maxStars = Math.max(1, totalStars);
  let cursor = 0;
  const points = [];
  for (let index = 0; index <= Math.min(days, 180); index += 1) {
    const ratio = index / Math.min(days, 180);
    const day = new Date(start.getTime() + ratio * days * 86_400_000);
    while (cursor < dates.length && dates[cursor] <= day) cursor += 1;
    points.push([left + ratio * chartWidth, top + chartHeight - (cursor / maxStars) * chartHeight]);
  }
  const line = points.map(([x, y], index) => `${index === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const area = `${line} L${(left + chartWidth).toFixed(1)},${top + chartHeight} L${left},${top + chartHeight} Z`;
  const labels = [0, 0.5, 1].map((ratio) => {
    const y = top + chartHeight - ratio * chartHeight;
    return `<g><line x1="${left}" x2="${left + chartWidth}" y1="${y}" y2="${y}" class="grid"/><text x="${left - 12}" y="${y + 4}" class="axis" text-anchor="end">${Math.round(maxStars * ratio)}</text></g>`;
  }).join("");
  const dateFormat = new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "short", day: "numeric", timeZone: "Asia/Shanghai" });
  const monthFormat = new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "short", timeZone: "Asia/Shanghai" });
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
  <title id="title">${escapeXml(repository)} Star 增长趋势</title><desc id="description">截至 ${escapeXml(dateFormat.format(today))}，仓库共有 ${totalStars} 个 Star。</desc>
  <style>.title{font:700 22px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;fill:#1f2937}.subtitle,.axis{font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;fill:#6b7280}.grid{stroke:#d1d5db;stroke-width:1;stroke-dasharray:3 5}</style>
  <rect width="${width}" height="${height}" rx="18" fill="#fffdf5" stroke="#d6d3d1"/>
  <text x="${left}" y="34" class="title">Star 增长趋势</text><text x="${width - right}" y="34" class="subtitle" text-anchor="end">${totalStars} Stars · 更新于 ${escapeXml(dateFormat.format(today))}</text>
  ${labels}<path d="${area}" fill="#fbbf24" fill-opacity=".18"/><path d="${line}" fill="none" stroke="#b45309" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/><path d="${line}" transform="translate(0,1.8)" fill="none" stroke="#f59e0b" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity=".9"/>
  <text x="${left}" y="${height - 22}" class="axis">${escapeXml(monthFormat.format(start))}</text><text x="${width - right}" y="${height - 22}" class="axis" text-anchor="end">${escapeXml(monthFormat.format(end))}</text>
</svg>`;
}

const stars = await fetchStars();
await mkdir(dirname(output), { recursive: true });
await writeFile(output, buildSvg(stars));
console.log(`Generated ${output} from ${stars.length} stars.`);
