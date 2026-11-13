// SPDX-License-Identifier: Apache-2.0
// Real browser required. --build-only is explicitly a bundling check, not a pass.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { chromium } from '../../../tooling/node_modules/playwright/index.mjs';
import { build } from '../../../tooling/node_modules/esbuild/lib/main.js';
import { stageEngine, upstreamRoot, toolingRoot, requireDependency, fixture } from './support.mjs';

const spreadsheet = await stageEngine('spreadsheet', { entry: 'entry.ts' });
const ppt = await stageEngine('ppt', { entry: 'entry.ts' });
let browser;
let server;
try {
  const runtime = resolve(spreadsheet.directory, 'runtime');
  await mkdir(runtime);
  await build({
    entryPoints: {
      spreadsheet: resolve(spreadsheet.source, 'entry.ts'),
      ppt: resolve(ppt.source, 'entry.ts'),
      'sheet.worker': resolve(spreadsheet.source, 'spreadsheet/worker/sheetjs/sheet.worker.ts'),
      'pptjs.worker': resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist/pptjs.worker.js'),
    },
    outdir: runtime, bundle: true, splitting: true, platform: 'browser', format: 'esm', target: 'es2022', logLevel: 'silent',
    nodePaths: [resolve(toolingRoot, 'node_modules')],
    alias: {
      '@file-viewer/core': resolve(upstreamRoot, 'packages/core/src/index.ts'),
      '@file-viewer/ppt': resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist/index.js'),
    },
  });
  const sheetjs = requireDependency('styled-exceljs');
  for (const [type, filename] of [['biff8', 'synthetic.xls'], ['xlsb', 'synthetic.xlsb']]) {
    const workbook = sheetjs.utils.book_new();
    sheetjs.utils.book_append_sheet(workbook, sheetjs.utils.aoa_to_sheet([
      ['Name', 'Count'], ['CrispCloud Ω', 42], ['<img src="https://remote.invalid/a" onerror="window.compromised=true">', 7],
    ]), 'Values');
    sheetjs.utils.book_append_sheet(workbook, sheetjs.utils.aoa_to_sheet([['Second worksheet'], [99]]), 'Secondary');
    await writeFile(resolve(runtime, filename), sheetjs.write(workbook, { type: 'buffer', bookType: type }));
  }
  for (const [source, name, hash] of [
    ['packages/renderers/spreadsheet/test/fixtures/github-178-embedded-image.xls', 'image.xls', 'bc5d4542e16382a4a79b639b744f767c7cd5c420b5d5a3c42f132cb51c62eb20'],
    ['apps/viewer-demo/public/example/office-demo.ppt', 'presentation.ppt', '636afd24d8bbd04ef771ed7ad4be6226721f951e81f6d2cf5e5d198bcc8bb927'],
    ['apps/viewer-demo/public/example/format-matrix-template.pot', 'template.pot', '12dfd552e38ffe1a6b8b9d9ec2af83585e5ded679b61cc7c4f1cfa11d8af0282'],
  ]) await writeFile(resolve(runtime, name), new Uint8Array(await fixture(source, hash)));

  await writeFile(resolve(runtime, 'index.html'), `<!doctype html><html><head><meta charset="utf-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline'; worker-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data: blob:; connect-src 'self'; object-src 'none'; frame-src 'none'">
  <style>html,body{margin:0;height:100%}#target{width:100%;height:100%;overflow:auto}</style>
  </head><body><div id="target"></div><script type="module">
  import {renderSpreadsheet} from './spreadsheet.js';
  import {renderPpt} from './ppt.js';
  const NativeWorker=window.Worker;
  window.liveWorkers=new Set();
  window.Worker=class extends NativeWorker {
    constructor(url,options){super(url,options);this.testUrl=String(url);window.liveWorkers.add(this);}
    terminate(){window.liveWorkers.delete(this);super.terminate();}
  };
  let instance,controller;
  window.closeTestDocument=()=>{controller?.abort();instance?.unmount?.();instance=undefined;};
  window.openTestDocument=async filename=>{
    window.closeTestDocument();controller=new AbortController();
    const bytes=await(await fetch('./'+filename)).arrayBuffer();
    const options={locale:'en-US',theme:'light',spreadsheet:{worker:false,workerUrl:'https://remote.invalid/worker.js'},presentation:{pptWorker:false,pptModuleUrl:'https://remote.invalid/module.js',pptWorkerUrl:'https://remote.invalid/ppt.js'}};
    instance=await(/\\.(ppt|pot)$/.test(filename)?renderPpt:renderSpreadsheet)(bytes,document.querySelector('#target'),{filename,signal:controller.signal,options});
    return true;
  };
  window.hasPaint=()=>Array.from(document.querySelectorAll('#target canvas')).some(canvas=>{
    if(canvas.width<2||canvas.height<2)return false;
    const data=canvas.getContext('2d')?.getImageData(0,0,canvas.width,canvas.height).data;if(!data)return false;
    const colors=new Set();for(let i=0;i<data.length;i+=164){if(data[i+3])colors.add(data[i]+','+data[i+1]+','+data[i+2]);if(colors.size>2)return true;}return false;
  });
  window.testReady=true;
  </script></body></html>`);

  if (process.argv.includes('--build-only')) {
    console.log('Browser bundles built for spreadsheet and PPT. No browser checks were executed.');
  } else {
    const known = new Set(await readdir(runtime));
    server = createServer(async (request, response) => {
      const path = new URL(request.url, 'http://127.0.0.1').pathname;
      const name = path.startsWith('/runtime/') ? path.slice(9) : '';
      if (!known.has(name)) { response.writeHead(404); response.end(); return; }
      try {
        const bytes = await readFile(resolve(runtime, name));
        const type = name.endsWith('.html') ? 'text/html' : name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' : 'application/octet-stream';
        response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }); response.end(bytes);
      } catch { response.writeHead(500); response.end(); }
    });
    await new Promise((resolveListen, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolveListen); });
    const origin = `http://127.0.0.1:${server.address().port}`;
    browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || undefined, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
    const page = await browser.newPage({ viewport: { width: 1100, height: 780 } });
    const errors = [];
    const externalRequests = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => { if (!request.url().startsWith(origin) && !/^(blob:|data:)/.test(request.url())) externalRequests.push(request.url()); });
    await page.goto(`${origin}/runtime/index.html`);
    await page.waitForFunction(() => window.testReady === true);

    for (const filename of ['synthetic.xls', 'synthetic.xlsb']) {
      assert.equal(await page.evaluate(filename => window.openTestDocument(filename), filename), true);
      assert.equal(await page.locator('.sheet-tab').count(), 2);
      assert.equal(await page.locator('.sheet-tab.active').innerText(), 'Values');
      await page.waitForFunction(() => window.hasPaint());
      await page.getByRole('button', { name: 'Secondary', exact: true }).click();
      await page.waitForFunction(() => document.querySelector('.sheet-tab.active')?.textContent === 'Secondary');
      assert.equal(await page.evaluate(() => window.compromised), undefined);
      assert.equal(await page.locator('#target script').count(), 0);
      assert.equal(await page.evaluate(() => window.liveWorkers.size), 1);
    }
    await page.evaluate(() => window.openTestDocument('image.xls'));
    await page.waitForFunction(() => document.querySelectorAll('.excel-image').length > 0);
    await page.evaluate(() => window.closeTestDocument());
    assert.equal(await page.locator('.excel-wrapper').count(), 0);
    assert.equal(await page.evaluate(() => window.liveWorkers.size), 0);

    for (const filename of ['presentation.ppt', 'template.pot']) {
      await page.evaluate(filename => window.openTestDocument(filename), filename);
      assert.equal(await page.locator('.ppt-binary-shell').getAttribute('data-ppt-virtualized'), 'true');
      assert.ok(await page.locator('.ppt-binary-page').count() > 0);
      await page.waitForFunction(() => window.hasPaint());
      assert.ok(await page.locator('canvas[data-render-state="rendered"]').count() > 0);
      await page.evaluate(() => window.closeTestDocument());
      assert.equal(await page.locator('.ppt-binary-shell').count(), 0);
      assert.equal(await page.evaluate(() => window.liveWorkers.size), 0);
    }
    assert.deepEqual(errors, []);
    assert.deepEqual(externalRequests, []);

    // Keep the module-worker request pending, then prove abort settles startup
    // and releases ownership without waiting for a response or the 30s timer.
    const held = [];
    await page.route('**/pptjs.worker.js', route => { held.push(route); });
    await page.evaluate(() => { window.pendingResult=window.openTestDocument('presentation.ppt').then(()=>({ok:true}),error=>({ok:false,name:error.name})); });
    await page.waitForFunction(() => Array.from(window.liveWorkers).some(worker => worker.testUrl.endsWith('/pptjs.worker.js')));
    await page.evaluate(() => window.closeTestDocument());
    const aborted = await page.evaluate(() => window.pendingResult);
    assert.equal(aborted.ok, false); assert.equal(aborted.name, 'AbortError');
    assert.equal(await page.evaluate(() => window.liveWorkers.size), 0);
    await Promise.all(held.map(route => route.abort().catch(() => {})));
    await page.unroute('**/pptjs.worker.js');

    // A failed spreadsheet Worker must reject; main-thread parsing is disabled.
    await page.route('**/sheet.worker.js', route => route.abort());
    const failed = await page.evaluate(() => window.openTestDocument('synthetic.xls').then(()=>({ok:true}),error=>({ok:false,message:error.message})));
    assert.equal(failed.ok, false); assert.match(failed.message, /worker|parsing/i);
    assert.equal(await page.evaluate(() => window.liveWorkers.size), 0);
    assert.equal(await page.locator('.excel-wrapper').count(), 0);
    assert.deepEqual(externalRequests, []);
    console.log('Browser smoke passed: actual BIFF8/XLSB grids, worksheet switching, embedded XLS image, PPT/POT canvas paint, local workers, cancellation, disposal and worker-failure rejection.');
  }
} finally {
  await browser?.close();
  if (server) await new Promise(resolveClose => server.close(resolveClose));
  await spreadsheet.close();
  await ppt.close();
}
