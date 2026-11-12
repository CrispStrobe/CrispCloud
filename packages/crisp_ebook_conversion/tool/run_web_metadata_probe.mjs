// Runs the production Dart web adapter with real Wasm in actual Node workers.
// --browser additionally runs that same compiled probe in Chromium.
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath, pathToFileURL} from 'node:url'
import {Worker as NodeWorker} from 'node:worker_threads'
import vm from 'node:vm'
import http from 'node:http'

const root = fileURLToPath(new URL('../', import.meta.url))
const compiled = path.join(root, 'build/web-metadata/probe.js')
const fixture = (await readFile(path.join(root, 'test/fixtures/generated/book.azw3'))).toString('base64')
const prefix = '/preview/assets/packages/crisp_ebook_conversion/assets/'
const origin = 'http://localhost:8080'
let active = 0, started = 0
const terminations = []
const bootstrap = `
const {parentPort, workerData} = require('node:worker_threads');
const {readFile} = require('node:fs/promises');
globalThis.self = globalThis;
globalThis.postMessage = (data, transfer) => parentPort.postMessage(data, transfer);
globalThis.fetch = async url => {
  if (String(url) !== workerData.wasm) throw Error('Unexpected test worker fetch');
  return new Response(await readFile(new URL(url)), {headers: {'Content-Type': 'application/wasm'}});
};
(async () => {
  await import(workerData.worker);
  parentPort.on('message', data => globalThis.onmessage({data}));
})().catch(error => { throw error; });
`

class WorkerAdapter {
    constructor(url, options) {
        assert.equal(options.type, 'module')
        const parsed = new URL(url)
        assert.equal(parsed.origin, origin)
        const filename = parsed.pathname.startsWith(prefix)
            ? path.join(root, 'assets', parsed.pathname.slice(prefix.length))
            : path.join(root, 'build/missing-worker.js')
        this.worker = new NodeWorker(bootstrap, {eval: true, workerData: {
            worker: pathToFileURL(filename).href,
            wasm: pathToFileURL(path.join(root, 'assets/kindling_metadata.wasm')).href,
        }})
        active++; started++
        this.worker.on('message', data => this.onmessage?.({data}))
        this.worker.on('error', error => this.onerror?.({message: String(error), preventDefault() {}}))
        this.worker.on('messageerror', () => this.onmessageerror?.({}))
    }
    postMessage(data, transfer) { this.worker.postMessage(data, transfer) }
    terminate() {
        if (this.closed) return
        this.closed = true
        active--
        terminations.push(this.worker.terminate())
    }
}

globalThis.self = globalThis
globalThis.document = {baseURI: `${origin}/preview/`, currentScript: null, scripts: []}
globalThis.Worker = WorkerAdapter
globalThis.metadataFixtureBase64 = fixture
let finish
const complete = new Promise(resolve => { finish = resolve })
globalThis.metadataSmokeFinished = json => finish(JSON.parse(json))
vm.runInThisContext(await readFile(compiled, 'utf8'), {filename: compiled})
const deadline = setTimeout(() => { throw new Error('Metadata adapter probe timed out') }, 30000)
const result = await complete
clearTimeout(deadline)
await Promise.all(terminations)
assert.equal(result.ok, true, JSON.stringify(result))
assert.equal(active, 0, 'All workers must be terminated')
assert.ok(started >= 10, 'Probe must exercise real worker requests')
console.log(`PASS compiled Dart web adapter: ${result.checks} assertions, ${started} real workers, none leaked`)

if (process.argv.includes('--browser')) {
    const {chromium} = await import('../../crisp_ebook_reader/node_modules/playwright/index.mjs')
    const html = `<!doctype html><meta charset="utf-8"><base href="/preview/">
      <script>globalThis.metadataFixtureBase64=${JSON.stringify(fixture)};
      globalThis.metadataSmokeFinished=value=>globalThis.metadataResult=JSON.parse(value);</script>
      <script src="/probe.js"></script>`
    const server = http.createServer(async (request, response) => {
        try {
            const pathname = new URL(request.url, 'http://localhost').pathname
            if (pathname === '/preview/') { response.setHeader('Content-Type', 'text/html'); response.end(html); return }
            const filename = pathname === '/probe.js' ? compiled :
                pathname.startsWith(prefix) ? path.join(root, 'assets', path.basename(pathname)) : null
            if (!filename) { response.writeHead(404); response.end(); return }
            response.setHeader('Content-Type', filename.endsWith('.wasm') ? 'application/wasm' : 'text/javascript')
            response.end(await readFile(filename))
        } catch { response.writeHead(404); response.end() }
    })
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
    let browser
    try {
        browser = await chromium.launch({headless: true,
            ...(process.env.CHROMIUM_PATH ? {executablePath: process.env.CHROMIUM_PATH} : {})})
        const page = await browser.newPage()
        await page.goto(`http://127.0.0.1:${server.address().port}/preview/`)
        await page.waitForFunction(() => globalThis.metadataResult, {timeout: 30000})
        const browserResult = await page.evaluate(() => globalThis.metadataResult)
        assert.equal(browserResult.ok, true, JSON.stringify(browserResult))
        console.log(`PASS actual Chromium metadata adapter: ${browserResult.checks} assertions`)
    } finally {
        await browser?.close()
        await new Promise(resolve => server.close(resolve))
    }
}
