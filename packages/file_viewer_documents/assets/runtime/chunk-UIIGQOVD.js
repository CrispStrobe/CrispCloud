// packages/core/src/output/export.ts
var triggerFileViewerBlobDownload = (blob, name) => {
  const objectUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = objectUrl;
  link.download = name;
  link.rel = "noopener";
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(objectUrl), 4e3);
};
var triggerFileViewerUrlDownload = (url, name) => {
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.rel = "noopener";
  link.target = "_blank";
  document.body.appendChild(link);
  link.click();
  link.remove();
};
var CANVAS_PRESENTATION_PROPERTIES = [
  "display",
  "position",
  "top",
  "right",
  "bottom",
  "left",
  "box-sizing",
  "width",
  "height",
  "min-width",
  "min-height",
  "max-width",
  "max-height",
  "margin-top",
  "margin-right",
  "margin-bottom",
  "margin-left",
  "padding-top",
  "padding-right",
  "padding-bottom",
  "padding-left",
  "border-top",
  "border-right",
  "border-bottom",
  "border-left",
  "border-radius",
  "transform",
  "transform-origin",
  "vertical-align",
  "float",
  "clear",
  "opacity",
  "visibility",
  "z-index",
  "align-self",
  "justify-self",
  "flex-grow",
  "flex-shrink",
  "flex-basis",
  "order",
  "grid-area"
];
var replaceFileViewerCanvasWithImages = (source, clone) => {
  const sourceCanvases = Array.from(source.querySelectorAll("canvas"));
  const clonedCanvases = Array.from(clone.querySelectorAll("canvas"));
  clonedCanvases.forEach((canvas, index) => {
    const sourceCanvas = sourceCanvases[index];
    if (!sourceCanvas) return;
    try {
      const image = canvas.ownerDocument.createElement("img");
      image.src = sourceCanvas.toDataURL("image/png");
      image.alt = sourceCanvas.getAttribute("aria-label") || "rendered canvas";
      image.className = canvas.className;
      image.id = canvas.id;
      image.style.cssText = canvas.style.cssText;
      const style = sourceCanvas.ownerDocument.defaultView?.getComputedStyle(sourceCanvas);
      if (style) {
        for (const property of CANVAS_PRESENTATION_PROPERTIES) {
          const value = style.getPropertyValue(property);
          if (value) image.style.setProperty(property, value, canvas.style.getPropertyPriority(property));
        }
      }
      if (!image.style.width || image.style.width === "auto") image.style.width = `${sourceCanvas.width}px`;
      if (!image.style.height || image.style.height === "auto") image.style.height = `${sourceCanvas.height}px`;
      canvas.replaceWith(image);
    } catch {
    }
  });
};
var waitForFileViewerNextPaint = (targetWindow) => {
  return new Promise((resolve) => {
    const currentWindow = targetWindow || globalThis.window;
    const schedule = currentWindow?.setTimeout?.bind(currentWindow) || globalThis.setTimeout.bind(globalThis);
    const cancel = currentWindow?.clearTimeout?.bind(currentWindow) || globalThis.clearTimeout.bind(globalThis);
    let frame;
    let timeout;
    let finished = false;
    const finish = () => {
      if (finished) return;
      finished = true;
      if (timeout !== void 0) cancel(timeout);
      if (frame !== void 0) currentWindow?.cancelAnimationFrame?.(frame);
      resolve();
    };
    timeout = schedule(finish, currentWindow?.requestAnimationFrame ? 250 : 0);
    if (finished || !currentWindow?.requestAnimationFrame) return;
    try {
      frame = currentWindow.requestAnimationFrame(() => {
        if (!finished) {
          try {
            frame = currentWindow.requestAnimationFrame(finish);
          } catch {
            finish();
          }
        }
      });
    } catch {
      finish();
    }
  });
};
var waitForImage = (image, timeoutMs) => {
  if (image.complete) return Promise.resolve();
  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      image.removeEventListener("load", finish);
      image.removeEventListener("error", finish);
      resolve();
    };
    const timeout = setTimeout(finish, timeoutMs);
    image.addEventListener("load", finish, { once: true });
    image.addEventListener("error", finish, { once: true });
    if (image.complete) finish();
    else if (typeof image.decode === "function") {
      try {
        image.decode().then(finish, () => {
          if (image.complete) finish();
        });
      } catch {
        if (image.complete) finish();
      }
    }
  });
};
var waitForFonts = async (documentRef, timeoutMs) => {
  if (!documentRef?.fonts) return;
  let timeout;
  try {
    await Promise.race([
      documentRef.fonts.ready,
      new Promise((resolve) => {
        timeout = setTimeout(resolve, timeoutMs);
      })
    ]);
  } catch {
  } finally {
    if (timeout !== void 0) clearTimeout(timeout);
  }
};
var waitForFileViewerImages = async (root) => {
  if (!root || typeof root.querySelectorAll !== "function") return;
  await Promise.all(Array.from(root.querySelectorAll("img"), (image) => waitForImage(image, 5e3)));
};
var bytesToDataUrl = (bytes, mimeType) => {
  const type = mimeType || "application/octet-stream";
  const nodeBuffer = globalThis.Buffer;
  if (nodeBuffer) {
    return `data:${type};base64,${nodeBuffer.from(bytes).toString("base64")}`;
  }
  let binary = "";
  const view = new Uint8Array(bytes);
  for (let index = 0; index < view.length; index += 1) {
    binary += String.fromCharCode(view[index]);
  }
  return `data:${type};base64,${btoa(binary)}`;
};
var blobToDataUrl = async (blob) => {
  if (typeof FileReader === "function") {
    try {
      return await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result || ""));
        reader.onerror = () => reject(reader.error || new Error("Failed to read blob"));
        reader.readAsDataURL(blob);
      });
    } catch {
    }
  }
  return bytesToDataUrl(await blob.arrayBuffer(), blob.type || "application/octet-stream");
};
var collectBlobUrls = (html) => {
  const matches = html.match(/blob:[^\s"'<>)\\]+/g) || [];
  return Array.from(new Set(matches));
};
var inlineFileViewerBlobUrlsInHtml = async (html) => {
  if (!html.includes("blob:") || typeof fetch !== "function") {
    return html;
  }
  const urls = collectBlobUrls(html);
  if (!urls.length) {
    return html;
  }
  const replacements = await Promise.all(urls.map(async (url) => {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        return null;
      }
      const blob = await response.blob();
      const dataUrl = await blobToDataUrl(blob);
      return dataUrl ? [url, dataUrl] : null;
    } catch {
      return null;
    }
  }));
  let next = html;
  for (const pair of replacements) {
    if (!pair) {
      continue;
    }
    const [from, to] = pair;
    next = next.split(from).join(to);
  }
  return next;
};
var waitForFileViewerPrintWindowReady = async (printWindow) => {
  const { document: printDocument } = printWindow;
  if (printDocument.readyState !== "complete") {
    await new Promise((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        printWindow.clearTimeout(timeout);
        printWindow.removeEventListener("load", finish);
        resolve();
      };
      const timeout = printWindow.setTimeout(finish, 1200);
      printWindow.addEventListener("load", finish, { once: true });
      if (printDocument.readyState === "complete") finish();
    });
  }
  await Promise.all([
    ...Array.from(printDocument.images, (image) => waitForImage(image, 1500)),
    waitForFonts(printDocument, 1500)
  ]);
  await waitForFileViewerNextPaint(printWindow);
};
var resolveFileViewerPrintStyle = async (adapter, options) => {
  if (options.mode !== "print" || !adapter?.printStyle) {
    return "";
  }
  if (typeof adapter.printStyle === "function") {
    return await adapter.printStyle(options);
  }
  return adapter.printStyle;
};
var prepareFileViewerRenderedContentForSnapshot = async (source, adapter) => {
  await adapter?.beforeSnapshot?.();
  await Promise.all([
    waitForFileViewerImages(source),
    waitForFonts(source.ownerDocument, 5e3)
  ]);
  await waitForFileViewerNextPaint(source.ownerDocument.defaultView || void 0);
};

export {
  triggerFileViewerBlobDownload,
  triggerFileViewerUrlDownload,
  replaceFileViewerCanvasWithImages,
  waitForFileViewerNextPaint,
  waitForFileViewerImages,
  inlineFileViewerBlobUrlsInHtml,
  waitForFileViewerPrintWindowReady,
  resolveFileViewerPrintStyle,
  prepareFileViewerRenderedContentForSnapshot
};
