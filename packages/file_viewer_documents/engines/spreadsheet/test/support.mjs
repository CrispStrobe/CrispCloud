// SPDX-License-Identifier: Apache-2.0
// Real-source test staging; the reviewed upstream checkout is never changed.
import { cp, mkdir, mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const packageRoot = resolve(here, '../../..');
export const toolingRoot = resolve(packageRoot, 'tooling');
const buildCheckout = resolve(toolingRoot, '.source');
export const upstreamRoot = process.env.FILE_VIEWER_UPSTREAM_DIR ||
  (existsSync(buildCheckout) ? buildCheckout : resolve(packageRoot, '../../../file-viewer'));
export const requireDependency = createRequire(resolve(toolingRoot, 'package.json'));
export const exactArrayBuffer = bytes => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
export const hash = bytes => createHash('sha256').update(bytes).digest('hex');
export async function fixture(relative, sha256) {
  const bytes = await readFile(resolve(upstreamRoot, relative));
  if (hash(bytes) !== sha256) throw new Error(`Fixture identity differs: ${relative}`);
  return exactArrayBuffer(bytes);
}

export async function stageEngine(engine, entries) {
  const renderer = engine === 'ppt' ? 'presentation-ppt' : engine;
  const { build } = await import(pathToFileURL(resolve(toolingRoot, 'node_modules/esbuild/lib/main.js')).href);
  const directory = await mkdtemp(resolve(tmpdir(), `crisp-${engine}-`));
  const source = resolve(directory, 'src');
  const output = resolve(directory, 'esm');
  try {
    await cp(resolve(upstreamRoot, `packages/renderers/${renderer}/src`), source, { recursive: true });
    await cp(resolve(packageRoot, `engines/${engine}/src`), source, { recursive: true });
    await mkdir(output, { recursive: true });
    await writeFile(resolve(directory, 'package.json'), '{"type":"module"}\n');
    await build({
      entryPoints: Object.fromEntries(Object.entries(entries).map(([name, relative]) => [name, resolve(source, relative)])),
      outdir: output, bundle: true, format: 'esm', platform: 'node', target: 'es2022', logLevel: 'silent',
      nodePaths: [resolve(toolingRoot, 'node_modules')],
      alias: {
        '@file-viewer/core': resolve(upstreamRoot, 'packages/core/src/index.ts'),
        '@file-viewer/ppt': resolve(upstreamRoot, 'apps/viewer-demo/public/vendor/ppt/dist/index.js'),
      },
    });
    return {
      directory, source, output,
      load: name => import(pathToFileURL(resolve(output, `${name}.js`)).href),
      close: () => rm(directory, { recursive: true, force: true }),
    };
  } catch (error) { await rm(directory, { recursive: true, force: true }); throw error; }
}

export class FakeWorker extends EventTarget {
  sent = [];
  terminated = false;
  postMessage(message) { this.sent.push(message); }
  terminate() { this.terminated = true; }
  respond(data) { this.dispatchEvent(new MessageEvent('message', { data })); }
}
