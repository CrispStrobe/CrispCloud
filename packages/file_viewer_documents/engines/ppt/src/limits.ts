// SPDX-License-Identifier: Apache-2.0
// CrispCloud resource policy for the Apache-2.0 Flyfish PPT 1.0.2 runtime.
import type { PptViewerRuntime } from '@file-viewer/ppt';
import type { DocumentFonts } from '../../host/fonts.js';

export const PPT_LIMITS = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  maxStreamBytes: 32 * 1024 * 1024,
  maxRecords: 100_000,
  maxDepth: 32,
  maxSlides: 200,
  maxShapes: 20_000,
  maxAssetBytes: 64 * 1024 * 1024,
  maxTextLength: 2 * 1024 * 1024,
});
export const PPT_INITIAL_TIMEOUT_MS = 30_000;
export const PPT_MAX_SLIDE_DIMENSION = 4096;
export const PPT_MAX_SLIDE_PIXELS = 4 * 1024 * 1024;

export function assertPptInput(buffer: ArrayBuffer): void {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) {
    throw new Error('PowerPoint input is empty or is not an ArrayBuffer.');
  }
  if (buffer.byteLength > PPT_LIMITS.maxFileBytes) {
    throw new Error('PowerPoint file exceeds the 32 MiB preview limit.');
  }
}

export function assertPptSlideBounds(model: { slides: readonly { size: { width: number; height: number } }[] }): void {
  if (!Array.isArray(model.slides) || model.slides.length > PPT_LIMITS.maxSlides) {
    throw new Error('PowerPoint presentation exceeds the slide limit.');
  }
  for (const slide of model.slides) {
    const width = slide?.size?.width;
    const height = slide?.size?.height;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 ||
        width > PPT_MAX_SLIDE_DIMENSION || height > PPT_MAX_SLIDE_DIMENSION ||
        width * height > PPT_MAX_SLIDE_PIXELS) {
      throw new Error('PowerPoint slide exceeds the preview canvas limits.');
    }
  }
}

/** Validate the parsed model before runtime.mount creates any page canvases. */
export function boundPptRuntime(runtime: PptViewerRuntime, fonts?: DocumentFonts): PptViewerRuntime {
  const open = runtime.open.bind(runtime);
  runtime.open = async input => {
    const document = await open(input);
    try {
      assertPptSlideBounds(document.model);
      if (fonts) {
        const render = document.renderSlide.bind(document);
        const release = document.releaseSlide.bind(document);
        const generation = new Map<number, number>();
        const pending = new Map<HTMLCanvasElement | OffscreenCanvas, number>();
        document.renderSlide = async (index, canvas, options = {}) => {
          const token = generation.get(index) || 0;
          const slide = document.model.slides[index];
          if (!slide) return render(index, canvas, options);
          const models = [slide];
          const masterIds = new Set<number>();
          let masterId = slide.showMasterShapes === false ? undefined : slide.masterId;
          while (masterId !== undefined && !masterIds.has(masterId)) {
            masterIds.add(masterId);
            const master = document.model.masters.find(item => item.id === masterId);
            if (!master) break;
            models.push(master); masterId = master.masterId;
          }
          pending.set(canvas, index);
          try {
            // Only visible/requested slides and their master chain need fonts.
            // Await faces before the runtime creates its Canvas text measurer.
            const prepared = await fonts.prepareModel(models, 'Arial');
            if (document.closed || (generation.get(index) || 0) !== token) {
              throw new DOMException('PowerPoint font rendering was aborted.', 'AbortError');
            }
            const withFonts = {...options, transformSvg: (svg: string) => prepared.embedSvg(svg)};
            return await render(index, canvas, withFonts);
          } finally { pending.delete(canvas); }
        };
        document.releaseSlide = async index => {
          generation.set(index, (generation.get(index) || 0) + 1);
          let released = false;
          for (const [canvas, slideIndex] of pending) {
            if (slideIndex !== index) continue;
            canvas.width = 1; canvas.height = 1;
            if ('dataset' in canvas) canvas.dataset.renderState = 'released';
            released = true;
          }
          return await release(index) || released;
        };
      }
      return document;
    } catch (error) {
      await document.close();
      throw error;
    }
  };
  return runtime;
}
