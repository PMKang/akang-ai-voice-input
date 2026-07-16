import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

const repository = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
const assetDirectory = resolve(process.cwd(), "assets");
const dataPath = resolve(assetDirectory, "star-history-data.json");
const chartPath = resolve(assetDirectory, "star-history.svg");

if (!repository || !token) throw new Error("GITHUB_REPOSITORY and GITHUB_TOKEN are required.");

const response = await fetch(`https://api.github.com/repos/${repository}`, {
  headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2026-03-10" },
});
if (!response.ok) throw new Error(`Could not read public Star count: ${response.status}`);
const { stargazers_count: starCount } = await response.json();

let history = [];
try { history = JSON.parse(await readFile(dataPath, "utf8")); } catch (error) { if (error.code !== "ENOENT") throw error; }
const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai" }).format(new Date());
history = history.filter((item) => item.date !== today);
history.push({ date: today, stars: starCount });
history.sort((a, b) => a.date.localeCompare(b.date));

const xml = (value) => String(value).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[character]);
const width = 880, height = 300, left = 62, right = 46, top = 58, bottom = 54;
const chartWidth = width - left - right, chartHeight = height - top - bottom;
const maxStars = Math.max(1, ...history.map((item) => item.stars));
const points = history.map((item, index) => {
  const ratio = history.length === 1 ? 0.5 : index / (history.length - 1);
  return [left + ratio * chartWidth, top + chartHeight - (item.stars / maxStars) * chartHeight];
});
const line = points.map(([x, y], index) => `${index ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
const area = `${line} L${(left + chartWidth).toFixed(1)},${top + chartHeight} L${left},${top + chartHeight} Z`;
const labels = [0, 0.5, 1].map((ratio) => {
  const y = top + chartHeight - ratio * chartHeight;
  return `<g><line x1="${left}" x2="${left + chartWidth}" y1="${y}" y2="${y}" class="grid"/><text x="${left - 12}" y="${y + 4}" class="axis" text-anchor="end">${Math.round(maxStars * ratio)}</text></g>`;
}).join("");
const chart = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title description">
<title id="title">${xml(repository)} Star 增长趋势</title><desc id="description">从 ${xml(history[0].date)} 开始自动记录；当前 ${starCount} 个 Star。</desc>
<style>.title{font:700 22px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;fill:#1f2937}.subtitle,.axis{font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;fill:#6b7280}.grid{stroke:#d1d5db;stroke-width:1;stroke-dasharray:3 5}</style>
<rect width="${width}" height="${height}" rx="18" fill="#fffdf5" stroke="#d6d3d1"/><text x="${left}" y="34" class="title">Star 增长趋势</text><text x="${width - right}" y="34" class="subtitle" text-anchor="end">${starCount} Stars · 每日自动记录</text>${labels}
<path d="${area}" fill="#fbbf24" fill-opacity=".18"/><path d="${line}" fill="none" stroke="#b45309" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/><path d="${line}" transform="translate(0,1.8)" fill="none" stroke="#f59e0b" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" opacity=".9"/>
<text x="${left}" y="${height - 22}" class="axis">${xml(history[0].date)}</text><text x="${width - right}" y="${height - 22}" class="axis" text-anchor="end">${today}</text></svg>`;

await mkdir(dirname(dataPath), { recursive: true });
await writeFile(dataPath, `${JSON.stringify(history, null, 2)}\n`);
await writeFile(chartPath, chart);
console.log(`Recorded ${starCount} stars for ${today}.`);
