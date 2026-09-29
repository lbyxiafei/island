// node render.mjs stills <outDir> <t,t,...>   |   node render.mjs video <out.mp4> <seconds>
// Renders index.html at 3840x2160 (1920x1080 CSS px, DPR 2) through headless Chrome (CDP).
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
const [, , mode, out, arg] = process.argv;
const FPS = 30, here = new URL('.', import.meta.url).pathname;
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--remote-debugging-port=9334', '--hide-scrollbars',
  '--window-size=1920,1080', `--user-data-dir=${here}chrome-profile`, '--allow-file-access-from-files', '--force-color-profile=srgb', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 60; i++) { try { targets = await (await fetch('http://127.0.0.1:9334/json/list')).json(); if (targets.find(t => t.type === 'page')) break; } catch {} await sleep(200); }
const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let seq = 0; const pending = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 2, mobile: false });
await send('Page.enable');
await send('Page.navigate', { url: 'file://' + here + 'index.html' + (process.env.SCENE_QUERY || '') });
await sleep(1500);
await send('Runtime.evaluate', { expression: 'Promise.all([...document.images].map(i => i.decode())).then(() => document.fonts.ready)', awaitPromise: true });
const frame = async (t, fmt) => {
  await send('Runtime.evaluate', { expression: `Promise.resolve(render(${t})).then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))`, awaitPromise: true });
  const shot = await send('Page.captureScreenshot', { format: fmt, quality: 94, captureBeyondViewport: false });
  return Buffer.from(shot.result.data, 'base64');
};
if (mode === 'stills') {
  mkdirSync(out, { recursive: true });
  for (const t of arg.split(',')) writeFileSync(`${out}/t${t}.png`, await frame(+t, 'png'));
} else {
  const ff = spawn('ffmpeg', ['-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const n = Math.round(+arg * FPS);
  for (let i = 0; i < n; i++) {
    const buf = await frame(i / FPS, 'jpeg');
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 150 === 0) console.log(`frame ${i}/${n}`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r));
}
ws.close(); chrome.kill();
