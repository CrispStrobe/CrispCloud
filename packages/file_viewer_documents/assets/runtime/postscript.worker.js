import {
  resolvePostscriptSafetyLimits
} from "./chunk-VJWTYBFP.js";
import "./chunk-PIRHQTI4.js";

// packages/renderers/design/src/postscriptRuntime/stet_wasm.js
var Interpreter = class _Interpreter {
  static __wrap(ptr) {
    const obj = Object.create(_Interpreter.prototype);
    obj.__wbg_ptr = ptr;
    InterpreterFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    InterpreterFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_interpreter_free(ptr, 0);
  }
};
if (Symbol.dispose) Interpreter.prototype[Symbol.dispose] = Interpreter.prototype.free;
var Page = class _Page {
  static __wrap(ptr) {
    const obj = Object.create(_Page.prototype);
    obj.__wbg_ptr = ptr;
    PageFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    PageFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_page_free(ptr, 0);
  }
  /**
   * Page height in pixels.
   * @returns {number}
   */
  get height() {
    const ret = wasm.page_height(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * RGBA pixel data (4 bytes per pixel, row-major).
   * @returns {Uint8Array}
   */
  get rgba() {
    const ret = wasm.page_rgba(this.__wbg_ptr);
    var v1 = getArrayU8FromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 1, 1);
    return v1;
  }
  /**
   * Page width in pixels.
   * @returns {number}
   */
  get width() {
    const ret = wasm.page_width(this.__wbg_ptr);
    return ret >>> 0;
  }
};
if (Symbol.dispose) Page.prototype[Symbol.dispose] = Page.prototype.free;
function create_interpreter() {
  const ret = wasm.create_interpreter();
  return Interpreter.__wrap(ret);
}
function page_count(interp) {
  _assertClass(interp, Interpreter);
  const ret = wasm.page_count(interp.__wbg_ptr);
  return ret >>> 0;
}
function page_dimensions(interp, page_index) {
  _assertClass(interp, Interpreter);
  const ret = wasm.page_dimensions(interp.__wbg_ptr, page_index);
  return ret;
}
function ps_stream_active(interp) {
  _assertClass(interp, Interpreter);
  const ret = wasm.ps_stream_active(interp.__wbg_ptr);
  return ret !== 0;
}
function render(interp, ps_data, dpi, filename) {
  _assertClass(interp, Interpreter);
  const ptr0 = passArray8ToWasm0(ps_data, wasm.__wbindgen_malloc);
  const len0 = WASM_VECTOR_LEN;
  const ptr1 = passStringToWasm0(filename, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
  const len1 = WASM_VECTOR_LEN;
  const ret = wasm.render(interp.__wbg_ptr, ptr0, len0, dpi, ptr1, len1);
  if (ret[2]) {
    throw takeFromExternrefTable0(ret[1]);
  }
  return takeFromExternrefTable0(ret[0]);
}
function render_viewport(interp, page_index, vp_x, vp_y, vp_w, vp_h, pixel_w, pixel_h) {
  _assertClass(interp, Interpreter);
  const ret = wasm.render_viewport(interp.__wbg_ptr, page_index, vp_x, vp_y, vp_w, vp_h, pixel_w, pixel_h);
  if (ret[2]) {
    throw takeFromExternrefTable0(ret[1]);
  }
  return Page.__wrap(ret[0]);
}
function set_max_vm(interp, max_bytes) {
  _assertClass(interp, Interpreter);
  wasm.set_max_vm(interp.__wbg_ptr, max_bytes);
}
function step_ps_page(interp) {
  _assertClass(interp, Interpreter);
  const ret = wasm.step_ps_page(interp.__wbg_ptr);
  if (ret[2]) {
    throw takeFromExternrefTable0(ret[1]);
  }
  return takeFromExternrefTable0(ret[0]);
}
function __wbg_get_imports() {
  const import0 = {
    __proto__: null,
    __wbg___wbindgen_throw_bb96b2010945f0bc: function(arg0, arg1) {
      throw new Error(getStringFromWasm0(arg0, arg1));
    },
    __wbg_error_757e9472f8410341: function(arg0, arg1) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.error(getStringFromWasm0(arg0, arg1));
      } finally {
        wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_log_e6372b4fbfc9f81e: function(arg0) {
      console.log(arg0);
    },
    __wbg_new_116be93542d39019: function() {
      const ret = new Array();
      return ret;
    },
    __wbg_new_227d7c05414eb861: function() {
      const ret = new Error();
      return ret;
    },
    __wbg_push_adb0107829f02d75: function(arg0, arg1) {
      const ret = arg0.push(arg1);
      return ret;
    },
    __wbg_stack_3b0d974bbf31e44f: function(arg0, arg1) {
      const ret = arg1.stack;
      const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN;
      getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbindgen_cast_0000000000000001: function(arg0) {
      const ret = arg0;
      return ret;
    },
    __wbindgen_cast_0000000000000002: function(arg0, arg1) {
      const ret = getStringFromWasm0(arg0, arg1);
      return ret;
    },
    __wbindgen_init_externref_table: function() {
      const table = wasm.__wbindgen_externrefs;
      const offset = table.grow(4);
      table.set(0, void 0);
      table.set(offset + 0, void 0);
      table.set(offset + 1, null);
      table.set(offset + 2, true);
      table.set(offset + 3, false);
    }
  };
  return {
    __proto__: null,
    "./stet_wasm_bg.js": import0
  };
}
var InterpreterFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_interpreter_free(ptr, 1));
var PageFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_page_free(ptr, 1));
function _assertClass(instance, klass) {
  if (!(instance instanceof klass)) {
    throw new Error(`expected instance of ${klass.name}`);
  }
}
function getArrayU8FromWasm0(ptr, len) {
  ptr = ptr >>> 0;
  return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
}
var cachedDataViewMemory0 = null;
function getDataViewMemory0() {
  if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || cachedDataViewMemory0.buffer.detached === void 0 && cachedDataViewMemory0.buffer !== wasm.memory.buffer) {
    cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
  }
  return cachedDataViewMemory0;
}
function getStringFromWasm0(ptr, len) {
  return decodeText(ptr >>> 0, len);
}
var cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
  if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
    cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
  }
  return cachedUint8ArrayMemory0;
}
function passArray8ToWasm0(arg, malloc) {
  const ptr = malloc(arg.length * 1, 1) >>> 0;
  getUint8ArrayMemory0().set(arg, ptr / 1);
  WASM_VECTOR_LEN = arg.length;
  return ptr;
}
function passStringToWasm0(arg, malloc, realloc) {
  if (realloc === void 0) {
    const buf = cachedTextEncoder.encode(arg);
    const ptr2 = malloc(buf.length, 1) >>> 0;
    getUint8ArrayMemory0().subarray(ptr2, ptr2 + buf.length).set(buf);
    WASM_VECTOR_LEN = buf.length;
    return ptr2;
  }
  let len = arg.length;
  let ptr = malloc(len, 1) >>> 0;
  const mem = getUint8ArrayMemory0();
  let offset = 0;
  for (; offset < len; offset++) {
    const code = arg.charCodeAt(offset);
    if (code > 127) break;
    mem[ptr + offset] = code;
  }
  if (offset !== len) {
    if (offset !== 0) {
      arg = arg.slice(offset);
    }
    ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
    const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
    const ret = cachedTextEncoder.encodeInto(arg, view);
    offset += ret.written;
    ptr = realloc(ptr, len, offset, 1) >>> 0;
  }
  WASM_VECTOR_LEN = offset;
  return ptr;
}
function takeFromExternrefTable0(idx) {
  const value = wasm.__wbindgen_externrefs.get(idx);
  wasm.__externref_table_dealloc(idx);
  return value;
}
var cachedTextDecoder = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
var MAX_SAFARI_DECODE_BYTES = 2146435072;
var numBytesDecoded = 0;
function decodeText(ptr, len) {
  numBytesDecoded += len;
  if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
    cachedTextDecoder = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
    cachedTextDecoder.decode();
    numBytesDecoded = len;
  }
  return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}
