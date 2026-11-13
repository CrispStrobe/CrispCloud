// SPDX-License-Identifier: Apache-2.0
// CrispCloud entry for the selected original grid renderer and bounded parser.
import type { FileRenderContext } from '@file-viewer/core';
import render from './spreadsheet.js';
import { assertSpreadsheetInput, SPREADSHEET_LIMITS } from './limits.js';

export async function renderSpreadsheet(buffer: ArrayBuffer, target: HTMLDivElement, context?: FileRenderContext) {
  assertSpreadsheetInput(buffer);
  if (context?.signal?.aborted) throw new DOMException('Spreadsheet rendering was aborted.', 'AbortError');
  if (!target?.ownerDocument?.defaultView?.Worker && typeof Worker === 'undefined') {
    throw new Error('Spreadsheet preview requires a parsing worker.');
  }
  const type = context?.filename?.split('.').pop()?.toLowerCase() || 'xls';
  const controller = new AbortController();
  const abort = () => controller.abort(context?.signal?.reason || new DOMException('Spreadsheet rendering was aborted.', 'AbortError'));
  context?.signal?.addEventListener('abort', abort, { once: true });
  const timeout = setTimeout(() => controller.abort(new Error('Spreadsheet preview exceeded the 30-second rendering limit.')), SPREADSHEET_LIMITS.workerTimeoutMs);
  let mounted = false;
  try {
    const instance = await render(buffer, target, type, {
      ...context,
      signal: controller.signal,
      options: {
        ...context?.options,
        spreadsheet: {
          ...context?.options?.spreadsheet,
          worker: true,
          workerUrl: new URL('./sheet.worker.js', import.meta.url).href,
        },
      },
    });
    if (controller.signal.aborted) {
      instance.unmount();
      throw controller.signal.reason;
    }
    mounted = true;
    const unmount = instance.unmount.bind(instance);
    let closed = false;
    return { ...instance, unmount: () => {
      if (closed) return;
      closed = true;
      context?.signal?.removeEventListener('abort', abort);
      unmount();
    } };
  } catch (error) {
    if (controller.signal.aborted) throw controller.signal.reason;
    throw error;
  } finally {
    clearTimeout(timeout);
    if (!mounted) context?.signal?.removeEventListener('abort', abort);
  }
}

export default renderSpreadsheet;
