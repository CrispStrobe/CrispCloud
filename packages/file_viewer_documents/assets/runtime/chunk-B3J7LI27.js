// packages/core/src/features/document/dom/providers.ts
var searchProviderRegistry = /* @__PURE__ */ new WeakMap();
var zoomProviderRegistry = /* @__PURE__ */ new WeakMap();
var viewStateProviderRegistry = /* @__PURE__ */ new WeakMap();
var isProviderElement = (root) => {
  return !!root && root.nodeType === 1;
};
var queryProviderHosts = (root, selector) => {
  if (!root?.querySelectorAll) {
    return [];
  }
  const hosts = Array.from(root.querySelectorAll(selector));
  if (isProviderElement(root) && root.shadowRoot) {
    hosts.push(...queryProviderHosts(root.shadowRoot, selector));
  }
  const elements = Array.from(root.querySelectorAll("*"));
  for (const element of elements) {
    if (element.shadowRoot) {
      hosts.push(...queryProviderHosts(element.shadowRoot, selector));
    }
  }
  return hosts;
};
var registerFileViewerSearchProvider = (host, provider) => {
  searchProviderRegistry.set(host, provider);
  host.__flyfishViewerSearchProvider = provider;
};
var unregisterFileViewerSearchProvider = (host) => {
  if (!host) {
    return;
  }
  searchProviderRegistry.delete(host);
  delete host.__flyfishViewerSearchProvider;
};
var registerFileViewerZoomProvider = (host, provider) => {
  zoomProviderRegistry.set(host, provider);
  host.dataset.viewerZoomProvider = host.dataset.viewerZoomProvider || "custom";
  host.__flyfishViewerZoomProvider = provider;
};
var unregisterFileViewerZoomProvider = (host) => {
  if (!host) {
    return;
  }
  zoomProviderRegistry.delete(host);
  delete host.dataset.viewerZoomProvider;
  delete host.__flyfishViewerZoomProvider;
};
var findFileViewerZoomProvider = (root) => {
  if (!root) {
    return null;
  }
  const direct = isProviderElement(root) ? zoomProviderRegistry.get(root) || root.__flyfishViewerZoomProvider : null;
  if (direct) {
    return direct;
  }
  const host = queryProviderHosts(root, "[data-viewer-zoom-provider]")[0];
  return host ? zoomProviderRegistry.get(host) || host.__flyfishViewerZoomProvider || null : null;
};
var registerFileViewerViewStateProvider = (host, provider) => {
  viewStateProviderRegistry.set(host, provider);
  host.dataset.viewerViewStateProvider = host.dataset.viewerViewStateProvider || "custom";
  host.__flyfishViewerViewStateProvider = provider;
};
var unregisterFileViewerViewStateProvider = (host) => {
  if (!host) {
    return;
  }
  viewStateProviderRegistry.delete(host);
  delete host.dataset.viewerViewStateProvider;
  delete host.__flyfishViewerViewStateProvider;
};
var findFileViewerViewStateProvider = (root) => {
  if (!root) {
    return null;
  }
  const direct = isProviderElement(root) ? viewStateProviderRegistry.get(root) || root.__flyfishViewerViewStateProvider : null;
  if (direct && (!isProviderElement(root) || root.dataset.viewerViewStateProvider !== "generic")) {
    return direct;
  }
  const hosts = queryProviderHosts(root, "[data-viewer-view-state-provider]");
  const customHost = hosts.find((host2) => host2.dataset.viewerViewStateProvider !== "generic");
  const genericHost = hosts.find((host2) => host2.dataset.viewerViewStateProvider === "generic");
  const host = customHost || genericHost;
  if (host) {
    return viewStateProviderRegistry.get(host) || host.__flyfishViewerViewStateProvider || null;
  }
  return direct || null;
};

// packages/core/src/features/document/dom/anchors.ts
var DEFAULT_FILE_VIEWER_ANCHOR_SELECTOR = [
  "[data-viewer-anchor-id]",
  ".pdfViewer .page",
  ".docx-wrapper section",
  ".docx p",
  ".docx li",
  ".docx table",
  ".markdown-body h1",
  ".markdown-body h2",
  ".markdown-body h3",
  ".markdown-body h4",
  ".markdown-body h5",
  ".markdown-body h6",
  ".markdown-body p",
  ".markdown-body li",
  ".markdown-body pre",
  ".markdown-body table",
  "article h1",
  "article h2",
  "article h3",
  "article h4",
  "article h5",
  "article h6",
  "article p",
  "article li",
  "article pre",
  "article table",
  "pre code",
  "p",
  "li",
  "tr",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "pre",
  "table"
].join(",");
var DEFAULT_FILE_VIEWER_ANCHOR_EXCLUDE_SELECTOR = [
  ".viewer-actions",
  ".viewer-watermark",
  ".state-panel",
  ".pdf-toolbar",
  ".pdf-nav-pane",
  ".flyfish-search-match"
].join(",");