var cachedTextEncoder = new TextEncoder();
if (!("encodeInto" in cachedTextEncoder)) {
  cachedTextEncoder.encodeInto = function(arg, view) {
    const buf = cachedTextEncoder.encode(arg);
    view.set(buf);
    return {
      read: arg.length,
      written: buf.length
    };
  };
}
var WASM_VECTOR_LEN = 0;
var wasmModule;
var wasmInstance;
var wasm;
function __wbg_finalize_init(instance, module) {
  wasmInstance = instance;
  wasm = instance.exports;
  wasmModule = module;
  cachedDataViewMemory0 = null;
  cachedUint8ArrayMemory0 = null;
  wasm.__wbindgen_start();
  return wasm;
}
async function __wbg_load(module, imports) {
  if (typeof Response === "function" && module instanceof Response) {
    if (!module.ok) {
      throw new Error(`failed to fetch Wasm: ${module.status} ${module.statusText} fetching '${module.url}'`);
    }
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        return await WebAssembly.instantiateStreaming(module, imports);
      } catch (e) {
        const validResponse = expectedResponseType(module.type);
        if (validResponse && module.headers.get("Content-Type") !== "application/wasm") {
          console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n", e);
        } else {
          throw e;
        }
      }
    }
    const bytes = await module.arrayBuffer();
    return await WebAssembly.instantiate(bytes, imports);
  } else {
    const instance = await WebAssembly.instantiate(module, imports);
    if (instance instanceof WebAssembly.Instance) {
      return { instance, module };
    } else {
      return instance;
    }
  }
  function expectedResponseType(type) {
    switch (type) {
      case "basic":
      case "cors":
      case "default":
        return true;
    }
    return false;
  }
}
async function __wbg_init(module_or_path) {
  if (wasm !== void 0) return wasm;
  if (module_or_path !== void 0) {
    if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
      ({ module_or_path } = module_or_path);
    } else {
      console.warn("using deprecated parameters for the initialization function; pass a single object instead");
    }
  }
  if (module_or_path === void 0) {
    module_or_path = new URL("stet_wasm_bg.wasm", import.meta.url);
  }
  const imports = __wbg_get_imports();
  if (typeof module_or_path === "string" || typeof Request === "function" && module_or_path instanceof Request || typeof URL === "function" && module_or_path instanceof URL) {
    module_or_path = fetch(module_or_path);
  }
  const { instance, module } = await __wbg_load(await module_or_path, imports);
  return __wbg_finalize_init(instance, module);
}

