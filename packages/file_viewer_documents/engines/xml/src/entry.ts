// SPDX-License-Identifier: Apache-2.0
// CrispCloud adapter, 2026-11-13. Uses the selected Apache File Viewer XML
// engines at d264009; original engine grants and modifications are in UPSTREAM.md.
import {decodeFileViewerTextBuffer, type FileRenderContext} from '@file-viewer/core';
import DOMPurify from 'dompurify';
import {validateXmlWithWasm, transformXmlWithWasm} from './xmlEngines.js';
import {checkXmlAbort, fetchXmlBytes, parseSafeXml, sameOriginXmlUrl, xmlEngineText} from './xmlSafety.js';

export const XML_LIMITS = Object.freeze({
  maxXmlBytes: 4 * 1024 * 1024,
  maxResourceBytes: 2 * 1024 * 1024,
  maxOutputBytes: 4 * 1024 * 1024,
  runtimeBytes: 2 * 1024 * 1024,
  timeoutMs: 15000,
});

function capped(value: number | undefined, maximum: number, minimum = 1): number {
  if (value === undefined) return maximum;
  if (!Number.isSafeInteger(value) || value < minimum) throw new Error('Invalid XML processing limit.');
  return Math.min(value, maximum);
}

export async function renderXml(buffer: ArrayBuffer, target: HTMLDivElement, context: FileRenderContext) {
  const documentRef = target.ownerDocument;
  const options = context.options?.xml;
  const limits = {
    xml: capped(options?.limits?.maxXmlBytes, XML_LIMITS.maxXmlBytes),
    resource: capped(options?.limits?.maxResourceBytes, XML_LIMITS.maxResourceBytes),
    output: capped(options?.limits?.maxOutputBytes, XML_LIMITS.maxOutputBytes),
    timeout: capped(options?.timeoutMs, XML_LIMITS.timeoutMs, 100),
  };
  const lifetime = new AbortController();
  if (context.signal?.aborted) lifetime.abort();
  checkXmlAbort(lifetime.signal);
  if (buffer.byteLength > limits.xml) throw new Error('XML exceeds its processing byte limit.');
  const source = decodeFileViewerTextBuffer(buffer).text;
  if (new TextEncoder().encode(source).length > limits.xml) throw new Error('Decoded XML exceeds its processing byte limit.');
  parseSafeXml(source, documentRef, 'xml');

  const root = documentRef.createElement('section');
  root.className = 'xml-tools';
  const title = documentRef.createElement('h2');
  title.textContent = 'XML validation and transformation';
  const info = documentRef.createElement('p');
  info.textContent = 'Choose a local XSD schema or XSLT 1.0 stylesheet. External resources are disabled. The original XML remains unchanged.';
  root.append(title, info);
  const status = documentRef.createElement('pre');
  status.className = 'xml-status';
  status.hidden = true;
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  const actions = documentRef.createElement('div');
  actions.className = 'xml-actions';
  const output = documentRef.createElement('section');
  output.className = 'xml-output';
  const buttons: HTMLButtonElement[] = [];
  const inputs: HTMLInputElement[] = [];
  const resources = new Map<'xsd' | 'xslt', string>();
  let active: AbortController | undefined;
  let revision = 0;
  let stopped = false;
  let outputUrl: string | undefined;
  const cancel = documentRef.createElement('button');
  cancel.type = 'button';
  cancel.textContent = 'Cancel';
  cancel.disabled = true;
  cancel.addEventListener('click', () => active?.abort());

  function clearOutput() {
    if (outputUrl) URL.revokeObjectURL(outputUrl);
    outputUrl = undefined;
    output.replaceChildren();
  }
  function show(value: string) {
    if (!stopped) {
      status.hidden = false;
      status.textContent = value.slice(0, 16384);
    }
  }
  function busy(value: boolean) {
    for (const button of buttons) button.disabled = value;
    cancel.disabled = !value;
    root.setAttribute('aria-busy', String(value));
  }
  function resourceText(value: string) {
    if (value.length > limits.resource || new TextEncoder().encode(value).length > limits.resource) {
      throw new Error('Schema or stylesheet exceeds its processing byte limit.');
    }
    return value;
  }

  for (const [kind, label, accept] of [['xsd', 'XML Schema', '.xsd'], ['xslt', 'XSLT stylesheet', '.xsl,.xslt']] as const) {
    const box = documentRef.createElement('label');
    box.className = 'xml-resource';
    box.append(documentRef.createTextNode(label));
    const input = documentRef.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.setAttribute('aria-label', `Choose ${label}`);
    const textarea = documentRef.createElement('textarea');
    textarea.setAttribute('aria-label', label);
    textarea.placeholder = `Paste ${label} or choose a file`;
    textarea.maxLength = limits.resource;
    let fileRevision = 0;
    const update = (value: string) => {
      revision++;
      active?.abort();
      clearOutput();
      resources.delete(kind);
      status.hidden = true;
      try { resources.set(kind, resourceText(value)); }
      catch (error) { show(error instanceof Error ? error.message : String(error)); }
    };
    textarea.addEventListener('input', () => { fileRevision++; update(textarea.value); });
    input.addEventListener('change', async () => {
      const file = input.files?.[0];
      const token = ++fileRevision;
      if (!file || stopped) return;
      update('');
      try {
        if (file.size > limits.resource) throw new Error('Schema or stylesheet exceeds its processing byte limit.');
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

  async function runtime(name: string, signal: AbortSignal) {
    const url = sameOriginXmlUrl(name, import.meta.url, new URL(documentRef.URL).origin);
    return fetchXmlBytes(url, XML_LIMITS.runtimeBytes, signal);
  }

  async function run(kind: 'xsd' | 'xslt') {
    if (active || stopped || lifetime.signal.aborted) return;
    const resource = resources.get(kind) || '';
    if (!resource.trim()) { show(`Choose or paste an ${kind.toUpperCase()} resource first.`); return; }
    const controller = new AbortController();
    const token = ++revision;
    active = controller;
    const abort = () => controller.abort();
    lifetime.signal.addEventListener('abort', abort, {once: true});
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; controller.abort(); }, limits.timeout);
    busy(true);
    clearOutput();
    show('Processing locally…');
    try {
      parseSafeXml(resourceText(resource), documentRef, kind);
      if (kind === 'xsd') {
        const [module, wasm] = await Promise.all([
          runtime('./xmllint-browser.mjs', controller.signal), runtime('./xmllint.wasm', controller.signal),
        ]);
        const result = await validateXmlWithWasm(new TextDecoder().decode(module), wasm, xmlEngineText(source), xmlEngineText(resource), controller.signal);
        checkXmlAbort(controller.signal);
        if (token !== revision || stopped) return;
        show(result.valid ? 'Valid: the XML conforms to the selected schema.' : `Invalid XML:\n${result.message || 'Schema validation failed.'}`);
      } else {
        const module = await runtime('./xslt-wasm.js', controller.signal);
        const result = await transformXmlWithWasm(new TextDecoder().decode(module), xmlEngineText(source), xmlEngineText(resource), limits.output, controller.signal);
        checkXmlAbort(controller.signal);
        if (token !== revision || stopped) return;
        if (typeof result.html !== 'string') throw new Error('The stylesheet produced no output.');
        const heading = documentRef.createElement('h3');
        heading.textContent = 'Output source';
        const pre = documentRef.createElement('pre');
        pre.dataset.xmlOutput = result.mimeType || 'application/xml';
        pre.textContent = result.html;
        output.append(heading, pre);
        if (result.mimeType === 'text/html') {
          const frame = documentRef.createElement('iframe');
          frame.title = 'Transformed XML preview';
          frame.setAttribute('sandbox', '');
          frame.setAttribute('referrerpolicy', 'no-referrer');
          // Navigation is not restricted by default-src: remove links too, so
          // an inert preview cannot navigate its own frame to a remote page.
          const sanitized = DOMPurify.sanitize(result.html, {
            FORBID_TAGS: ['script', 'iframe', 'object', 'embed', 'form', 'base', 'link', 'meta'],
            FORBID_ATTR: ['srcset', 'href', 'xlink:href', 'action', 'formaction', 'target', 'download'],
          });
          const page = `<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; object-src 'none'; base-uri 'none'; form-action 'none'"></head><body>${sanitized}</body></html>`;
          outputUrl = URL.createObjectURL(new Blob([page], {type: 'text/html'}));
          frame.src = outputUrl;
          output.append(frame);
          show('Transformation complete. Original output and a script-free HTML preview are shown.');
        } else {
          show('Transformation complete. The original XML or text output is shown as source.');
        }
        context.onProgressiveRender?.();
      }
    } catch (error) {
      if (token === revision) show(controller.signal.aborted
        ? timedOut ? 'Processing exceeded its time limit and was stopped.' : 'Processing cancelled.'
        : error instanceof Error ? error.message : String(error));
    } finally {
      clearTimeout(timeout);
      lifetime.signal.removeEventListener('abort', abort);
      if (active === controller) active = undefined;
      if (!stopped) busy(false);
    }
  }

  for (const [kind, label] of [['xsd', 'Validate with XSD'], ['xslt', 'Transform with XSLT']] as const) {
    const button = documentRef.createElement('button');
    button.type = 'button';
    button.textContent = label;
    button.addEventListener('click', () => void run(kind));
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
    inputs.forEach(input => { input.value = ''; });
    context.signal?.removeEventListener('abort', destroy);
    target.replaceChildren();
  };
  context.signal?.addEventListener('abort', destroy, {once: true});
  if (context.signal?.aborted) { destroy(); checkXmlAbort(lifetime.signal); }
  return {$el: root, destroy};
}

export default renderXml;
