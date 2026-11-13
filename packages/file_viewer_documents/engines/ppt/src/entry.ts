// SPDX-License-Identifier: Apache-2.0
// CrispCloud entry for the selected Apache-2.0 binary PowerPoint renderer.
import type { FileRenderContext } from '@file-viewer/core';
import render from './index.js';
import { assertPptInput, PPT_INITIAL_TIMEOUT_MS } from './limits.js';

export async function renderPpt(buffer: ArrayBuffer, target: HTMLDivElement, context?: FileRenderContext) {
  assertPptInput(buffer);
  if (context?.signal?.aborted) throw new DOMException('PowerPoint rendering was aborted.', 'AbortError');
  if (typeof Worker === 'undefined') throw new Error('PowerPoint preview requires a parsing worker.');
  if (!target?.ownerDocument?.defaultView?.IntersectionObserver) {
    throw new Error('PowerPoint preview requires virtual slide rendering.');
  }
  const controller = new AbortController();
  const abort = () => controller.abort(context?.signal?.reason || new DOMException('PowerPoint rendering was aborted.', 'AbortError'));
  context?.signal?.addEventListener('abort', abort, { once: true });
  const timeout = setTimeout(() => controller.abort(new Error('PowerPoint preview exceeded the 30-second rendering limit.')), PPT_INITIAL_TIMEOUT_MS);
  try {
    const instance = await render(buffer, target, 'ppt', {
      ...context,
      signal: controller.signal,
      options: {
        ...context?.options,
        presentation: {
          ...context?.options?.presentation,
          pptModuleUrl: undefined,
          pptWorkerUrl: new URL('./pptjs.worker.js', import.meta.url).href,
          pptWorker: true,
          pptWasmUrl: undefined,
          pptFontUrl: undefined,
          pptCache: false,
          pptVirtualize: true,
          pptVirtualRootMargin: '100px 0px',
          pptReleaseDelayMs: 0,
        },
      },
    });
    if (controller.signal.aborted) {
      instance.unmount();
      throw controller.signal.reason;
    }
    // The renderer's startup abort listener is removed once mounting completes.
    // The host signal still owns the mounted instance's whole lifetime.
    const unmount = instance.unmount.bind(instance);
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      context?.signal?.removeEventListener('abort', close);
      unmount();
    };
    context?.signal?.addEventListener('abort', close, { once: true });
    return { ...instance, unmount: close };
  } catch (error) {
    if (controller.signal.aborted) throw controller.signal.reason;
    throw error;
  } finally {
    clearTimeout(timeout);
    context?.signal?.removeEventListener('abort', abort);
  }
}

export default renderPpt;
