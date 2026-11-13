import {
  assertWordPerfectInput
} from "./chunk-OJSGNLVQ.js";
import "./chunk-PIRHQTI4.js";

// packages/renderers/wordperfect/src/workerClient.ts
var requestId = 0;
var localAsset = (value, fallback) => {
  const base = new URL(document.baseURI);
  const url = new URL(value?.toString() || fallback, base);
  if (url.origin !== base.origin || !["http:", "https:"].includes(url.protocol)) {
    throw new Error("WordPerfect engine assets must use the local viewer origin.");
  }
  return url.href;
};
var parseWordPerfectWithWorker = async (buffer, options, signal) => {
  assertWordPerfectInput(buffer);
  if (signal?.aborted) throw new DOMException("WordPerfect parsing was aborted.", "AbortError");
  if (options?.useWorker === false || typeof Worker === "undefined") {
    throw new Error("The structured WordPerfect preview requires a Web Worker and WebAssembly.");
  }
  const workerUrl = localAsset(options?.workerUrl, "wordperfect.worker.js");
  const wasmUrl = localAsset(options?.wasmUrl, "libwpd.wasm");
  const worker = new Worker(workerUrl, { type: "module", name: "crispcloud-wordperfect" });
  const id = ++requestId;
  const configuredTimeout = options?.workerTimeoutMs;
  const timeoutMs = typeof configuredTimeout === "number" && Number.isFinite(configuredTimeout) ? Math.min(6e4, Math.max(1e3, configuredTimeout)) : 6e4;
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (callback) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      worker.terminate();
      callback();
    };
    const onAbort = () => finish(() => reject(new DOMException("WordPerfect parsing was aborted.", "AbortError")));
    const timer = setTimeout(() => finish(() => reject(new Error(`WordPerfect parsing exceeded ${timeoutMs}ms.`))), timeoutMs);
    worker.addEventListener("message", (event) => {
      if (event.data?.id !== id) return;
      finish(() => event.data.ok && event.data.document ? resolve(event.data.document) : reject(new Error(event.data.error || "WordPerfect Worker failed.")));
    });
    worker.addEventListener("error", (event) => finish(() => reject(new Error(event.message || "WordPerfect Worker failed to load."))));
    worker.addEventListener("messageerror", () => finish(() => reject(new Error("WordPerfect Worker returned an unreadable result."))));
    signal?.addEventListener("abort", onAbort, { once: true });
    if (signal?.aborted) {
      onAbort();
      return;
    }
    try {
      const transferable = buffer.slice(0);
      worker.postMessage({ id, buffer: transferable, wasmUrl }, [transferable]);
    } catch (error) {
      finish(() => reject(error));
    }
  });
};

