// SPDX-License-Identifier: Apache-2.0
// Adapted from flyfish-dev/file-viewer d264009ca6efb3daed79a39d1ae63133e0f25558.
// Modified for CrispCloud: enforce limits before copying, require the real engine,
// bind assets to this local origin, and close the worker on all failure paths.
import type { FileViewerWordPerfectOptions } from '@file-viewer/core';
import { assertWordPerfectInput, type WordPerfectDocument } from './parser.js';

let requestId = 0;

const localAsset = (value: string | URL | undefined, fallback: string) => {
  const base = new URL(document.baseURI);
  const url = new URL(value?.toString() || fallback, base);
  if (url.origin !== base.origin || !['http:', 'https:'].includes(url.protocol)) {
    throw new Error('WordPerfect engine assets must use the local viewer origin.');
  }
  return url.href;
};

export const parseWordPerfectWithWorker = async (
  buffer: ArrayBuffer, options?: FileViewerWordPerfectOptions, signal?: AbortSignal
): Promise<WordPerfectDocument> => {
  assertWordPerfectInput(buffer);
  if (signal?.aborted) throw new DOMException('WordPerfect parsing was aborted.', 'AbortError');
  if (options?.useWorker === false || typeof Worker === 'undefined') {
    throw new Error('The structured WordPerfect preview requires a Web Worker and WebAssembly.');
  }
  const workerUrl = localAsset(options?.workerUrl, 'wordperfect.worker.js');
  const wasmUrl = localAsset(options?.wasmUrl, 'libwpd.wasm');
  const worker = new Worker(workerUrl, { type: 'module', name: 'crispcloud-wordperfect' });
  const id = ++requestId;
  const configuredTimeout = options?.workerTimeoutMs;
  const timeoutMs = typeof configuredTimeout === 'number' && Number.isFinite(configuredTimeout)
    ? Math.min(60_000, Math.max(1_000, configuredTimeout)) : 60_000;
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback: () => void) => {
      if (settled) return;
      settled = true; clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort); worker.terminate(); callback();
    };
    const onAbort = () => finish(() => reject(new DOMException('WordPerfect parsing was aborted.', 'AbortError')));
    const timer = setTimeout(() => finish(() => reject(new Error(`WordPerfect parsing exceeded ${timeoutMs}ms.`))), timeoutMs);
    worker.addEventListener('message', (event: MessageEvent<{ id: number; ok: boolean; document?: WordPerfectDocument; error?: string }>) => {
      if (event.data?.id !== id) return;
      finish(() => event.data.ok && event.data.document
        ? resolve(event.data.document) : reject(new Error(event.data.error || 'WordPerfect Worker failed.')));
    });
    worker.addEventListener('error', event => finish(() => reject(new Error(event.message || 'WordPerfect Worker failed to load.'))));
    worker.addEventListener('messageerror', () => finish(() => reject(new Error('WordPerfect Worker returned an unreadable result.'))));
    signal?.addEventListener('abort', onAbort, { once: true });
    if (signal?.aborted) { onAbort(); return; }
    try {
      const transferable = buffer.slice(0);
      worker.postMessage({ id, buffer: transferable, wasmUrl }, [transferable]);
    } catch (error) { finish(() => reject(error)); }
  });
};
