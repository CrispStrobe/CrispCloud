import {
  DEFAULT_RENDERER_DEFINITIONS,
  normalizeFileViewerErrorMessage,
  resolveFileViewerAssetUrl,
  resolveFileViewerRuntimeAssetBaseUrl
} from "./chunk-3E27RFED.js";
import {
  waitForFileViewerNextPaint
} from "./chunk-UIIGQOVD.js";
import "./chunk-V2DBS5C2.js";
import "./chunk-XPXVZBDO.js";
import {
  createFileViewerZoomChangeEmitter,
  registerFileViewerZoomProvider,
  resolveFileViewerFitScale,
  unregisterFileViewerZoomProvider
} from "./chunk-B3J7LI27.js";
import {
  createFileViewerTranslator
} from "./chunk-X3L4DUK6.js";
import "./chunk-PIRHQTI4.js";

// packages/renderers/presentation-ppt/src/limits.ts
var PPT_LIMITS = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  maxStreamBytes: 32 * 1024 * 1024,
  maxRecords: 1e5,
  maxDepth: 32,
  maxSlides: 200,
  maxShapes: 2e4,
  maxAssetBytes: 64 * 1024 * 1024,
  maxTextLength: 2 * 1024 * 1024
});
var PPT_INITIAL_TIMEOUT_MS = 3e4;
var PPT_MAX_SLIDE_DIMENSION = 4096;
var PPT_MAX_SLIDE_PIXELS = 4 * 1024 * 1024;
function assertPptInput(buffer) {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) {
    throw new Error("PowerPoint input is empty or is not an ArrayBuffer.");
  }
  if (buffer.byteLength > PPT_LIMITS.maxFileBytes) {
    throw new Error("PowerPoint file exceeds the 32 MiB preview limit.");
  }
}
function assertPptSlideBounds(model) {
  if (!Array.isArray(model.slides) || model.slides.length > PPT_LIMITS.maxSlides) {
    throw new Error("PowerPoint presentation exceeds the slide limit.");
  }
  for (const slide of model.slides) {
    const width = slide?.size?.width;
    const height = slide?.size?.height;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || width > PPT_MAX_SLIDE_DIMENSION || height > PPT_MAX_SLIDE_DIMENSION || width * height > PPT_MAX_SLIDE_PIXELS) {
      throw new Error("PowerPoint slide exceeds the preview canvas limits.");
    }
  }
}
function boundPptRuntime(runtime) {
  const open = runtime.open.bind(runtime);
  runtime.open = async (input) => {
    const document2 = await open(input);
    try {
      assertPptSlideBounds(document2.model);
      return document2;
    } catch (error) {
      await document2.close();
      throw error;
    }
  };
  return runtime;
}

