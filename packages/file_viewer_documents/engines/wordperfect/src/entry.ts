// SPDX-License-Identifier: Apache-2.0
// CrispCloud entry for the selected, patched WordPerfect renderer.
import type { FileRenderContext } from '@file-viewer/core';
import render from './wordperfect.js';

export const renderWordPerfect = (buffer: ArrayBuffer, target: HTMLDivElement, context?: FileRenderContext) =>
  render(buffer, target, 'wpd', context);
export default renderWordPerfect;
