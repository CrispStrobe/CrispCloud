// SPDX-License-Identifier: Apache-2.0
// Test-only staging helper. No generated engine or fixture bytes enter this repo.
import { cp, mkdir, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const buildCheckout = resolve(here, '../../../tooling/.source');
export const upstreamRoot = process.env.FILE_VIEWER_UPSTREAM_DIR ||
  (existsSync(buildCheckout) ? buildCheckout : resolve(here, '../../../../../../file-viewer'));
const enginesRoot = resolve(here, '../..');
const esbuildUrl = new URL('../../../tooling/node_modules/esbuild/lib/main.js', import.meta.url);

export const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
export const exactArrayBuffer = bytes => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
export const fixtureBytes = async (engine, path, expectedHash) => {
  const bytes = await readFile(resolve(upstreamRoot, 'packages/renderers', engine, path));
  if (expectedHash && sha256(bytes) !== expectedHash) throw new Error(`Unexpected ${engine}/${path} fixture/runtime bytes.`);
  return bytes;
};

export const stageEngine = async (engine, entryNames) => {
  const { build } = await import(esbuildUrl.href);
  const directory = await mkdtemp(resolve(tmpdir(), `crisp-document-${engine}-`));
  const source = resolve(directory, 'src');
  const output = resolve(directory, 'esm');
  try {
    await cp(resolve(upstreamRoot, 'packages/renderers', engine, 'src'), source, { recursive: true });
    const overrides = resolve(enginesRoot, engine, 'src');
    for (const name of await readdir(overrides)) await cp(resolve(overrides, name), resolve(source, name));
    await mkdir(output, { recursive: true });
    await writeFile(resolve(directory, 'package.json'), '{"type":"module"}\n');
    await build({
      entryPoints: Object.fromEntries(entryNames.map(name => [name, resolve(source, `${name}.ts`)])),
      outdir: output, bundle: true, format: 'esm', platform: 'node', target: 'es2020', logLevel: 'silent',
    });
    return {
      directory, source, output,
      load: name => import(pathToFileURL(resolve(output, `${name}.js`)).href),
      close: () => rm(directory, { recursive: true, force: true }),
    };
  } catch (error) { await rm(directory, { recursive: true, force: true }); throw error; }
};

export class FakeWorker extends EventTarget {
  static instances = [];
  static behavior = undefined;
  terminated = false;
  sent = [];
  constructor(url, options) {
    super(); this.url = url; this.options = options;
    FakeWorker.instances.push(this);
  }
  postMessage(message, transfers) {
    this.sent.push({ message, transfers });
    FakeWorker.behavior?.(this, message);
  }
  terminate() { this.terminated = true; }
  respond(data) { this.dispatchEvent(new MessageEvent('message', { data })); }
}

export const withFakeWorkers = async run => {
  const previousWorker = globalThis.Worker;
  const previousDocument = globalThis.document;
  FakeWorker.instances = []; FakeWorker.behavior = undefined;
  globalThis.Worker = FakeWorker;
  globalThis.document = { baseURI: 'http://127.0.0.1:8123/runtime/index.html' };
  try { return await run(); }
  finally {
    for (const worker of FakeWorker.instances) worker.terminate();
    if (previousWorker === undefined) delete globalThis.Worker; else globalThis.Worker = previousWorker;
    if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument;
  }
};
