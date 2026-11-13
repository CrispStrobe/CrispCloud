// crisp-host/index.ts
var channel = "crisp-document-v1";
var session = location.hash.slice(1);
var target = document.querySelector("#document");
var kinds = /* @__PURE__ */ new Set(["wordperfect", "chm", "spreadsheet", "ppt", "postscript", "xml"]);
var bytes;
var received = 0;
var metadata;
var instance;
var controller;
var opening = false;
var closed = false;
function disposeInstance() {
  const old = instance;
  instance = void 0;
  if (typeof old?.unmount === "function") old.unmount();
  else old?.destroy?.();
}
function appearance(value) {
  document.documentElement.lang = String(value.locale || "en").slice(0, 64);
  document.body.dataset.dark = String(value.dark === true);
  document.body.dataset.viewerTheme = value.dark === true ? "dark" : "light";
  target.style.zoom = String(Math.min(3, Math.max(0.5, Number(value.fontScale) || 1)));
}
function emit(type, values = {}) {
  const message = JSON.stringify({ channel, session, type, ...values });
  const host = window;
  if (host.CrispDocumentMessage?.postMessage) host.CrispDocumentMessage.postMessage(message);
  else if (host.flutter_inappwebview?.callHandler) host.flutter_inappwebview.callHandler("CrispDocumentMessage", message);
  else if (window.parent !== window) window.parent.postMessage(message, location.origin);
}
function fail(error) {
  if (closed) return;
  controller?.abort();
  disposeInstance();
  bytes = void 0;
  const message = error instanceof Error ? error.message : String(error);
  target.replaceChildren();
  const notice = document.createElement("p");
  notice.className = "document-error";
  notice.textContent = message.slice(0, 2048);
  target.append(notice);
  emit("error", { message: notice.textContent });
}
async function open() {
  if (opening || !metadata || !bytes || received !== bytes.length) throw new Error("The document transfer is incomplete.");
  opening = true;
  controller = new AbortController();
  appearance(metadata);
  const context = {
    filename: String(metadata.filename),
    signal: controller.signal,
    options: {
      locale: metadata.locale,
      theme: metadata.dark === true ? "dark" : "light",
      wordPerfect: {
        useWorker: true,
        workerUrl: new URL("./wordperfect.worker.js", import.meta.url).href,
        wasmUrl: new URL("./libwpd.wasm", import.meta.url).href
      },
      chm: {
        workerUrl: new URL("./chm.worker.js", import.meta.url).href,
        wasmModuleUrl: new URL("./chm_wasm.js", import.meta.url).href,
        wasmUrl: new URL("./chm_wasm_bg.wasm", import.meta.url).href
      }
    }
  };
  const input = bytes.buffer;
  bytes = void 0;
  switch (metadata.kind) {
    case "wordperfect":
      instance = await (await import("./entry-NDHWTUCQ.js")).default(input, target, context);
      break;
    case "chm":
      instance = await (await import("./entry-7RJCH66I.js")).default(input, target, context);
      break;
    case "spreadsheet":
      instance = await (await import("./entry-U22M3L7A.js")).default(input, target, context);
      break;
    case "ppt":
      instance = await (await import("./entry-IMEYDMPT.js")).default(input, target, context);
      break;
    case "postscript":
      instance = await (await import("./entry-K66XL2UG.js")).default(input, target, context);
      break;
    case "xml":
      instance = await (await import("./entry-GW5ZCGSR.js")).default(input, target, context);
      break;
    default:
      throw new Error("Unsupported document engine.");
  }
  if (closed || controller.signal.aborted) {
    disposeInstance();
    return;
  }
  emit("loaded");
}
function receive(value) {
  if (closed || !value || typeof value !== "object") return;
  const message = value;
  if (message.channel !== channel || message.session !== session) return;
  try {
    if (message.type === "begin") {
      if (metadata || opening) throw new Error("A document is already open in this session.");
      if (!kinds.has(String(message.kind)) || typeof message.filename !== "string" || message.filename.length > 4096) throw new Error("Invalid document request.");
      const limit = (message.kind === "xml" ? 4 : ["ppt", "spreadsheet", "postscript"].includes(String(message.kind)) ? 32 : 64) * 1024 * 1024;
      if (!Number.isSafeInteger(message.length) || Number(message.length) < 0 || Number(message.length) > limit) throw new Error("Document exceeds the preview input limit.");
      metadata = message;
      bytes = new Uint8Array(Number(message.length));
      received = 0;
    } else if (message.type === "chunk") {
      if (!bytes || opening || message.offset !== received || typeof message.data !== "string" || message.data.length > 256 * 1024) throw new Error("Invalid document transfer chunk.");
      const chunk = atob(message.data);
      if (chunk.length > bytes.length - received) throw new Error("Document transfer exceeds its declared length.");
      for (let i = 0; i < chunk.length; i++) bytes[received + i] = chunk.charCodeAt(i);
      received += chunk.length;
    } else if (message.type === "appearance") {
      appearance(message);
    } else if (message.type === "open") {
      void open().catch(fail);
    }
  } catch (error) {
    fail(error);
  }
}
Object.defineProperty(window, "crispDocumentHost", { value: Object.freeze({ receive, ready: () => emit("ready") }), writable: false });
window.addEventListener("message", (event) => {
  if (event.source !== window.parent || event.origin !== location.origin) return;
  try {
    receive(typeof event.data === "string" ? JSON.parse(event.data) : event.data);
  } catch {
  }
});
window.addEventListener("pagehide", () => {
  closed = true;
  controller?.abort();
  disposeInstance();
  bytes = void 0;
});
window.addEventListener("flutterInAppWebViewPlatformReady", () => emit("ready"));
if (/^[A-Za-z0-9_-]{32,64}$/.test(session)) emit("ready");
