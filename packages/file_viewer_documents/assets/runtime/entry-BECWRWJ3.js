import {
  purify_default
} from "./chunk-G2WIWTPZ.js";
import {
  decodeFileViewerTextBuffer
} from "./chunk-3E27RFED.js";
import "./chunk-UIIGQOVD.js";
import "./chunk-V2DBS5C2.js";
import "./chunk-XPXVZBDO.js";
import "./chunk-B3J7LI27.js";
import "./chunk-X3L4DUK6.js";
import "./chunk-PIRHQTI4.js";

// packages/renderers/text/src/xmlSafety.ts
var XmlProfileError = class extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = "XmlProfileError";
  }
  code;
};
var MiB = 1024 * 1024;
var xmlHardLimits = Object.freeze({
  maxXmlBytes: 4 * MiB,
  maxResourceBytes: 2 * MiB,
  maxOutputBytes: 8 * MiB,
  maxProfiles: 32,
  maxTotalResourceBytes: 16 * MiB
});
function checkXmlAbort(signal) {
  if (signal.aborted) {
    throw signal.reason instanceof XmlProfileError ? signal.reason : new XmlProfileError("cancelled", "XML profile processing was cancelled.");
  }
}
function sameOriginXmlUrl(value, base, origin) {
  let url;
  try {
    url = new URL(value, base);
  } catch {
    throw new XmlProfileError("resource-error", "Invalid XML resource URL.");
  }
  if (!/^https?:$/.test(url.protocol) || url.origin !== origin || url.username || url.password || url.hash) {
    throw new XmlProfileError("unsafe-resource", "XML resources must use same-origin HTTP(S) URLs without credentials or fragments.");
  }
  return url.href;
}
async function fetchXmlBytes(url, maxBytes, signal) {
  checkXmlAbort(signal);
  const response = await fetch(url, {
    signal,
    redirect: "error",
    credentials: "same-origin",
    mode: "same-origin",
    referrerPolicy: "no-referrer"
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new XmlProfileError("resource-error", `XML resource returned HTTP ${response.status}.`);
  }
  const length = Number(response.headers.get("content-length"));
  if (length > maxBytes) {
    await response.body?.cancel();
    throw new XmlProfileError("limit-exceeded", "XML resource exceeds its byte limit.");
  }
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  let completed = false;
  try {
    while (true) {
      checkXmlAbort(signal);
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) throw new XmlProfileError("limit-exceeded", "XML resource exceeds its byte limit.");
      chunks.push(value);
    }
    checkXmlAbort(signal);
    completed = true;
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return bytes;
  } finally {
    if (!completed) await reader.cancel().catch(() => void 0);
    reader.releaseLock();
  }
}
var XSD = "http://www.w3.org/2001/XMLSchema";
var XSL = "http://www.w3.org/1999/XSL/Transform";
function parseSafeXml(source, documentRef, kind) {
  if (/<!\s*(?:DOCTYPE|ENTITY)\b/i.test(source)) {
    throw new XmlProfileError("unsafe-resource", "DTD and entity declarations are disabled for XML profiles.");
  }
  const Parser = documentRef.defaultView?.DOMParser;
  if (!Parser) throw new XmlProfileError("engine-error", "XML parsing requires a browser document.");
  const doc = new Parser().parseFromString(source, "application/xml");
  if (!doc.documentElement || doc.getElementsByTagName("parsererror").length) {
    throw new XmlProfileError("invalid-xml", `Malformed ${kind.toUpperCase()} document.`);
  }
  const root = doc.documentElement;
  if (kind === "xsd" && (root.namespaceURI !== XSD || root.localName !== "schema")) {
    throw new XmlProfileError("invalid-xml", "Expected an XML Schema document.");
  }
  if (kind === "xslt" && (root.namespaceURI !== XSL || !["stylesheet", "transform"].includes(root.localName))) {
    throw new XmlProfileError("invalid-xml", "Expected an XSLT 1.0 stylesheet.");
  }
  for (const element of Array.from(doc.getElementsByTagName("*"))) {
    if (element.namespaceURI === XSD && ["include", "import", "redefine", "override"].includes(element.localName) || element.namespaceURI === XSL && ["include", "import"].includes(element.localName) || element.namespaceURI === "http://www.w3.org/2001/XInclude") {
      throw new XmlProfileError("unsafe-resource", "Schema dependencies, XSLT imports/includes and XInclude are disabled.");
    }
    if (kind !== "xslt") continue;
    for (const attribute of Array.from(element.attributes)) {
      if (/(?:^|[^\w.-])document\s*\(/.test(attribute.value) || attribute.localName === "extension-element-prefixes" && attribute.value.trim()) {
        throw new XmlProfileError("unsafe-resource", "XSLT document() and extension instructions are disabled.");
      }
    }
    if (element.namespaceURI === XSL && element.localName === "output") {
      const method = element.getAttribute("method");
      if (method && !["html", "xml", "text"].includes(method)) throw new XmlProfileError("transform-error", "Only standard HTML, XML and text XSLT output is supported.");
    }
  }
  return doc;
}
function xmlEngineText(source) {
  return source.replace(/^(\uFEFF?<\?xml\s[^?]*?encoding\s*=\s*)(["'])[^"']*\2/, '$1"UTF-8"');
}

// packages/renderers/text/src/xmlWasmMemory.ts
function limitXmlWasmMemory(input, maxPages = 1024) {
  const bytes = ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength) : new Uint8Array(input);
  if (!Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > 1024) throw new Error("Invalid XML WASM memory limit.");
  if (bytes.length < 8 || ![0, 97, 115, 109, 1, 0, 0, 0].every((value, index) => bytes[index] === value)) {
    throw new Error("Invalid XML WASM module.");
  }
  let offset = 8;
  const read = () => {
    let value = 0;
    for (let index = 0; index < 5; index++) {
      if (offset >= bytes.length) throw new Error("Truncated WASM section.");
      const byte = bytes[offset++];
      if (index === 4 && byte > 15) throw new Error("Invalid WASM section integer.");
      value += (byte & 127) * 2 ** (index * 7);
      if (!(byte & 128)) return value;
    }
    throw new Error("Invalid WASM section integer.");
  };
  const encode = (value) => {
    const output2 = [];
    do {
      const byte = value % 128;
      value = Math.floor(value / 128);
      output2.push(byte | (value ? 128 : 0));
    } while (value);
    return output2;
  };
  const parts = [bytes.subarray(0, 8)];
  let foundMemory = false;
  while (offset < bytes.length) {
    const start = offset;
    const id = bytes[offset++];
    const length = read();
    const end = offset + length;
    if (end > bytes.length) throw new Error("Truncated WASM section.");
    if (id !== 5) {
      parts.push(bytes.subarray(start, end));
    } else {
      if (foundMemory || read() !== 1) throw new Error("XML WASM requires exactly one defined memory.");
      foundMemory = true;
      const flags = read();
      if (flags !== 0 && flags !== 1) throw new Error("Shared or memory64 XML WASM is not supported.");
      const initial = read();
      const maximum = flags === 1 ? read() : maxPages;
      if (initial > maxPages || maximum < initial || offset !== end) throw new Error("Invalid XML WASM memory declaration.");
      const memory = [1, 1, ...encode(initial), ...encode(Math.min(maximum, maxPages))];
      parts.push(new Uint8Array([5, ...encode(memory.length), ...memory]));
    }
    offset = end;
  }
  if (!foundMemory) throw new Error("XML WASM did not declare its own memory.");
  const output = new Uint8Array(parts.reduce((size, part) => size + part.length, 0));
  offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.length;
  }
  return output;
}

// packages/renderers/text/src/xmlEngines.ts
function runXsltWorker() {
  const scope = globalThis;
  const NativeModule = WebAssembly.Module;
  WebAssembly.Module = class extends NativeModule {
    constructor(bytes) {
      super(scope.__fileViewerLimitXmlWasmMemory(bytes));
      if (NativeModule.imports(this).some((entry) => entry.kind === "memory")) {
        throw new Error("Imported XML WASM memory is not supported.");
      }
    }
  };
  let networkAttempt = false;
  const deny = () => {
    networkAttempt = true;
    throw new Error("External XML resources are disabled.");
  };
  Object.defineProperty(globalThis, "fetch", { value: async () => deny(), writable: false, configurable: false });
  for (const name of ["XMLHttpRequest", "WebSocket", "EventSource", "importScripts"]) {
    Object.defineProperty(globalThis, name, { value: deny, writable: false, configurable: false });
  }
  scope.onmessage = async ({ data }) => {
    let engine;
    const pointers = [];
    try {
      engine = await createXSLTTransformModule({ print: () => void 0, printErr: () => void 0 });
      const encoder = new TextEncoder();
      const allocate = (bytes) => {
        const pointer = engine._malloc(bytes.length + 1);
        if (!pointer) throw new Error("XSLT memory allocation failed.");
        pointers.push(pointer);
        const heap2 = new Uint8Array(engine.wasmMemory.buffer);
        heap2.set(bytes, pointer);
        heap2[pointer + bytes.length] = 0;
        return pointer;
      };
      const xml = encoder.encode(data.xml);
      const style = encoder.encode(data.resource);
      const xmlPointer = allocate(xml);
      const stylePointer = allocate(style);
      const urlPointer = allocate(encoder.encode("stylesheet.xsl"));
      const mimePointer = allocate(new Uint8Array(32));
      const transform = engine.cwrap("transform", "number", Array(7).fill("number"), { async: true });
      const result = await transform(xmlPointer, xml.length, stylePointer, style.length, 0, urlPointer, mimePointer);
      if (!result) throw new Error("The XSLT engine could not transform this document.");
      pointers.push(result);
      if (networkAttempt) throw new Error("The XSLT engine attempted to read a blocked external resource.");
      const heap = new Uint8Array(engine.wasmMemory.buffer);
      if (!Number.isSafeInteger(result) || result < 1 || result >= heap.length) throw new Error("Invalid XSLT result pointer.");
      let end = result;
      const bound = Math.min(heap.length, result + data.maxOutputBytes + 1);
      while (end < bound && heap[end] !== 0) end++;
      if (end === bound) throw new Error("XSLT output exceeds its byte limit.");
      const mime = new TextDecoder().decode(heap.subarray(mimePointer, mimePointer + 32)).split("\0")[0];
      if (!["text/html", "application/xml", "text/xml", "text/plain"].includes(mime)) throw new Error("XSLT returned an unsupported output media type.");
      scope.postMessage({ html: new TextDecoder("utf-8", { fatal: true }).decode(heap.subarray(result, end)), mimeType: mime });
    } catch (error) {
      scope.postMessage({ error: error instanceof Error ? error.message.slice(0, 1024) : "XSLT engine failed." });
    } finally {
      for (const pointer of pointers) engine?._free(pointer);
    }
  };
}
function runXsdWorker() {
  const scope = globalThis;
  const deny = () => {
    throw new Error("External XML resources are disabled.");
  };
  Object.defineProperty(globalThis, "fetch", { value: async () => deny(), writable: false, configurable: false });
  for (const name of ["XMLHttpRequest", "WebSocket", "EventSource", "importScripts"]) {
    Object.defineProperty(globalThis, name, { value: deny, writable: false, configurable: false });
  }
  scope.onmessage = async ({ data }) => {
    let errors = "";
    try {
      if (!data.wasm || !WebAssembly.validate(data.wasm)) {
        throw new Error("Invalid XML Schema WASM binary.");
      }
      await Module({
        inputFiles: [
          { fileName: "input.xml", contents: data.xml },
          { fileName: "schema.xsd", contents: data.resource }
        ],
        arguments: ["--nonet", "--noout", "--schema", "schema.xsd", "input.xml"],
        wasmBinary: data.wasm,
        wasmMemory: new WebAssembly.Memory({ initial: 256, maximum: 1024 }),
        print: () => void 0,
        printErr: (message) => {
          errors = (errors + message + "\n").slice(0, 8192);
        },
        onExit: (exitCode) => {
          if (![0, 3, 4].includes(exitCode)) scope.postMessage({ error: errors || "XML Schema engine failed." });
          else scope.postMessage({ valid: exitCode === 0, message: errors });
        },
        onAbort: () => scope.postMessage({ error: "XML Schema engine exhausted its memory or aborted." })
      });
    } catch (error) {
      scope.postMessage({ error: error instanceof Error ? error.message.slice(0, 1024) : "XML Schema engine failed." });
    }
  };
}
async function runWorker(source, bootstrap, task, signal, module) {
  checkXmlAbort(signal);
  if (typeof Worker === "undefined") throw new XmlProfileError("engine-error", "XML profiles require Web Workers.");
  const memoryGuard = module ? "" : `
;globalThis.__fileViewerLimitXmlWasmMemory = (${limitXmlWasmMemory.toString()});
`;
  const blobUrl = URL.createObjectURL(new Blob([source, memoryGuard, "\n;(", bootstrap.toString(), ")();"], { type: "text/javascript" }));
  let worker;
  let abort;
  try {
    worker = new Worker(blobUrl, { type: module ? "module" : "classic", name: module ? "file-viewer-xsd" : "file-viewer-xslt" });
    return await new Promise((resolve, reject) => {
      abort = () => {
        try {
          checkXmlAbort(signal);
        } catch (error) {
          reject(error);
        }
      };
      signal.addEventListener("abort", abort, { once: true });
      worker.onmessage = ({ data }) => {
        if (data?.error) reject(new XmlProfileError(module ? "engine-error" : "transform-error", data.error));
        else if (module ? typeof data?.valid === "boolean" : typeof data?.html === "string") resolve(data);
        else reject(new XmlProfileError("engine-error", "Invalid XML worker response."));
      };
      worker.onerror = (event) => {
        event.preventDefault();
        reject(new XmlProfileError("engine-error", `XML worker failed to load or execute: ${event.message?.slice(0, 1024) || "unknown worker error"}`));
      };
      worker.onmessageerror = () => reject(new XmlProfileError("engine-error", "Invalid XML worker message."));
      checkXmlAbort(signal);
      worker.postMessage(task);
    });
  } finally {
    if (abort) signal.removeEventListener("abort", abort);
    worker?.terminate();
    URL.revokeObjectURL(blobUrl);
  }
}
function validateXmlWithWasm(source, wasm, xml, schema, signal) {
  return runWorker(source, runXsdWorker, { xml, resource: schema, wasm, maxOutputBytes: 0 }, signal, true);
}
function transformXmlWithWasm(source, xml, stylesheet, maxOutputBytes, signal) {
  return runWorker(source, runXsltWorker, { xml, resource: stylesheet, maxOutputBytes }, signal, false);
}

// packages/renderers/text/src/entry.ts
var XML_LIMITS = Object.freeze({
  maxXmlBytes: 4 * 1024 * 1024,
  maxResourceBytes: 2 * 1024 * 1024,
  maxOutputBytes: 4 * 1024 * 1024,
  runtimeBytes: 2 * 1024 * 1024,
  timeoutMs: 15e3
});
function capped(value, maximum, minimum = 1) {
  if (value === void 0) return maximum;
  if (!Number.isSafeInteger(value) || value < minimum) throw new Error("Invalid XML processing limit.");
  return Math.min(value, maximum);
}
async function renderXml(buffer, target, context) {
  const documentRef = target.ownerDocument;
  const options = context.options?.xml;
  const limits = {
    xml: capped(options?.limits?.maxXmlBytes, XML_LIMITS.maxXmlBytes),
    resource: capped(options?.limits?.maxResourceBytes, XML_LIMITS.maxResourceBytes),
    output: capped(options?.limits?.maxOutputBytes, XML_LIMITS.maxOutputBytes),
    timeout: capped(options?.timeoutMs, XML_LIMITS.timeoutMs, 100)
  };
  const lifetime = new AbortController();
  if (context.signal?.aborted) lifetime.abort();
  checkXmlAbort(lifetime.signal);
  if (buffer.byteLength > limits.xml) throw new Error("XML exceeds its processing byte limit.");
  const source = decodeFileViewerTextBuffer(buffer).text;
  if (new TextEncoder().encode(source).length > limits.xml) throw new Error("Decoded XML exceeds its processing byte limit.");
  parseSafeXml(source, documentRef, "xml");
  const root = documentRef.createElement("section");
  root.className = "xml-tools";
  const title = documentRef.createElement("h2");
  title.textContent = "XML validation and transformation";
  const info = documentRef.createElement("p");
  info.textContent = "Choose a local XSD schema or XSLT 1.0 stylesheet. External resources are disabled. The original XML remains unchanged.";
  root.append(title, info);
  const status = documentRef.createElement("pre");
  status.className = "xml-status";
  status.hidden = true;
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  const actions = documentRef.createElement("div");
  actions.className = "xml-actions";
  const output = documentRef.createElement("section");
  output.className = "xml-output";
  const buttons = [];
  const inputs = [];
  const resources = /* @__PURE__ */ new Map();
  let active;
  let revision = 0;
  let stopped = false;
  let outputUrl;
  const cancel = documentRef.createElement("button");
  cancel.type = "button";
  cancel.textContent = "Cancel";
  cancel.disabled = true;
  cancel.addEventListener("click", () => active?.abort());
  function clearOutput() {
    if (outputUrl) URL.revokeObjectURL(outputUrl);
    outputUrl = void 0;
    output.replaceChildren();
  }
  function show(value) {
    if (!stopped) {
      status.hidden = false;
      status.textContent = value.slice(0, 16384);
    }
  }
  function busy(value) {
    for (const button of buttons) button.disabled = value;
    cancel.disabled = !value;
    root.setAttribute("aria-busy", String(value));
  }
  function resourceText(value) {
    if (value.length > limits.resource || new TextEncoder().encode(value).length > limits.resource) {
      throw new Error("Schema or stylesheet exceeds its processing byte limit.");
    }
    return value;
  }
  for (const [kind, label, accept] of [["xsd", "XML Schema", ".xsd"], ["xslt", "XSLT stylesheet", ".xsl,.xslt"]]) {
    const box = documentRef.createElement("label");
    box.className = "xml-resource";
    box.append(documentRef.createTextNode(label));
    const input = documentRef.createElement("input");
    input.type = "file";
    input.accept = accept;
    input.setAttribute("aria-label", `Choose ${label}`);
    const textarea = documentRef.createElement("textarea");
    textarea.setAttribute("aria-label", label);
    textarea.placeholder = `Paste ${label} or choose a file`;
    textarea.maxLength = limits.resource;
    let fileRevision = 0;
    const update = (value) => {
      revision++;
      active?.abort();
      clearOutput();
      resources.delete(kind);
      status.hidden = true;
      try {
        resources.set(kind, resourceText(value));
      } catch (error) {
        show(error instanceof Error ? error.message : String(error));
      }
    };
    textarea.addEventListener("input", () => {
      fileRevision++;
      update(textarea.value);
    });
    input.addEventListener("change", async () => {
      const file = input.files?.[0];
      const token = ++fileRevision;
      if (!file || stopped) return;
      update("");
      try {
        if (file.size > limits.resource) throw new Error("Schema or stylesheet exceeds its processing byte limit.");
        const value = resourceText(decodeFileViewerTextBuffer(await file.arrayBuffer()).text);
        if (stopped || token !== fileRevision) return;
        textarea.value = value;
        update(value);
      } catch (error) {
        if (!stopped && token === fileRevision) show(error instanceof Error ? error.message : String(error));
      }
    });
    inputs.push(input);
    box.append(input, textarea);
    root.append(box);
  }
  async function runtime(name, signal) {
    const url = sameOriginXmlUrl(name, import.meta.url, new URL(documentRef.URL).origin);
    return fetchXmlBytes(url, XML_LIMITS.runtimeBytes, signal);
  }
  async function run(kind) {
    if (active || stopped || lifetime.signal.aborted) return;
    const resource = resources.get(kind) || "";
    if (!resource.trim()) {
      show(`Choose or paste an ${kind.toUpperCase()} resource first.`);
      return;
    }
    const controller = new AbortController();
    const token = ++revision;
    active = controller;
    const abort = () => controller.abort();
    lifetime.signal.addEventListener("abort", abort, { once: true });
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, limits.timeout);
    busy(true);
    clearOutput();
    show("Processing locally\u2026");
    try {
      parseSafeXml(resourceText(resource), documentRef, kind);
      if (kind === "xsd") {
        const [module, wasm] = await Promise.all([
          runtime("./xmllint-browser.mjs", controller.signal),
          runtime("./xmllint.wasm", controller.signal)
        ]);
        const result = await validateXmlWithWasm(new TextDecoder().decode(module), wasm, xmlEngineText(source), xmlEngineText(resource), controller.signal);
        checkXmlAbort(controller.signal);
        if (token !== revision || stopped) return;
        show(result.valid ? "Valid: the XML conforms to the selected schema." : `Invalid XML:
${result.message || "Schema validation failed."}`);
      } else {
        const module = await runtime("./xslt-wasm.js", controller.signal);
        const result = await transformXmlWithWasm(new TextDecoder().decode(module), xmlEngineText(source), xmlEngineText(resource), limits.output, controller.signal);
        checkXmlAbort(controller.signal);
        if (token !== revision || stopped) return;
        if (typeof result.html !== "string") throw new Error("The stylesheet produced no output.");
        const heading = documentRef.createElement("h3");
        heading.textContent = "Output source";
        const pre = documentRef.createElement("pre");
        pre.dataset.xmlOutput = result.mimeType || "application/xml";
        pre.textContent = result.html;
        output.append(heading, pre);
        if (result.mimeType === "text/html") {
          const frame = documentRef.createElement("iframe");
          frame.title = "Transformed XML preview";
          frame.setAttribute("sandbox", "");
          frame.setAttribute("referrerpolicy", "no-referrer");
          const sanitized = purify_default.sanitize(result.html, {
            FORBID_TAGS: ["script", "iframe", "object", "embed", "form", "input", "button", "textarea", "select", "option", "optgroup", "datalist", "base", "link", "meta"],
            FORBID_ATTR: ["srcset", "href", "xlink:href", "action", "formaction", "target", "download"]
          });
          const page = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; object-src 'none'; base-uri 'none'; form-action 'none'"></head><body>${sanitized}</body></html>`;
          outputUrl = URL.createObjectURL(new Blob([page], { type: "text/html" }));
          frame.src = outputUrl;
          output.append(frame);
          show("Transformation complete. Original output and a script-free HTML preview are shown.");
        } else {
          show("Transformation complete. The original XML or text output is shown as source.");
        }
        context.onProgressiveRender?.();
      }
    } catch (error) {
      if (token === revision) show(controller.signal.aborted ? timedOut ? "Processing exceeded its time limit and was stopped." : "Processing cancelled." : error instanceof Error ? error.message : String(error));
    } finally {
      clearTimeout(timeout);
      lifetime.signal.removeEventListener("abort", abort);
      if (active === controller) active = void 0;
      if (!stopped) busy(false);
    }
  }
  for (const [kind, label] of [["xsd", "Validate with XSD"], ["xslt", "Transform with XSLT"]]) {
    const button = documentRef.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.addEventListener("click", () => void run(kind));
    buttons.push(button);
    actions.append(button);
  }
  actions.append(cancel);
  root.append(actions, status, output);
  target.replaceChildren(root);
  const destroy = () => {
    if (stopped) return;
    stopped = true;
    revision++;
    lifetime.abort();
    active?.abort();
    clearOutput();
    resources.clear();
    inputs.forEach((input) => {
      input.value = "";
    });
    context.signal?.removeEventListener("abort", destroy);
    target.replaceChildren();
  };
  context.signal?.addEventListener("abort", destroy, { once: true });
  if (context.signal?.aborted) {
    destroy();
    checkXmlAbort(lifetime.signal);
  }
  return { $el: root, destroy };
}
var entry_default = renderXml;
export {
  XML_LIMITS,
  entry_default as default,
  renderXml
};
