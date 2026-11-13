// Tests the actual shipped CSP, chunks, worker URLs and Flutter-host protocol.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {dirname, extname, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {chromium} from 'playwright';

const here = dirname(fileURLToPath(import.meta.url));
const assets = resolve(here, '../assets');
const upstream = process.env.FILE_VIEWER_UPSTREAM_DIR || resolve(here, '.source');
const session = '12345678901234567890123456789012';
const mime = {'.html':'text/html', '.js':'text/javascript', '.mjs':'text/javascript', '.css':'text/css', '.wasm':'application/wasm', '.json':'application/json'};
const server = createServer(async (request, response) => {
  try {
    const path = resolve(assets, `.${new URL(request.url, 'http://localhost').pathname}`);
    if (!path.startsWith(assets + sep)) throw Error('Outside asset root');
    const data = await readFile(path);
    response.writeHead(200, {'Content-Type':mime[extname(path)] || 'application/octet-stream', 'X-Content-Type-Options':'nosniff'});
    response.end(data);
  } catch {
    response.writeHead(404); response.end();
  }
});
await new Promise(resolveListen => server.listen(0, '127.0.0.1', resolveListen));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({headless:true, executablePath:process.env.CHROME_EXECUTABLE || undefined});
  const cases = [
    ['wordperfect','sample.wpd','packages/renderers/wordperfect/test/fixtures/corel_wp6.wpd','.wpd-warning'],
    ['chm','sample.chm','packages/renderers/chm/rust/tests/fixtures/complete.chm','.chm-topic-frame'],
    ['spreadsheet','sample.xls','packages/renderers/spreadsheet/test/fixtures/github-178-embedded-image.xls','.excel-wrapper'],
    ['ppt','sample.pot','apps/viewer-demo/public/example/format-matrix-template.pot','.ppt-binary-shell'],
    ['postscript','sample.ps',null,'canvas'],
    ['xml','sample.xml',null,'.xml-tools'],
  ];
  for (const [kind, filename, fixture, selector] of cases) {
    const page = await browser.newPage({viewport:{width:1100,height:800}});
    const errors = [], external = [], failedAssets = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400 && !response.url().endsWith('/favicon.ico')) failedAssets.push(`${response.status()} ${response.url()}`); });
    await page.route('**/*', async route => {
      const url = route.request().url();
      if (/^https?:/.test(url) && new URL(url).origin !== origin) { external.push(url); await route.abort(); }
      else await route.continue();
    });
    await page.addInitScript(() => {
      window.testMessages = [];
      window.CrispDocumentMessage = {postMessage: value => window.testMessages.push(JSON.parse(value))};
      const NativeWorker = window.Worker;
      window.testWorkers = new Set();
      window.Worker = class extends NativeWorker {
        constructor(...args) { super(...args); window.testWorkers.add(this); }
        terminate() { window.testWorkers.delete(this); return super.terminate(); }
      };
    });
    await page.goto(`${origin}/index.html#${session}`);
    await page.waitForFunction(() => window.testMessages.some(message => message.type === 'ready'));
    const bytes = fixture ? await readFile(resolve(upstream, fixture)) : Buffer.from(kind === 'xml'
      ? '<order><quantity>2</quantity><price>12.5</price></order>'
      : '%!PS-Adobe-3.0\n%%BoundingBox: 0 0 200 200\n<< /PageSize [200 200] >> setpagedevice\n1 0 0 setrgbcolor 20 20 120 100 rectfill\nshowpage\n');
    const send = async value => page.evaluate(value => window.crispDocumentHost.receive(value),
      {channel:'crisp-document-v1',session,...value});
    // Messages for another session must not consume the current session.
    await send({type:'begin',session:'wrong-session',filename:'wrong',kind:'xml',length:0});
    await send({type:'begin',filename,kind,length:bytes.length,locale:'en',dark:false,fontScale:1});
    for (let offset=0;offset<bytes.length;offset+=192*1024) {
      await send({type:'chunk',offset,data:bytes.subarray(offset,offset+192*1024).toString('base64')});
    }
    await send({type:'open'});
    await page.waitForFunction(() => window.testMessages.some(message => ['loaded','error'].includes(message.type)), undefined, {timeout:90000});
    const result = await page.evaluate(() => window.testMessages.find(message => ['loaded','error'].includes(message.type)));
    assert.equal(result.type, 'loaded', `${kind}: ${result.message || 'failed'}`);
    await page.locator(selector).first().waitFor();
    if (kind === 'chm') {
      assert.equal(await page.locator(selector).getAttribute('sandbox'), 'allow-same-origin');
      await page.frameLocator(selector).locator('h1').waitFor();
      assert.equal(await page.frameLocator(selector).locator('h1').innerText(), 'Welcome');
    }
    if (kind === 'ppt') await page.locator('canvas[data-render-state="rendered"]').first().waitFor();
    if (kind === 'wordperfect') assert.equal(await page.locator('.wpd-page > table').count(), 3);
    await send({type:'appearance',dark:true,fontScale:1.25,locale:'de'});
    assert.equal(await page.locator('body').getAttribute('data-dark'), 'true');
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pagehide')));
    await page.waitForFunction(() => window.testWorkers.size === 0);
    assert.deepEqual(external, [], `${kind}: external requests`);
    assert.deepEqual(failedAssets, [], `${kind}: missing shipped assets`);
    assert.deepEqual(errors, [], `${kind}: browser exceptions`);
    console.log(`Shipped host passed: ${kind}, exact local assets/CSP, nonce, chunk transfer and cleanup.`);
    await page.close();
  }
  const page = await browser.newPage();
  await page.addInitScript(() => { window.messages=[]; window.CrispDocumentMessage={postMessage:value=>window.messages.push(JSON.parse(value))}; });
  await page.goto(`${origin}/index.html#${session}`);
  await page.waitForFunction(() => window.crispDocumentHost);
  await page.evaluate(session => window.crispDocumentHost.receive({channel:'crisp-document-v1',session,type:'begin',kind:'xml',filename:'too-large.xml',length:4*1024*1024+1}), session);
  assert.match(await page.locator('.document-error').innerText(), /limit/);
  await page.close();
} finally {
  await browser?.close();
  await new Promise(resolveClose => server.close(resolveClose));
}
