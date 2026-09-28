// Renders site/index.html frame by frame through headless Chrome (CDP), no deps.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
const [, , outDir, fps = '30', dur = '60', only, page = 'index.html'] = process.argv;
mkdirSync(outDir, { recursive: true });
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--remote-debugging-port=9333', '--hide-scrollbars', '--window-size=1920,1080',
  `--user-data-dir=${outDir}/../chrome-profile`, '--allow-file-access-from-files', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 50; i++) { try { targets = await (await fetch('http://127.0.0.1:9333/json/list')).json(); if (targets.find(t => t.type === 'page')) break; } catch {} await sleep(200); }
const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.onopen = r);
let seq = 0; const pending = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise(r => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });
await send('Page.enable');
await send('Page.navigate', { url: 'file://' + new URL('site/' + page, import.meta.url).pathname });
await sleep(1500);
await send('Runtime.evaluate', { expression: 'Promise.all([...document.images].map(i => i.decode()))', awaitPromise: true });
const times = only && only !== 'all' ? only.split(',').map(Number) : Array.from({ length: Math.round(+fps * +dur) }, (_, i) => i / +fps);
for (let i = 0; i < times.length; i++) {
  await send('Runtime.evaluate', { expression: `Promise.resolve(render(${times[i]})).then(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))))`, awaitPromise: true });
  const shot = await send('Page.captureScreenshot', { format: only && only !== 'all' ? 'png' : 'jpeg', quality: 95 });
  const name = only && only !== 'all' ? `t${times[i]}.png` : `${String(i).padStart(5, '0')}.jpg`;
  writeFileSync(`${outDir}/${name}`, Buffer.from(shot.result.data, 'base64'));
}
ws.close(); chrome.kill();