// packages/core/src/features/document/dom/scroll.ts
var DEFAULT_FILE_VIEWER_SCROLL_CONTAINER_SELECTOR = "[data-viewer-scroll-container], .pdf-wrapper";
var DEFAULT_FILE_VIEWER_SCROLL_CONTAINER_CANDIDATE_SELECTOR = "div, section, article, pre";
var DEFAULT_FILE_VIEWER_SCROLLABLE_OVERFLOW_VALUES = ["auto", "scroll", "overlay"];
var getFileViewerScrollableRange = (element) => {
  return Math.max(0, element.scrollHeight - element.clientHeight);
};
var isFileViewerScrollableElement = (element, options = {}) => {
  const minScrollRange = options.minScrollRange ?? 2;
  if (getFileViewerScrollableRange(element) <= minScrollRange) {
    return false;
  }
  const ownerView = element.ownerDocument?.defaultView;
  const view = ownerView?.getComputedStyle ? ownerView : typeof window !== "undefined" ? window : void 0;
  if (!view?.getComputedStyle) {
    return false;
  }
  const style = view.getComputedStyle(element);
  const overflowY = style.overflowY || style.overflow;
  const overflowValues = options.overflowValues || DEFAULT_FILE_VIEWER_SCROLLABLE_OVERFLOW_VALUES;
  return overflowValues.includes(overflowY);
};
var resolveFileViewerScrollContainer = (root, options = {}) => {
  if (!root) {
    return null;
  }
  const preferredSelector = options.preferredSelector || DEFAULT_FILE_VIEWER_SCROLL_CONTAINER_SELECTOR;
  const candidateSelector = options.candidateSelector || DEFAULT_FILE_VIEWER_SCROLL_CONTAINER_CANDIDATE_SELECTOR;
  const preferred = root.querySelector(preferredSelector);
  if (preferred && isFileViewerScrollableElement(preferred, options)) {
    return preferred;
  }
  if (isFileViewerScrollableElement(root, options)) {
    return root;
  }
  const scrollableChildren = Array.from(root.querySelectorAll(candidateSelector)).filter((element) => isFileViewerScrollableElement(element, options)).sort((a, b) => getFileViewerScrollableRange(b) - getFileViewerScrollableRange(a));
  return scrollableChildren[0] || preferred || root;
};

// packages/core/src/features/document/model.ts
var createEmptyFileViewerSearchState = (query = "") => ({
  query,
  total: 0,
  currentIndex: -1,
  current: null,
  matches: []
});

