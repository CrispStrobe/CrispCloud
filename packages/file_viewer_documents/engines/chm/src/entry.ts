// SPDX-License-Identifier: Apache-2.0
// CrispCloud entry for the selected, patched CHM renderer.
import type { FileRenderContext } from '@file-viewer/core';
import { resolveChmOptions } from './model.js';
import render from './chm.js';

export const renderChm = async (buffer: ArrayBuffer, target: HTMLDivElement, context?: FileRenderContext) => {
  const options = resolveChmOptions(context?.options?.chm);
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) throw new Error('CHM input is empty or is not an ArrayBuffer.');
  if (buffer.byteLength > options.maxArchiveBytes) throw new Error('CHM file exceeds the configured preview limit (maximum 64 MiB).');
  if (context?.signal?.aborted) throw new DOMException('CHM rendering was aborted.', 'AbortError');
  return render(buffer, target, 'chm', context);
};
export default renderChm;
