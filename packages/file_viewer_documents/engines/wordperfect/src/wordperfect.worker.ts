// SPDX-License-Identifier: Apache-2.0
// Adapted from flyfish-dev/file-viewer d264009ca6efb3daed79a39d1ae63133e0f25558.
// Modified for CrispCloud: require structured parsing; never substitute text extraction.
/// <reference lib="webworker" />
import { parseWordPerfectWithLibWpd } from './libwpd.js';

interface WordPerfectWorkerRequest { id: number; buffer: ArrayBuffer; wasmUrl?: string }
const workerScope = self as unknown as DedicatedWorkerGlobalScope;
workerScope.addEventListener('message', async (event: MessageEvent<WordPerfectWorkerRequest>) => {
  const { id, buffer } = event.data;
  try {
    const moduleUrl = new URL('libwpd.mjs', workerScope.location.href).href;
    const wasmUrl = event.data.wasmUrl || new URL('libwpd.wasm', workerScope.location.href).href;
    if (new URL(wasmUrl).origin !== new URL(workerScope.location.href).origin) {
      throw new Error('WordPerfect WebAssembly must use the local viewer origin.');
    }
    const document = await parseWordPerfectWithLibWpd(buffer, moduleUrl, wasmUrl);
    workerScope.postMessage({ id, ok: true, document });
  } catch (error) {
    workerScope.postMessage({ id, ok: false, error: error instanceof Error ? error.message : String(error) });
  }
});
