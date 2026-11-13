// packages/renderers/chm/src/model.ts
var DEFAULT_CHM_OPTIONS = Object.freeze({
  workerTimeoutMs: 6e4,
  maxArchiveBytes: 64 * 1024 * 1024,
  maxEntries: 2e4,
  maxEntryBytes: 16 * 1024 * 1024,
  maxTotalDecompressedBytes: 128 * 1024 * 1024,
  maxHtmlBytes: 4 * 1024 * 1024,
  maxSearchTopics: 2e3,
  maxSearchResults: 200
});
var MIB = 1024 * 1024;
var CHM_HARD_LIMITS = Object.freeze({
  maxArchiveBytes: 64 * MIB,
  maxEntries: 2e4,
  maxEntryBytes: 16 * MIB,
  maxTotalDecompressedBytes: 128 * MIB,
  maxHtmlBytes: 4 * MIB
});
var finiteLimit = (value, fallback, minimum, maximum = Number.MAX_SAFE_INTEGER) => {
  if (!Number.isFinite(value) || value == null) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.floor(value)));
};
var resolveChmOptions = (options) => ({
  workerTimeoutMs: finiteLimit(options?.workerTimeoutMs, DEFAULT_CHM_OPTIONS.workerTimeoutMs, 1e3, 6e4),
  maxArchiveBytes: finiteLimit(
    options?.maxArchiveBytes,
    DEFAULT_CHM_OPTIONS.maxArchiveBytes,
    1,
    CHM_HARD_LIMITS.maxArchiveBytes
  ),
  maxEntries: finiteLimit(
    options?.maxEntries,
    DEFAULT_CHM_OPTIONS.maxEntries,
    1,
    CHM_HARD_LIMITS.maxEntries
  ),
  maxEntryBytes: finiteLimit(
    options?.maxEntryBytes,
    DEFAULT_CHM_OPTIONS.maxEntryBytes,
    1,
    CHM_HARD_LIMITS.maxEntryBytes
  ),
  maxTotalDecompressedBytes: finiteLimit(
    options?.maxTotalDecompressedBytes,
    DEFAULT_CHM_OPTIONS.maxTotalDecompressedBytes,
    1,
    CHM_HARD_LIMITS.maxTotalDecompressedBytes
  ),
  maxHtmlBytes: finiteLimit(
    options?.maxHtmlBytes,
    DEFAULT_CHM_OPTIONS.maxHtmlBytes,
    1,
    CHM_HARD_LIMITS.maxHtmlBytes
  ),
  maxSearchTopics: finiteLimit(options?.maxSearchTopics, DEFAULT_CHM_OPTIONS.maxSearchTopics, 1, 2e3),
  maxSearchResults: finiteLimit(options?.maxSearchResults, DEFAULT_CHM_OPTIONS.maxSearchResults, 1, 200)
});
var stringValue = (value) => typeof value === "string" ? value : "";
var numberValue = (value) => typeof value === "number" && Number.isFinite(value) ? value : void 0;
var booleanValue = (value) => value === true;
var normalizeTopic = (value) => {
  if (!value || typeof value !== "object") return null;
  const source = value;
  const path = stringValue(source.path || source.local || source.url);
  if (!path) return null;
  return {
    title: stringValue(source.title || source.name) || path,
    path,
    contextId: numberValue(source.contextId ?? source.context_id)
  };
};
var normalizeNavigationNodes = (value) => {
  if (!Array.isArray(value)) return [];
  const roots = [];
  const queue = [];
  for (let index = value.length - 1; index >= 0; index -= 1) {
    queue.push({ source: value[index], target: roots });
  }
  while (queue.length) {
    const current = queue.pop();
    if (!current?.source || typeof current.source !== "object") continue;
    const source = current.source;
    const children = [];
    const node = {
      title: stringValue(source.title || source.name || source.keyword) || stringValue(source.path || source.local),
      path: stringValue(source.path || source.local || source.url) || void 0,
      keyword: stringValue(source.keyword) || void 0,
      children
    };
    current.target.push(node);
    const aliases = Array.isArray(source.locals) ? source.locals.filter((item) => typeof item === "string" && Boolean(item)) : [];
    if (!node.path && aliases.length) node.path = aliases[0];
    for (let index = node.path ? 1 : 0; index < aliases.length; index += 1) {
      children.push({ title: `${node.title} \xB7 ${index + 1}`, path: aliases[index], children: [] });
    }
    const sourceChildren = Array.isArray(source.children) ? source.children : [];
    for (let index = sourceChildren.length - 1; index >= 0; index -= 1) {
      queue.push({ source: sourceChildren[index], target: children });
    }
  }
  return roots;
};
var normalizeChmManifest = (value) => {
  const source = value && typeof value === "object" ? value : {};
  const mergedArchives = source.mergedArchives ?? source.merged_archives;
  const topics = Array.isArray(source.topics) ? source.topics.map(normalizeTopic).filter((topic) => Boolean(topic)) : [];
  return {
    title: stringValue(source.title),
    warnings: Array.isArray(source.warnings) ? source.warnings.filter((item) => typeof item === "string").slice(0, 100).map((item) => item.slice(0, 2048)) : [],
    mergedArchives: Array.isArray(mergedArchives) ? mergedArchives.filter((item) => typeof item === "string").slice(0, 100).map((item) => item.slice(0, 2048)) : [],
    homePath: stringValue(source.homePath ?? source.home_path),
    encoding: stringValue(source.encoding) || "windows-1252",
    language: stringValue(source.language) || void 0,
    topics,
    contents: normalizeNavigationNodes(source.contents ?? source.toc),
    index: normalizeNavigationNodes(source.index ?? source.keywords),
    hasBinaryToc: booleanValue(source.hasBinaryToc ?? source.has_binary_toc),
    hasBinaryIndex: booleanValue(source.hasBinaryIndex ?? source.has_binary_index),
    hasFullTextIndex: booleanValue(source.hasFullTextIndex ?? source.has_full_text_index) || Boolean(source.fullTextIndex && typeof source.fullTextIndex === "object" && source.fullTextIndex.available)
  };
};
var normalizeChmEntries = (value) => {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const source = item;
    const path = stringValue(source.path || source.name);
    if (!path) return [];
    return [{
      path,
      size: numberValue(source.size ?? source.length ?? source.byteLength ?? source.byte_length) ?? 0,
      section: numberValue(source.section)
    }];
  });
};