// packages/core/src/features/document/zoom.ts
var createFileViewerZoomChangeEmitter = () => {
  const listeners = /* @__PURE__ */ new Set();
  return {
    emit() {
      listeners.forEach((listener) => listener());
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    clear() {
      listeners.clear();
    }
  };
};

// packages/core/src/features/document/fit.ts
var clampScale = (scale, minScale, maxScale) => {
  let nextScale = scale;
  if (Number.isFinite(minScale)) {
    nextScale = Math.max(Number(minScale), nextScale);
  }
  if (Number.isFinite(maxScale)) {
    nextScale = Math.min(Number(maxScale), nextScale);
  }
  return nextScale;
};
var resolveFileViewerFitScale = ({
  mode,
  viewportWidth,
  viewportHeight,
  contentWidth,
  contentHeight,
  minScale,
  maxScale
}) => {
  if (viewportWidth <= 0 || viewportHeight <= 0 || contentWidth <= 0 || contentHeight <= 0) {
    return void 0;
  }
  const widthScale = viewportWidth / contentWidth;
  const heightScale = viewportHeight / contentHeight;
  const containScale = Math.min(widthScale, heightScale);
  const coverScale = Math.max(widthScale, heightScale);
  const nextScale = (() => {
    switch (mode) {
      case "cover":
        return coverScale;
      case "width":
        return widthScale;
      case "height":
        return heightScale;
      case "actual":
        return 1;
      case "scale-down":
        return Math.min(1, containScale);
      case "auto":
      case "contain":
      default:
        return containScale;
    }
  })();
  if (!Number.isFinite(nextScale) || nextScale <= 0) {
    return void 0;
  }
  return clampScale(nextScale, minScale, maxScale);
};

// packages/core/src/features/document/imageHandTool.ts
function installFileViewerImageHandTool(container, signal) {
  const view = container.ownerDocument.defaultView;
  if (!view || signal?.aborted) return () => {
  };
  const cursor = container.style.getPropertyValue("cursor");
  const cursorPriority = container.style.getPropertyPriority("cursor");
  const selection = container.style.getPropertyValue("user-select");
  const selectionPriority = container.style.getPropertyPriority("user-select");
  const previousMode = container.getAttribute("data-viewer-image-hand-tool");
  const previousPanning = container.getAttribute("data-viewer-image-panning");
  const style = container.ownerDocument.createElement("style");
  style.textContent = '[data-viewer-image-hand-tool="true"] img{cursor:grab!important}[data-viewer-image-panning="true"] img{cursor:grabbing!important}';
  container.append(style);
  const interactive = 'a,button,input,textarea,select,option,[contenteditable]:not([contenteditable="false"]),[role="button"]:not(img),[role="link"],[role="textbox"]';
  let drag = null;
  let disposed = false;
  let suppressClick = false;
  let clickTimer = 0;
  const canPan = () => container.scrollWidth > container.clientWidth || container.scrollHeight > container.clientHeight;
  const syncCursor = () => {
    if (disposed || drag?.moved) return;
    const enabled = canPan();
    container.setAttribute("data-viewer-image-hand-tool", String(enabled));
    container.style.setProperty("cursor", enabled ? "grab" : cursor, enabled ? "" : cursorPriority);
  };
  const finish = () => {
    const state = drag;
    if (!state) return;
    drag = null;
    container.style.setProperty("user-select", selection, selectionPriority);
    container.removeAttribute("data-viewer-image-panning");
    view.removeEventListener("pointermove", move, true);
    view.removeEventListener("pointerup", up, true);
    view.removeEventListener("pointercancel", up, true);
    view.removeEventListener("blur", finish);
    if (container.hasPointerCapture?.(state.id)) container.releasePointerCapture(state.id);
    suppressClick = state.moved;
    view.clearTimeout(clickTimer);
    clickTimer = view.setTimeout(() => {
      suppressClick = false;
    }, 250);
    syncCursor();
  };
  const move = (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    if (!(event.buttons & 1)) {
      finish();
      return;
    }
    const dx = (event.clientX - drag.x) / drag.ratioX;
    const dy = (event.clientY - drag.y) / drag.ratioY;
    if (!drag.moved && Math.hypot(dx, dy) < 3) return;
    if (!drag.moved) {
      drag.moved = true;
      container.setAttribute("data-viewer-image-panning", "true");
      container.style.cursor = "grabbing";
      container.style.setProperty("user-select", "none");
      try {
        container.setPointerCapture?.(event.pointerId);
      } catch {
      }
    }
    container.scrollLeft = drag.left - dx;
    container.scrollTop = drag.top - dy;
    event.preventDefault();
  };
  const up = (event) => {
    if (event.pointerId === drag?.id) finish();
  };
  const down = (event) => {
    if (disposed || event.defaultPrevented || event.pointerType !== "mouse" || event.button !== 0 || event.isPrimary === false || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
    if (event.composedPath().some((node) => node !== container && node.matches?.(interactive))) return;
    finish();
    suppressClick = false;
    syncCursor();
    if (!canPan()) return;
    const rect = container.getBoundingClientRect();
    const ratioX = container.offsetWidth ? rect.width / container.offsetWidth : 1;
    const ratioY = container.offsetHeight ? rect.height / container.offsetHeight : 1;
    if (![ratioX, ratioY].every((value) => Number.isFinite(value) && value > 0)) return;
    const x = (event.clientX - rect.left) / ratioX - container.clientLeft;
    const y = (event.clientY - rect.top) / ratioY - container.clientTop;
    if (x < 0 || y < 0 || x >= container.clientWidth || y >= container.clientHeight) return;
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, left: container.scrollLeft, top: container.scrollTop, ratioX, ratioY, moved: false };
    view.addEventListener("pointermove", move, { capture: true, passive: false });
    view.addEventListener("pointerup", up, true);
    view.addEventListener("pointercancel", up, true);
    view.addEventListener("blur", finish);
  };
  const click = (event) => {
    if (suppressClick && event.detail > 0) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  };
  const nativeDrag = (event) => {
    if (drag) event.preventDefault();
  };
  const restoreAttribute = (name, value) => value === null ? container.removeAttribute(name) : container.setAttribute(name, value);
  const dispose = () => {
    if (disposed) return;
    finish();
    disposed = true;
    view.clearTimeout(clickTimer);
    suppressClick = false;
    container.style.setProperty("cursor", cursor, cursorPriority);
    container.style.setProperty("user-select", selection, selectionPriority);
    restoreAttribute("data-viewer-image-hand-tool", previousMode);
    restoreAttribute("data-viewer-image-panning", previousPanning);
    container.removeEventListener("pointerdown", down);
    container.removeEventListener("pointermove", syncCursor);
    container.removeEventListener("pointerover", syncCursor);
    container.removeEventListener("lostpointercapture", up);
    container.removeEventListener("click", click, true);
    container.removeEventListener("dragstart", nativeDrag);
    signal?.removeEventListener("abort", dispose);
    style.remove();
  };
  container.addEventListener("pointerdown", down);
  container.addEventListener("pointermove", syncCursor);
  container.addEventListener("pointerover", syncCursor);
  container.addEventListener("lostpointercapture", up);
  container.addEventListener("click", click, true);
  container.addEventListener("dragstart", nativeDrag);
  signal?.addEventListener("abort", dispose, { once: true });
  syncCursor();
  return dispose;
}

export {
  createEmptyFileViewerSearchState,
  registerFileViewerSearchProvider,
  unregisterFileViewerSearchProvider,
  registerFileViewerZoomProvider,
  unregisterFileViewerZoomProvider,
  findFileViewerZoomProvider,
  registerFileViewerViewStateProvider,
  unregisterFileViewerViewStateProvider,
  findFileViewerViewStateProvider,
  resolveFileViewerScrollContainer,
  createFileViewerZoomChangeEmitter,
  resolveFileViewerFitScale,
  installFileViewerImageHandTool
};
