// SPDX-License-Identifier: Apache-2.0
// CrispCloud selection adapter, 2026-11-13. See ../UPSTREAM.md for grants,
// immutable native provenance and modifications to the Apache wrapper.
import type {FileRenderContext} from '@file-viewer/core';
import renderPostscript from './postscript.js';

export const POSTSCRIPT_LIMITS = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  postscriptMaxPages: 200,
  postscriptMaxSourceDimension: 100000,
  postscriptMaxVmBytes: 128 * 1024 * 1024,
  maxCanvasPixels: 16 * 1024 * 1024,
  maxCanvasDimension: 8192,
  workerTimeoutMs: 30000,
  maxLayerCacheBytes: 32 * 1024 * 1024,
  postscriptMaxPrintBytes: 128 * 1024 * 1024,
});

function localAsset(name: string, documentRef: Document): string {
  const url = new URL(name, import.meta.url);
  if (!/^https?:$/.test(url.protocol) || url.origin !== new URL(documentRef.URL).origin || url.username || url.password || url.hash) {
    throw new Error('PostScript runtime assets must use the local viewer origin.');
  }
  return url.href;
}

export async function renderSelectedPostscript(buffer: ArrayBuffer, target: HTMLDivElement, context: FileRenderContext) {
  if (context.signal?.aborted) throw new DOMException('PostScript rendering was aborted.', 'AbortError');
  const requested = context.options?.design;
  const limits: Record<keyof typeof POSTSCRIPT_LIMITS, number> = {...POSTSCRIPT_LIMITS};
  for (const key of Object.keys(limits) as (keyof typeof limits)[]) {
    const value = requested?.[key];
    if (value === undefined) continue;
    if (!Number.isSafeInteger(value) || value < 1 ||
        (key === 'workerTimeoutMs' && value < 1000) ||
        (key === 'postscriptMaxVmBytes' && value < 16 * 1024 * 1024)) {
      throw new Error('Invalid PostScript preview limit.');
    }
    limits[key] = Math.min(value, limits[key]);
  }
  if (buffer.byteLength > limits.maxFileBytes) throw new Error('PostScript exceeds its preview input limit.');
  const options = {...context.options, design: {
    ...requested,
    ...limits,
    postscriptWorkerUrl: localAsset('./postscript.worker.js', target.ownerDocument),
    postscriptWasmUrl: localAsset('./stet_wasm_bg.wasm', target.ownerDocument),
  }};
  const type = context.filename?.toLowerCase().endsWith('.ps') ? 'ps' : 'eps';
  return renderPostscript(buffer, target, type, {...context, options});
}

export default renderSelectedPostscript;
