// Renders scene.html frame by frame (deterministic, 60 fps) into frames/, then encodes an MP4.
// Usage: node record.mjs [--stills t1,t2,...]   (stills: write only those moments as PNGs)
import { chromium } from "playwright-core";   // npm i playwright-core (uses your installed Chrome)
import fs from "node:fs"; import path from "node:path"; import { execFileSync } from "node:child_process";
const HERE = path.dirname(new URL(import.meta.url).pathname);
const SCRIPT = JSON.parse(fs.readFileSync(path.join(HERE, "script.json"), "utf8"));
const stillsArg = process.argv.indexOf("--stills");
const stills = stillsArg > 0 ? process.argv[stillsArg + 1].split(",").map(Number) : null;
const FPS = 60, DPR = stills ? 1 : 1;
const browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--hide-scrollbars", "--force-color-profile=srgb"] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: DPR });
await page.addInitScript(s => { window.SCRIPT = s; }, SCRIPT);
await page.goto("file://" + path.join(HERE, "scene.html"));
await page.evaluate(() => document.fonts.ready);
const total = await page.evaluate(() => window.TOTAL);
console.log("total", total.toFixed(2), "s");
if (stills) {
  fs.mkdirSync(path.join(HERE, "stills"), { recursive: true });
  for (const t of stills) { await page.evaluate(t => setT(t), t); await page.screenshot({ path: path.join(HERE, "stills", `t${t}.png`) }); }
} else {
  const dir = path.join(HERE, "frames"); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir);
  const n = Math.round(total * FPS);
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => setT(t), i / FPS);
    await page.screenshot({ path: path.join(dir, String(i).padStart(5, "0") + ".jpg"), type: "jpeg", quality: 94 });
    if (i % 300 === 0) console.log("frame", i, "/", n);
  }
  execFileSync("ffmpeg", ["-v", "error", "-y", "-framerate", String(FPS), "-i", path.join(dir, "%05d.jpg"),
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    path.join(HERE, "blackbar-demo.mp4")]);
  console.log("wrote blackbar-demo.mp4");
}
await browser.close();
