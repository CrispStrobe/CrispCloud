import type { FileRenderContext } from '@file-viewer/core';
import {createDocumentFonts, validateDocumentFonts, type DocumentFonts, type DocumentFontContext} from './fonts.js';

const channel = 'crisp-document-v1';
const session = location.hash.slice(1);
const target = document.querySelector<HTMLDivElement>('#document')!;
const kinds = new Set(['wordperfect', 'chm', 'spreadsheet', 'ppt', 'postscript', 'xml']);
let bytes: Uint8Array | undefined;
let received = 0;
let metadata: Record<string, unknown> | undefined;
let instance: any;
let fonts: DocumentFonts | undefined;
let controller: AbortController | undefined;
let opening = false;
let closed = false;

function disposeInstance() {
  const old = instance;
  instance = undefined;
  if (typeof old?.unmount === 'function') old.unmount();
  else old?.destroy?.();
  fonts?.dispose();
  fonts = undefined;
}

function fontDiagnostic(message: string) {
  if (closed) return;
  let notice = document.querySelector<HTMLElement>('.document-font-warning');
  if (!notice) {
    notice = document.createElement('aside');
    notice.className = 'document-font-warning';
    notice.setAttribute('role', 'status');
    Object.assign(notice.style, {padding: '10px 16px', background: '#fff8dc', color: '#422e00', font: '14px/1.5 system-ui,sans-serif', maxHeight: '96px', overflow: 'auto', flex: 'none'});
    target.before(notice);
    Object.assign(document.body.style, {display: 'flex', flexDirection: 'column'});
    Object.assign(target.style, {flex: '1', height: 'auto', minHeight: '0'});
  }
  notice.textContent = [notice.textContent, message].filter(Boolean).join(' ').slice(0, 2048);
  emit('diagnostic', {code: 'font-fallback', message});
}

function appearance(value: Record<string, unknown>) {
  document.documentElement.lang = String(value.locale || 'en').slice(0, 64);
  document.body.dataset.dark = String(value.dark === true);
  document.body.dataset.viewerTheme = value.dark === true ? 'dark' : 'light';
  target.style.zoom = String(Math.min(3, Math.max(.5, Number(value.fontScale) || 1)));
}

function emit(type: string, values: Record<string, unknown> = {}) {
  const message = JSON.stringify({channel, session, type, ...values});
  const host = window as any;
  if (host.CrispDocumentMessage?.postMessage) host.CrispDocumentMessage.postMessage(message);
  else if (host.flutter_inappwebview?.callHandler) host.flutter_inappwebview.callHandler('CrispDocumentMessage', message);
  else if (window.parent !== window) window.parent.postMessage(message, location.origin);
}

function fail(error: unknown) {
  if (closed) return;
  controller?.abort();
  disposeInstance();
  bytes = undefined;
  const message = error instanceof Error ? error.message : String(error);
  target.replaceChildren();
  const notice = document.createElement('p');
  notice.className = 'document-error';
  notice.textContent = message.slice(0, 2048);
  target.append(notice);
  emit('error', {message: notice.textContent});
}

async function open() {
  if (opening || !metadata || !bytes || received !== bytes.length) throw new Error('The document transfer is incomplete.');
  opening = true;
  controller = new AbortController();
  appearance(metadata);
  if (['wordperfect', 'spreadsheet', 'ppt'].includes(String(metadata.kind)) && Array.isArray(metadata.fonts) && metadata.fonts.length) {
    fonts = createDocumentFonts(validateDocumentFonts(metadata.fonts, location.href), document, controller.signal, fontDiagnostic);
  }
  const context = {
    filename: String(metadata.filename), signal: controller.signal,
    crispFonts: fonts,
    options: {
      locale: metadata.locale, theme: metadata.dark === true ? 'dark' : 'light',
      wordPerfect: {
        useWorker: true,
        workerUrl: new URL('./wordperfect.worker.js', import.meta.url).href,
        wasmUrl: new URL('./libwpd.wasm', import.meta.url).href,
      },
      chm: {
        workerUrl: new URL('./chm.worker.js', import.meta.url).href,
        wasmModuleUrl: new URL('./chm_wasm.js', import.meta.url).href,
        wasmUrl: new URL('./chm_wasm_bg.wasm', import.meta.url).href,
      },
    },
  } as FileRenderContext & DocumentFontContext;
  const input = bytes.buffer;
  bytes = undefined;
  switch (metadata.kind) {
    case 'wordperfect': instance = await (await import('@crisp/wordperfect')).default(input, target, context); break;
    case 'chm': instance = await (await import('@crisp/chm')).default(input, target, context); break;
    case 'spreadsheet': instance = await (await import('@crisp/spreadsheet')).default(input, target, context); break;
    case 'ppt': instance = await (await import('@crisp/ppt')).default(input, target, context); break;
    case 'postscript': instance = await (await import('@crisp/postscript')).default(input, target, context); break;
    case 'xml': instance = await (await import('@crisp/xml')).default(input, target, context); break;
    default: throw new Error('Unsupported document engine.');
  }
  if (closed || controller.signal.aborted) { disposeInstance(); return; }
  emit('loaded');
}

function receive(value: unknown) {
  if (closed || !value || typeof value !== 'object') return;
  const message = value as Record<string, unknown>;
  if (message.channel !== channel || message.session !== session) return;
  try {
    if (message.type === 'begin') {
      if (metadata || opening) throw new Error('A document is already open in this session.');
      if (!kinds.has(String(message.kind)) || typeof message.filename !== 'string' || message.filename.length > 4096) throw new Error('Invalid document request.');
      const limit = (message.kind === 'xml' ? 4 :
        ['ppt', 'spreadsheet', 'postscript'].includes(String(message.kind)) ? 32 : 64) * 1024 * 1024;
      if (!Number.isSafeInteger(message.length) || Number(message.length) < 0 || Number(message.length) > limit) throw new Error('Document exceeds the preview input limit.');
      validateDocumentFonts(message.fonts, location.href);
      metadata = message;
      bytes = new Uint8Array(Number(message.length));
      received = 0;
    } else if (message.type === 'chunk') {
      if (!bytes || opening || message.offset !== received || typeof message.data !== 'string' || message.data.length > 256 * 1024) throw new Error('Invalid document transfer chunk.');
      const chunk = atob(message.data);
      if (chunk.length > bytes.length - received) throw new Error('Document transfer exceeds its declared length.');
      for (let i = 0; i < chunk.length; i++) bytes[received + i] = chunk.charCodeAt(i);
      received += chunk.length;
    } else if (message.type === 'appearance') {
      appearance(message);
    } else if (message.type === 'open') {
      void open().catch(fail);
    }
  } catch (error) { fail(error); }
}

Object.defineProperty(window, 'crispDocumentHost', {value: Object.freeze({receive, ready: () => emit('ready')}), writable: false});
window.addEventListener('message', event => {
  if (event.source !== window.parent || event.origin !== location.origin) return;
  try { receive(typeof event.data === 'string' ? JSON.parse(event.data) : event.data); } catch { /* unrelated message */ }
});
window.addEventListener('pagehide', () => { closed = true; controller?.abort(); disposeInstance(); bytes = undefined; });
window.addEventListener('flutterInAppWebViewPlatformReady', () => emit('ready'));
if (/^[A-Za-z0-9_-]{32,64}$/.test(session)) emit('ready');
