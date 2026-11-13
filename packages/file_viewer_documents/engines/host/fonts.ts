// SPDX-License-Identifier: MIT
// Existing application fonts, scoped to one isolated document preview.
export interface DocumentFontDescriptor {
  family: string;
  aliases: string[];
  weight: number;
  italic: boolean;
  url: string;
}

export interface DocumentFontRequest {
  family?: string;
  weight?: number;
  italic?: boolean;
  text?: string;
}

export interface PreparedDocumentFonts {
  /** Standalone SVG images do not inherit the document's loaded FontFace set. */
  embedSvg(svg: string): string;
}

export interface DocumentFonts {
  prepare(requests: readonly DocumentFontRequest[], fallback: string): Promise<PreparedDocumentFonts>;
  prepareModel(model: unknown, fallback: string): Promise<PreparedDocumentFonts>;
  familyCss(requested: string | undefined, fallback: string): string;
  dispose(): void;
}

/** An optional capability; upstream contexts and standalone engines still work. */
export interface DocumentFontContext { crispFonts?: DocumentFonts }

const MAX_FACES = 64;
const MAX_FACE_BYTES = 4 * 1024 * 1024;
const MAX_PREVIEW_BYTES = 16 * 1024 * 1024;
const MAX_SVG_FONT_CSS_BYTES = 24 * 1024 * 1024;
const MAX_MODEL_NODES = 200_000;
const LOAD_TIMEOUT_MS = 5_000;
const arabic = /[\u0600-\u06ff\u0750-\u077f\u08a0-\u08ff\ufb50-\ufdff\ufe70-\ufeff]/;
const latin = /[A-Za-z0-9\u00c0-\u052f]/;
const generic = new Set(['serif', 'sans-serif', 'monospace', 'system-ui']);
const cleanName = (value: unknown): value is string => typeof value === 'string' &&
  value.length > 0 && value.length <= 128 && value.trim() === value &&
  !/[\u0000-\u001f\u007f]/.test(value);
const key = (value: string) => value.toLocaleLowerCase('en-US');
const abortError = () => new DOMException('Document font loading was aborted.', 'AbortError');
const quote = (value: string) => JSON.stringify(value);

/** Only the exact native session or Flutter app asset route can supply fonts. */
export function validateDocumentFonts(value: unknown, hostHref: string): DocumentFontDescriptor[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > MAX_FACES) throw new Error('Invalid document font catalog.');
  const host = new URL(hostHref);
  const session = host.hash.slice(1);
  const nativePrefix = /^[A-Za-z0-9_-]{32,64}$/.test(session) &&
    host.pathname === `/${session}/index.html` ? `/${session}/fonts/` : undefined;
  const webSuffix = 'assets/packages/file_viewer_documents/assets/index.html';
  const webPrefix = host.pathname.endsWith(webSuffix)
    ? host.pathname.slice(0, -webSuffix.length) + 'assets/' : undefined;
  const seen = new Set<string>();
  return value.map(raw => {
    if (!raw || typeof raw !== 'object' || !cleanName(raw.family) ||
        !Array.isArray(raw.aliases) || raw.aliases.length > 16 || !raw.aliases.every(cleanName) ||
        !Number.isInteger(raw.weight) || raw.weight < 100 || raw.weight > 900 || raw.weight % 100 !== 0 ||
        typeof raw.italic !== 'boolean' || typeof raw.url !== 'string' || raw.url.length > 2048 ||
        /[%\\\u0000-\u0020\u007f]/.test(raw.url)) throw new Error('Invalid document font descriptor.');
    const url = new URL(raw.url);
    if (!['http:', 'https:'].includes(url.protocol) || url.origin !== host.origin ||
        url.username || url.password || url.search || url.hash || url.href !== raw.url) {
      throw new Error('Document fonts must use the local viewer origin.');
    }
    const native = nativePrefix && url.pathname.startsWith(nativePrefix) &&
      /^\d+\.(?:ttf|otf|woff|woff2)$/.test(url.pathname.slice(nativePrefix.length));
    const asset = webPrefix && url.pathname.startsWith(webPrefix) &&
      /^(?:assets|packages)\/(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*\/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*\.(?:ttf|otf|woff|woff2)$/.test(url.pathname.slice(webPrefix.length));
    if (!native && !asset) throw new Error('Document font URL is outside the allowed asset route.');
    const id = `${key(raw.family)}|${raw.weight}|${raw.italic}`;
    if (seen.has(id)) throw new Error('Duplicate document font face.');
    seen.add(id);
    return {family: raw.family, aliases: [...raw.aliases], weight: raw.weight, italic: raw.italic, url: url.href};
  });
}