// packages/renderers/wordperfect/src/wordperfect.ts
var styleText = `
.wpd-viewer{width:100%;height:100%;overflow:auto;padding:28px;background:var(--file-viewer-render-surface-background,#dfe5eb);box-sizing:border-box;color:#1f2937}.wpd-page{width:min(100%,880px);min-height:1040px;margin:0 auto;padding:56px 64px;background:#fff;box-shadow:0 16px 38px rgba(15,23,42,.12);box-sizing:border-box;font:16px/1.85 Georgia,'Times New Roman',serif}.wpd-page p,.wpd-page h1,.wpd-page h2,.wpd-page h3,.wpd-page h4,.wpd-page h5,.wpd-page h6{margin:0 0 13px;white-space:pre-wrap}.wpd-page h1{font-size:1.65em}.wpd-page h2{font-size:1.4em}.wpd-page h3{font-size:1.2em}.wpd-page a{color:#2563eb}.wpd-table{width:100%;margin:18px 0;border-collapse:collapse}.wpd-table td{padding:7px 9px;border:1px solid #94a3b8;vertical-align:top}.wpd-running{margin:0 0 24px;padding:0 0 12px;border-bottom:1px solid #cbd5e1;color:#475569;font-size:.85em}.wpd-footer{margin-top:28px;padding-top:12px;border-top:1px solid #cbd5e1}.wpd-notes{margin-top:28px;padding:16px;background:#f8fafc;border-left:4px solid #94a3b8;font-size:.9em}
[data-viewer-theme='dark'] .wpd-viewer{background:var(--file-viewer-render-surface-background,#0d1117)}.wpd-page{color-scheme:light}.wpd-warning{max-width:880px;margin:0 auto 16px;padding:12px 16px;background:#fff8dc;color:#422e00;border:1px solid #c9ac55;border-radius:6px;font:14px/1.5 system-ui,sans-serif}
@media(max-width:720px){.wpd-viewer{padding:10px}.wpd-page{min-height:0;padding:34px 24px}}
`;
var appendParagraph = (parent, paragraph) => {
  const level = Math.min(6, Math.max(1, paragraph.level || 1));
  const element = document.createElement(paragraph.kind === "heading" ? `h${level}` : "p");
  if (paragraph.list) {
    const marker = paragraph.list.ordered ? `${paragraph.list.counter}. ` : "\u2022 ";
    element.append(document.createTextNode(`${"  ".repeat(Math.max(0, paragraph.list.level - 1))}${marker}`));
  }
  paragraph.runs.forEach((run) => {
    let node = document.createElement("span");
    node.textContent = run.text;
    const styles = new Set(run.styles);
    if (styles.has("bold")) node.style.fontWeight = "700";
    if (styles.has("italic")) node.style.fontStyle = "italic";
    const decorations = [styles.has("underline") ? "underline" : "", styles.has("strikethrough") ? "line-through" : ""].filter(Boolean);
    if (decorations.length) node.style.textDecoration = decorations.join(" ");
    if (styles.has("superscript")) node.style.verticalAlign = "super";
    if (styles.has("subscript")) node.style.verticalAlign = "sub";
    if (run.href) {
      const link = document.createElement("a");
      link.href = run.href;
      link.rel = "noopener noreferrer";
      link.target = "_blank";
      link.appendChild(node);
      node = link;
    }
    element.appendChild(node);
  });
  parent.appendChild(element);
};
var appendTable = (parent, table) => {
  const element = document.createElement("table");
  element.className = "wpd-table";
  table.rows.forEach((row) => {
    const tr = document.createElement("tr");
    row.filter((cell) => !cell.covered).forEach((cell) => {
      const td = document.createElement("td");
      td.textContent = cell.text;
      td.colSpan = Math.max(1, cell.colSpan);
      td.rowSpan = Math.max(1, cell.rowSpan);
      tr.appendChild(td);
    });
    element.appendChild(tr);
  });
  parent.appendChild(element);
};
var appendBlock = (parent, block) => {
  if (block.kind === "table") appendTable(parent, block.table);
  else appendParagraph(parent, block.paragraph);
};
function renderWordPerfectModel(model, target, context) {
  if (context?.signal?.aborted) throw new DOMException("WordPerfect rendering was aborted.", "AbortError");
  const style = document.createElement("style");
  style.textContent = styleText;
  const root = document.createElement("div");
  root.className = "wpd-viewer";
  if (model.warnings.length) {
    const warning = document.createElement("aside");
    warning.className = "wpd-warning";
    warning.setAttribute("role", "status");
    warning.textContent = model.warnings.join(" ");
    root.appendChild(warning);
  }
  const page = document.createElement("article");
  page.className = "wpd-page";
  page.dataset.viewerAnchorId = "wordperfect-body";
  if (model.headerBlocks.length) {
    const header = document.createElement("header");
    header.className = "wpd-running";
    model.headerBlocks.forEach((block) => appendBlock(header, block));
    page.appendChild(header);
  }
  model.blocks.forEach((block) => appendBlock(page, block));
  if (model.noteBlocks.length) {
    const notes = document.createElement("aside");
    notes.className = "wpd-notes";
    model.noteBlocks.forEach((block) => appendBlock(notes, block));
    page.appendChild(notes);
  }
  if (model.footerBlocks.length) {
    const footer = document.createElement("footer");
    footer.className = "wpd-running wpd-footer";
    model.footerBlocks.forEach((block) => appendBlock(footer, block));
    page.appendChild(footer);
  }
  root.appendChild(page);
  target.replaceChildren(style, root);
  context?.registerThumbnailAdapter?.({ getTarget: () => page });
  const unmount = () => {
    context?.signal?.removeEventListener("abort", unmount);
    context?.registerThumbnailAdapter?.(null);
    if (root.parentNode === target) target.replaceChildren();
  };
  context?.signal?.addEventListener("abort", unmount, { once: true });
  return { $el: target, unmount, destroy: unmount };
}
async function renderWordPerfect(buffer, target, _type, context) {
  assertWordPerfectInput(buffer);
  const model = await parseWordPerfectWithWorker(buffer, context?.options?.wordPerfect, context?.signal);
  return renderWordPerfectModel(model, target, context);
}

// packages/renderers/wordperfect/src/entry.ts
var renderWordPerfect2 = (buffer, target, context) => renderWordPerfect(buffer, target, "wpd", context);
var entry_default = renderWordPerfect2;
export {
  entry_default as default,
  renderWordPerfect2 as renderWordPerfect
};