// packages/renderers/presentation-ppt/src/index.ts
var MIN_ZOOM = 0.25;
var MAX_ZOOM = 3;
var ZOOM_STEP = 0.15;
var MAX_NATIVE_SCALE = 1.5;
var MIN_NATIVE_SCALE = 0.75;
var RERENDER_DELAY_MS = 160;
var pptStyle = `
.ppt-binary-shell{position:relative;box-sizing:border-box;min-height:100%;padding:24px 20px;background:var(--file-viewer-render-surface-background,#eef3f8);color:#1f2d3b;font-family:Aptos,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif}
.ppt-binary-loading{position:sticky;top:12px;z-index:3;box-sizing:border-box;display:flex;width:max-content;max-width:calc(100% - 24px);align-items:center;gap:10px;margin:0 auto 18px;padding:10px 14px;border:1px solid rgba(42,94,144,.14);border-radius:999px;background:rgba(255,255,255,.92);color:#41556b;box-shadow:0 12px 32px rgba(24,44,64,.12);backdrop-filter:blur(18px)}
.ppt-binary-loading[hidden],.ppt-binary-error[hidden]{display:none!important}
.ppt-binary-loading-dot{width:9px;height:9px;flex:0 0 auto;border-radius:999px;background:#1f9d67;box-shadow:0 0 0 6px rgba(31,157,103,.13)}
.ppt-binary-error{box-sizing:border-box;width:min(680px,calc(100% - 32px));margin:48px auto;padding:24px;border:1px solid rgba(28,43,58,.12);border-radius:16px;background:#fff;color:#1f2d3b;box-shadow:0 16px 42px rgba(25,42,54,.08)}
.ppt-binary-error strong{display:block;margin-bottom:10px;font-size:18px}.ppt-binary-error p{margin:0;color:#607282;line-height:1.7}.ppt-binary-error small{display:block;margin-top:12px;color:#7a8b99;line-height:1.6}
.ppt-binary-slides{display:grid;box-sizing:border-box;width:max-content;min-width:100%;justify-items:center;gap:22px;margin:0 auto}
.ppt-binary-page{position:relative;box-sizing:border-box;overflow:hidden;background:#fff;box-shadow:0 10px 34px rgba(15,23,42,.14);transform-origin:top center;transition:width .18s ease}
.ppt-binary-page canvas{display:block;max-width:none;height:auto;background:#fff}
.ppt-binary-page-error{position:absolute;inset:0;display:grid;place-items:center;padding:24px;background:#fff;color:#8b3a3a;text-align:center}
[data-viewer-theme='dark'] .ppt-binary-shell{background:var(--file-viewer-render-surface-background,#101820);color:#e5eef8}
[data-viewer-theme='dark'] .ppt-binary-loading{border-color:rgba(148,163,184,.18);background:rgba(15,23,42,.9);color:#cbd5e1;box-shadow:0 18px 44px rgba(0,0,0,.26)}
[data-viewer-theme='dark'] .ppt-binary-error{border-color:rgba(148,163,184,.18);background:#151f2b;color:#f8fafc;box-shadow:0 22px 56px rgba(0,0,0,.32)}
[data-viewer-theme='dark'] .ppt-binary-error p,[data-viewer-theme='dark'] .ppt-binary-error small{color:#94a3b8}
[data-viewer-theme='dark'] .ppt-binary-page{color-scheme:only light;forced-color-adjust:none;box-shadow:0 16px 44px rgba(0,0,0,.34)}
@media (prefers-color-scheme:dark){[data-viewer-theme='system'] .ppt-binary-shell{background:var(--file-viewer-render-surface-background,#101820);color:#e5eef8}[data-viewer-theme='system'] .ppt-binary-loading{border-color:rgba(148,163,184,.18);background:rgba(15,23,42,.9);color:#cbd5e1}[data-viewer-theme='system'] .ppt-binary-error{border-color:rgba(148,163,184,.18);background:#151f2b;color:#f8fafc}[data-viewer-theme='system'] .ppt-binary-error p,[data-viewer-theme='system'] .ppt-binary-error small{color:#94a3b8}}
@media (max-width:640px){.ppt-binary-shell{padding:14px 10px}.ppt-binary-slides{gap:14px}.ppt-binary-loading{top:8px;margin-bottom:12px;padding:8px 12px;font-size:13px}}
@media (prefers-reduced-motion:reduce){.ppt-binary-page{transition:none}}
`;
var pptPrintStyle = `
  .ppt-binary-shell { background: #fff !important; padding: 0 !important; }
  .ppt-binary-loading, .ppt-binary-error { display: none !important; }
  .ppt-binary-slides { display: block !important; width: 100% !important; min-width: 0 !important; }
  .ppt-binary-page { width: 100% !important; margin: 0 auto !important; box-shadow: none !important; break-after: page; page-break-after: always; }
  .ppt-binary-page:last-child { break-after: auto; page-break-after: auto; }
  .ppt-binary-page canvas, .ppt-binary-page img { display: block; width: 100% !important; height: auto !important; }
`;
var clampZoom = (value) => Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
var createElement = (documentRef, tagName, className, text) => {
  const element = documentRef.createElement(tagName);
  if (className) element.className = className;
  if (text !== void 0) element.textContent = text;
  return element;
};
var loadPptModule = async (moduleUrl) => {
  const module = moduleUrl ? await import(
    /* webpackIgnore: true */
    /* @vite-ignore */
    moduleUrl
  ) : await import("./dist-NVM75KNJ.js");
  if (!module || typeof module.createPptViewer !== "function") {
    throw new Error("The configured PPT module does not export createPptViewer().");
  }
  return module;
};
var loadPptRuntime = async (moduleUrl, options) => {
  const module = await loadPptModule(moduleUrl);
  return boundPptRuntime(await module.createPptViewer(options));
};
var canvasToBlob = (canvas) => new Promise((resolve) => {
  if (typeof canvas.toBlob === "function") {
    try {
      canvas.toBlob(resolve, "image/png");
      return;
    } catch {
    }
  }
  try {
    const dataUrl = canvas.toDataURL("image/png");
    fetch(dataUrl).then((response) => response.blob()).then(resolve, () => resolve(null));
  } catch {
    resolve(null);
  }
});
var buildExportAdapter = (pages, targetWindow, captureSlideDataUrls) => ({
  print: true,
  exportHtml: true,
  includeDocumentStyles: false,
  beforeSnapshot: () => waitForFileViewerNextPaint(targetWindow || void 0),
  getPrintMaskPages: () => pages,
  printStyle: pptPrintStyle,
  toHtml: async () => {
    const dataUrls = await captureSlideDataUrls();
    const slides = dataUrls.map((dataUrl, index) => {
      return `<section class="ppt-binary-page" data-viewer-print-page-index="${index}"><img src="${dataUrl}" alt="Slide ${index + 1}"></section>`;
    }).join("");
    return `<div class="ppt-binary-shell"><div class="ppt-binary-slides">${slides}</div></div>`;
  }
});
async function renderPpt(buffer, target, _type, context) {
  const t = createFileViewerTranslator(context?.options);
  const documentRef = target.ownerDocument || document;
  const targetWindow = documentRef.defaultView || (typeof window !== "undefined" ? window : null);
  const zoomEmitter = createFileViewerZoomChangeEmitter();
  const style = createElement(documentRef, "style");
  style.textContent = pptStyle;
  const shell = createElement(documentRef, "div", "ppt-binary-shell");
  shell.dataset.viewerZoomProvider = "ppt";
  const loading = createElement(documentRef, "div", "ppt-binary-loading");
  loading.setAttribute("role", "status");
  loading.setAttribute("aria-live", "polite");
  const loadingLabel = createElement(documentRef, "span", void 0, t("presentation.ppt.state.loading"));
  loading.append(createElement(documentRef, "span", "ppt-binary-loading-dot"), loadingLabel);
  const error = createElement(documentRef, "div", "ppt-binary-error");
  error.hidden = true;
  const errorTitle = createElement(documentRef, "strong", void 0, t("presentation.ppt.error.title"));
  const errorMessage = createElement(documentRef, "p");
  const errorHint = createElement(documentRef, "small", void 0, t("presentation.ppt.error.assetHint"));
  error.append(errorTitle, errorMessage, errorHint);
  const slides = createElement(documentRef, "div", "ppt-binary-slides");
  shell.append(loading, error, slides);
  target.replaceChildren(style, shell);
  let pptRuntime = null;
  let pptDocument = null;
  let mountedViewer = null;
  let resourceClosePromise = null;
  let pages = [];
  const canvases = [];
  let canvasStateObserver = null;
  let snapshotRuntimeOptions = null;
  let snapshotModuleUrl;
  let currentScale = 1;
  let disposed = false;
  let ready = false;
  let renderGeneration = 0;
  let rerenderTimer = null;
  let statsRefreshTimer = null;
  let statsRefreshGeneration = 0;
  const throwIfAborted = () => {
    if (disposed || context?.signal?.aborted) {
      throw context?.signal?.reason || new DOMException("PPT rendering aborted.", "AbortError");
    }
  };
  const clearRerenderTimer = () => {
    if (rerenderTimer !== null) {
      if (targetWindow) targetWindow.clearTimeout(rerenderTimer);
      else clearTimeout(rerenderTimer);
      rerenderTimer = null;
    }
  };
  const clearStatsRefreshTimer = () => {
    if (statsRefreshTimer !== null) {
      if (targetWindow) targetWindow.clearTimeout(statsRefreshTimer);
      else clearTimeout(statsRefreshTimer);
      statsRefreshTimer = null;
    }
  };
  const refreshRuntimeStats = async () => {
    const mounted = mountedViewer;
    if (!mounted || disposed) return;
    const generation = ++statsRefreshGeneration;
    try {
      const stats = await mounted.cacheStats();
      if (generation !== statsRefreshGeneration || mounted !== mountedViewer || disposed) return;
      const publishNumber = (key, value) => {
        if (Number.isFinite(value)) shell.dataset[key] = String(value);
      };
      shell.dataset.pptCacheEnabled = String(stats.enabled);
      shell.dataset.pptCacheAvailable = String(stats.available);
      publishNumber("pptCacheEntries", stats.entries);
      publishNumber("pptCacheBytes", stats.bytes);
      publishNumber("pptAttachedCanvases", stats.attachedCanvases);
      publishNumber("pptActiveCanvases", stats.activeCanvases);
      publishNumber("pptWasmMemoryBytes", stats.wasmMemoryBytes);
    } catch {
    }
  };
  const scheduleRuntimeStatsRefresh = () => {
    clearStatsRefreshTimer();
    const run = () => {
      statsRefreshTimer = null;
      void refreshRuntimeStats();
    };
    statsRefreshTimer = targetWindow ? targetWindow.setTimeout(run, 200) : setTimeout(run, 200);
  };
  const closeResources = () => {
    if (resourceClosePromise) return resourceClosePromise;
    const mountedToClose = mountedViewer;
    const documentToClose = pptDocument;
    const runtimeToClose = pptRuntime;
    mountedViewer = null;
    pptDocument = null;
    pptRuntime = null;
    canvasStateObserver?.disconnect();
    canvasStateObserver = null;
    clearStatsRefreshTimer();
    if (!mountedToClose && !documentToClose && !runtimeToClose) return Promise.resolve();
    resourceClosePromise = (async () => {
      try {
        if (mountedToClose) {
          await mountedToClose.close();
        } else if (documentToClose && !documentToClose.closed) {
          await documentToClose.close();
        }
      } finally {
        await runtimeToClose?.close();
      }
    })();
    return resourceClosePromise;
  };
  const disposeResources = () => {
    void closeResources().catch((closeError) => {
      console.warn("PPT runtime cleanup warning:", closeError);
    });
  };
  const abort = () => {
    renderGeneration += 1;
    clearRerenderTimer();
    clearStatsRefreshTimer();
    void pptRuntime?.close().catch(() => {
    });
  };
  context?.signal?.addEventListener("abort", abort, { once: true });
  const getZoomState = () => ({
    scale: currentScale,
    label: `${Math.round(currentScale * 100)}%`,
    canZoomIn: currentScale < MAX_ZOOM,
    canZoomOut: currentScale > MIN_ZOOM,
    canReset: Math.abs(currentScale - 1) > 1e-3,
    minScale: MIN_ZOOM,
    maxScale: MAX_ZOOM
  });
  const applyCssZoom = () => {
    if (!pptDocument) return;
    const width = Math.max(1, Math.round(pptDocument.width * currentScale));
    const height = Math.max(1, Math.round(pptDocument.height * currentScale));
    pages.forEach((page, index) => {
      page.style.width = `${width}px`;
      page.style.height = `${height}px`;
      page.style.maxWidth = "none";
      const canvas = canvases[index];
      if (canvas) {
        canvas.style.width = `${width}px`;
        canvas.style.height = `${height}px`;
        canvas.style.maxWidth = "none";
      }
    });
  };
  const renderActiveSlides = async (generation) => {
    const document2 = pptDocument;
    const mounted = mountedViewer;
    if (!document2 || !mounted) return;
    const pixelRatio = Math.min(2, Math.max(1, targetWindow?.devicePixelRatio || 1));
    const nativeScale = Math.min(
      MAX_NATIVE_SCALE,
      Math.max(MIN_NATIVE_SCALE, currentScale * pixelRatio)
    );
    const activeIndices = canvases.map((canvas, index) => ({ index, state: canvas.dataset.renderState })).filter((item) => item.state === "rendering" || item.state === "rendered").map((item) => item.index);
    for (const index of activeIndices) {
      throwIfAborted();
      if (generation !== renderGeneration) return;
      const canvas = canvases[index];
      const page = pages[index];
      try {
        if (canvas.dataset.renderState === "rendering") {
          await mounted.renderSlide(index);
          if (disposed || context?.signal?.aborted || generation !== renderGeneration) return;
        }
        if (canvas.dataset.renderState !== "rendered") continue;
        const result = await document2.renderSlide(index, canvas, {
          scale: nativeScale,
          pixelRatio: 1
        });
        if (disposed || context?.signal?.aborted || generation !== renderGeneration) return;
        if (result.cancelled) continue;
        if (!page.isConnected) return;
        page.querySelector(".ppt-binary-page-error")?.remove();
      } catch (slideError) {
        if (disposed || context?.signal?.aborted || generation !== renderGeneration || !page.isConnected) {
          return;
        }
        const message = createElement(
          documentRef,
          "div",
          "ppt-binary-page-error",
          `${t("presentation.ppt.error.parseFailed")} (${index + 1})`
        );
        page.append(message);
        console.warn(`PPT slide ${index + 1} render warning:`, slideError);
      }
      applyCssZoom();
      if (index + 1 < canvases.length) {
        await waitForFileViewerNextPaint(targetWindow || void 0);
      }
    }
  };
  const scheduleQualityRender = () => {
    clearRerenderTimer();
    const generation = renderGeneration;
    const run = () => {
      rerenderTimer = null;
      void renderActiveSlides(generation).catch((renderError) => {
        if (!disposed && !context?.signal?.aborted) {
          console.warn("PPT quality rerender warning:", renderError);
        }
      });
    };
    rerenderTimer = targetWindow ? targetWindow.setTimeout(run, RERENDER_DELAY_MS) : setTimeout(run, RERENDER_DELAY_MS);
  };
  const setZoom = (scale) => {
    currentScale = clampZoom(scale);
    renderGeneration += 1;
    applyCssZoom();
    zoomEmitter.emit();
    scheduleQualityRender();
    return getZoomState();
  };
  const fit = (request) => {
    if (!pptDocument) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "ppt-not-ready",
        provider: "zoom"
      };
    }
    const scale = resolveFileViewerFitScale({
      mode: request.mode,
      viewportWidth: Math.max(1, (request.viewportWidth || shell.clientWidth || 0) - request.padding * 2),
      viewportHeight: Math.max(1, (request.viewportHeight || shell.clientHeight || 0) - request.padding * 2),
      contentWidth: pptDocument.width,
      contentHeight: pptDocument.height,
      currentScale,
      minScale: request.minScale ?? MIN_ZOOM,
      maxScale: request.maxScale ?? MAX_ZOOM
    });
    if (!scale) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "unmeasurable",
        provider: "zoom"
      };
    }
    const state = setZoom(scale);
    return {
      applied: true,
      mode: request.mode,
      resize: request.resize,
      scale: state.scale,
      source: request.source,
      provider: "zoom"
    };
  };
  const captureDirectSlides = async (slideIndices, encode) => {
    const runtimeOptions = snapshotRuntimeOptions;
    if (!runtimeOptions) throw new Error(t("presentation.ppt.error.parseFailed"));
    const runtime = await loadPptRuntime(snapshotModuleUrl, {
      ...runtimeOptions,
      worker: false,
      cache: false
    });
    let document2 = null;
    try {
      document2 = await runtime.open(buffer.slice(0));
      const output = [];
      for (let position = 0; position < slideIndices.length; position += 1) {
        const slideIndex = slideIndices[position];
        throwIfAborted();
        const canvas = createElement(documentRef, "canvas");
        try {
          await document2.renderSlide(slideIndex, canvas, {
            scale: MAX_NATIVE_SCALE,
            pixelRatio: 1
          });
          throwIfAborted();
          output.push(await encode(canvas));
        } finally {
          canvas.width = 1;
          canvas.height = 1;
        }
        if (position + 1 < slideIndices.length && (position + 1) % 4 === 0) {
          await waitForFileViewerNextPaint(targetWindow || void 0);
        }
      }
      return output;
    } finally {
      if (document2 && !document2.closed) await document2.close().catch(() => {
      });
      await runtime.close().catch(() => {
      });
    }
  };
  try {
    throwIfAborted();
    const presentationOptions = context?.options?.presentation;
    const runtimeBaseUrl = resolveFileViewerRuntimeAssetBaseUrl(documentRef);
    const moduleUrl = presentationOptions?.pptModuleUrl ? resolveFileViewerAssetUrl(
      presentationOptions.pptModuleUrl,
      String(presentationOptions.pptModuleUrl),
      { documentBaseUrl: runtimeBaseUrl }
    ) : void 0;
    const resolvePptAssetUrl = (value) => value ? resolveFileViewerAssetUrl(value, String(value), { documentBaseUrl: runtimeBaseUrl }) : void 0;
    const runtimeOptions = {
      worker: true,
      parseOptions: { limits: { ...PPT_LIMITS } },
      cache: presentationOptions?.pptCache,
      wasmUrl: resolvePptAssetUrl(presentationOptions?.pptWasmUrl),
      fontUrl: resolvePptAssetUrl(presentationOptions?.pptFontUrl),
      workerUrl: resolvePptAssetUrl(presentationOptions?.pptWorkerUrl)
    };
    snapshotModuleUrl = moduleUrl;
    snapshotRuntimeOptions = runtimeOptions;
    const runtime = await loadPptRuntime(moduleUrl, runtimeOptions);
    pptRuntime = runtime;
    shell.dataset.pptRuntimeMode = runtime.mode;
    throwIfAborted();
    slides.className = "ppt-binary-mount";
    const mounted = await runtime.mount(slides, buffer, {
      replace: true,
      className: "ppt-binary-slides",
      scale: 1,
      pixelRatio: 1,
      virtualize: presentationOptions?.pptVirtualize !== false,
      rootMargin: presentationOptions?.pptVirtualRootMargin,
      releaseDelayMs: presentationOptions?.pptReleaseDelayMs
    });
    mountedViewer = mounted;
    pptDocument = mounted.document;
    shell.dataset.pptVirtualized = String(mounted.virtualized);
    throwIfAborted();
    Object.assign(mounted.root.style, {
      width: "max-content",
      minWidth: "100%",
      maxWidth: "none",
      padding: "0px",
      background: "transparent",
      justifyContent: "",
      gap: ""
    });
    pages = Array.from(mounted.root.children).map((element, index) => {
      const page = element;
      page.classList.add("ppt-binary-page");
      page.dataset.slideIndex = String(index);
      page.dataset.viewerPrintPageIndex = String(index);
      page.style.maxWidth = "none";
      return page;
    });
    canvases.push(...mounted.canvases);
    canvases.forEach((canvas, index) => {
      canvas.setAttribute("role", "img");
      canvas.setAttribute("aria-label", `Slide ${index + 1}`);
      canvas.style.maxWidth = "none";
    });
    const shellStyle = targetWindow?.getComputedStyle?.(shell);
    const horizontalPadding = (Number.parseFloat(shellStyle?.paddingLeft || "") || 0) + (Number.parseFloat(shellStyle?.paddingRight || "") || 0);
    const availableWidth = Math.max(
      0,
      (shell.clientWidth || target.clientWidth || 0) - horizontalPadding
    );
    currentScale = availableWidth > 0 ? clampZoom(Math.min(1, availableWidth / pptDocument.width)) : 1;
    applyCssZoom();
    registerFileViewerZoomProvider(shell, {
      zoomIn: () => setZoom(currentScale + ZOOM_STEP),
      zoomOut: () => setZoom(currentScale - ZOOM_STEP),
      resetZoom: () => setZoom(1),
      setZoom,
      fit,
      getState: getZoomState,
      subscribe: zoomEmitter.subscribe
    });
    const MutationObserverCtor = targetWindow?.MutationObserver;
    if (MutationObserverCtor) {
      canvasStateObserver = new MutationObserverCtor((records) => {
        if (records.some((record) => record.target.dataset?.renderState === "rendered")) {
          scheduleQualityRender();
        }
        scheduleRuntimeStatsRefresh();
      });
      canvases.forEach((canvas) => {
        canvasStateObserver?.observe(canvas, {
          attributes: true,
          attributeFilter: ["data-render-state"]
        });
      });
    }
    ready = true;
    loading.hidden = true;
    void refreshRuntimeStats();
    context?.onProgressiveRender?.();
    context?.registerExportAdapter?.(buildExportAdapter(
      pages,
      targetWindow,
      () => captureDirectSlides(
        canvases.map((_, index) => index),
        (canvas) => canvas.toDataURL("image/png")
      )
    ));
    context?.registerThumbnailAdapter?.({
      captureSource: "rendered",
      beforeCapture: () => {
        if (!ready) throw new Error(t("presentation.ppt.error.parseFailed"));
      },
      capture: async () => (await captureDirectSlides([0], canvasToBlob))[0] || null,
      getTarget: () => pages[0] || null
    });
    zoomEmitter.emit();
  } catch (renderError) {
    if (disposed || context?.signal?.aborted) {
      clearRerenderTimer();
      context?.registerExportAdapter?.(null);
      context?.registerThumbnailAdapter?.(null);
      unregisterFileViewerZoomProvider(shell);
      await closeResources().catch(() => {
      });
      throw renderError;
    }
    loading.hidden = true;
    error.hidden = false;
    errorMessage.textContent = normalizeFileViewerErrorMessage(renderError, context?.options) || t("presentation.ppt.error.parseFailed");
    context?.registerExportAdapter?.(null);
    context?.registerThumbnailAdapter?.(null);
    unregisterFileViewerZoomProvider(shell);
    await closeResources().catch(() => {
    });
    throw renderError;
  } finally {
    context?.signal?.removeEventListener("abort", abort);
  }
  return {
    $el: shell,
    unmount() {
      disposed = true;
      renderGeneration += 1;
      clearRerenderTimer();
      clearStatsRefreshTimer();
      context?.registerExportAdapter?.(null);
      context?.registerThumbnailAdapter?.(null);
      unregisterFileViewerZoomProvider(shell);
      disposeResources();
      target.replaceChildren();
    }
  };
}
var binaryPresentationDefinition = DEFAULT_RENDERER_DEFINITIONS.find(
  (definition) => definition.id === "office-presentation-binary"
);
if (!binaryPresentationDefinition) {
  throw new Error("@file-viewer/renderer-ppt could not locate the core PPT renderer definition.");
}
var binaryPresentationRendererDefinition = binaryPresentationDefinition;
var renderFileViewerBinaryPresentation = renderPpt;
var pptRenderer = {
  id: "file-viewer-renderer-presentation-ppt",
  label: "Flyfish File Viewer PPT renderer",
  definitions: [binaryPresentationRendererDefinition],
  handlers: [
    {
      rendererId: binaryPresentationRendererDefinition.id,
      handler: renderFileViewerBinaryPresentation
    }
  ]
};