/** Parse family lists without treating a quoted comma as a separator. */
export function fontFamilies(value: string | undefined): string[] {
  if (!value || value.length > 2048) return [];
  const trimmed = value.trim();
  const wrapped = (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"));
  if (!value.includes(',') && !wrapped) return cleanName(trimmed) ? [trimmed] : [];
  const names: string[] = [];
  let name = '', quoted = '', escaped = false;
  for (const char of value) {
    if (escaped) { name += char; escaped = false; }
    else if (char === '\\') escaped = true;
    else if (quoted) { if (char === quoted) quoted = ''; else name += char; }
    else if (char === '"' || char === "'") quoted = char;
    else if (char === ',') { if (cleanName(name.trim())) names.push(name.trim()); name = ''; }
    else name += char;
  }
  if (cleanName(name.trim())) names.push(name.trim());
  return names.slice(0, 16);
}

/** The parsed models are already bounded; skip binary image/native payloads. */
export function collectDocumentFontRequests(model: unknown, fallback: string): DocumentFontRequest[] {
  const requests = new Map<string, DocumentFontRequest>();
  const add = (request: DocumentFontRequest) => {
    const id = `${request.family}|${request.weight}|${request.italic}`;
    // Preserve script requirements without retaining/copying whole paragraphs.
    const sample = (requests.get(id)?.text || '') + (request.text || '');
    const text = (latin.test(sample) ? 'A' : '') + (arabic.test(sample) ? 'ا' : '');
    requests.set(id, {...request, text});
    if (request.text && arabic.test(request.text)) {
      const id = `arabic|${request.weight}|${request.italic}`;
      const previous = requests.get(id)?.text || '';
      const arabicRequest = {...request, family: 'Noto Naskh Arabic', text: (latin.test(previous + text) ? 'A' : '') + 'ا'};
      requests.set(id, arabicRequest);
    }
  };
  add({family: fallback, weight: 400, italic: false});
  const stack: Array<{value: unknown; inherited: DocumentFontRequest}> = [
    {value: model, inherited: {family: fallback, weight: 400, italic: false}},
  ];
  const visited = new Set<object>();
  let nodes = 0;
  while (stack.length) {
    if (++nodes > MAX_MODEL_NODES) throw new Error('Document font inspection exceeds its model limit.');
    const {value, inherited} = stack.pop()!;
    if (typeof value === 'string') { if (arabic.test(value)) add({...inherited, text: value}); continue; }
    if (!value || typeof value !== 'object' || ArrayBuffer.isView(value) || value instanceof ArrayBuffer || visited.has(value)) continue;
    visited.add(value);
    if (Array.isArray(value)) {
      for (const child of value) stack.push({value: child, inherited});
      continue;
    }
    const record = value as Record<string, any>;
    const style = record.style && typeof record.style === 'object' ? record.style : record;
    const shorthand = typeof style.font === 'string'
      ? style.font.match(/^(.*?)\d+(?:\.\d+)?(?:px|pt)(?:\/[^\s]+)?\s+(.+)$/) : null;
    const styles = new Set(Array.isArray(record.styles) ? record.styles : []);
    const weight = style.bold !== undefined ? (style.bold ? 700 : 400) :
      style.fontWeight !== undefined ? (/bold/i.test(String(style.fontWeight)) ? 700 : Number(style.fontWeight) || 400) :
      styles.has('bold') || record.kind === 'heading' || shorthand && /\bbold\b|\b[6-9]00\b/.test(shorthand[1]) ? 700 : inherited.weight;
    const italic = style.italic !== undefined ? style.italic === true :
      style.fontStyle !== undefined ? /italic|oblique/.test(style.fontStyle) :
      styles.has('italic') || !!(shorthand && /italic|oblique/.test(shorthand[1])) || inherited.italic;
    const request = {family: typeof style.fontFamily === 'string' ? style.fontFamily : shorthand?.[2] || inherited.family,
      weight, italic, text: typeof record.text === 'string' ? record.text : undefined};
    if (request.text !== undefined || style.fontFamily || style.font || style.fontWeight || style.fontStyle || record.kind === 'heading') add(request);
    for (const [name, child] of Object.entries(record)) {
      if (['assets', 'images', 'metadata', 'sourceText', 'style', 'styles'].includes(name)) continue;
      stack.push({value: child, inherited: request});
    }
  }
  return [...requests.values()];
}

type FontBytes = {bytes: Uint8Array<ArrayBuffer>; dataUrl?: string};
type LoadedFont = {family: string; descriptor: DocumentFontDescriptor; data: FontBytes};

export function createDocumentFonts(
  descriptors: readonly DocumentFontDescriptor[], documentRef: Document, signal: AbortSignal,
  diagnostic: (message: string) => void,
): DocumentFonts {
  const families = new Map<string, DocumentFontDescriptor[]>();
  const aliases = new Map<string, string>();
  for (const descriptor of descriptors) {
    const family = key(descriptor.family);
    const faces = families.get(family) || [];
    faces.push(descriptor); families.set(family, faces);
    aliases.set(family, family);
    for (const alias of descriptor.aliases) aliases.set(key(alias), family);
  }
  const bytes = new Map<string, Promise<FontBytes>>();
  const loaded = new Map<string, Promise<LoadedFont | undefined>>();
  const registered = new Set<FontFace>();
  const pending = new Set<AbortController>();
  const lifetime = new AbortController();
  const warnings = new Set<string>();
  let receivedBytes = 0, disposed = false;
  const check = () => { if (disposed || signal.aborted) throw signal.reason || abortError(); };
  const warn = (message: string) => {
    if (!warnings.has(message) && warnings.size < 8) { warnings.add(message); diagnostic(message); }
  };
  const read = (url: string): Promise<FontBytes> => {
    let result = bytes.get(url);
    if (result) return result;
    result = (async () => {
      check();
      const controller = new AbortController();
      pending.add(controller);
      const abort = () => controller.abort(signal.reason || abortError());
      signal.addEventListener('abort', abort, {once: true});
      const timer = setTimeout(() => controller.abort(new Error('Font loading timed out.')), LOAD_TIMEOUT_MS);
      try {
        const response = await fetch(url, {signal: controller.signal, credentials: 'same-origin', redirect: 'error'});
        if (!response.ok || response.redirected) throw new Error('The bundled font asset is unavailable.');
        if (Number(response.headers.get('content-length')) > MAX_FACE_BYTES) throw new Error('Bundled font exceeds its size limit.');
        const chunks: Uint8Array[] = [];
        let length = 0;
        const accept = (chunk: Uint8Array) => {
          length += chunk.length; receivedBytes += chunk.length;
          if (length > MAX_FACE_BYTES || receivedBytes > MAX_PREVIEW_BYTES) {
            controller.abort(); throw new Error('Bundled fonts exceed the preview memory limit.');
          }
          chunks.push(chunk);
        };
        if (response.body) {
          const reader = response.body.getReader();
          try {
            for (;;) { const chunk = await reader.read(); if (chunk.done) break; accept(chunk.value); }
          } finally { reader.releaseLock(); }
        } else accept(new Uint8Array(await response.arrayBuffer()));
        check();
        const content = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { content.set(chunk, offset); offset += chunk.length; }
        return {bytes: content};
      } finally {
        clearTimeout(timer); pending.delete(controller); signal.removeEventListener('abort', abort);
      }
    })();
    bytes.set(url, result);
    return result;
  };
  const load = (family: string, descriptor: DocumentFontDescriptor): Promise<LoadedFont | undefined> => {
    const id = `${key(family)}|${descriptor.weight}|${descriptor.italic}`;
    let result = loaded.get(id);
    if (result) return result;
    if (loaded.size >= MAX_FACES) { warn('Some document fonts use browser fallback because the preview font limit was reached.'); return Promise.resolve(undefined); }
    result = (async () => {
      try {
        check();
        const data = await read(descriptor.url);
        const FontFaceCtor = documentRef.defaultView?.FontFace || globalThis.FontFace;
        if (!FontFaceCtor || !documentRef.fonts) throw new Error('This browser cannot load document fonts.');
        const face = new FontFaceCtor(quote(family), data.bytes, {weight: String(descriptor.weight), style: descriptor.italic ? 'italic' : 'normal'});
        let timer: ReturnType<typeof setTimeout> | undefined;
        let stop: (() => void) | undefined;
        const abort = new Promise<never>((_, reject) => {
          stop = () => reject(abortError());
          lifetime.signal.addEventListener('abort', stop, {once: true});
          timer = setTimeout(() => reject(new Error('Font decoding timed out.')), LOAD_TIMEOUT_MS);
        });
        try { await Promise.race([face.load(), abort]); }
        finally { clearTimeout(timer); if (stop) lifetime.signal.removeEventListener('abort', stop); }
        check();
        documentRef.fonts.add(face); registered.add(face);
        return {family, descriptor, data};
      } catch (error) {
        check();
        warn(`A bundled font (${descriptor.family}) could not load. Browser fallback may change line breaks.`);
        return undefined;
      }
    })();
    loaded.set(id, result);
    return result;
  };
  const choose = (name: string, request: DocumentFontRequest) => {
    const family = aliases.get(key(name));
    const candidates = family && families.get(family);
    if (!candidates) return undefined;
    return [...candidates].sort((a, b) =>
      (a.italic === !!request.italic ? 0 : 1000) + Math.abs(a.weight - (request.weight || 400)) -
      ((b.italic === !!request.italic ? 0 : 1000) + Math.abs(b.weight - (request.weight || 400))))[0];
  };
  const dataUrl = (font: LoadedFont) => {
    if (!font.data.dataUrl) {
      const chunks: string[] = [];
      // Chunk boundaries are multiples of three, so only the last has padding.
      for (let start = 0; start < font.data.bytes.length; start += 24_576) {
        chunks.push(btoa(String.fromCharCode(...font.data.bytes.subarray(start, start + 24_576))));
      }
      const extension = font.descriptor.url.split('.').pop();
      font.data.dataUrl = `data:font/${extension};base64,${chunks.join('')}`;
    }
    return font.data.dataUrl;
  };
  const prepare = async (requests: readonly DocumentFontRequest[], fallback: string): Promise<PreparedDocumentFonts> => {
    check();
    const selected = new Map<string, Promise<LoadedFont | undefined>>();
    for (const request of requests) {
      const names = fontFamilies(request.family);
      if (!names.length) names.push(fallback);
      const primary = choose(names[0], request);
      if (request.text && arabic.test(request.text)) names.push('Noto Naskh Arabic');
      for (const name of names) {
        const descriptor = choose(name, request);
        if (!descriptor) continue;
        const registerAs = generic.has(key(name)) ? descriptor.family : name;
        selected.set(`${key(registerAs)}|${descriptor.weight}|${descriptor.italic}`, load(registerAs, descriptor));
      }
      if (!primary) {
        warn(`The font “${names[0]}” is not bundled. An installed font or the preview fallback will be used.`);
      }
      // Script fallback must not hide an unknown requested family. Noto Naskh
      // also needs the Latin default when a run contains both writing systems.
      if (!primary || key(primary.family) === 'noto naskh arabic' && request.text && latin.test(request.text)) {
        const descriptor = choose(fallback, request);
        if (descriptor) selected.set(`${key(descriptor.family)}|${descriptor.weight}|${descriptor.italic}`, load(descriptor.family, descriptor));
      }
    }
    const faces = (await Promise.all(selected.values())).filter((face): face is LoadedFont => !!face);
    check();
    return {embedSvg(svg) {
      check();
      if (!faces.length) return svg;
      const rules: string[] = [];
      let length = 0;
      for (const face of faces) {
        const rule = `@font-face{font-family:${quote(face.family)};font-weight:${face.descriptor.weight};font-style:${face.descriptor.italic ? 'italic' : 'normal'};src:url(${quote(dataUrl(face))})}`;
        length += rule.length;
        if (length > MAX_SVG_FONT_CSS_BYTES) {
          warn('Some slide font aliases use browser fallback because the image font limit was reached.');
          break;
        }
        rules.push(rule);
      }
      const css = rules.join('\n');
      // XML escapes keep a document-supplied family name inside the stylesheet.
      const style = `<style>${css.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</style>`;
      return svg.replace(/<svg\b[^>]*>/, opening => opening.endsWith('/>')
        ? opening.slice(0, -2) + '>' + style + '</svg>' : opening + style);
    }};
  };
  const result: DocumentFonts = {
    prepare,
    async prepareModel(model, fallback) {
      try { return await prepare(collectDocumentFontRequests(model, fallback), fallback); }
      catch (error) {
        check();
        warn('Some font details could not be inspected. The preview uses its bundled default font.');
        return prepare([{family: fallback, weight: 400}], fallback);
      }
    },
    familyCss(requested, fallback) {
      const names = fontFamilies(requested).filter(name => !generic.has(key(name)));
      const fallbackFace = choose(fallback, {weight: 400});
      names.push(generic.has(key(fallback)) ? fallbackFace?.family || fallback : fallback, 'Noto Naskh Arabic');
      return [...new Set(names)].map(quote).join(',') + ',sans-serif';
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      lifetime.abort(abortError());
      for (const controller of pending) controller.abort(abortError());
      for (const font of registered) documentRef.fonts?.delete(font);
      pending.clear(); registered.clear(); bytes.clear(); loaded.clear();
      signal.removeEventListener('abort', result.dispose);
    },
  };
  signal.addEventListener('abort', result.dispose, {once: true});
  return result;
}
