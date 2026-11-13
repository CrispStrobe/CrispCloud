// SPDX-License-Identifier: Apache-2.0
// Selected-engine test staging. Native outputs stay unchanged; generated files
// live in a temporary directory and are not distributed as test dependencies.
import {cp, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {dirname, extname, join, resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const documentRoot = resolve(here, '../../..');
const tooling = join(documentRoot, 'tooling');
const require = createRequire(join(tooling, 'package.json'));
export const upstreamRoot = process.env.FILE_VIEWER_UPSTREAM_DIR || resolve(here, '../../../../../../file-viewer');
export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export const toolingImport = name => import(pathToFileURL(require.resolve(name)).href);
export const npmPath = name => dirname(require.resolve(`${name}/package.json`));
export const fixture = (kind, name) => readFile(join(documentRoot, 'engines', kind, 'test/fixtures', name));

export async function stageSelected(kind) {
  const {build} = await toolingImport('esbuild');
  const directory = await mkdtemp(join(tmpdir(), `crisp-${kind}-`));
  const source = join(directory, 'src');
  const runtime = join(directory, 'runtime');
  const upstreamName = kind === 'xml' ? 'text' : 'design';
  try {
    await cp(join(upstreamRoot, 'packages/renderers', upstreamName, 'src'), source, {recursive: true});
    await cp(join(upstreamRoot, 'packages/core/src'), join(directory, 'core'), {recursive: true});
    await cp(join(documentRoot, 'engines', kind, 'src'), source, {recursive: true});
    await writeFile(join(directory, 'package.json'), '{"type":"module"}\n');
    const names = kind === 'xml'
      ? ['entry', 'xmlSafety', 'xmlWasmMemory', 'xmlEngines']
      : ['entry', 'postscript.worker', 'postscriptLimits', 'postscriptWorkerClient'];
    const built = await build({
      entryPoints: Object.fromEntries(names.map(name => [name, join(source, `${name}.ts`)])),
      outdir: runtime, bundle: true, splitting: true, format: 'esm', platform: 'browser',
      target: 'es2022', metafile: true, logLevel: 'warning', legalComments: 'linked',
      nodePaths: [join(tooling, 'node_modules')],
      alias: {'@file-viewer/core': join(directory, 'core/index.ts')},
    });
    if (kind === 'xml') {
      for (const [name, relative] of [['xmllint-wasm', 'xmllint-browser.mjs'], ['xmllint-wasm', 'xmllint.wasm'], ['xslt-polyfill', 'dist/xslt-wasm.js']]) {
        await cp(join(npmPath(name), relative), join(runtime, relative.split('/').at(-1)));
      }
    } else {
      const wasm = await readFile(join(upstreamRoot, 'packages/renderers/design/runtime/postscript/stet_wasm_bg.wasm'));
      if (sha256(wasm) !== 'b8d72531ec41ca497d67a79589a1dbb44748a4fefd088aa122007fbb28e06b20') throw new Error('Stet native artifact differs from the reviewed pin.');
      await writeFile(join(runtime, 'stet_wasm_bg.wasm'), wasm);
      await cp(join(source, 'postscriptRuntime/stet_wasm.js'), join(runtime, 'stet-native.mjs'));
    }
    return {
      directory, source, runtime, metafile: built.metafile,
      load: name => import(pathToFileURL(join(runtime, `${name}.js`)).href),
      close: () => rm(directory, {recursive: true, force: true}),
    };
  } catch (error) { await rm(directory, {recursive: true, force: true}); throw error; }
}

export async function startBrowser(stage) {
  const imported = await toolingImport('playwright');
  // require.resolve selects Playwright's CommonJS export, whose browser types
  // live on the default export when imported through a file URL.
  const {chromium} = imported.default || imported;
  const requests = [];
  const csp = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval' blob:; style-src 'self' 'unsafe-inline' blob:; img-src 'self' blob: data:; font-src 'self' blob: data:; media-src 'none'; frame-src blob:; connect-src 'self' blob: data:; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; form-action 'none'";
  const server = createServer(async (request, response) => {
    const pathname = new URL(request.url, 'http://127.0.0.1').pathname;
    requests.push(pathname);
    if (pathname === '/') {
      response.setHeader('content-type', 'text/html');
      response.end(`<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${csp}"><link rel="icon" href="data:,"><style>html,body,#document{height:100%;margin:0}.xml-tools{padding:16px}.xml-tools textarea{display:block;width:90%;height:100px}.xml-output iframe{width:90%;height:300px}</style><main id="document"></main>`);
      return;
    }
    const path = resolve(stage.directory, `.${pathname}`);
    if (!path.startsWith(`${stage.directory}${sep}`)) { response.writeHead(403).end(); return; }
    try {
      const bytes = await readFile(path);
      response.setHeader('content-type', ({'.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm'})[extname(path)] || 'application/octet-stream');
      response.setHeader('content-length', bytes.length);
      response.end(bytes);
    } catch { response.writeHead(404).end(); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  let browser;
  try {
    browser = await chromium.launch({
      headless: true,
      ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath: process.env.CHROMIUM_EXECUTABLE} : {}),
    });
  } catch (error) { await new Promise(resolve => server.close(resolve)); throw error; }
  const context = await browser.newContext({viewport: {width: 1100, height: 800}});
  const page = await context.newPage();
  const failures = [];
  page.on('pageerror', error => failures.push(String(error)));
  await page.addInitScript(() => {
    const NativeWorker = globalThis.Worker;
    globalThis.workerStats = {created: 0, terminated: 0};
    globalThis.Worker = class extends NativeWorker {
      constructor(...args) { super(...args); globalThis.workerStats.created++; this.stopped = false; }
      terminate() { if (!this.stopped) { this.stopped = true; globalThis.workerStats.terminated++; } super.terminate(); }
    };
    // Observe native object URLs without substituting their browser behavior.
    const createObjectURL = URL.createObjectURL.bind(URL);
    const revokeObjectURL = URL.revokeObjectURL.bind(URL);
    globalThis.objectUrlStats = {created: [], revoked: []};
    URL.createObjectURL = object => {
      const url = createObjectURL(object);
      globalThis.objectUrlStats.created.push(url);
      return url;
    };
    URL.revokeObjectURL = url => {
      globalThis.objectUrlStats.revoked.push(url);
      return revokeObjectURL(url);
    };
    globalThis.previewController = new AbortController();
  });
  const origin = `http://127.0.0.1:${server.address().port}`;
  await page.goto(origin);
  return {
    page, origin, requests, failures,
    open: async (bytes, filename, options = {}) => page.evaluate(async ({bytes, filename, options}) => {
      globalThis.previewController?.abort();
      globalThis.previewInstance?.destroy();
      globalThis.previewController = new AbortController();
      const {default: render} = await import('/runtime/entry.js');
      globalThis.previewInstance = await render(Uint8Array.from(bytes).buffer, document.querySelector('#document'), {
        filename, options, signal: globalThis.previewController.signal,
      });
    }, {bytes: [...bytes], filename, options}),
    close: async () => {
      await page.evaluate(() => { globalThis.previewController?.abort(); globalThis.previewInstance?.destroy(); }).catch(() => {});
      await browser.close();
      await new Promise(resolve => server.close(resolve));
    },
  };
}