// packages/renderers/presentation-ppt/src/entry.ts
async function renderPpt2(buffer, target, context) {
  assertPptInput(buffer);
  if (context?.signal?.aborted) throw new DOMException("PowerPoint rendering was aborted.", "AbortError");
  if (typeof Worker === "undefined") throw new Error("PowerPoint preview requires a parsing worker.");
  if (!target?.ownerDocument?.defaultView?.IntersectionObserver) {
    throw new Error("PowerPoint preview requires virtual slide rendering.");
  }
  const controller = new AbortController();
  const abort = () => controller.abort(context?.signal?.reason || new DOMException("PowerPoint rendering was aborted.", "AbortError"));
  context?.signal?.addEventListener("abort", abort, { once: true });
  const timeout = setTimeout(() => controller.abort(new Error("PowerPoint preview exceeded the 30-second rendering limit.")), PPT_INITIAL_TIMEOUT_MS);
  try {
    const instance = await renderPpt(buffer, target, "ppt", {
      ...context,
      signal: controller.signal,
      options: {
        ...context?.options,
        presentation: {
          ...context?.options?.presentation,
          pptModuleUrl: void 0,
          pptWorkerUrl: new URL("./pptjs.worker.js", import.meta.url).href,
          pptWorker: true,
          pptWasmUrl: void 0,
          pptFontUrl: void 0,
          pptCache: false,
          pptVirtualize: true,
          pptVirtualRootMargin: "100px 0px",
          pptReleaseDelayMs: 0
        }
      }
    });
    if (controller.signal.aborted) {
      instance.unmount();
      throw controller.signal.reason;
    }
    const unmount = instance.unmount.bind(instance);
    let closed = false;
    const close = () => {
      if (closed) return;
      closed = true;
      context?.signal?.removeEventListener("abort", close);
      unmount();
    };
    context?.signal?.addEventListener("abort", close, { once: true });
    return { ...instance, unmount: close };
  } catch (error) {
    if (controller.signal.aborted) throw controller.signal.reason;
    throw error;
  } finally {
    clearTimeout(timeout);
    context?.signal?.removeEventListener("abort", abort);
  }
}
var entry_default = renderPpt2;
export {
  entry_default as default,
  renderPpt2 as renderPpt
};