// packages/renderers/design/src/postscript.worker.ts
var scope = self;
var nativeFetch = globalThis.fetch.bind(globalThis);
var pinnedWasmSha256 = "b8d72531ec41ca497d67a79589a1dbb44748a4fefd088aa122007fbb28e06b20";
var denyExternal = () => {
  throw new Error("External PostScript resources are disabled.");
};
Object.defineProperty(globalThis, "fetch", { value: async () => denyExternal(), writable: false, configurable: false });
for (const name of ["XMLHttpRequest", "WebSocket", "EventSource", "importScripts"]) {
  Object.defineProperty(globalThis, name, { value: denyExternal, writable: false, configurable: false });
}
async function loadPinnedWasm(value) {
  const url = new URL(value, scope.location.href);
  if (!/^https?:$/.test(url.protocol) || url.origin !== scope.location.origin || url.username || url.password || url.hash) {
    throw new Error("PostScript WASM must use the local viewer origin.");
  }
  const response = await nativeFetch(url, { redirect: "error", credentials: "omit", mode: "same-origin" });
  if (!response.ok || !response.body) throw new Error("The bundled PostScript engine is unavailable.");
  const maximum = 16 * 1024 * 1024;
  if (Number(response.headers.get("content-length")) > maximum) {
    await response.body.cancel();
    throw new Error("PostScript engine exceeds its asset byte limit.");
  }
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  let complete = false;
  try {
    while (true) {
      const { done, value: chunk } = await reader.read();
      if (done) break;
      total += chunk.byteLength;
      if (total > maximum) throw new Error("PostScript engine exceeds its asset byte limit.");
      chunks.push(chunk);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const hash = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
    if (hash !== pinnedWasmSha256) throw new Error("PostScript engine does not match the reviewed native artifact.");
    complete = true;
    return bytes;
  } finally {
    if (!complete) await reader.cancel().catch(() => void 0);
    reader.releaseLock();
  }
}
var PostscriptWorkerError = class extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = "PostscriptWorkerError";
  }
  code;
};
var initializedWasmUrl;
var documentSession;
var closeDocument = () => {
  documentSession?.interpreter.free();
  documentSession = void 0;
};
var hasPostscriptHeader = (buffer) => {
  if (buffer.byteLength < 4) return false;
  const bytes = new Uint8Array(buffer, 0, Math.min(buffer.byteLength, 32));
  const ps = bytes[0] === 37 && bytes[1] === 33 && bytes[2] === 80 && bytes[3] === 83;
  const dosEps = bytes[0] === 197 && bytes[1] === 208 && bytes[2] === 211 && bytes[3] === 198;
  return ps || dosEps;
};
var validatePage = (interpreter, index, limits) => {
  const dimensions = page_dimensions(interpreter, index);
  if (!dimensions || dimensions.length < 3) {
    throw new PostscriptWorkerError("POSTSCRIPT_PAGE_INVALID", `PostScript page ${index + 1} has no dimensions.`);
  }
  const width = Number(dimensions[0]);
  const height = Number(dimensions[1]);
  const pageDpi = Number(dimensions[2]);
  if (![width, height, pageDpi].every(Number.isFinite) || width <= 0 || height <= 0 || pageDpi <= 0) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_PAGE_INVALID",
      `PostScript page ${index + 1} reports invalid dimensions.`
    );
  }
  if (width > limits.maxSourceDimension || height > limits.maxSourceDimension) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_PAGE_DIMENSION_LIMIT",
      `PostScript page ${index + 1} exceeds the ${limits.maxSourceDimension}-unit source-dimension limit.`
    );
  }
  const minScale = limits.minDpi / pageDpi;
  const minWidth = Math.max(1, Math.round(width * minScale));
  const minHeight = Math.max(1, Math.round(height * minScale));
  if (minWidth > limits.maxCanvasDimension || minHeight > limits.maxCanvasDimension || minWidth * minHeight > limits.maxRenderedPixels) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_PAGE_RASTER_LIMIT",
      `PostScript page ${index + 1} cannot fit the configured raster limits even at ${limits.minDpi} DPI.`
    );
  }
  return { index, width, height, referenceDpi: pageDpi };
};
var openDocument = async (buffer, filename, wasmUrl, limitOverrides) => {
  closeDocument();
  const limits = resolvePostscriptSafetyLimits(limitOverrides);
  if (buffer.byteLength > limits.maxFileBytes) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_FILE_LIMIT",
      `PostScript source exceeds the ${limits.maxFileBytes}-byte safety limit.`
    );
  }
  if (!hasPostscriptHeader(buffer)) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_SIGNATURE_INVALID",
      "The source is not an Adobe PostScript document or DOS EPS container."
    );
  }
  if (initializedWasmUrl && initializedWasmUrl !== wasmUrl) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_WASM_URL_CHANGED",
      "A PostScript Worker cannot switch WebAssembly binaries after initialization."
    );
  }
  if (!initializedWasmUrl) {
    await __wbg_init({ module_or_path: await loadPinnedWasm(wasmUrl) });
    initializedWasmUrl = wasmUrl;
  }
  const interpreter = create_interpreter();
  set_max_vm(interpreter, limits.maxVmBytes);
  try {
    const referenceDpi = 72;
    render(interpreter, new Uint8Array(buffer), referenceDpi, filename);
    while (ps_stream_active(interpreter)) {
      step_ps_page(interpreter);
      const knownPages = page_count(interpreter);
      if (knownPages > limits.maxPages) {
        throw new PostscriptWorkerError(
          "POSTSCRIPT_PAGE_LIMIT",
          `PostScript execution reached the ${limits.maxPages}-page safety limit before the program ended.`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    const count = page_count(interpreter);
    if (count < 1) {
      throw new PostscriptWorkerError("POSTSCRIPT_EMPTY", "The PostScript program did not produce a page.");
    }
    if (count > limits.maxPages) {
      throw new PostscriptWorkerError(
        "POSTSCRIPT_PAGE_LIMIT",
        `PostScript output exceeds the ${limits.maxPages}-page safety limit.`
      );
    }
    const pages = Array.from({ length: count }, (_, index) => validatePage(interpreter, index, limits));
    documentSession = { interpreter, limits, pages };
    return {
      engine: "stet-wasm",
      engineVersion: "0.8.7",
      renderBackend: "cpu-tiny-skia",
      colorProfile: "CGATS001Compat-v2-micro (CC0)",
      fontSubstitutes: ["URW Base35 (OFL-1.1)"],
      pages
    };
  } catch (error) {
    interpreter.free();
    throw error;
  }
};
var renderPage = (pageIndex, dpi) => {
  if (!documentSession) {
    throw new PostscriptWorkerError("POSTSCRIPT_NOT_OPEN", "The PostScript Worker has no open document.");
  }
  const { interpreter, limits, pages } = documentSession;
  if (!Number.isSafeInteger(pageIndex) || pageIndex < 0 || pageIndex >= pages.length) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_PAGE_RANGE",
      `PostScript page index ${pageIndex} is outside 0..${pages.length - 1}.`
    );
  }
  if (!Number.isFinite(dpi) || dpi < limits.minDpi || dpi > limits.maxDpi) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_DPI_LIMIT",
      `PostScript render DPI must be between ${limits.minDpi} and ${limits.maxDpi}.`
    );
  }
  const source = pages[pageIndex];
  const scale = dpi / source.referenceDpi;
  const width = Math.max(1, Math.round(source.width * scale));
  const height = Math.max(1, Math.round(source.height * scale));
  if (width > limits.maxCanvasDimension || height > limits.maxCanvasDimension) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_CANVAS_DIMENSION_LIMIT",
      `PostScript raster ${width}\xD7${height} exceeds the ${limits.maxCanvasDimension}-pixel canvas dimension limit.`
    );
  }
  if (width * height > limits.maxRenderedPixels) {
    throw new PostscriptWorkerError(
      "POSTSCRIPT_PIXEL_LIMIT",
      `PostScript raster ${width}\xD7${height} exceeds the ${limits.maxRenderedPixels}-pixel limit.`
    );
  }
  const page = render_viewport(
    interpreter,
    pageIndex,
    0,
    0,
    source.width,
    source.height,
    width,
    height
  );
  try {
    if (page.width !== width || page.height !== height) {
      throw new PostscriptWorkerError("POSTSCRIPT_PAGE_INVALID", "The PostScript engine returned unexpected raster dimensions.");
    }
    const bytes = page.rgba;
    if (bytes.byteLength !== width * height * 4) {
      throw new PostscriptWorkerError("POSTSCRIPT_PAGE_INVALID", "The PostScript engine returned an invalid pixel buffer.");
    }
    const rgba = new Uint8ClampedArray(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return { pageIndex, dpi, width: page.width, height: page.height, rgba };
  } finally {
    page.free();
  }
};
var errorCode = (error) => {
  if (error instanceof PostscriptWorkerError) return error.code;
  if (error instanceof Error && "code" in error && typeof error.code === "string") {
    return error.code;
  }
  return "POSTSCRIPT_ENGINE_FAILURE";
};
var processRequest = async (request) => {
  try {
    if (request.type === "open") {
      const result2 = await openDocument(request.buffer, request.filename, request.wasmUrl, request.limits);
      const response2 = { id: request.id, ok: true, type: "open", result: result2 };
      scope.postMessage(response2);
      return;
    }
    if (request.type === "destroy") {
      closeDocument();
      const response2 = { id: request.id, ok: true, type: "destroy" };
      scope.postMessage(response2);
      return;
    }
    const result = renderPage(request.pageIndex, request.dpi);
    const response = { id: request.id, ok: true, type: "renderPage", result };
    scope.postMessage(response, [result.rgba.buffer]);
  } catch (error) {
    const code = errorCode(error);
    if (request.type === "open") closeDocument();
    const response = {
      id: request.id,
      ok: false,
      error: {
        name: error instanceof Error ? error.name : "Error",
        code,
        message: error instanceof Error ? error.message : String(error),
        fatal: request.type === "open" || code === "POSTSCRIPT_ENGINE_FAILURE"
      }
    };
    scope.postMessage(response);
  }
};
var operationQueue = Promise.resolve();
scope.addEventListener("message", (event) => {
  operationQueue = operationQueue.catch(() => void 0).then(() => processRequest(event.data));
});
