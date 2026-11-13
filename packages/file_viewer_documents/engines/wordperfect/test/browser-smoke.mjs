// SPDX-License-Identifier: Apache-2.0
// Real-browser smoke for the selected WPD/CHM engine slice, separate from native host validation.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../../tooling/node_modules/playwright/index.mjs';
import { build } from '../../../tooling/node_modules/esbuild/lib/main.js';
import { stageEngine, upstreamRoot } from './support.mjs';

const wpd = await stageEngine('wordperfect', ['entry']);
const chm = await stageEngine('chm', ['entry']);
let browser;
let server;
try {
  const runtime = resolve(wpd.directory, 'runtime');
  await mkdir(runtime);
  await build({
    entryPoints: {
      'wordperfect-entry': resolve(wpd.source, 'entry.ts'),
      'chm-entry': resolve(chm.source, 'entry.ts'),
      'chm-security': resolve(chm.source, 'security.ts'),
      'wordperfect.worker': resolve(wpd.source, 'wordperfect.worker.ts'),
      'chm.worker': resolve(chm.source, 'chm.worker.ts'),
    },
    outdir: runtime, bundle: true, platform: 'browser', format: 'esm', target: 'es2020', logLevel: 'silent',
  });
  const originals = [
    ['wordperfect/vendor/libwpd.mjs', 'libwpd.mjs'],
    ['wordperfect/vendor/libwpd.wasm', 'libwpd.wasm'],
    ['wordperfect/test/fixtures/corel_wp6.wpd', 'document.wpd'],
    ['chm/src/wasm/chm_wasm.js', 'chm_wasm.js'],
    ['chm/src/wasm/chm_wasm_bg.wasm', 'chm_wasm_bg.wasm'],
    ['chm/rust/tests/fixtures/complete.chm', 'document.chm'],
  ];
  for (const [source, destination] of originals) {
    await cp(resolve(upstreamRoot, 'packages/renderers', source), resolve(runtime, destination));
  }
  await writeFile(resolve(runtime, 'index.html'), `<!doctype html><html><head>
  <meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval'; worker-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data: blob:; connect-src 'self'; frame-src 'self' blob:">
  <style>html,body{margin:0;height:100%}#target{width:100%;height:100%}</style></head><body><div id="target"></div>
  <script type="module">
  import {renderWordPerfect} from './wordperfect-entry.js';
  import {renderChm} from './chm-entry.js';
  import {sanitizeChmHtmlDocument} from './chm-security.js';
  let instance, controller;
  window.openTestDocument=async (kind)=>{
    instance?.destroy?.();controller?.abort();controller=new AbortController();
    const bytes=await (await fetch('./document.'+(kind==='wpd'?'wpd':'chm'))).arrayBuffer();
    const context={filename:'Engine fixture.'+kind,signal:controller.signal,options:{locale:'en-US'}};
    instance=await (kind==='wpd'?renderWordPerfect:renderChm)(bytes,document.querySelector('#target'),context);
  };
  window.closeTestDocument=()=>{instance?.destroy?.();controller?.abort();};
  window.sanitizeTestHtml=html=>sanitizeChmHtmlDocument(html,'/index.html');
  window.testReady=true;
  </script></body></html>`);
  const knownFiles = new Set(['index.html', ...originals.map(([, name]) => name),
    'wordperfect-entry.js', 'chm-entry.js', 'chm-security.js', 'wordperfect.worker.js', 'chm.worker.js']);
  server = createServer(async (request, response) => {
    const path = new URL(request.url, 'http://127.0.0.1').pathname;
    const name = path.startsWith('/runtime/') ? path.slice('/runtime/'.length) : '';
    if (!knownFiles.has(name)) { response.writeHead(404); response.end(); return; }
    try {
      const bytes = await readFile(resolve(runtime, name));
      const type = name.endsWith('.wasm') ? 'application/wasm' : name.endsWith('.html') ? 'text/html' : name.endsWith('.js') || name.endsWith('.mjs') ? 'text/javascript' : 'application/octet-stream';
      response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }); response.end(bytes);
    } catch { response.writeHead(500); response.end(); }
  });
  await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
  const address = server.address();
  browser = await chromium.launch({
    headless: true, executablePath: process.env.CHROME_EXECUTABLE || undefined,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage({ viewport: { width: 1100, height: 780 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${address.port}/runtime/index.html`);
  await page.waitForFunction(() => window.testReady === true);
  await page.evaluate(() => window.openTestDocument('wpd'));
  assert.equal(await page.locator('.wpd-page > table').count(), 3);
  assert.match(await page.locator('.wpd-warning').innerText(), /page layout.*images.*equations/);
  assert.ok(await page.locator('.wpd-warning').isVisible());
  assert.equal(await page.locator('.wpd-footer').count(), 1);
  assert.equal(await page.locator('.wpd-notes').count(), 1);
  const ordered = await page.locator('.wpd-page').evaluate(page => Array.from(page.children)
    .filter(element => element.matches('p,h1,h2,h3,h4,h5,h6,table')).map(element => element.tagName === 'TABLE' ? 'T' : 'P').join(''));
  assert.match(ordered, /TPT/);
  await page.evaluate(() => window.openTestDocument('chm'));
  await page.waitForFunction(() => document.querySelector('.chm-viewer')?.dataset.chmReady === 'true');
  assert.equal(await page.locator('.chm-topic-frame').getAttribute('sandbox'), 'allow-same-origin');
  const topic = page.frameLocator('.chm-topic-frame');
  await topic.locator('h1').waitFor();
  assert.equal(await topic.locator('h1').innerText(), 'Welcome');
  await topic.locator('a').click();
  await page.waitForFunction(() => document.querySelector('.chm-topic-frame')?.contentDocument?.querySelector('h1')?.textContent === 'Setup', undefined, { timeout: 5000 });
  const sanitized = await page.evaluate(() => window.sanitizeTestHtml('<script>alert(1)</script><img src="https://remote.invalid/a.png" onerror="alert(1)"><object data="file:///secret"></object><p>Readable help</p>'));
  assert.ok(!sanitized.html.includes('<script'));
  assert.ok(!sanitized.html.includes('onerror='));
  assert.ok(!sanitized.html.includes('https://remote.invalid'));
  assert.ok(!sanitized.html.includes('<object'));
  assert.match(sanitized.html, /Readable help/);
  assert.match(sanitized.html, /script-src[^;]*none/);
  await page.evaluate(() => window.closeTestDocument());
  assert.equal(await page.locator('.chm-viewer').count(), 0);
  assert.deepEqual(errors, []);
  console.log('Browser smoke passed: real WPD WASM and ordered DOM/warnings; real CHM WASM, sandbox, internal topic navigation, HTML sanitization and disposal.');
} finally {
  await browser?.close();
  if (server) await new Promise(resolveClose => server.close(resolveClose));
  await wpd.close(); await chm.close();
}