// packages/renderers/chm/src/security.ts
var CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f]/;
var MAX_CHM_PATH_LENGTH = 4096;
var ABSOLUTE_SCHEME_PATTERN = /^([a-z][a-z0-9+.-]*):/i;
var EXTERNAL_SCHEMES = /* @__PURE__ */ new Set(["http", "https", "mailto", "tel"]);
var BLOCKED_SCHEMES = /* @__PURE__ */ new Set([
  "about",
  "blob",
  "file",
  "ftp",
  "javascript",
  "resource",
  "shell",
  "vbscript"
]);
var MAX_CHM_HTML_TEXT_LENGTH = 16 * 1024 * 1024;
var MAX_CHM_HTML_MARKUP_TOKENS = 1e5;
var MAX_CHM_SVG_TEXT_LENGTH = 8 * 1024 * 1024;
var MAX_CHM_SVG_MARKUP_TOKENS = 5e4;
var MAX_CHM_CSS_TEXT_LENGTH = 4 * 1024 * 1024;
var MAX_CHM_SEARCH_TEXT_LENGTH = 4 * 1024 * 1024;
var createStringBuilder = (maxLength = Number.POSITIVE_INFINITY) => {
  const chunks = [];
  let buffer = "";
  let length = 0;
  const append = (value) => {
    if (!value || length >= maxLength) return;
    const remaining = maxLength - length;
    const next = value.length > remaining ? value.slice(0, remaining) : value;
    length += next.length;
    if (buffer.length + next.length <= 16384) {
      buffer += next;
      return;
    }
    if (buffer) chunks.push(buffer);
    if (next.length > 16384) {
      chunks.push(next);
      buffer = "";
    } else {
      buffer = next;
    }
  };
  return {
    append,
    get length() {
      return length;
    },
    finish: () => {
      if (buffer) chunks.push(buffer);
      return chunks.join("");
    }
  };
};
var assertChmMarkupBudget = (source, maxLength, maxTokens, kind) => {
  if (source.length > maxLength) {
    throw new Error(`CHM_LIMIT_EXCEEDED: ${kind} text exceeds ${maxLength} characters.`);
  }
  let tokens = 0;
  let tagTokens = 0;
  let inTag = false;
  let inTagToken = false;
  let quote = "";
  const maxTagTokens = maxTokens * 3;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (!quote && character === "<") {
      tokens += 1;
      if (tokens > maxTokens) {
        throw new Error(`CHM_LIMIT_EXCEEDED: ${kind} markup exceeds ${maxTokens} tokens.`);
      }
      if (!inTag) {
        inTag = true;
        inTagToken = false;
      }
      continue;
    }
    if (!inTag) continue;
    if (quote) {
      if (character === quote) quote = "";
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      continue;
    }
    if (character === ">") {
      inTag = false;
      inTagToken = false;
      continue;
    }
    if (isAsciiWhitespace(character)) {
      inTagToken = false;
      continue;
    }
    if (!inTagToken) {
      inTagToken = true;
      tagTokens += 1;
      if (tagTokens > maxTagTokens) {
        throw new Error(`CHM_LIMIT_EXCEEDED: ${kind} markup exceeds ${maxTagTokens} tag fields.`);
      }
    }
  }
};
var assertChmSvgSourceSafety = (source) => {
  assertChmMarkupBudget(source, MAX_CHM_SVG_TEXT_LENGTH, MAX_CHM_SVG_MARKUP_TOKENS, "SVG");
  for (let index = 0; index + 2 < source.length; index += 1) {
    if (source[index] !== "<" || source[index + 1] !== "!") continue;
    let cursor = index + 2;
    while (isAsciiWhitespace(source[cursor])) cursor += 1;
    let end = cursor;
    while (end < source.length) {
      const code = source.charCodeAt(end);
      if (!(code >= 65 && code <= 90 || code >= 97 && code <= 122)) break;
      end += 1;
    }
    const keyword = source.slice(cursor, end).toLowerCase();
    if (keyword === "doctype" || keyword === "entity") {
      throw new Error(`CHM_SECURITY_BLOCKED: SVG ${keyword.toUpperCase()} declarations are disabled.`);
    }
  }
};
var safeDecodeURIComponent = (value) => {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
};
var normalizeChmPath = (input) => {
  if (typeof input !== "string" || CONTROL_CHARACTER_PATTERN.test(input)) return null;
  const trimmed = input.trim();
  if (!trimmed || trimmed.length > MAX_CHM_PATH_LENGTH) return null;
  const decoded = safeDecodeURIComponent(trimmed);
  if (/^(?:[a-z]:[\\/]|[\\/]{2})/i.test(decoded)) return null;
  const source = decoded.replace(/\\/g, "/");
  const segments = [];
  for (const segment of source.split("/")) {
    if (!segment || segment === ".") continue;
    if (segment === "..") {
      if (!segments.length) return null;
      segments.pop();
      continue;
    }
    if (CONTROL_CHARACTER_PATTERN.test(segment)) return null;
    segments.push(segment);
  }
  return `/${segments.join("/")}`;
};
var splitReference = (value) => {
  const hashIndex = value.indexOf("#");
  const fragment = hashIndex >= 0 ? safeDecodeURIComponent(value.slice(hashIndex + 1)) : "";
  const withoutFragment = hashIndex >= 0 ? value.slice(0, hashIndex) : value;
  const queryIndex = withoutFragment.indexOf("?");
  return {
    path: queryIndex >= 0 ? withoutFragment.slice(0, queryIndex) : withoutFragment,
    fragment
  };
};
var unwrapCompiledHelpUrl = (value) => {
  const delimiter = value.indexOf("::");
  return delimiter >= 0 ? value.slice(delimiter + 2) : "";
};
var resolveChmReference = (basePath, rawUrl) => {
  if (typeof rawUrl !== "string") return { kind: "blocked" };
  let value = rawUrl.trim();
  if (!value || CONTROL_CHARACTER_PATTERN.test(value)) return { kind: "blocked" };
  if (value.startsWith("#")) {
    return { kind: "fragment", fragment: safeDecodeURIComponent(value.slice(1)) };
  }
  if (value.startsWith("//")) return { kind: "external", url: value };
  const schemeMatch = value.match(ABSOLUTE_SCHEME_PATTERN);
  if (schemeMatch) {
    const scheme = schemeMatch[1].toLowerCase();
    if (scheme === "ms-its" || scheme === "mk" || scheme === "its") {
      value = unwrapCompiledHelpUrl(value);
      if (!value) return { kind: "blocked" };
    } else if (scheme === "data") {
      return /^data:image\/(?:avif|bmp|gif|jpeg|png|webp);/i.test(value) ? { kind: "data", url: value } : { kind: "blocked" };
    } else if (EXTERNAL_SCHEMES.has(scheme)) {
      return { kind: "external", url: value };
    } else if (BLOCKED_SCHEMES.has(scheme) || scheme) {
      return { kind: "blocked" };
    }
  }
  const { path: rawPath, fragment } = splitReference(value);
  if (!rawPath && fragment) return { kind: "fragment", fragment };
  const normalizedBase = normalizeChmPath(basePath) || "/";
  const baseDirectory = normalizedBase.includes("/") ? normalizedBase.slice(0, normalizedBase.lastIndexOf("/") + 1) : "";
  const joined = rawPath.startsWith("/") ? rawPath : `${baseDirectory}${rawPath}`;
  const path = normalizeChmPath(joined);
  if (path == null || path === "/") return { kind: "blocked" };
  return { kind: "internal", path, fragment: fragment || void 0 };
};
var normalizeEncoding = (value) => {
  const normalized = (value || "").trim().toLowerCase().replace(/_/g, "-");
  if (!normalized) return "";
  if (normalized === "utf8") return "utf-8";
  if (normalized === "gbk" || normalized === "cp936") return "gb18030";
  if (normalized === "big5-hkscs") return "big5";
  if (normalized === "shift-jis" || normalized === "sjis" || normalized === "cp932") return "shift_jis";
  if (normalized === "euc-kr" || normalized === "cp949") return "euc-kr";
  if (/^windows-?\d+$/.test(normalized)) return normalized.replace(/^windows-?/, "windows-");
  if (/^cp\d+$/.test(normalized)) return normalized.replace(/^cp/, "windows-");
  return normalized;
};
var sniffHtmlEncoding = (bytes) => {
  const prefix = bytes.subarray(0, Math.min(bytes.byteLength, 8192));
  let ascii = "";
  for (let index = 0; index < prefix.byteLength; index += 1) {
    const value = prefix[index];
    ascii += value >= 32 && value <= 126 ? String.fromCharCode(value) : " ";
  }
  let position = 0;
  while (position < ascii.length) {
    const open = ascii.indexOf("<", position);
    if (open < 0) break;
    if (ascii.startsWith("<!--", open)) {
      const end2 = ascii.indexOf("-->", open + 4);
      position = end2 < 0 ? ascii.length : end2 + 3;
      continue;
    }
    let cursor = open + 1;
    const nameStart = cursor;
    while (isHtmlNameCharacter(ascii[cursor])) cursor += 1;
    const name = ascii.slice(nameStart, cursor).toLowerCase();
    const end = scanHtmlTagEnd(ascii, cursor);
    position = name === "script" || name === "style" ? skipHtmlRawTextElement(ascii, end, name) : end;
    if (name !== "meta") continue;
    const attributes = /* @__PURE__ */ new Map();
    while (cursor < end && ascii[cursor] !== ">") {
      if (!isHtmlNameCharacter(ascii[cursor])) {
        cursor += 1;
        continue;
      }
      const start = cursor;
      while (isHtmlNameCharacter(ascii[cursor])) cursor += 1;
      const attribute = ascii.slice(start, cursor).toLowerCase();
      while (isAsciiWhitespace(ascii[cursor])) cursor += 1;
      if (ascii[cursor] !== "=") continue;
      cursor += 1;
      while (isAsciiWhitespace(ascii[cursor])) cursor += 1;
      const quote = ascii[cursor] === '"' || ascii[cursor] === "'" ? ascii[cursor++] : "";
      const valueStart = cursor;
      if (quote) {
        while (cursor < end && ascii[cursor] !== quote) cursor += 1;
      } else {
        while (cursor < end && !isAsciiWhitespace(ascii[cursor]) && ascii[cursor] !== ">") cursor += 1;
      }
      if (!attributes.has(attribute)) attributes.set(attribute, ascii.slice(valueStart, cursor));
      if (quote && ascii[cursor] === quote) cursor += 1;
    }
    let encoding = attributes.get("charset");
    if (!encoding) {
      for (const parameter of (attributes.get("content") || "").split(";")) {
        const equals = parameter.indexOf("=");
        if (equals >= 0 && parameter.slice(0, equals).trim().toLowerCase() === "charset") {
          encoding = parameter.slice(equals + 1);
          break;
        }
      }
    }
    const token = encoding?.trim().match(/^[^\s"'/>;]+/)?.[0];
    if (token) return normalizeEncoding(token);
  }
  return "";
};
var decodeWith = (bytes, encoding) => {
  try {
    return new TextDecoder(encoding, { fatal: false }).decode(bytes);
  } catch {
    return "";
  }
};
var decodeChmText = (bytes, fallbackEncoding = "windows-1252") => {
  if (bytes.byteLength >= 3 && bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191) {
    return decodeWith(bytes.subarray(3), "utf-8");
  }
  if (bytes.byteLength >= 2 && bytes[0] === 255 && bytes[1] === 254) {
    return decodeWith(bytes.subarray(2), "utf-16le");
  }
  if (bytes.byteLength >= 2 && bytes[0] === 254 && bytes[1] === 255) {
    const swapped = new Uint8Array(bytes.byteLength - 2);
    for (let index = 2; index + 1 < bytes.byteLength; index += 2) {
      swapped[index - 2] = bytes[index + 1];
      swapped[index - 1] = bytes[index];
    }
    return decodeWith(swapped, "utf-16le");
  }
  const candidates = [sniffHtmlEncoding(bytes), normalizeEncoding(fallbackEncoding), "utf-8", "windows-1252"];
  for (const encoding of candidates) {
    if (!encoding) continue;
    const decoded = decodeWith(bytes, encoding);
    if (decoded) return decoded.replace(/^\ufeff/, "");
  }
  return "";
};
var isAsciiWhitespace = (character) => character === " " || character === "	" || character === "\n" || character === "\f" || character === "\r";
var isHtmlNameCharacter = (character) => {
  if (!character) return false;
  const code = character.charCodeAt(0);
  return code >= 48 && code <= 57 || code >= 65 && code <= 90 || code >= 97 && code <= 122 || character === ":" || character === "_" || character === "-";
};
var startsWithAsciiCaseInsensitive = (source, index, expected) => {
  if (index + expected.length > source.length) return false;
  for (let offset = 0; offset < expected.length; offset += 1) {
    const actual = source.charCodeAt(index + offset);
    const wanted = expected.charCodeAt(offset);
    const folded = actual >= 65 && actual <= 90 ? actual + 32 : actual;
    if (folded !== wanted) return false;
  }
  return true;
};
var scanHtmlTagEnd = (source, start) => {
  let index = start;
  let quote = "";
  while (index < source.length) {
    const character = source[index];
    if (quote) {
      if (character === quote) quote = "";
    } else if (character === '"' || character === "'") {
      quote = character;
    } else if (character === ">") {
      return index + 1;
    }
    index += 1;
  }
  return source.length;
};
var skipHtmlRawTextElement = (source, start, name) => {
  let index = start;
  while (index < source.length) {
    if (source[index] === "<" && source[index + 1] === "/" && startsWithAsciiCaseInsensitive(source, index + 2, name) && !isHtmlNameCharacter(source[index + 2 + name.length])) {
      return scanHtmlTagEnd(source, index + 2 + name.length);
    }
    index += 1;
  }
  return source.length;
};
var decodeSearchEntity = (source, index) => {
  let end = index + 1;
  const limit = Math.min(source.length, index + 13);
  while (end < limit && source[end] !== ";") {
    if (source[end] === "&" || source[end] === "<" || isAsciiWhitespace(source[end])) return null;
    end += 1;
  }
  if (end >= limit || source[end] !== ";") return null;
  const entity = source.slice(index + 1, end).toLowerCase();
  const named = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: '"'
  };
  if (named[entity] != null) return { end: end + 1, value: named[entity] };
  const numeric = entity.startsWith("#x") ? Number.parseInt(entity.slice(2), 16) : entity.startsWith("#") ? Number.parseInt(entity.slice(1), 10) : Number.NaN;
  if (!Number.isFinite(numeric) || numeric <= 0 || numeric > 1114111 || numeric >= 55296 && numeric <= 57343) {
    return null;
  }
  return { end: end + 1, value: String.fromCodePoint(numeric) };
};
var extractChmSearchText = (html, maxOutputLength = MAX_CHM_SEARCH_TEXT_LENGTH) => {
  const output = createStringBuilder(Math.max(0, maxOutputLength));
  let index = 0;
  let pendingSpace = false;
  const appendText = (value) => {
    if (!value) return;
    if (isAsciiWhitespace(value)) {
      pendingSpace = output.length > 0;
      return;
    }
    if (pendingSpace && output.length < maxOutputLength) output.append(" ");
    pendingSpace = false;
    output.append(value);
  };
  while (index < html.length) {
    const character = html[index];
    if (character === "<") {
      pendingSpace = output.length > 0;
      if (html.startsWith("<!--", index)) {
        const end = html.indexOf("-->", index + 4);
        index = end < 0 ? html.length : end + 3;
        continue;
      }
      let cursor = index + 1;
      const closing = html[cursor] === "/";
      if (closing) cursor += 1;
      while (isAsciiWhitespace(html[cursor])) cursor += 1;
      const nameStart = cursor;
      while (isHtmlNameCharacter(html[cursor])) cursor += 1;
      const name = html.slice(nameStart, cursor).toLowerCase();
      const tagEnd = scanHtmlTagEnd(html, cursor);
      index = !closing && (name === "script" || name === "style") ? skipHtmlRawTextElement(html, tagEnd, name) : tagEnd;
      continue;
    }
    if (character === "&") {
      const entity = decodeSearchEntity(html, index);
      if (entity) {
        appendText(entity.value);
        index = entity.end;
        continue;
      }
    }
    appendText(character);
    index += 1;
  }
  return output.finish().trim();
};
var INTERNAL_RESOURCE_SCHEME = "chm-internal:";
var MAX_CHM_TOPIC_RESOURCE_PATHS = 2048;
var MAX_CHM_CSS_RESOURCE_PATHS = 1024;
var isHexDigit = (character) => {
  if (!character) return false;
  const code = character.charCodeAt(0);
  return code >= 48 && code <= 57 || code >= 65 && code <= 70 || code >= 97 && code <= 102;
};
var isCssIdentifierCharacter = (character) => {
  if (!character) return false;
  const code = character.charCodeAt(0);
  return code >= 48 && code <= 57 || code >= 65 && code <= 90 || code >= 97 && code <= 122 || character === "_" || character === "-";
};
var normalizeCssSyntax = (css) => {
  const output = createStringBuilder();
  let index = 0;
  let spanStart = 0;
  while (index < css.length) {
    if (css[index] === "/" && css[index + 1] === "*") {
      output.append(css.slice(spanStart, index));
      const end = css.indexOf("*/", index + 2);
      if (end < 0) {
        index = css.length;
        spanStart = index;
        break;
      }
      index = end + 2;
      spanStart = index;
      continue;
    }
    if (css[index] !== "\\") {
      index += 1;
      continue;
    }
    output.append(css.slice(spanStart, index));
    const next = css[index + 1];
    if (next === "\n" || next === "\f") {
      index += 2;
      spanStart = index;
      continue;
    }
    if (next === "\r") {
      index += css[index + 2] === "\n" ? 3 : 2;
      spanStart = index;
      continue;
    }
    let cursor = index + 1;
    while (cursor < css.length && cursor < index + 7 && isHexDigit(css[cursor])) cursor += 1;
    if (cursor > index + 1) {
      const hex = css.slice(index + 1, cursor);
      const codePoint = Number.parseInt(hex, 16);
      if (css[cursor] === "\r" && css[cursor + 1] === "\n") cursor += 2;
      else if (/[\t\n\f\r ]/.test(css[cursor] || "")) cursor += 1;
      const decoded = codePoint > 0 && codePoint <= 1114111 ? String.fromCodePoint(codePoint) : "\uFFFD";
      if (/^["'();\\]$/.test(decoded)) output.append(`\\${hex} `);
      else output.append(decoded);
      index = cursor;
      spanStart = index;
      continue;
    }
    if (next) {
      if (/^["'();\\]$/.test(next)) output.append(`\\${next}`);
      else output.append(next);
      index += 2;
    } else {
      index += 1;
    }
    spanStart = index;
  }
  output.append(css.slice(spanStart));
  return output.finish();
};
var stripCssImports = (css) => {
  const output = createStringBuilder();
  let index = 0;
  let spanStart = 0;
  while (index < css.length) {
    const isImport = css[index] === "@" && css.slice(index, index + 7).toLowerCase() === "@import" && !isCssIdentifierCharacter(css[index + 7]);
    if (!isImport) {
      index += 1;
      continue;
    }
    output.append(css.slice(spanStart, index));
    index += 7;
    let quote = "";
    let parenthesisDepth = 0;
    while (index < css.length) {
      const character = css[index];
      if (character === "\\") {
        index = Math.min(css.length, index + 2);
        continue;
      }
      if (quote) {
        if (character === quote) quote = "";
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if (character === "(") {
        parenthesisDepth += 1;
      } else if (character === ")" && parenthesisDepth > 0) {
        parenthesisDepth -= 1;
      } else if (character === ";" && parenthesisDepth === 0) {
        index += 1;
        break;
      }
      index += 1;
    }
    spanStart = index;
  }
  output.append(css.slice(spanStart));
  return output.finish();
};
var matchCssFunction = (css, index, name) => {
  if (isCssIdentifierCharacter(css[index - 1]) || css.slice(index, index + name.length).toLowerCase() !== name) return -1;
  let cursor = index + name.length;
  if (isCssIdentifierCharacter(css[cursor])) return -1;
  while (/[\t\n\f\r ]/.test(css[cursor] || "")) cursor += 1;
  return css[cursor] === "(" ? cursor : -1;
};
var readCssFunction = (css, openParenthesis) => {
  let cursor = openParenthesis + 1;
  let depth = 1;
  let quote = "";
  while (cursor < css.length) {
    const character = css[cursor];
    if (character === "\\") {
      cursor = Math.min(css.length, cursor + 2);
      continue;
    }
    if (quote) {
      if (character === quote) quote = "";
    } else if (character === '"' || character === "'") {
      quote = character;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")") {
      depth -= 1;
      if (depth === 0) return { body: css.slice(openParenthesis + 1, cursor), end: cursor + 1 };
    }
    cursor += 1;
  }
  return { body: css.slice(openParenthesis + 1), end: css.length };
};
var matchDangerousDeclaration = (css, index) => {
  if (isCssIdentifierCharacter(css[index - 1])) return -1;
  for (const name of ["behavior", "-moz-binding"]) {
    if (css.slice(index, index + name.length).toLowerCase() !== name) continue;
    let cursor = index + name.length;
    if (isCssIdentifierCharacter(css[cursor])) continue;
    while (/[\t\n\f\r ]/.test(css[cursor] || "")) cursor += 1;
    if (css[cursor] === ":") return cursor + 1;
  }
  return -1;
};
var skipCssDeclarationValue = (css, start) => {
  let cursor = start;
  let depth = 0;
  let quote = "";
  while (cursor < css.length) {
    const character = css[cursor];
    if (character === "\\") {
      cursor = Math.min(css.length, cursor + 2);
      continue;
    }
    if (quote) {
      if (character === quote) quote = "";
    } else if (character === '"' || character === "'") {
      quote = character;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")" && depth > 0) {
      depth -= 1;
    } else if (depth === 0 && (character === ";" || character === "}")) {
      return character === ";" ? cursor + 1 : cursor;
    }
    cursor += 1;
  }
  return cursor;
};
var recordResourcePath = (resources, path, maxResourcePaths) => {
  if (resources.has(path)) return true;
  if (resources.size >= maxResourcePaths) return false;
  resources.add(path);
  return true;
};
var sanitizeCss = (css, basePath, resources, maxResourcePaths) => {
  if (css.length > MAX_CHM_CSS_TEXT_LENGTH) return "";
  const source = stripCssImports(normalizeCssSyntax(css));
  const output = createStringBuilder();
  let index = 0;
  let spanStart = 0;
  while (index < source.length) {
    const character = source[index];
    if (character === '"' || character === "'") {
      index += 1;
      while (index < source.length) {
        if (source[index] === "\\") index = Math.min(source.length, index + 2);
        else if (source[index++] === character) break;
        else index += 0;
      }
      continue;
    }
    const declarationStart = matchDangerousDeclaration(source, index);
    if (declarationStart >= 0) {
      output.append(source.slice(spanStart, index));
      index = skipCssDeclarationValue(source, declarationStart);
      spanStart = index;
      continue;
    }
    const expressionStart = matchCssFunction(source, index, "expression");
    if (expressionStart >= 0) {
      output.append(source.slice(spanStart, index));
      index = readCssFunction(source, expressionStart).end;
      spanStart = index;
      continue;
    }
    const urlStart = matchCssFunction(source, index, "url");
    if (urlStart >= 0) {
      output.append(source.slice(spanStart, index));
      const parsed = readCssFunction(source, urlStart);
      let raw = parsed.body.trim();
      if (raw.startsWith('"') && raw.endsWith('"') || raw.startsWith("'") && raw.endsWith("'")) {
        raw = raw.slice(1, -1).trim();
      }
      const resolved = resolveChmReference(basePath, raw);
      if (resolved.kind === "data" && resolved.url) {
        output.append(`url("${resolved.url.replace(/"/g, "%22")}")`);
      } else if (resolved.kind === "fragment" && resolved.fragment && /^[\w:.-]+$/.test(resolved.fragment)) {
        output.append(`url("#${resolved.fragment}")`);
      } else if (resolved.kind === "internal" && resolved.path && recordResourcePath(resources, resolved.path, maxResourcePaths)) {
        output.append(`url("${INTERNAL_RESOURCE_SCHEME}${encodeURIComponent(resolved.path)}")`);
      } else {
        output.append('url("")');
      }
      index = parsed.end;
      spanStart = index;
      continue;
    }
    index += 1;
  }
  output.append(source.slice(spanStart));
  return output.finish();
};
var sanitizeEmbeddedCssAttribute = (value, basePath) => sanitizeCss(value, basePath, /* @__PURE__ */ new Set(), 0);
var sanitizeChmCss = (css, basePath, maxResourcePaths = MAX_CHM_CSS_RESOURCE_PATHS) => {
  const resources = /* @__PURE__ */ new Set();
  return {
    css: sanitizeCss(css, basePath, resources, maxResourcePaths),
    resourcePaths: Array.from(resources)
  };
};
var RESOURCE_ATTRIBUTES = [
  ["img", "src"],
  ["source", "src"],
  ["audio", "src"],
  ["video", "src"],
  ["video", "poster"],
  ["track", "src"],
  ["input", "src"],
  ["img", "lowsrc"],
  ["img", "dynsrc"],
  ["body", "background"],
  ["table", "background"],
  ["td", "background"],
  ["th", "background"],
  ["image", "href"],
  ["image", "xlink:href"],
  ["use", "href"],
  ["use", "xlink:href"],
  ["feImage", "href"],
  ["feImage", "xlink:href"]
];
var removeUnsafeElements = (document) => {
  document.querySelectorAll(
    "script,object,embed,applet,iframe,frame,frameset,form,input,button,textarea,select,option,base,noscript,template,foreignObject,animate,animateMotion,set"
  ).forEach((element) => element.remove());
  document.querySelectorAll("meta[http-equiv]").forEach((element) => element.remove());
};
var sanitizeChmHtmlDocument = (html, basePath, serialize = true) => {
  if (typeof DOMParser === "undefined") {
    throw new Error("CHM_SECURITY_DOM_UNAVAILABLE: DOMParser is required to sanitize CHM topics.");
  }
  assertChmMarkupBudget(html, MAX_CHM_HTML_TEXT_LENGTH, MAX_CHM_HTML_MARKUP_TOKENS, "HTML");
  const document = new DOMParser().parseFromString(html, "text/html");
  const resources = /* @__PURE__ */ new Set();
  removeUnsafeElements(document);
  document.querySelectorAll("*").forEach((element) => {
    for (const attribute of Array.from(element.attributes)) {
      const name = attribute.name.toLowerCase();
      if (name.startsWith("on") || name === "srcdoc" || name === "ping" || name === "formaction") {
        element.removeAttribute(attribute.name);
      }
    }
    const inlineStyle = element.getAttribute("style");
    if (inlineStyle) {
      element.setAttribute("style", sanitizeCss(inlineStyle, basePath, resources, MAX_CHM_TOPIC_RESOURCE_PATHS));
    }
    for (const attribute of Array.from(element.attributes)) {
      if (attribute.name.toLowerCase() === "style") continue;
      if (/(?:url\s*\(|@import\b|expression\s*\(|behavior\s*:|-moz-binding|\\|\/\*)/i.test(attribute.value)) {
        element.setAttribute(attribute.name, sanitizeEmbeddedCssAttribute(attribute.value, basePath));
      }
    }
  });
  document.querySelectorAll("style").forEach((style) => {
    style.textContent = sanitizeCss(style.textContent || "", basePath, resources, MAX_CHM_TOPIC_RESOURCE_PATHS);
  });
  document.querySelectorAll("a,area").forEach((element) => {
    const hasXlink = element.hasAttribute("xlink:href") || element.hasAttributeNS("http://www.w3.org/1999/xlink", "href");
    if (!element.hasAttribute("href") && !hasXlink) return;
    const raw = element.getAttribute("href") || element.getAttribute("xlink:href") || element.getAttributeNS("http://www.w3.org/1999/xlink", "href") || "";
    const resolved = resolveChmReference(basePath, raw);
    element.removeAttribute("href");
    element.removeAttribute("xlink:href");
    element.removeAttributeNS("http://www.w3.org/1999/xlink", "href");
    element.setAttribute("data-chm-link-kind", resolved.kind);
    if (resolved.path) element.setAttribute("data-chm-path", resolved.path);
    if (resolved.fragment) element.setAttribute("data-chm-fragment", resolved.fragment);
    if (resolved.kind === "internal" || resolved.kind === "fragment") {
      element.setAttribute("href", "#");
    } else {
      element.setAttribute("aria-disabled", "true");
      element.setAttribute("title", "External and active links are disabled in CHM preview.");
    }
  });
  document.querySelectorAll("link[href]").forEach((element) => {
    const relation = (element.getAttribute("rel") || "").toLowerCase().split(/\s+/);
    const resolved = resolveChmReference(basePath, element.getAttribute("href") || "");
    element.removeAttribute("href");
    if (!relation.includes("stylesheet") || resolved.kind !== "internal" || !resolved.path) {
      element.remove();
      return;
    }
    if (!recordResourcePath(resources, resolved.path, MAX_CHM_TOPIC_RESOURCE_PATHS)) {
      element.remove();
      return;
    }
    element.setAttribute("data-chm-resource-href", resolved.path);
  });
  for (const [selector, attribute] of RESOURCE_ATTRIBUTES) {
    document.querySelectorAll(`${selector}[${attribute.replace(":", "\\:")}]`).forEach((element) => {
      const raw = element.getAttribute(attribute) || "";
      const resolved = resolveChmReference(basePath, raw);
      element.removeAttribute(attribute);
      if (resolved.kind === "fragment" && resolved.fragment) {
        element.setAttribute(attribute, `#${resolved.fragment}`);
      } else if (resolved.kind === "data" && resolved.url) {
        element.setAttribute(attribute, resolved.url);
      } else if (resolved.kind === "internal" && resolved.path && recordResourcePath(resources, resolved.path, MAX_CHM_TOPIC_RESOURCE_PATHS)) {
        element.setAttribute(`data-chm-resource-${attribute.replace(":", "-")}`, resolved.path);
      }
    });
  }
  document.querySelectorAll("[srcset]").forEach((element) => element.removeAttribute("srcset"));
  const csp = document.createElement("meta");
  csp.setAttribute("http-equiv", "Content-Security-Policy");
  csp.setAttribute("content", [
    "default-src 'none'",
    "script-src 'none'",
    "style-src 'unsafe-inline' blob:",
    "img-src data: blob:",
    "font-src data: blob:",
    "media-src data: blob:",
    "connect-src 'none'",
    "object-src 'none'",
    "frame-src 'none'",
    "worker-src 'none'",
    "base-uri 'none'",
    "form-action 'none'"
  ].join("; "));
  document.head.prepend(csp);
  const viewerStyle = document.createElement("style");
  viewerStyle.textContent = [
    ":root{color-scheme:light dark}",
    "html,body{min-height:100%;margin:0}",
    'body{padding:24px;box-sizing:border-box;background:#fff;color:#172033;font:16px/1.65 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow-wrap:anywhere}',
    "img,video,svg,table{max-width:100%}",
    "pre{white-space:pre-wrap}",
    "a[aria-disabled=true]{color:inherit;text-decoration:line-through;cursor:not-allowed}",
    "@media(prefers-color-scheme:dark){body{background:#111827;color:#e5eef8}a{color:#7dd3fc}}"
  ].join("");
  document.head.append(viewerStyle);
  return {
    document,
    html: serialize ? `<!doctype html>${document.documentElement.outerHTML}` : "",
    title: document.title || "",
    resourcePaths: Array.from(resources)
  };
};

export {
  resolveChmOptions,
  normalizeChmManifest,
  normalizeChmEntries,
  MAX_CHM_SVG_TEXT_LENGTH,
  MAX_CHM_CSS_TEXT_LENGTH,
  assertChmSvgSourceSafety,
  normalizeChmPath,
  decodeChmText,
  extractChmSearchText,
  MAX_CHM_TOPIC_RESOURCE_PATHS,
  MAX_CHM_CSS_RESOURCE_PATHS,
  sanitizeChmCss,
  sanitizeChmHtmlDocument
};
