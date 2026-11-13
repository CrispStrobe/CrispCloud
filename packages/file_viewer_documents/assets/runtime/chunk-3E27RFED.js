import {
  findFileViewerViewStateProvider,
  findFileViewerZoomProvider,
  registerFileViewerViewStateProvider,
  resolveFileViewerFitScale,
  resolveFileViewerScrollContainer,
  unregisterFileViewerViewStateProvider
} from "./chunk-B3J7LI27.js";
import {
  resolveFileViewerLocale,
  translateFileViewerMessage
} from "./chunk-X3L4DUK6.js";

// packages/core/src/source/textEncoding.ts
var DEFAULT_FILE_VIEWER_TEXT_FALLBACK_ENCODING = "gb18030";
var SINGLE_BYTE_ENCODING_ALIASES = /* @__PURE__ */ new Map([
  ["iso-8859-1", "iso-8859-1"],
  ["iso8859-1", "iso-8859-1"],
  ["iso88591", "iso-8859-1"],
  ["latin1", "iso-8859-1"],
  ["latin-1", "iso-8859-1"],
  ["l1", "iso-8859-1"],
  ["cp819", "iso-8859-1"],
  ["ibm819", "iso-8859-1"],
  ["iso-8859-2", "iso-8859-2"],
  ["iso8859-2", "iso-8859-2"],
  ["iso88592", "iso-8859-2"],
  ["latin2", "iso-8859-2"],
  ["latin-2", "iso-8859-2"],
  ["l2", "iso-8859-2"],
  ["iso-8859-15", "iso-8859-15"],
  ["iso8859-15", "iso-8859-15"],
  ["iso885915", "iso-8859-15"],
  ["latin9", "iso-8859-15"],
  ["latin-9", "iso-8859-15"],
  ["l9", "iso-8859-15"],
  ["windows-1250", "windows-1250"],
  ["windows1250", "windows-1250"],
  ["cp1250", "windows-1250"],
  ["x-cp1250", "windows-1250"],
  ["windows-1251", "windows-1251"],
  ["windows1251", "windows-1251"],
  ["cp1251", "windows-1251"],
  ["x-cp1251", "windows-1251"],
  ["windows-1252", "windows-1252"],
  ["windows1252", "windows-1252"],
  ["cp1252", "windows-1252"],
  ["x-cp1252", "windows-1252"]
]);
var SINGLE_BYTE_ENCODINGS = new Set(SINGLE_BYTE_ENCODING_ALIASES.values());
var normalizeEncoding = (encoding) => {
  const normalized = String(encoding || "auto").trim().toLowerCase().replace(/_/g, "-");
  if (normalized === "utf8" || normalized === "utf-8") {
    return "utf-8";
  }
  if (normalized === "utf16" || normalized === "utf-16" || normalized === "utf16le" || normalized === "utf-16le") {
    return "utf-16le";
  }
  if (normalized === "utf16be" || normalized === "utf-16be") {
    return "utf-16be";
  }
  if (normalized === "gbk" || normalized === "cp936" || normalized === "gb2312") {
    return "gbk";
  }
  if (normalized === "gb18030") {
    return "gb18030";
  }
  const singleByte = SINGLE_BYTE_ENCODING_ALIASES.get(normalized);
  if (singleByte) {
    return singleByte;
  }
  return "auto";
};
var toResolvedEncoding = (encoding) => {
  return encoding === "gbk" ? "gb18030" : encoding;
};
var normalizeFallbackEncoding = (fallbackEncoding) => {
  const normalized = normalizeEncoding(fallbackEncoding);
  return normalized === "auto" ? DEFAULT_FILE_VIEWER_TEXT_FALLBACK_ENCODING : toResolvedEncoding(normalized);
};
var isContinuationByte = (value) => {
  return value !== void 0 && value >= 128 && value <= 191;
};
var isValidFileViewerUtf8 = (bytes) => {
  for (let index = 0; index < bytes.length; ) {
    const first = bytes[index];
    if (first === void 0) {
      return false;
    }
    if (first <= 127) {
      index += 1;
      continue;
    }
    const second = bytes[index + 1];
    const third = bytes[index + 2];
    const fourth = bytes[index + 3];
    if (first >= 194 && first <= 223 && isContinuationByte(second)) {
      index += 2;
      continue;
    }
    if (first === 224 && second !== void 0 && second >= 160 && second <= 191 && isContinuationByte(third)) {
      index += 3;
      continue;
    }
    if ((first >= 225 && first <= 236 || first >= 238 && first <= 239) && isContinuationByte(second) && isContinuationByte(third)) {
      index += 3;
      continue;
    }
    if (first === 237 && second !== void 0 && second >= 128 && second <= 159 && isContinuationByte(third)) {
      index += 3;
      continue;
    }
    if (first === 240 && second !== void 0 && second >= 144 && second <= 191 && isContinuationByte(third) && isContinuationByte(fourth)) {
      index += 4;
      continue;
    }
    if (first >= 241 && first <= 243 && isContinuationByte(second) && isContinuationByte(third) && isContinuationByte(fourth)) {
      index += 4;
      continue;
    }
    if (first === 244 && second !== void 0 && second >= 128 && second <= 143 && isContinuationByte(third) && isContinuationByte(fourth)) {
      index += 4;
      continue;
    }
    return false;
  }
  return true;
};
var inferBomlessUtf16 = (bytes) => {
  const sampleLength = Math.min(bytes.length - bytes.length % 2, 4096);
  if (sampleLength < 4) {
    return null;
  }
  let evenNulls = 0;
  let oddNulls = 0;
  for (let index = 0; index < sampleLength; index += 2) {
    evenNulls += bytes[index] === 0 ? 1 : 0;
    oddNulls += bytes[index + 1] === 0 ? 1 : 0;
  }
  const pairs = sampleLength / 2;
  if (oddNulls / pairs >= 0.3 && evenNulls / pairs <= 0.05) {
    return "utf-16le";
  }
  if (evenNulls / pairs >= 0.3 && oddNulls / pairs <= 0.05) {
    return "utf-16be";
  }
  return null;
};
var resolveFileViewerTextEncoding = (bytes, encoding = "auto", fallbackEncoding = DEFAULT_FILE_VIEWER_TEXT_FALLBACK_ENCODING) => {
  const normalized = normalizeEncoding(encoding);
  if (normalized !== "auto") {
    return {
      encoding: toResolvedEncoding(normalized),
      bomLength: normalized === "utf-8" && bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191 ? 3 : normalized === "utf-16le" && bytes[0] === 255 && bytes[1] === 254 || normalized === "utf-16be" && bytes[0] === 254 && bytes[1] === 255 ? 2 : 0
    };
  }
  if (bytes[0] === 239 && bytes[1] === 187 && bytes[2] === 191) {
    return { encoding: "utf-8", bomLength: 3 };
  }
  if (bytes[0] === 255 && bytes[1] === 254) {
    return { encoding: "utf-16le", bomLength: 2 };
  }
  if (bytes[0] === 254 && bytes[1] === 255) {
    return { encoding: "utf-16be", bomLength: 2 };
  }
  const utf16 = inferBomlessUtf16(bytes);
  if (utf16) {
    return { encoding: utf16, bomLength: 0 };
  }
  return isValidFileViewerUtf8(bytes) ? { encoding: "utf-8", bomLength: 0 } : { encoding: normalizeFallbackEncoding(fallbackEncoding), bomLength: 0 };
};
var createFileViewerTextDecoder = (encoding) => {
  if (typeof TextDecoder === "undefined") {
    throw new Error("Text decoding requires the browser TextDecoder API.");
  }
  try {
    return new TextDecoder(encoding);
  } catch (error) {
    if (encoding === "gb18030" && error instanceof RangeError) {
      throw Object.assign(
        new Error("This browser does not provide GB18030 text decoding. Use a current browser or select UTF-8 explicitly."),
        { cause: error }
      );
    }
    throw error;
  }
};
var decodeFileViewerTextBuffer = (data, encoding = "auto", fallbackEncoding = DEFAULT_FILE_VIEWER_TEXT_FALLBACK_ENCODING) => {
  const bytes = new Uint8Array(data);
  const resolved = resolveFileViewerTextEncoding(bytes, encoding, fallbackEncoding);
  return {
    text: createFileViewerTextDecoder(resolved.encoding).decode(bytes.subarray(resolved.bomLength)),
    encoding: resolved.encoding
  };
};

// packages/core/src/source/index.ts
var normalizeFileExtension = (extension) => {
  return extension.trim().replace(/^\./, "").toLowerCase();
};

// packages/core/src/platform/assets.ts
var DEFAULT_FILE_VIEWER_ARCHIVE_WORKER_PATH = "vendor/libarchive/worker-bundle.js";
var DEFAULT_FILE_VIEWER_ARCHIVE_WASM_PATH = "vendor/libarchive/libarchive.wasm";
var DEFAULT_FILE_VIEWER_CHM_WORKER_PATH = "vendor/chm/chm.worker.js";
var DEFAULT_FILE_VIEWER_CHM_WORKER_PACKAGE_PATH = "@file-viewer/renderer-chm/worker/chm.worker.js";
var DEFAULT_FILE_VIEWER_CHM_WASM_MODULE_PATH = "vendor/chm/chm_wasm.js";
var DEFAULT_FILE_VIEWER_CHM_WASM_MODULE_PACKAGE_PATH = "@file-viewer/renderer-chm/wasm/chm_wasm.js";
var DEFAULT_FILE_VIEWER_CHM_WASM_PATH = "vendor/chm/chm_wasm_bg.wasm";
var DEFAULT_FILE_VIEWER_CHM_WASM_PACKAGE_PATH = "@file-viewer/renderer-chm/wasm/chm_wasm_bg.wasm";
var DEFAULT_FILE_VIEWER_DOCX_WORKER_PATH = "vendor/docx/docx.worker.js";
var DEFAULT_FILE_VIEWER_DOCX_WORKER_JSZIP_PATH = "vendor/docx/jszip.min.js";
var DEFAULT_FILE_VIEWER_PRESENTATION_WORKER_PATH = "vendor/pptx/pptx.worker.js";
var DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH = "vendor/ppt";
var DEFAULT_FILE_VIEWER_PPT_MODULE_PATH = `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/dist/pptjs.mjs`;
var DEFAULT_FILE_VIEWER_PPT_WORKER_PATH = `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/dist/pptjs.worker.js`;
var DEFAULT_FILE_VIEWER_PPT_FRAME_CACHE_PATH = `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/frame-cache.mjs`;
var DEFAULT_FILE_VIEWER_PPT_WASM_PATH = `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/ppt-native.wasm`;
var DEFAULT_FILE_VIEWER_PPT_FONT_PATH = `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/ppt-font-cjk.otf`;
var DEFAULT_FILE_VIEWER_SPREADSHEET_WORKER_PATH = "vendor/xlsx/sheet.worker.js";
var DEFAULT_FILE_VIEWER_IWORK_WORKER_PATH = "vendor/iwork/iwork.worker.js";
var DEFAULT_FILE_VIEWER_IWORK_WORKER_PACKAGE_PATH = "@file-viewer/renderer-iwork/worker/iwork.worker.js";
var DEFAULT_FILE_VIEWER_HANGUL_WORKER_PATH = "vendor/hangul/hangul.worker.js";
var DEFAULT_FILE_VIEWER_HANGUL_WORKER_PACKAGE_PATH = "@file-viewer/renderer-hangul/worker/hangul.worker.js";
var DEFAULT_FILE_VIEWER_WORDPERFECT_WORKER_PATH = "vendor/wordperfect/wordperfect.worker.js";
var DEFAULT_FILE_VIEWER_WORDPERFECT_WORKER_PACKAGE_PATH = "@file-viewer/renderer-wordperfect/worker/wordperfect.worker.js";
var DEFAULT_FILE_VIEWER_WORDPERFECT_WASM_PATH = "vendor/wordperfect/libwpd.wasm";
var DEFAULT_FILE_VIEWER_WORDPERFECT_WASM_PACKAGE_PATH = "@file-viewer/renderer-wordperfect/worker/libwpd.wasm";
var DEFAULT_FILE_VIEWER_WORDPERFECT_MODULE_PATH = "vendor/wordperfect/libwpd.mjs";
var DEFAULT_FILE_VIEWER_WORDPERFECT_MODULE_PACKAGE_PATH = "@file-viewer/renderer-wordperfect/worker/libwpd.mjs";
var DEFAULT_FILE_VIEWER_PDF_WORKER_PATH = "vendor/pdf/pdf.worker.mjs";
var DEFAULT_FILE_VIEWER_PDF_CMAP_PATH = "vendor/pdf/cmaps/";
var DEFAULT_FILE_VIEWER_PDF_WASM_PATH = "vendor/pdf/wasm/";
var DEFAULT_FILE_VIEWER_PDF_STANDARD_FONT_PATH = "vendor/pdf/standard_fonts/";
var DEFAULT_FILE_VIEWER_PDF_CJK_FONT_FALLBACK_PATH = "vendor/pdf/fonts/";
var DEFAULT_FILE_VIEWER_DRAWIO_VIEWER_SCRIPT_PATH = "vendor/drawio/viewer-static.min.js";
var DEFAULT_FILE_VIEWER_DRAWIO_ASSET_PATH = "vendor/drawio/";
var DEFAULT_FILE_VIEWER_CAD_RUNTIME_VERSION = "0.8.3";
var COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION = "0.8.0";
var DEFAULT_FILE_VIEWER_CAD_WASM_PATH = `wasm/cad/${DEFAULT_FILE_VIEWER_CAD_RUNTIME_VERSION}/`;
var DEFAULT_FILE_VIEWER_CAD_WORKER_PATH = `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}dwg-worker.js`;
var DEFAULT_FILE_VIEWER_CAD_DWF_WASM_PATH = `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}dwfv-render.wasm`;
var DEFAULT_FILE_VIEWER_CAD_LIBREDWG_SCRIPT_PATH = `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}libredwg-web.js`;
var DEFAULT_FILE_VIEWER_CAD_LIBREDWG_WASM_PATH = `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}libredwg-web.wasm`;
var DEFAULT_FILE_VIEWER_TYPST_COMPILER_WASM_URL = "wasm/typst/typst_ts_web_compiler_bg.wasm";
var DEFAULT_FILE_VIEWER_TYPST_RENDERER_WASM_URL = "wasm/typst/typst_ts_renderer_bg.wasm";
var DEFAULT_FILE_VIEWER_TYPST_FONT_ASSETS_URL = "wasm/typst/fonts/";
var DEFAULT_FILE_VIEWER_TYPST_COMPILER_WASM_PACKAGE_PATH = "@myriaddreamin/typst-ts-web-compiler/pkg/typst_ts_web_compiler_bg.wasm";
var DEFAULT_FILE_VIEWER_TYPST_RENDERER_WASM_PACKAGE_PATH = "@myriaddreamin/typst-ts-renderer/pkg/typst_ts_renderer_bg.wasm";
var DEFAULT_FILE_VIEWER_DATA_SQL_WASM_URL = "wasm/data/sql-wasm.wasm";
var DEFAULT_FILE_VIEWER_DATA_SQL_WASM_PACKAGE_PATH = "sql.js/dist/sql-wasm.wasm";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_WORKER_PATH = "vendor/design/illustrator-pgf.worker.js";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/illustrator-pgf.worker.js";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_LICENSE_PATH = "vendor/design/LICENSE.illustrator-pgf-MIT.txt";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/illustrator-pgf-MIT.txt";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_ZSTD_LICENSE_PATH = "vendor/design/LICENSE.fzstd-MIT.txt";
var DEFAULT_FILE_VIEWER_ILLUSTRATOR_ZSTD_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/fzstd-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_WORKER_PATH = "vendor/design/photoshop.worker.js";
var DEFAULT_FILE_VIEWER_DESIGN_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/photoshop.worker.js";
var DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH = "vendor/design/adobe-container.worker.js";
var DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/adobe-container.worker.js";
var DEFAULT_FILE_VIEWER_ADOBE_RESOURCE_WORKER_PATH = "vendor/design/adobe-resource.worker.js";
var DEFAULT_FILE_VIEWER_ADOBE_RESOURCE_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/adobe-resource.worker.js";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_WORKER_PATH = "vendor/design/postscript.worker.js";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/postscript.worker.js";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_WASM_PATH = "vendor/design/stet_wasm_bg.wasm";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_WASM_PACKAGE_PATH = "@file-viewer/renderer-design/wasm/postscript.wasm";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_APACHE_LICENSE_PATH = "vendor/design/LICENSE.stet-Apache-2.0.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_APACHE_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Stet-Apache-2.0.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_MIT_LICENSE_PATH = "vendor/design/LICENSE.stet-MIT.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_MIT_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Stet-MIT.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_URW_LICENSE_PATH = "vendor/design/LICENSE.Stet-URW-Fonts-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_URW_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Stet-URW-Fonts-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CMYK_NOTICE_PATH = "vendor/design/LICENSE.Stet-CMYK-Profile.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CMYK_NOTICE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Stet-CMYK-Profile.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CC0_LICENSE_PATH = "vendor/design/LICENSE.CC0-1.0.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CC0_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/CC0-1.0.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_NATIVE_NOTICES_PATH = "vendor/design/Stet_NATIVE_THIRD_PARTY_LICENSES.json";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_NATIVE_NOTICES_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Stet_NATIVE_THIRD_PARTY_LICENSES.json";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CARLITO_LICENSE_PATH = "vendor/design/LICENSE.Carlito-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_CARLITO_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Carlito-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_TINOS_LICENSE_PATH = "vendor/design/LICENSE.Tinos-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_TINOS_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Tinos-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_COUSINE_LICENSE_PATH = "vendor/design/LICENSE.Cousine-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_COUSINE_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/Cousine-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_NOTO_SYMBOLS_LICENSE_PATH = "vendor/design/LICENSE.NotoSansSymbols2-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_POSTSCRIPT_NOTO_SYMBOLS_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/NotoSansSymbols2-OFL-1.1.txt";
var DEFAULT_FILE_VIEWER_IDML_WORKER_PATH = "vendor/design/idml.worker.js";
var DEFAULT_FILE_VIEWER_IDML_WORKER_PACKAGE_PATH = "@file-viewer/renderer-design/worker/idml.worker.js";
var DEFAULT_FILE_VIEWER_IDML_WASM_PATH = "vendor/design/paged_introspect_wasm_bg.wasm";
var DEFAULT_FILE_VIEWER_IDML_WASM_PACKAGE_PATH = "@paged-media/introspect-wasm/paged_introspect_wasm_bg.wasm";
var DEFAULT_FILE_VIEWER_IDML_LICENSE_PATH = "vendor/design/LICENSE.introspect-wasm-MPL-2.0.txt";
var DEFAULT_FILE_VIEWER_IDML_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/MPL-2.0.txt";
var DEFAULT_FILE_VIEWER_DESIGN_THIRD_PARTY_NOTICES_PATH = "vendor/design/THIRD_PARTY_NOTICES.md";
var DEFAULT_FILE_VIEWER_DESIGN_THIRD_PARTY_NOTICES_PACKAGE_PATH = "@file-viewer/renderer-design/third-party-notices";
var DEFAULT_FILE_VIEWER_DESIGN_XMLDOM_LICENSE_PATH = "vendor/design/LICENSE.xmldom-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_XMLDOM_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/xmldom-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_SAXES_LICENSE_PATH = "vendor/design/LICENSE.saxes-ISC.txt";
var DEFAULT_FILE_VIEWER_DESIGN_SAXES_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/saxes-ISC.txt";
var DEFAULT_FILE_VIEWER_DESIGN_AG_PSD_LICENSE_PATH = "vendor/design/LICENSE.ag-psd-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_AG_PSD_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/ag-psd-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_WEBTOON_PSD_LICENSE_PATH = "vendor/design/LICENSE.webtoon-psd-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_WEBTOON_PSD_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/webtoon-psd-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_BASE64_JS_LICENSE_PATH = "vendor/design/LICENSE.base64-js-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_BASE64_JS_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/base64-js-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_PAKO_LICENSE_PATH = "vendor/design/LICENSE.pako-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_PAKO_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/pako-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_XMLCHARS_LICENSE_PATH = "vendor/design/LICENSE.xmlchars-MIT.txt";
var DEFAULT_FILE_VIEWER_DESIGN_XMLCHARS_LICENSE_PACKAGE_PATH = "@file-viewer/renderer-design/licenses/xmlchars-MIT.txt";
var DEFAULT_FILE_VIEWER_MODEL_WORKER_URL = "wasm/model/occt-worker.js";
var DEFAULT_FILE_VIEWER_MODEL_RUNTIME_URL = "wasm/model/occt-import-js.js";
var DEFAULT_FILE_VIEWER_MODEL_WASM_URL = "wasm/model/occt-import-js.wasm";
var DEFAULT_FILE_VIEWER_MODEL_OCCT_LICENSE_URL = "wasm/model/LICENSE.occt.txt";
var DEFAULT_FILE_VIEWER_MODEL_IMPORT_LICENSE_URL = "wasm/model/LICENSE.occt-import-js.txt";
var DEFAULT_FILE_VIEWER_MODEL_RUNTIME_PACKAGE_PATH = "occt-import-js/dist/occt-import-js.js";
var DEFAULT_FILE_VIEWER_MODEL_WASM_PACKAGE_PATH = "occt-import-js/dist/occt-import-js.wasm";
var DEFAULT_FILE_VIEWER_MODEL_OCCT_LICENSE_PACKAGE_PATH = "occt-import-js/dist/license.occt.txt";
var DEFAULT_FILE_VIEWER_MODEL_IMPORT_LICENSE_PACKAGE_PATH = "occt-import-js/dist/license.occt-import-js.txt";
var automaticFileViewerAssetBaseUrl = /* @__PURE__ */ Symbol("automatic-file-viewer-asset-base");
var configuredFileViewerAssetBaseUrl = automaticFileViewerAssetBaseUrl;
var pathDepth = (pathname) => pathname.split("/").filter(Boolean).length;
var longestCommonDirectoryPath = (left, right) => {
  const leftSegments = left.split("/").filter(Boolean);
  const rightSegments = right.split("/").filter(Boolean);
  const common = [];
  const length = Math.min(leftSegments.length, Math.max(0, rightSegments.length - 1));
  for (let index = 0; index < length && leftSegments[index] === rightSegments[index]; index += 1) {
    common.push(leftSegments[index]);
  }
  return common.length ? `/${common.join("/")}/` : "/";
};
var resolveFileViewerScriptAssetBaseCandidate = (script, documentBaseUrl, index) => {
  try {
    const rawScriptUrl = script.src || script.getAttribute("src") || "";
    if (!rawScriptUrl) {
      return [];
    }
    const scriptUrl = new URL(rawScriptUrl, documentBaseUrl);
    const viteClient = scriptUrl.pathname.match(/^(.*\/)@vite\/client$/i);
    const isSourceModule = /\/(?:src|node_modules|@fs|@id|@vite)(?:\/|$)/i.test(
      scriptUrl.pathname
    );
    const documentUrl = new URL(documentBaseUrl);
    const documentPathname = documentUrl.pathname.endsWith("/") ? documentUrl.pathname : `${documentUrl.pathname}/`;
    const scriptName = scriptUrl.pathname.slice(scriptUrl.pathname.lastIndexOf("/") + 1);
    const isEntryScript = /^(?:app|index|main|runtime|umi)(?:[.-]|$)/i.test(scriptName);
    const candidates = /* @__PURE__ */ new Map();
    const addCandidate = (basePath, quality) => {
      const url = new URL(basePath, scriptUrl).href;
      const candidateUrl = new URL(url);
      let score = quality + index / 1e4;
      if (candidateUrl.origin === documentUrl.origin) {
        score += 8;
      }
      if (documentPathname.startsWith(candidateUrl.pathname)) {
        score += 16 + pathDepth(candidateUrl.pathname) / 4;
      }
      if (script.type === "module") {
        score += 2;
      }
      if (isEntryScript) {
        score += 2;
      }
      const previous = candidates.get(url);
      if (!previous || previous.score < score) {
        candidates.set(url, { url, score });
      }
    };
    if (viteClient) {
      addCandidate(viteClient[1], 12);
    }
    if (isSourceModule) {
      return [...candidates.values()];
    }
    const pathSegments = scriptUrl.pathname.split("/").filter(Boolean);
    const directories = pathSegments.slice(0, -1);
    const emittedDirectoryWeights = [
      { segments: ["static", "js"], weight: 9 },
      { segments: ["assets", "js"], weight: 9 },
      { segments: ["assets", "chunks"], weight: 8 },
      { segments: ["assets"], weight: 6 },
      { segments: ["static"], weight: 6 },
      { segments: ["js"], weight: 4 }
    ];
    emittedDirectoryWeights.forEach(({ segments, weight }) => {
      for (let segmentIndex = 0; segmentIndex <= directories.length - segments.length; segmentIndex += 1) {
        const matches = segments.every(
          (segment, offset) => directories[segmentIndex + offset]?.toLowerCase() === segment
        );
        if (!matches) {
          continue;
        }
        const basePath = directories.slice(0, segmentIndex).length ? `/${directories.slice(0, segmentIndex).join("/")}/` : "/";
        addCandidate(basePath, weight + segments.length);
      }
    });
    if (isEntryScript) {
      const scriptDirectory = scriptUrl.pathname.slice(0, scriptUrl.pathname.lastIndexOf("/") + 1);
      addCandidate(scriptDirectory, 3);
    }
    if (scriptUrl.origin === documentUrl.origin) {
      addCandidate(
        longestCommonDirectoryPath(documentUrl.pathname, scriptUrl.pathname),
        8
      );
    }
    return [...candidates.values()];
  } catch {
    return [];
  }
};
var resolveFileViewerRuntimeAssetBaseUrl = (documentRef) => {
  const documentBaseUrl = documentRef.baseURI || documentRef.URL || "file:///";
  if (configuredFileViewerAssetBaseUrl !== automaticFileViewerAssetBaseUrl) {
    if (!configuredFileViewerAssetBaseUrl) {
      return documentBaseUrl;
    }
    try {
      return new URL(configuredFileViewerAssetBaseUrl, documentBaseUrl).href;
    } catch {
      return configuredFileViewerAssetBaseUrl;
    }
  }
  if (documentRef.querySelector("base[href]")) {
    return documentBaseUrl;
  }
  const candidates = Array.from(documentRef.querySelectorAll("script[src]")).flatMap((script, index) => resolveFileViewerScriptAssetBaseCandidate(script, documentBaseUrl, index)).sort((left, right) => right.score - left.score);
  return candidates[0]?.url || documentBaseUrl;
};
var createDesignThirdPartyAssets = (rendererId, includeContainerXmlLicenses = false) => {
  const assets = [
    {
      id: `${rendererId}-third-party-notices`,
      rendererId,
      kind: "license",
      target: "public",
      required: true,
      defaultPath: DEFAULT_FILE_VIEWER_DESIGN_THIRD_PARTY_NOTICES_PATH,
      packagePath: DEFAULT_FILE_VIEWER_DESIGN_THIRD_PARTY_NOTICES_PACKAGE_PATH,
      description: "Third-party notices for the bundled Adobe design Worker and WebAssembly dependency closure."
    }
  ];
  if (includeContainerXmlLicenses) {
    assets.push(
      {
        id: `${rendererId}-xmldom-license`,
        rendererId,
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_XMLDOM_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_XMLDOM_LICENSE_PACKAGE_PATH,
        description: "@xmldom/xmldom MIT license text for the bundled Adobe container Worker."
      },
      {
        id: `${rendererId}-saxes-license`,
        rendererId,
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_SAXES_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_SAXES_LICENSE_PACKAGE_PATH,
        description: "saxes ISC and inherited notice text for the bundled Adobe container Worker."
      },
      {
        id: `${rendererId}-xmlchars-license`,
        rendererId,
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_XMLCHARS_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_XMLCHARS_LICENSE_PACKAGE_PATH,
        description: "xmlchars MIT license text for the dependency bundled through saxes."
      }
    );
  }
  return assets;
};
var createPhotoshopWorkerLicenseAssets = (rendererId, includeWebtoonPsd = false) => {
  const assets = [
    {
      id: `${rendererId}-ag-psd-license`,
      rendererId,
      kind: "license",
      target: "public",
      required: true,
      defaultPath: DEFAULT_FILE_VIEWER_DESIGN_AG_PSD_LICENSE_PATH,
      packagePath: DEFAULT_FILE_VIEWER_DESIGN_AG_PSD_LICENSE_PACKAGE_PATH,
      description: "ag-psd MIT license and upstream image/brush ownership notice."
    },
    {
      id: `${rendererId}-base64-js-license`,
      rendererId,
      kind: "license",
      target: "public",
      required: true,
      defaultPath: DEFAULT_FILE_VIEWER_DESIGN_BASE64_JS_LICENSE_PATH,
      packagePath: DEFAULT_FILE_VIEWER_DESIGN_BASE64_JS_LICENSE_PACKAGE_PATH,
      description: "base64-js MIT license text for the dependency bundled through ag-psd."
    },
    {
      id: `${rendererId}-pako-license`,
      rendererId,
      kind: "license",
      target: "public",
      required: true,
      defaultPath: DEFAULT_FILE_VIEWER_DESIGN_PAKO_LICENSE_PATH,
      packagePath: DEFAULT_FILE_VIEWER_DESIGN_PAKO_LICENSE_PACKAGE_PATH,
      description: "pako MIT license text for the dependency bundled through ag-psd."
    }
  ];
  if (includeWebtoonPsd) {
    assets.push({
      id: `${rendererId}-webtoon-psd-license`,
      rendererId,
      kind: "license",
      target: "public",
      required: true,
      defaultPath: DEFAULT_FILE_VIEWER_DESIGN_WEBTOON_PSD_LICENSE_PATH,
      packagePath: DEFAULT_FILE_VIEWER_DESIGN_WEBTOON_PSD_LICENSE_PACKAGE_PATH,
      description: "@webtoon/psd MIT license text for the bundled PSB parser."
    });
  }
  return assets;
};
var DEFAULT_FILE_VIEWER_RENDERER_ASSET_MANIFESTS = [
  {
    rendererId: "chm",
    assets: [
      {
        id: "chm-worker",
        rendererId: "chm",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CHM_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_CHM_WORKER_PACKAGE_PATH,
        optionPath: "chm.workerUrl",
        description: "Module Worker that isolates Rust/WASM CHM parsing, LZX decompression, search and virtual-file access."
      },
      {
        id: "chm-wasm-module",
        rendererId: "chm",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CHM_WASM_MODULE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_CHM_WASM_MODULE_PACKAGE_PATH,
        optionPath: "chm.wasmModuleUrl",
        description: "wasm-bindgen ES module loader for the browser-local Rust CHM engine."
      },
      {
        id: "chm-wasm",
        rendererId: "chm",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CHM_WASM_PATH,
        packagePath: DEFAULT_FILE_VIEWER_CHM_WASM_PACKAGE_PATH,
        optionPath: "chm.wasmUrl",
        description: "Rust WebAssembly engine for bounded ITSF/ITSP parsing and LZX decompression."
      }
    ]
  },
  {
    rendererId: "model",
    assets: [
      {
        id: "model-occt-worker",
        rendererId: "model",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_MODEL_WORKER_URL,
        optionPath: "model.workerUrl",
        description: "File Viewer worker that runs STEP, IGES, and BREP tessellation off the UI thread."
      },
      {
        id: "model-occt-runtime",
        rendererId: "model",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_MODEL_RUNTIME_URL,
        packagePath: DEFAULT_FILE_VIEWER_MODEL_RUNTIME_PACKAGE_PATH,
        optionPath: "model.runtimeUrl",
        description: "Self-hosted occt-import-js runtime for browser-native STEP, IGES, and BREP preview."
      },
      {
        id: "model-occt-wasm",
        rendererId: "model",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_MODEL_WASM_URL,
        packagePath: DEFAULT_FILE_VIEWER_MODEL_WASM_PACKAGE_PATH,
        optionPath: "model.wasmUrl",
        description: "OpenCascade WebAssembly geometry kernel used by the model renderer."
      },
      {
        id: "model-occt-license",
        rendererId: "model",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_MODEL_OCCT_LICENSE_URL,
        packagePath: DEFAULT_FILE_VIEWER_MODEL_OCCT_LICENSE_PACKAGE_PATH,
        description: "OpenCascade license notice distributed with the browser geometry kernel."
      },
      {
        id: "model-occt-import-license",
        rendererId: "model",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_MODEL_IMPORT_LICENSE_URL,
        packagePath: DEFAULT_FILE_VIEWER_MODEL_IMPORT_LICENSE_PACKAGE_PATH,
        description: "occt-import-js license notice distributed with the browser geometry kernel."
      }
    ]
  },
  {
    rendererId: "drawing",
    assets: [
      {
        id: "drawio-viewer-script",
        rendererId: "drawing",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DRAWIO_VIEWER_SCRIPT_PATH,
        optionPath: "drawing.viewerScriptUrl",
        description: "Official diagrams.net viewer-static.min.js self-hosted for offline Draw.io rendering."
      },
      {
        id: "drawio-offline-assets",
        rendererId: "drawing",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DRAWIO_ASSET_PATH,
        description: "Official diagrams.net styles, shapes, stencils, images, mxGraph and math assets for offline rendering."
      }
    ]
  },
  {
    rendererId: "pdf",
    assets: [
      {
        id: "pdf-worker",
        rendererId: "pdf",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PDF_WORKER_PATH,
        optionPath: "pdf.workerUrl",
        description: "PDF.js module worker copied into viewer assets for offline PDF rendering."
      },
      {
        id: "pdf-cmaps",
        rendererId: "pdf",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PDF_CMAP_PATH,
        optionPath: "pdf.cMapUrl",
        description: "PDF.js packed CMaps used for CJK and embedded text decoding."
      },
      {
        id: "pdf-wasm",
        rendererId: "pdf",
        kind: "wasm-directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PDF_WASM_PATH,
        optionPath: "pdf.wasmUrl",
        description: "PDF.js WebAssembly helpers for image decoding and fully self-hosted PDF rendering."
      },
      {
        id: "pdf-standard-fonts",
        rendererId: "pdf",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PDF_STANDARD_FONT_PATH,
        optionPath: "pdf.standardFontDataUrl",
        description: "PDF.js standard font data used when PDF files reference base fonts."
      },
      {
        id: "pdf-cjk-font-fallback",
        rendererId: "pdf",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PDF_CJK_FONT_FALLBACK_PATH,
        optionPath: "pdf.cjkFontFallbackPath",
        description: "Self-hosted Noto Sans SC variable font shards used for missing unembedded CJK fonts."
      }
    ]
  },
  {
    rendererId: "archive",
    assets: [
      {
        id: "libarchive-worker",
        rendererId: "archive",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ARCHIVE_WORKER_PATH,
        optionPath: "archive.workerUrl",
        description: "libarchive.js module worker used for broad archive format parsing."
      },
      {
        id: "libarchive-wasm",
        rendererId: "archive",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ARCHIVE_WASM_PATH,
        optionPath: "archive.wasmUrl",
        description: "libarchive.js WebAssembly module expected next to the public worker."
      }
    ]
  },
  {
    rendererId: "cad",
    assets: [
      {
        id: "cad-wasm-directory",
        rendererId: "cad",
        kind: "wasm-directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CAD_WASM_PATH,
        optionPath: "cad.wasmPath",
        description: "@flyfish-dev/cad-viewer WebAssembly directory for DWG/DXF helpers."
      },
      {
        id: "cad-dwg-worker",
        rendererId: "cad",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CAD_WORKER_PATH,
        optionPath: "cad.workerUrl",
        description: "DWG worker entry used by @flyfish-dev/cad-viewer."
      },
      {
        id: "cad-dwf-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CAD_DWF_WASM_PATH,
        optionPath: "cad.dwfWasmUrl",
        description: "DWF/DWFx/XPS raster WebAssembly module used by @flyfish-dev/cad-viewer."
      },
      {
        id: "cad-libredwg-script",
        rendererId: "cad",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CAD_LIBREDWG_SCRIPT_PATH,
        description: "LibreDWG JavaScript runtime loaded by the CAD DWG worker for offline parsing."
      },
      {
        id: "cad-libredwg-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_CAD_LIBREDWG_WASM_PATH,
        description: "LibreDWG WebAssembly runtime loaded by the CAD DWG worker for offline parsing."
      },
      {
        id: "cad-license",
        rendererId: "cad",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}LICENSE`,
        description: "The installed CAD runtime redistribution license."
      },
      {
        id: "cad-notice",
        rendererId: "cad",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_CAD_WASM_PATH}NOTICE`,
        description: "The installed CAD runtime third-party attribution notice."
      },
      {
        id: "cad-compat-0-8-0-wasm-directory",
        rendererId: "cad",
        kind: "wasm-directory",
        target: "public",
        required: true,
        defaultPath: `wasm/cad/${COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION}/`,
        description: "Legacy @flyfish-dev/cad-viewer 0.8.0 directory kept for full-package path compatibility."
      },
      {
        id: "cad-compat-0-8-0-dwg-worker",
        rendererId: "cad",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: `wasm/cad/${COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION}/dwg-worker.js`,
        description: "Legacy CAD 0.8.0 DWG worker kept for full-package path compatibility."
      },
      {
        id: "cad-compat-0-8-0-dwf-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: `wasm/cad/${COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION}/dwfv-render.wasm`,
        description: "Legacy CAD 0.8.0 DWF runtime kept for full-package path compatibility."
      },
      {
        id: "cad-compat-0-8-0-libredwg-script",
        rendererId: "cad",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: `wasm/cad/${COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION}/libredwg-web.js`,
        description: "Legacy CAD 0.8.0 LibreDWG script kept for full-package path compatibility."
      },
      {
        id: "cad-compat-0-8-0-libredwg-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: `wasm/cad/${COMPATIBILITY_FILE_VIEWER_CAD_RUNTIME_VERSION}/libredwg-web.wasm`,
        description: "Legacy CAD 0.8.0 LibreDWG WebAssembly runtime kept for full-package path compatibility."
      },
      {
        id: "cad-legacy-dwg-worker",
        rendererId: "cad",
        kind: "worker",
        target: "public",
        required: false,
        defaultPath: "wasm/cad/dwg-worker.js",
        description: "Unversioned compatibility alias for deployments that explicitly configured the former DWG worker path."
      },
      {
        id: "cad-legacy-dwf-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: false,
        defaultPath: "wasm/cad/dwfv-render.wasm",
        description: "Unversioned compatibility alias for deployments that explicitly configured the former DWF runtime path."
      },
      {
        id: "cad-legacy-libredwg-script",
        rendererId: "cad",
        kind: "script",
        target: "public",
        required: false,
        defaultPath: "wasm/cad/libredwg-web.js",
        description: "Unversioned compatibility alias for the former LibreDWG JavaScript runtime path."
      },
      {
        id: "cad-legacy-libredwg-wasm",
        rendererId: "cad",
        kind: "wasm",
        target: "public",
        required: false,
        defaultPath: "wasm/cad/libredwg-web.wasm",
        description: "Unversioned compatibility alias for the former LibreDWG WebAssembly runtime path."
      }
    ]
  },
  {
    rendererId: "office-word-openxml",
    assets: [
      {
        id: "docx-worker",
        rendererId: "office-word-openxml",
        kind: "worker",
        target: "public",
        required: false,
        defaultPath: DEFAULT_FILE_VIEWER_DOCX_WORKER_PATH,
        optionPath: "docx.workerUrl",
        description: "Optional @file-viewer/docx worker for off-main-thread DOCX ZIP/XML parsing."
      },
      {
        id: "docx-worker-jszip",
        rendererId: "office-word-openxml",
        kind: "script",
        target: "public",
        required: false,
        defaultPath: DEFAULT_FILE_VIEWER_DOCX_WORKER_JSZIP_PATH,
        optionPath: "docx.workerJsZipUrl",
        description: "JSZip runtime loaded by the @file-viewer/docx worker for fully offline DOCX parsing."
      }
    ]
  },
  {
    rendererId: "office-presentation-binary",
    assets: [
      {
        id: "ppt-module",
        rendererId: "office-presentation-binary",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PPT_MODULE_PATH,
        optionPath: "presentation.pptModuleUrl",
        description: "Self-hosted TypeScript PPT standalone module for PowerPoint 97\u20132003 preview."
      },
      {
        id: "ppt-worker",
        rendererId: "office-presentation-binary",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_PPT_WORKER_PATH,
        optionPath: "presentation.pptWorkerUrl",
        description: "TypeScript PPT parsing Worker; layout and Canvas rendering use the main thread."
      },
      {
        id: "ppt-runtime-dist",
        rendererId: "office-presentation-binary",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/dist`,
        description: "Unmodified compiled JavaScript and declarations from the installed PPT package."
      },
      {
        id: "ppt-runtime-manifest",
        rendererId: "office-presentation-binary",
        kind: "metadata",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/dist/manifest.json`,
        description: "Integrity and edition metadata for the official binary-PPT runtime."
      },
      {
        id: "ppt-runtime-package",
        rendererId: "office-presentation-binary",
        kind: "metadata",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/package.json`,
        description: "Package identity metadata for the official binary-PPT runtime."
      },
      {
        id: "ppt-runtime-readme",
        rendererId: "office-presentation-binary",
        kind: "metadata",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/README.md`,
        description: "Usage and supported-format limits shipped with the PPT runtime."
      },
      {
        id: "ppt-runtime-license",
        rendererId: "office-presentation-binary",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/LICENSE`,
        description: "License shipped by the independently versioned @file-viewer/ppt package."
      },
      {
        id: "ppt-runtime-notice",
        rendererId: "office-presentation-binary",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: `${DEFAULT_FILE_VIEWER_PPT_RUNTIME_PATH}/NOTICE.md`,
        description: "Notices shipped by the independently versioned @file-viewer/ppt package."
      }
    ]
  },
  {
    rendererId: "office-presentation",
    assets: [
      {
        id: "pptx-worker",
        rendererId: "office-presentation",
        kind: "worker",
        target: "public",
        required: false,
        defaultPath: DEFAULT_FILE_VIEWER_PRESENTATION_WORKER_PATH,
        optionPath: "presentation.workerUrl",
        description: "Optional @file-viewer/pptx worker for stable PPTX parsing in IIFE, CDN, and offline deployments."
      }
    ]
  },
  {
    rendererId: "spreadsheet-openxml",
    assets: [
      {
        id: "spreadsheet-worker",
        rendererId: "spreadsheet-openxml",
        kind: "worker",
        target: "public",
        required: false,
        defaultPath: DEFAULT_FILE_VIEWER_SPREADSHEET_WORKER_PATH,
        optionPath: "spreadsheet.workerUrl",
        description: "Optional Spreadsheet worker for off-main-thread styled-exceljs workbook parsing."
      }
    ]
  },
  ...["apple-pages", "apple-numbers", "apple-keynote"].map((rendererId) => ({
    rendererId,
    assets: [
      {
        id: `${rendererId}-iwork-worker`,
        rendererId,
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_IWORK_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_IWORK_WORKER_PACKAGE_PATH,
        optionPath: "iwork.workerUrl",
        description: "Module Worker for bounded ZIP, Snappy, IWA/Protobuf and iWork 09 XML/APXL parsing."
      }
    ]
  })),
  {
    rendererId: "office-hangul",
    assets: [
      {
        id: "hangul-worker",
        rendererId: "office-hangul",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_HANGUL_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_HANGUL_WORKER_PACKAGE_PATH,
        optionPath: "hangul.workerUrl",
        description: "Module Worker for bounded HWP v5 CFB and HWPX ZIP/XML parsing."
      }
    ]
  },
  {
    rendererId: "office-wordperfect",
    assets: [
      {
        id: "wordperfect-worker",
        rendererId: "office-wordperfect",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_WORDPERFECT_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_WORDPERFECT_WORKER_PACKAGE_PATH,
        optionPath: "wordPerfect.workerUrl",
        description: "Module Worker for bounded WordPerfect signature detection and parsing."
      },
      {
        id: "wordperfect-libwpd-wasm",
        rendererId: "office-wordperfect",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_WORDPERFECT_WASM_PATH,
        packagePath: DEFAULT_FILE_VIEWER_WORDPERFECT_WASM_PACKAGE_PATH,
        optionPath: "wordPerfect.wasmUrl",
        description: "MPL-2.0 libwpd/librevenge WebAssembly parser lazy-loaded by the WordPerfect Worker."
      },
      {
        id: "wordperfect-libwpd-module",
        rendererId: "office-wordperfect",
        kind: "script",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_WORDPERFECT_MODULE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_WORDPERFECT_MODULE_PACKAGE_PATH,
        description: "Emscripten ES module loader for the MPL-2.0 libwpd/librevenge WebAssembly runtime."
      },
      {
        id: "wordperfect-third-party-notices",
        rendererId: "office-wordperfect",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: "vendor/wordperfect/THIRD_PARTY_NOTICES.md",
        packagePath: "@file-viewer/renderer-wordperfect/third-party-notices",
        description: "Matching source availability and third-party notices for the WordPerfect native runtime."
      },
      {
        id: "wordperfect-native-licenses",
        rendererId: "office-wordperfect",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: "vendor/wordperfect/licenses",
        description: "Complete parser and linked toolchain licenses and native provenance."
      }
    ]
  },
  {
    rendererId: "typst",
    assets: [
      {
        id: "typst-native-third-party-licenses",
        rendererId: "typst",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: "wasm/typst/NATIVE_THIRD_PARTY_LICENSES.json",
        packagePath: "@file-viewer/renderer-typst/native-third-party-licenses",
        description: "Complete collected native dependency license texts and matching Typst WASM provenance."
      },
      {
        id: "typst-compiler-wasm",
        rendererId: "typst",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_TYPST_COMPILER_WASM_URL,
        packagePath: DEFAULT_FILE_VIEWER_TYPST_COMPILER_WASM_PACKAGE_PATH,
        optionPath: "typst.compilerWasmUrl",
        description: "Typst compiler WebAssembly module copied to the public assets directory."
      },
      {
        id: "typst-renderer-wasm",
        rendererId: "typst",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_TYPST_RENDERER_WASM_URL,
        packagePath: DEFAULT_FILE_VIEWER_TYPST_RENDERER_WASM_PACKAGE_PATH,
        optionPath: "typst.rendererWasmUrl",
        description: "Typst SVG renderer WebAssembly module copied to the public assets directory."
      },
      {
        id: "typst-font-assets",
        rendererId: "typst",
        kind: "directory",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_TYPST_FONT_ASSETS_URL,
        optionPath: "typst.fontAssetsUrl",
        description: "Self-hosted default Typst text fonts used by typst.ts without public CDN requests."
      }
    ]
  },
  {
    rendererId: "illustrator-pdf-design",
    assets: [
      ...createDesignThirdPartyAssets("illustrator-pdf-design"),
      {
        id: "illustrator-pgf-license",
        rendererId: "illustrator-pdf-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_LICENSE_PACKAGE_PATH,
        description: "illustrator-pgf MIT license text for the bundled native Illustrator Worker."
      },
      {
        id: "illustrator-pgf-worker",
        rendererId: "illustrator-pdf-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_WORKER_PACKAGE_PATH,
        optionPath: "design.illustratorWorkerUrl",
        description: "Terminable module Worker for bounded native Illustrator PGF/private-source parsing and Canvas rendering."
      },
      {
        id: "illustrator-zstd-license",
        rendererId: "illustrator-pdf-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_ZSTD_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_ILLUSTRATOR_ZSTD_LICENSE_PACKAGE_PATH,
        description: "fzstd MIT license text for the bounded streaming zstd decoder bundled into the Illustrator Worker."
      }
    ]
  },
  {
    rendererId: "photoshop-design",
    assets: [
      ...createDesignThirdPartyAssets("photoshop-design"),
      ...createPhotoshopWorkerLicenseAssets("photoshop-design", true),
      {
        id: "photoshop-design-worker",
        rendererId: "photoshop-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_WORKER_PACKAGE_PATH,
        optionPath: "design.workerUrl",
        description: "Module Worker for bounded PSD/PSB parsing and composite/layer pixel synthesis."
      }
    ]
  },
  {
    rendererId: "photoshop-resource-design",
    assets: [
      ...createDesignThirdPartyAssets("photoshop-resource-design"),
      ...createPhotoshopWorkerLicenseAssets("photoshop-resource-design"),
      {
        id: "photoshop-resource-worker",
        rendererId: "photoshop-resource-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_ADOBE_RESOURCE_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_ADOBE_RESOURCE_WORKER_PACKAGE_PATH,
        optionPath: "design.adobeResourceWorkerUrl",
        description: "Module Worker for bounded Photoshop ABR, CSH, PAT, GRD, and ASL resource parsing."
      }
    ]
  },
  {
    rendererId: "adobe-palette-design",
    assets: [
      ...createDesignThirdPartyAssets("adobe-palette-design", true),
      {
        id: "adobe-palette-container-worker",
        rendererId: "adobe-palette-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH,
        optionPath: "design.containerWorkerUrl",
        description: "Terminable module Worker for bounded ASE and ACO palette parsing."
      }
    ]
  },
  {
    rendererId: "indesign-exchange-design",
    assets: [
      ...createDesignThirdPartyAssets("indesign-exchange-design", true),
      {
        id: "indesign-exchange-container-worker",
        rendererId: "indesign-exchange-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH,
        optionPath: "design.containerWorkerUrl",
        description: "Terminable module Worker for bounded ICML, IDMS, and legacy INX parsing and layout-fragment reconstruction."
      }
    ]
  },
  {
    rendererId: "adobe-animate-xfl-design",
    assets: [
      ...createDesignThirdPartyAssets("adobe-animate-xfl-design", true),
      {
        id: "adobe-animate-xfl-container-worker",
        rendererId: "adobe-animate-xfl-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH,
        optionPath: "design.containerWorkerUrl",
        description: "Terminable module Worker for bounded modern ZIP/XFL-based Animate FLA parsing and first-frame reconstruction."
      }
    ]
  },
  {
    rendererId: "adobe-xd-design",
    assets: [
      ...createDesignThirdPartyAssets("adobe-xd-design", true),
      {
        id: "adobe-xd-container-worker",
        rendererId: "adobe-xd-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH,
        optionPath: "design.containerWorkerUrl",
        description: "Terminable module Worker for bounded XD package parsing and saved-preview extraction."
      }
    ]
  },
  {
    rendererId: "indesign-native-design",
    assets: [
      ...createDesignThirdPartyAssets("indesign-native-design", true),
      {
        id: "indesign-native-container-worker",
        rendererId: "indesign-native-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_DESIGN_CONTAINER_WORKER_PACKAGE_PATH,
        optionPath: "design.containerWorkerUrl",
        description: "Terminable module Worker for bounded native INDD and INDT parsing."
      }
    ]
  },
  {
    rendererId: "postscript-design",
    assets: [
      ...createDesignThirdPartyAssets("postscript-design"),
      {
        id: "postscript-design-worker",
        rendererId: "postscript-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_WORKER_PACKAGE_PATH,
        optionPath: "design.postscriptWorkerUrl",
        description: "Terminable module Worker for bounded EPS/PostScript execution and page rasterization."
      },
      {
        id: "postscript-design-wasm",
        rendererId: "postscript-design",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_WASM_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_WASM_PACKAGE_PATH,
        optionPath: "design.postscriptWasmUrl",
        description: "Unpatched Stet WebAssembly interpreter with URW Base35 OFL fonts and the CC0 Compact ICC CMYK profile."
      },
      {
        id: "postscript-design-license-stet-apache",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_APACHE_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_APACHE_LICENSE_PACKAGE_PATH,
        description: "Stet Apache-2.0 license text."
      },
      {
        id: "postscript-design-license-stet-mit",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_MIT_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_STET_MIT_LICENSE_PACKAGE_PATH,
        description: "Stet MIT license text."
      },
      {
        id: "postscript-design-license-urw-ofl",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_URW_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_URW_LICENSE_PACKAGE_PATH,
        description: "URW Base35 font provenance, copyright notices and complete SIL OFL 1.1 text."
      },
      {
        id: "postscript-design-license-cmyk-provenance",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CMYK_NOTICE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CMYK_NOTICE_PACKAGE_PATH,
        description: "Provenance of the CC0 Compact ICC CMYK profile embedded by Stet."
      },
      {
        id: "postscript-design-license-cc0",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CC0_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CC0_LICENSE_PACKAGE_PATH,
        description: "Complete CC0 1.0 legal text for the embedded CMYK profile."
      },
      {
        id: "postscript-design-license-native-dependencies",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_NATIVE_NOTICES_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_NATIVE_NOTICES_PACKAGE_PATH,
        description: "Exact locked Rust dependency legal materials and original standard-library grants, bound to the Stet WASM hash."
      },
      {
        id: "postscript-design-license-carlito-ofl",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CARLITO_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_CARLITO_LICENSE_PACKAGE_PATH,
        description: "Carlito SIL Open Font License 1.1 text."
      },
      {
        id: "postscript-design-license-tinos-ofl",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_TINOS_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_TINOS_LICENSE_PACKAGE_PATH,
        description: "Tinos SIL Open Font License 1.1 text."
      },
      {
        id: "postscript-design-license-cousine-ofl",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_COUSINE_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_COUSINE_LICENSE_PACKAGE_PATH,
        description: "Cousine SIL Open Font License 1.1 text."
      },
      {
        id: "postscript-design-license-noto-symbols-ofl",
        rendererId: "postscript-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_POSTSCRIPT_NOTO_SYMBOLS_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_POSTSCRIPT_NOTO_SYMBOLS_LICENSE_PACKAGE_PATH,
        description: "Noto Sans Symbols 2 SIL Open Font License 1.1 text."
      }
    ]
  },
  {
    rendererId: "indesign-idml-design",
    assets: [
      ...createDesignThirdPartyAssets("indesign-idml-design"),
      {
        id: "indesign-idml-native-third-party-licenses",
        rendererId: "indesign-idml-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: "vendor/design/Introspect_NATIVE_THIRD_PARTY_LICENSES.json",
        packagePath: "@file-viewer/renderer-design/licenses/Introspect_NATIVE_THIRD_PARTY_LICENSES.json",
        description: "Complete collected native dependency license texts and matching Introspect WASM provenance."
      },
      {
        id: "indesign-idml-worker",
        rendererId: "indesign-idml-design",
        kind: "worker",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_IDML_WORKER_PATH,
        packagePath: DEFAULT_FILE_VIEWER_IDML_WORKER_PACKAGE_PATH,
        optionPath: "design.idmlWorkerUrl",
        description: "Module Worker that validates IDML packages and renders pages outside the UI thread."
      },
      {
        id: "indesign-idml-wasm",
        rendererId: "indesign-idml-design",
        kind: "wasm",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_IDML_WASM_PATH,
        packagePath: DEFAULT_FILE_VIEWER_IDML_WASM_PACKAGE_PATH,
        optionPath: "design.idmlWasmUrl",
        description: "Self-hosted @paged-media/introspect-wasm CPU renderer used by the IDML Worker."
      },
      {
        id: "indesign-idml-license",
        rendererId: "indesign-idml-design",
        kind: "license",
        target: "public",
        required: true,
        defaultPath: DEFAULT_FILE_VIEWER_IDML_LICENSE_PATH,
        packagePath: DEFAULT_FILE_VIEWER_IDML_LICENSE_PACKAGE_PATH,
        description: "MPL-2.0 license text distributed with the IDML WebAssembly engine."
      }
    ]
  },
  {
    rendererId: "data-asset",
    assets: [
      {
        id: "data-sql-wasm",
        rendererId: "data-asset",
        kind: "wasm",
        target: "public",
        required: false,
        defaultPath: DEFAULT_FILE_VIEWER_DATA_SQL_WASM_URL,
        packagePath: DEFAULT_FILE_VIEWER_DATA_SQL_WASM_PACKAGE_PATH,
        optionPath: "data.sqlWasmUrl",
        description: "sql.js WebAssembly module copied to the public assets directory for SQLite previews."
      }
    ]
  }
];
var DEFAULT_FILE_VIEWER_DOCUMENT_BASE_URL = "file:///";
var resolveFileViewerAssetUrl = (value, fallback, options = {}) => {
  const raw = value ? String(value) : fallback;
  const documentBaseUrl = options.documentBaseUrl || DEFAULT_FILE_VIEWER_DOCUMENT_BASE_URL;
  const configuredBaseUrl = !value && configuredFileViewerAssetBaseUrl !== automaticFileViewerAssetBaseUrl ? configuredFileViewerAssetBaseUrl : void 0;
  const preferredBaseUrl = options.baseUrl || configuredBaseUrl;
  const baseUrl = preferredBaseUrl ? preferredBaseUrl.endsWith("/") ? preferredBaseUrl : `${preferredBaseUrl}/` : documentBaseUrl;
  const resolvedBase = preferredBaseUrl ? new URL(baseUrl, documentBaseUrl).href : baseUrl;
  const resolved = new URL(raw, resolvedBase).href;
  return options.trimTrailingSlash ? resolved.replace(/\/+$/, "") : resolved;
};
var resolveFileViewerPostscriptWorkerUrl = (options, documentBaseUrl) => resolveFileViewerAssetUrl(
  options?.postscriptWorkerUrl,
  DEFAULT_FILE_VIEWER_POSTSCRIPT_WORKER_PATH,
  { documentBaseUrl }
);
var resolveFileViewerPostscriptWasmUrl = (options, documentBaseUrl) => resolveFileViewerAssetUrl(
  options?.postscriptWasmUrl,
  DEFAULT_FILE_VIEWER_POSTSCRIPT_WASM_PATH,
  { documentBaseUrl }
);

// packages/core/src/registry/formats.generated.ts
var DEFAULT_RENDERER_DEFINITIONS = [
  {
    "id": "office-word-openxml",
    "label": "Word OpenXML",
    "category": "office",
    "extensions": [
      "docx",
      "docm",
      "dotx",
      "dotm"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-word",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "OOXML Transitional",
      "OOXML Strict"
    ],
    "knownLimits": [
      "VBA is never executed"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "office-word-binary",
    "label": "Word Binary",
    "category": "office",
    "extensions": [
      "doc",
      "dot"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-word",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "Word 97-2003 Binary"
    ],
    "knownLimits": [
      "Macros are never executed"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "office-presentation-binary",
    "label": "PowerPoint 97\u20132003",
    "category": "office",
    "extensions": [
      "ppt",
      "pot"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-ppt",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "PowerPoint 97-2003 Binary"
    ],
    "knownLimits": [
      "Host fonts and complex effects can differ from PowerPoint",
      "Macros are never executed"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "office-presentation",
    "label": "PowerPoint OpenXML",
    "category": "office",
    "extensions": [
      "pptx",
      "pptm",
      "potx",
      "potm",
      "ppsx",
      "ppsm"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-pptx",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "OOXML Transitional",
      "OOXML Strict"
    ],
    "knownLimits": [
      "Macros and external programs are never executed"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "open-document",
    "label": "Open Document",
    "category": "office",
    "extensions": [
      "rtf",
      "odt",
      "odp"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-word",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "RTF",
      "OpenDocument"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "spreadsheet-openxml",
    "label": "Spreadsheet",
    "category": "office",
    "extensions": [
      "xlsx",
      "xltx",
      "xlsm",
      "xlsb",
      "xls",
      "xlt",
      "xla",
      "xlam",
      "xltm",
      "csv",
      "tsv",
      "ods",
      "fods"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-spreadsheet",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "OOXML",
      "BIFF",
      "OpenDocument",
      "Delimited text"
    ],
    "knownLimits": [
      "VBA and add-in code are never executed",
      "Formula results are read from the saved workbook cache"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "apple-pages",
    "label": "Apple Pages",
    "category": "office",
    "extensions": [
      "pages"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-iwork",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "iWork '09 index.xml(.gz)",
      "iWork 2013+ IWA"
    ],
    "knownLimits": [
      "Static preview only",
      "Encrypted iwpv2 files are detected but not decrypted"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "apple-numbers",
    "label": "Apple Numbers",
    "category": "office",
    "extensions": [
      "numbers"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-iwork",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "iWork '09 index.xml",
      "iWork 2013+ IWA"
    ],
    "knownLimits": [
      "Formula results are read from the saved document cache",
      "Encrypted iwpv2 files are detected but not decrypted"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "apple-keynote",
    "label": "Apple Keynote",
    "category": "office",
    "extensions": [
      "key"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-iwork",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "iWork '09 index.apxl",
      "iWork 2013+ IWA"
    ],
    "knownLimits": [
      "Animations, transitions and video playback are not executed",
      "Encrypted iwpv2 files are detected but not decrypted"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "office-wordperfect",
    "label": "WordPerfect",
    "category": "office",
    "extensions": [
      "wpd",
      "wp",
      "wp5",
      "wp6"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-wordperfect",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "WordPerfect 4.2",
      "WordPerfect 5.x",
      "WordPerfect 6+"
    ],
    "knownLimits": [
      "Macros are never executed",
      ".wp5 and .wp6 are routing aliases for genuine WP5/WP6 payloads, not separate container formats",
      "Pagination and unsupported embedded objects are presented as structured static preview"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "spreadsheet-dbf",
    "label": "dBASE Table",
    "category": "office",
    "extensions": [
      "dbf"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-spreadsheet",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "dBASE III/IV",
      "Visual FoxPro"
    ],
    "knownLimits": [
      "Missing DBT/FPT memo sidecars are reported as incomplete"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "pdf",
    "label": "PDF",
    "category": "document",
    "extensions": [
      "pdf"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-pdf",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "PDF"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": "provider"
    }
  },
  {
    "id": "ofd",
    "label": "OFD",
    "category": "document",
    "extensions": [
      "ofd"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-ofd",
    "presets": [
      "standard",
      "office",
      "all"
    ],
    "containerVersions": [
      "OFD"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "office-hangul",
    "label": "Hancom Hangul",
    "category": "office",
    "extensions": [
      "hwp",
      "hwpx"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-hangul",
    "presets": [
      "office",
      "all"
    ],
    "containerVersions": [
      "HWP v5 CFB",
      "HWPX ZIP/XML"
    ],
    "knownLimits": [
      "Encrypted, DRM-protected and distribution documents are detected but not decrypted",
      "Charts, OLE objects and advanced drawing effects remain limited in the static structured preview",
      "HWP v5 pagination is approximated when the binary producer omits usable page geometry"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "typst",
    "label": "Typst",
    "category": "document",
    "extensions": [
      "typ",
      "typst"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-typst",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "Typst source"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "archive",
    "label": "Archive",
    "category": "archive",
    "extensions": [
      "zip",
      "zipx",
      "7z",
      "rar",
      "tar",
      "gz",
      "gzip",
      "tgz",
      "bz2",
      "bzip2",
      "tbz",
      "tbz2",
      "xz",
      "txz",
      "lzma",
      "zst",
      "tzst",
      "cab",
      "ar",
      "cpio",
      "iso",
      "xar",
      "lha",
      "lzh",
      "jar",
      "war",
      "ear",
      "apk",
      "cbz",
      "cbr"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-archive",
    "presets": [
      "standard",
      "all"
    ],
    "containerVersions": [
      "libarchive-supported containers"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "chm",
    "label": "Compiled HTML Help",
    "category": "ebook",
    "extensions": [
      "chm"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-chm",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "Microsoft HTML Help ITSF v2/v3",
      "LZX MSCompressed and uncompressed content"
    ],
    "knownLimits": [
      "ActiveX, Shortcut/WinHelp commands, scripts and external network resources are intentionally blocked",
      "Merged help collections require each referenced CHM file to be opened separately"
    ],
    "capabilities": {
      "download": true,
      "print": "adapter",
      "exportHtml": "adapter",
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "email",
    "label": "Email",
    "category": "email",
    "extensions": [
      "eml",
      "msg",
      "mbox"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-email",
    "presets": [
      "standard",
      "all"
    ],
    "containerVersions": [
      "MIME",
      "Outlook MSG",
      "mbox"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "eda",
    "label": "EDA",
    "category": "eda",
    "extensions": [
      "olb",
      "dra",
      "gds",
      "oas",
      "oasis"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-eda",
    "presets": [
      "engineering",
      "all"
    ],
    "containerVersions": [
      "OrCAD",
      "GDSII",
      "OASIS"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "cad",
    "label": "CAD",
    "category": "cad",
    "extensions": [
      "dxf",
      "dwg",
      "dwf",
      "dwfx",
      "xps"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-cad",
    "presets": [
      "engineering",
      "all"
    ],
    "containerVersions": [
      "DWG",
      "DXF",
      "DWF",
      "DWFX/XPS"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "model",
    "label": "3D Model",
    "category": "model",
    "extensions": [
      "glb",
      "gltf",
      "obj",
      "stl",
      "ply",
      "fbx",
      "dae",
      "3ds",
      "3mf",
      "amf",
      "usd",
      "usda",
      "usdc",
      "usdz",
      "kmz",
      "step",
      "stp",
      "iges",
      "igs",
      "ifc",
      "3dm",
      "brep",
      "pcd",
      "wrl",
      "vrml",
      "xyz",
      "vtk",
      "vtp"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-3d",
    "presets": [
      "engineering",
      "all"
    ],
    "containerVersions": [
      "Mesh",
      "CAD exchange",
      "scene"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "geo",
    "label": "Geospatial",
    "category": "geo",
    "extensions": [
      "geojson",
      "kml",
      "gpx",
      "shp"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-geo",
    "presets": [
      "engineering",
      "all"
    ],
    "containerVersions": [
      "GeoJSON",
      "KML",
      "GPX",
      "Shapefile"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "drawing",
    "label": "Drawing",
    "category": "drawing",
    "extensions": [
      "excalidraw",
      "drawio",
      "dio",
      "mermaid",
      "mmd",
      "plantuml",
      "puml"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-drawing",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "Draw.io",
      "Excalidraw",
      "Mermaid",
      "PlantUML"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "bpmn",
    "label": "BPMN 2.0",
    "category": "drawing",
    "extensions": [
      "bpmn"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-drawing",
    "presets": [],
    "containerVersions": [
      "BPMN 2.0 XML with BPMN DI"
    ],
    "knownLimits": [
      "Explicit opt-in with bpmn-js",
      "Diagram preview requires BPMN DI layout; source remains available without it",
      "Read-only preview; process scripts are never executed",
      "The bpmn.io watermark is retained under the upstream license"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "mindmap",
    "label": "Mind Map",
    "category": "mindmap",
    "extensions": [
      "xmind"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-mindmap",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "XMind"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "epub",
    "label": "EPUB",
    "category": "ebook",
    "extensions": [
      "epub"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-epub",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "EPUB 2",
      "EPUB 3"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": true,
      "zoom": false,
      "search": "provider"
    }
  },
  {
    "id": "ebook-fb2",
    "label": "FictionBook",
    "category": "ebook",
    "extensions": [
      "fb2"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-epub",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "FictionBook 2 XML"
    ],
    "knownLimits": [
      "External network resources are not loaded"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "umd",
    "label": "UMD",
    "category": "ebook",
    "extensions": [
      "umd"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-epub",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "UMD"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": true
    }
  },
  {
    "id": "image",
    "label": "Image",
    "category": "image",
    "extensions": [
      "gif",
      "jpg",
      "jpeg",
      "bmp",
      "tiff",
      "tif",
      "png",
      "svg",
      "webp",
      "avif",
      "ico",
      "heic",
      "heif",
      "jxl"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-image",
    "presets": [
      "lite",
      "standard",
      "all"
    ],
    "containerVersions": [
      "Raster",
      "SVG"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "dicom",
    "label": "DICOM",
    "category": "medical-image",
    "extensions": [
      "dcm",
      "dicom"
    ],
    "async": true,
    "supportLevel": "basic",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-dicom",
    "presets": [],
    "containerVersions": [
      "DICOM Part 10"
    ],
    "knownLimits": [
      "Local single-file and multi-frame viewing only; series assembly, PACS/DICOMweb, MPR, segmentation, measurement tools, and diagnostic-use claims are not included",
      "Tested transfer syntaxes are Implicit/Explicit VR Little Endian, JPEG Lossless Process 14 SV1, JPEG-LS Lossless, and JPEG 2000 Lossless"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": "provider",
      "search": false
    }
  },
  {
    "id": "signature",
    "label": "Digital signatures and evidence containers",
    "category": "cryptographic-container",
    "extensions": [
      "p7m",
      "p7s",
      "p7c",
      "p7b",
      "pkcs7",
      "cms",
      "cmsc",
      "tsd",
      "tst",
      "tsq",
      "tsr",
      "asics",
      "scs",
      "asice",
      "sce",
      "ers",
      "asc",
      "sig",
      "pgp",
      "gpg",
      "jws"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-signature",
    "presets": [],
    "containerVersions": [
      "CMS/PKCS#7",
      "CAdES attributes",
      "RFC 3161",
      "RFC 5544",
      "ASiC-S/E",
      "RFC 4998",
      "RFC 7515",
      "OpenPGP RFC 9580"
    ],
    "knownLimits": [
      "Opt-in renderer; it is not added to the published preset-all/full compatibility closure",
      "Cryptographic checks are reported separately from certificate/key trust, policy, qualified-signature status and legal validity",
      "ASiC XML references and RFC 4998 renewal chains are structurally inspected; full XAdES and archival-policy validation are not claimed",
      "OpenPGP private-key operations and automatic decryption are intentionally excluded"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "markdown",
    "label": "Markdown",
    "category": "markdown",
    "extensions": [
      "md",
      "markdown"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-text",
    "presets": [
      "lite",
      "standard",
      "all"
    ],
    "containerVersions": [
      "CommonMark/GFM"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "code",
    "label": "Code and Text",
    "category": "code",
    "extensions": [
      "txt",
      "lrc",
      "json",
      "js",
      "mjs",
      "cjs",
      "css",
      "java",
      "py",
      "html",
      "htm",
      "jsx",
      "ts",
      "tsx",
      "xml",
      "log",
      "vue",
      "yaml",
      "yml",
      "ini",
      "sh",
      "bash",
      "sql",
      "go",
      "rs",
      "php",
      "c",
      "cpp",
      "cc",
      "h",
      "hpp",
      "cs",
      "diff",
      "patch",
      "bundle",
      "bdl",
      "jsonc",
      "json5",
      "ipynb",
      "toml",
      "proto",
      "hcl",
      "tex",
      "gv",
      "http",
      "react",
      "rb",
      "swift",
      "kt"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-text",
    "presets": [
      "lite",
      "standard",
      "all"
    ],
    "containerVersions": [
      "Plain text",
      "source code",
      "Git bundle",
      "LRC lyrics"
    ],
    "knownLimits": [
      "LRC is a static annotated/lyrics/source preview, not synchronized audio playback"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "video",
    "label": "Video",
    "category": "media",
    "extensions": [
      "mp4",
      "webm",
      "m3u8"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-media",
    "presets": [
      "lite",
      "standard",
      "all"
    ],
    "containerVersions": [
      "Browser media"
    ],
    "knownLimits": [
      "Codec support follows the browser"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "audio",
    "label": "Audio",
    "category": "media",
    "extensions": [
      "mp3",
      "mpeg",
      "wav",
      "ogg",
      "oga",
      "opus",
      "m4a",
      "aac",
      "flac",
      "weba",
      "midi",
      "mid"
    ],
    "async": true,
    "supportLevel": "high-fidelity",
    "status": "stable",
    "packageName": "@file-viewer/renderer-media",
    "presets": [
      "lite",
      "standard",
      "all"
    ],
    "containerVersions": [
      "Browser media",
      "MIDI"
    ],
    "knownLimits": [
      "Codec support follows the browser"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "photoshop-design",
    "label": "Adobe Photoshop",
    "category": "asset",
    "extensions": [
      "psb",
      "pdd",
      "psdt"
    ],
    "async": true,
    "supportLevel": "experimental",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "enhancesRendererId": "data-asset",
    "enhancesExtensions": [
      "psd"
    ],
    "containerVersions": [
      "PSD v1",
      "PSB v2"
    ],
    "knownLimits": [
      "Pixel rendering is enabled only for 8-bit RGB and grayscale documents; unsupported color modes and bit depths are rejected instead of decoded incorrectly",
      "The untouched merged composite is the fidelity reference and must have been saved with Maximize Compatibility using Raw or PackBits RLE compression; ZIP composites are rejected",
      "Auxiliary channels are accepted only when PSD layer-info declares one merged-transparency channel; PSB currently requires exactly the base RGB or grayscale channels",
      "Embedded ICC profiles are detected but not color-converted yet, so profiled color is not reference-verified",
      "The PSD/PSB container version is taken from the 8BPS header; a mismatched filename extension is diagnosed and never used as the format authority",
      "Legacy PhotoDeluxe PDD and Photoshop template PSDT inputs are accepted only when the bytes validate as a PSD v1 8BPS container; unrelated files sharing those extensions are rejected",
      "PSD layer visibility is interactive only for flat normal-blend 100%-opacity documents without masks, effects, clipping, adjustments, groups, or resource-limit violations",
      "PSB currently exposes the saved composite and a read-only layer tree; interactive PSB layer recomposition is not claimed, and PSB files containing ZIP-compressed layer channels are rejected"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": false,
      "zoom": true,
      "search": false
    }
  },
  {
    "id": "illustrator-pdf-design",
    "label": "Adobe Illustrator AI/AIT",
    "category": "asset",
    "extensions": [
      "ait"
    ],
    "async": true,
    "supportLevel": "experimental",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "enhancesRendererId": "data-asset",
    "enhancesExtensions": [
      "ai"
    ],
    "containerVersions": [
      "Illustrator PDF-compatible AI/AIT",
      "Illustrator native PGF/private source"
    ],
    "knownLimits": [
      "Automatic mode prefers the verified PDF-compatible surface for the highest saved appearance fidelity, while Native PGF mode parses the editable private source in a dedicated bounded Worker and exposes native artboards and layer visibility",
      "A PDF header alone is insufficient: the renderer also requires Illustrator-origin XMP, MIME, creator, or AIPrivateData evidence so an ordinary renamed PDF is not advertised as an Illustrator document",
      "The packaged browser Worker decodes uncompressed, deflate, and Illustrator 24 zstd private source entirely offline; zstd output is streamed through the same decoded-byte ceiling and unsupported long-distance frames fail explicitly",
      "Native PGF rendering currently preserves and reports unknown operators but does not claim complete Illustrator gradients, text shaping, placed or embedded images, plugins, effects, masks, blending, overprint, spot-color management, or font substitution fidelity",
      "The PDF renderer is required only for the saved PDF surface; native-only AI/AIT can open without it, and PDF pages or optional-content groups are not presented as native artboards or layers"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": false,
      "zoom": true,
      "search": true
    }
  },
  {
    "id": "indesign-idml-design",
    "label": "Adobe InDesign IDML",
    "category": "asset",
    "extensions": [
      "idml"
    ],
    "async": true,
    "supportLevel": "experimental",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "IDML package",
      "@paged-media/introspect-wasm 0.73.4"
    ],
    "knownLimits": [
      "Pages are rendered locally by the CPU WASM engine in a module Worker; the browser never uploads the IDML package",
      "ZIP64, encrypted, multi-disk, overlapping, unsafe-path, unsupported-compression, and configured expansion-limit packages are rejected before the WASM engine opens them",
      "The current engine page tree lists TextFrame and Rectangle objects only even though other supported objects may still appear in rendered page pixels",
      "Each page render rebuilds the upstream document internally; interactive requests are latest-wins, preview is lazy, and print-all is bounded by the configured total RGBA working-set limit"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": false,
      "zoom": true,
      "search": false
    }
  },
  {
    "id": "indesign-exchange-design",
    "label": "Adobe InCopy and InDesign Exchange",
    "category": "asset",
    "extensions": [
      "icml",
      "idms",
      "inx"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "ICML InCopyInterchange",
      "IDMS PageItem",
      "legacy INX"
    ],
    "knownLimits": [
      "ICML is rendered as styled story content because the format does not carry a complete document page layout",
      "IDMS page-item paths, transforms, colors, stories, styles, layers, and linked-resource metadata are parsed in a terminable Worker and shown as a bounded layout-fragment preview; it is not advertised as a complete INDD page",
      "Legacy INX abbreviated records have no maintained browser layout engine; common page items and geometry are visualized while every unmapped element name remains visible in the structure inventory",
      "UTF-8, signature, DTD/entity, source size, node, depth, attribute, text, story, item, point, style, and color limits are enforced; linked resource paths are never fetched"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "adobe-animate-xfl-design",
    "label": "Adobe Animate XFL",
    "category": "asset",
    "extensions": [
      "fla",
      "xfl"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "Modern compressed XFL-based FLA (CS5+)",
      "single DOMDocument XML XFL"
    ],
    "knownLimits": [
      "Modern ZIP/XFL-based FLA is parsed in a terminable Worker; legacy binary FLA (Flash CS4 and earlier) is explicitly rejected",
      "The bounded first-frame preview reconstructs solid shapes, static text, nested symbols, and direct PNG/JPEG instances; masks, filters, tweens, ActionScript, audio/video playback, and proprietary bitmap .dat payloads remain structure-only",
      "A standard uncompressed .xfl is only a marker beside DOMDocument.xml, LIBRARY, and media folders; a single browser File object cannot access those siblings, so it must be packaged as FLA or supplied through a future folder/multi-file API",
      "ZIP64, encryption, multi-disk archives, overlapping records, unsafe or ambiguous paths, CRC failures, unsupported compression, DTD/entity XML, external XML stylesheets, and configured size/node/depth/ratio limits are rejected"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "adobe-xd-design",
    "label": "Adobe XD Package",
    "category": "asset",
    "extensions": [
      "xd"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "XD UCF package",
      "AGC JSON inventory"
    ],
    "knownLimits": [
      "A terminable module Worker shows the highest-resolution structurally referenced embedded PNG/JPEG rendition and a bounded manifest, artboard, layer, and resource inventory",
      "Native AGC vector scene reconstruction is not implemented; files without a saved preview remain structure-only",
      "ZIP64, encrypted, multi-disk, overlapping, unsafe-path, CRC-invalid, unsupported-compression, and configured expansion-limit packages are rejected"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "indesign-native-design",
    "label": "Adobe InDesign Native",
    "category": "asset",
    "extensions": [
      "indd",
      "indt"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "InDesign 2+ native database",
      "INDD",
      "INDT"
    ],
    "knownLimits": [
      "A terminable module Worker shows a JPEG/PNG preview only when it is embedded in a structurally verified contiguous XMP object",
      "The proprietary native layout database is not reconstructed; files without a saved XMP thumbnail remain metadata- or structure-only and should be exported to IDML for full page rendering",
      "The reader follows declared master-page and object boundaries and never scans arbitrary binary bytes for coincidental image signatures; legacy InDesign 1.x is rejected"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  },
  {
    "id": "postscript-design",
    "label": "Adobe EPS and PostScript",
    "category": "asset",
    "extensions": [
      "ps"
    ],
    "async": true,
    "supportLevel": "experimental",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "enhancesRendererId": "data-asset",
    "enhancesExtensions": [
      "eps"
    ],
    "containerVersions": [
      "EPSF/DSC PostScript",
      "Adobe PostScript programs"
    ],
    "knownLimits": [
      "Stet WASM renders pages in a terminable Worker with latest-wins interactive requests and bounded source size, VM memory, page count, dimensions, pixels, DPI, total print working set, and retained canvas cache",
      "The unpatched Stet runtime embeds URW Base35 fonts under OFL-1.1 and the Compact ICC Profiles CGATS001Compat-v2-micro CMYK profile under CC0; document-specific fonts and print conditions can still differ from Adobe applications",
      "This experimental path is not claimed to implement every Adobe PostScript Level 3 operator, font technology, color-management workflow, or printer device"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": false,
      "zoom": true,
      "search": false
    }
  },
  {
    "id": "adobe-palette-design",
    "label": "Adobe Color Palettes",
    "category": "asset",
    "extensions": [
      "ase",
      "aco"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "ASE 1.x",
      "ACO v1/v2"
    ],
    "knownLimits": [
      "ASE RGB, CMYK, Gray, and CIELAB colors and ACO RGB, HSB, CMYK, CIELAB, and Gray colors are parsed with strict bounds in a terminable module Worker",
      "Browser swatches convert CIELAB D50 and device CMYK to approximate sRGB; original model values remain visible for reference",
      "Unknown ASE blocks and bounded ACO trailing application data are skipped and reported rather than executed"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "photoshop-resource-design",
    "label": "Adobe Photoshop Resources and Presets",
    "category": "asset",
    "extensions": [
      "abr",
      "csh",
      "pat",
      "grd",
      "asl"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-design",
    "presets": [],
    "containerVersions": [
      "Photoshop ABR 6.x",
      "Photoshop CSH v2",
      "PAT v1",
      "GRD v5",
      "ASL v2",
      "ag-psd 31.0.2"
    ],
    "knownLimits": [
      "ABR previews decode saved brush-tip alpha, embedded patterns, and bounded preset metadata; they do not simulate Photoshop's stroke engine, dynamics, or paint blending",
      "CSH previews reconstruct bounded Bezier path geometry; subtract, intersect, and exclude composition is exposed as metadata rather than claimed as Photoshop-equivalent raster output",
      "PAT previews decode bounded RGB, grayscale, indexed-color, alpha, Raw, and PackBits pattern tiles; unsupported image modes and compression variants fail closed",
      "GRD previews render saved solid color stops and deterministic bounded noise samples from v5 descriptors; they do not claim Photoshop's complete interpolation and color-management pipeline",
      "ASL previews expose bounded layer-effect descriptors, blend metadata, and embedded pattern thumbnails as a structure view; they do not rasterize Photoshop's full effect stack",
      "Legacy ABR variants before 6.x and unknown CSH container versions are rejected instead of being scanned heuristically"
    ],
    "capabilities": {
      "download": true,
      "print": true,
      "exportHtml": false,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "data-asset",
    "label": "Data Asset",
    "category": "asset",
    "extensions": [
      "ttf",
      "otf",
      "woff",
      "woff2",
      "psd",
      "ai",
      "eps",
      "sqlite",
      "wasm",
      "parquet",
      "avro",
      "webarchive"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "stable",
    "packageName": "@file-viewer/renderer-data",
    "presets": [
      "all"
    ],
    "containerVersions": [
      "Font",
      "design",
      "database",
      "binary data"
    ],
    "knownLimits": [],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": true,
      "zoom": false,
      "search": true
    }
  },
  {
    "id": "binary-inspector",
    "label": "Binary Inspector",
    "category": "asset",
    "extensions": [
      "bin",
      "hex",
      "elf",
      "exe",
      "dll",
      "class",
      "macho"
    ],
    "async": true,
    "supportLevel": "structured",
    "status": "experimental",
    "packageName": "@file-viewer/renderer-binary",
    "presets": [],
    "containerVersions": [
      "Raw bytes",
      "ELF",
      "PE/COFF",
      "Mach-O",
      "PNG",
      "ZIP",
      "WebAssembly",
      "Java class"
    ],
    "knownLimits": [
      "The package is explicit opt-in and never claims application/octet-stream or extensions owned by dedicated renderers",
      "Only a reviewed built-in template catalog is parsed in a terminable module Worker; user-authored templates, dynamic imports, editing, and patching are out of scope",
      "Whole inputs, parse time, structure nodes, nesting, and decoded string bytes are capped before data reaches the DOM; large files are rejected instead of partially scanning arbitrary pages"
    ],
    "capabilities": {
      "download": true,
      "print": false,
      "exportHtml": false,
      "zoom": false,
      "search": false
    }
  }
];
var DEFAULT_REGISTERED_EXTENSIONS = Object.freeze(
  Array.from(new Set(DEFAULT_RENDERER_DEFINITIONS.flatMap((definition) => definition.extensions))).sort()
);
var DEFAULT_STABLE_SUPPORTED_EXTENSIONS = Object.freeze(
  Array.from(new Set(DEFAULT_RENDERER_DEFINITIONS.filter((definition) => definition.status === "stable").flatMap((definition) => definition.extensions))).sort()
);

// packages/core/src/registry/formats.ts
var extensionsFor = (rendererId) => Object.freeze(
  [...DEFAULT_RENDERER_DEFINITIONS.find((definition) => definition.id === rendererId)?.extensions ?? []]
);
var ARCHIVE_EXTENSIONS = extensionsFor("archive");
var MODEL_EXTENSIONS = extensionsFor("model");
var TEXT_EXTENSIONS = extensionsFor("code");
var IMAGE_EXTENSIONS = extensionsFor("image");

// packages/core/src/source/precheck.ts
var DEFAULT_MAX_PACKAGE_METADATA_BYTES = 8 * 1024 * 1024;
var OPEN_XML_REQUIRED_PARTS = {
  docx: ["[content_types].xml", "word/document.xml"],
  docm: ["[content_types].xml", "word/document.xml"],
  dotx: ["[content_types].xml", "word/document.xml"],
  dotm: ["[content_types].xml", "word/document.xml"],
  xlsx: ["[content_types].xml", "xl/workbook.xml"],
  xltx: ["[content_types].xml", "xl/workbook.xml"],
  xlsm: ["[content_types].xml", "xl/workbook.xml"],
  xltm: ["[content_types].xml", "xl/workbook.xml"],
  xlsb: ["[content_types].xml", "xl/workbook.bin"],
  pptx: ["[content_types].xml", "ppt/presentation.xml"],
  pptm: ["[content_types].xml", "ppt/presentation.xml"],
  potx: ["[content_types].xml", "ppt/presentation.xml"],
  potm: ["[content_types].xml", "ppt/presentation.xml"],
  ppsx: ["[content_types].xml", "ppt/presentation.xml"],
  ppsm: ["[content_types].xml", "ppt/presentation.xml"],
  odt: ["content.xml"],
  ods: ["content.xml"],
  odp: ["content.xml"],
  ofd: ["ofd.xml"],
  numbers: ["index/document.iwa"],
  epub: ["meta-inf/container.xml"],
  xps: ["[content_types].xml"],
  dwfx: ["[content_types].xml"]
};
var ZIP_EXTENSIONS = /* @__PURE__ */ new Set([
  ...Object.keys(OPEN_XML_REQUIRED_PARTS),
  "zip",
  "zipx",
  "jar",
  "war",
  "ear",
  "apk",
  "cbz"
]);
var TEXT_DECODER = new TextDecoder("utf-8");

// packages/core/src/features/document/search.ts
var SKIP_SELECTOR = [
  "script",
  "style",
  "textarea",
  "input",
  "select",
  "button",
  ".viewer-actions",
  ".viewer-watermark",
  ".state-panel",
  ".pdf-toolbar",
  ".pdf-nav-pane",
  '[aria-hidden="true"]',
  ".flyfish-search-match",
  ".textLayer",
  ".annotationLayer",
  ".xfaLayer",
  "svg",
  "canvas",
  "iframe",
  "video",
  "audio"
].join(",");

// packages/core/src/features/document/viewState.ts
var cloneFileViewerViewState = (state) => {
  if (!state) {
    return null;
  }
  return {
    ...state,
    spreadsheet: state.spreadsheet ? {
      ...state.spreadsheet,
      range: state.spreadsheet.range ? { ...state.spreadsheet.range } : void 0
    } : void 0,
    zoom: state.zoom ? { ...state.zoom } : void 0,
    scroll: state.scroll ? { ...state.scroll } : void 0,
    navigation: state.navigation ? { ...state.navigation } : void 0,
    extra: state.extra ? { ...state.extra } : void 0
  };
};
var createFileViewerViewStateChange = (state, patch = {}) => ({
  state: cloneFileViewerViewState(state) || {},
  action: patch.action || "init",
  source: patch.source || "viewer",
  timestamp: patch.timestamp || Date.now()
});
var createFileViewerViewStateChangeEmitter = () => {
  const listeners = /* @__PURE__ */ new Set();
  return {
    emit(change) {
      listeners.forEach((listener) => listener(change));
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    }
  };
};
var getViewStateWindow = (host) => {
  return host.ownerDocument?.defaultView || (typeof window !== "undefined" ? window : void 0);
};
var waitForViewStateFrame = (host) => {
  const ownerWindow = getViewStateWindow(host);
  return new Promise((resolve) => {
    if (ownerWindow?.requestAnimationFrame) {
      ownerWindow.requestAnimationFrame(() => resolve());
      return;
    }
    setTimeout(resolve, 16);
  });
};
var readFileViewerScrollState = (element) => {
  const maxTop = Math.max(0, element.scrollHeight - element.clientHeight);
  const maxLeft = Math.max(0, element.scrollWidth - element.clientWidth);
  return {
    top: element.scrollTop || 0,
    left: element.scrollLeft || 0,
    width: element.scrollWidth || 0,
    height: element.scrollHeight || 0,
    clientWidth: element.clientWidth || 0,
    clientHeight: element.clientHeight || 0,
    topRatio: maxTop > 0 ? (element.scrollTop || 0) / maxTop : 0,
    leftRatio: maxLeft > 0 ? (element.scrollLeft || 0) / maxLeft : 0
  };
};
var resolveScrollValue = (value, ratio, maxValue) => {
  if (Number.isFinite(value)) {
    return Number(value);
  }
  if (Number.isFinite(ratio)) {
    return Number(ratio) * maxValue;
  }
  return void 0;
};
var registerFileViewerGenericViewStateProvider = ({
  host,
  renderer,
  scrollTarget
}) => {
  const emitter = createFileViewerViewStateChangeEmitter();
  const ownerWindow = getViewStateWindow(host);
  let destroyed = false;
  let scrollFrame = 0;
  let suppressScrollEventUntil = 0;
  let unsubscribeZoom = null;
  const resolveScrollTarget = () => {
    if (typeof scrollTarget === "function") {
      return scrollTarget() || host;
    }
    return scrollTarget || resolveFileViewerScrollContainer(host) || host;
  };
  const getZoomProvider = () => findFileViewerZoomProvider(host);
  const getState = () => {
    const zoom = getZoomProvider()?.getState?.();
    const scrollElement = resolveScrollTarget();
    return {
      renderer,
      scale: zoom?.scale,
      zoom,
      scroll: scrollElement ? readFileViewerScrollState(scrollElement) : void 0
    };
  };
  const emit = (action, source = "viewer") => {
    if (destroyed) {
      return getState();
    }
    const state = getState();
    emitter.emit(createFileViewerViewStateChange(state, { action, source }));
    return state;
  };
  const suppressProgrammaticScrollEvents = () => {
    suppressScrollEventUntil = Math.max(suppressScrollEventUntil, Date.now() + 180);
  };
  const applyScrollState = (scroll) => {
    if (!scroll) {
      return;
    }
    const scrollElement = resolveScrollTarget();
    const maxTop = Math.max(0, scrollElement.scrollHeight - scrollElement.clientHeight);
    const maxLeft = Math.max(0, scrollElement.scrollWidth - scrollElement.clientWidth);
    const top = resolveScrollValue(scroll.top, scroll.topRatio, maxTop);
    const left = resolveScrollValue(scroll.left, scroll.leftRatio, maxLeft);
    suppressProgrammaticScrollEvents();
    if (top !== void 0) {
      scrollElement.scrollTop = Math.min(Math.max(0, top), maxTop);
    }
    if (left !== void 0) {
      scrollElement.scrollLeft = Math.min(Math.max(0, left), maxLeft);
    }
  };
  const fit = async (request) => {
    const zoomProvider2 = getZoomProvider();
    if (zoomProvider2?.fit) {
      return zoomProvider2.fit(request);
    }
    if (!zoomProvider2?.setZoom) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "zoom-provider-unavailable",
        provider: "view-state"
      };
    }
    const zoomState = zoomProvider2.getState();
    const currentScale = Number(zoomState.scale) > 0 ? Number(zoomState.scale) : 1;
    const scrollElement = resolveScrollTarget();
    const viewportWidth = request.viewportWidth || scrollElement.clientWidth || host.clientWidth;
    const viewportHeight = request.viewportHeight || scrollElement.clientHeight || host.clientHeight;
    const contentWidth = Math.max(
      scrollElement.scrollWidth || 0,
      host.scrollWidth || 0,
      scrollElement.getBoundingClientRect?.().width || 0
    );
    const contentHeight = Math.max(
      scrollElement.scrollHeight || 0,
      host.scrollHeight || 0,
      scrollElement.getBoundingClientRect?.().height || 0
    );
    const scale = resolveFileViewerFitScale({
      mode: request.mode,
      viewportWidth,
      viewportHeight,
      contentWidth: contentWidth / currentScale,
      contentHeight: contentHeight / currentScale,
      currentScale,
      minScale: request.minScale ?? zoomState.minScale,
      maxScale: request.maxScale ?? zoomState.maxScale
    });
    if (!scale) {
      return {
        applied: false,
        mode: request.mode,
        resize: request.resize,
        source: request.source,
        reason: "unmeasurable",
        provider: "view-state"
      };
    }
    suppressProgrammaticScrollEvents();
    await zoomProvider2.setZoom(scale);
    await waitForViewStateFrame(host);
    const state = emit("fit", request.source);
    return {
      applied: true,
      mode: request.mode,
      resize: request.resize,
      scale,
      source: request.source,
      provider: "view-state",
      state
    };
  };
  const scheduleScrollChange = () => {
    if (destroyed || Date.now() < suppressScrollEventUntil || scrollFrame) {
      return;
    }
    const requestFrame = ownerWindow?.requestAnimationFrame || ((callback) => {
      return setTimeout(() => callback(Date.now()), 16);
    });
    scrollFrame = requestFrame(() => {
      scrollFrame = 0;
      emit("scroll", "user");
    });
  };
  const provider = {
    getState,
    async applyState(state, options = {}) {
      const source = options.source || "api";
      const action = options.action || "restore";
      const notify = options.notify !== false;
      const zoomProvider2 = getZoomProvider();
      const nextScale = Number(state.scale ?? state.zoom?.scale);
      suppressProgrammaticScrollEvents();
      if (Number.isFinite(nextScale) && zoomProvider2?.setZoom) {
        await zoomProvider2.setZoom(nextScale);
      }
      await waitForViewStateFrame(host);
      applyScrollState(state.scroll);
      await waitForViewStateFrame(host);
      applyScrollState(state.scroll);
      if (notify) {
        return emit(action, source);
      }
      return getState();
    },
    fit,
    subscribe: emitter.subscribe
  };
  host.dataset.viewerViewStateProvider = "generic";
  registerFileViewerViewStateProvider(host, provider);
  host.addEventListener?.("scroll", scheduleScrollChange, {
    capture: true,
    passive: true
  });
  const zoomProvider = getZoomProvider();
  unsubscribeZoom = zoomProvider?.subscribe?.(() => {
    emit("zoom-change", "viewer");
  }) || null;
  return {
    provider,
    destroy() {
      destroyed = true;
      unsubscribeZoom?.();
      unsubscribeZoom = null;
      if (scrollFrame && ownerWindow?.cancelAnimationFrame) {
        ownerWindow.cancelAnimationFrame(scrollFrame);
      }
      scrollFrame = 0;
      host.removeEventListener?.("scroll", scheduleScrollChange, true);
      unregisterFileViewerViewStateProvider(host);
    }
  };
};

// packages/core/src/registry/capabilities.ts
var DEFAULT_OPERATION_AVAILABILITY = Object.freeze({
  download: false,
  print: false,
  exportHtml: false,
  zoom: false,
  zoomIn: false,
  zoomOut: false,
  zoomReset: false
});
var DOM_PRINTABLE_EXTENSIONS = [
  "pptx",
  "pptm",
  "potx",
  "potm",
  "ppsx",
  "ppsm",
  "ofd",
  "dxf",
  "dwg",
  "dwf",
  "dwfx",
  "xps",
  "excalidraw",
  "drawio",
  "dio",
  "mermaid",
  "mmd",
  "plantuml",
  "puml",
  "umd",
  "md",
  "markdown",
  "olb",
  "dra",
  ...TEXT_EXTENSIONS,
  ...IMAGE_EXTENSIONS
];
var NON_PRINTABLE_EXTENSIONS = [
  "xlsx",
  "xltx",
  "xlsm",
  "xlsb",
  "xls",
  "xlt",
  "xltm",
  "csv",
  "tsv",
  "ods",
  "fods",
  "numbers",
  ...ARCHIVE_EXTENSIONS,
  "eml",
  "msg",
  "epub",
  "mp4",
  "mp3",
  "mpeg",
  "wav",
  "ogg",
  "oga",
  "opus",
  "m4a",
  "aac",
  "flac",
  "weba",
  ...MODEL_EXTENSIONS
];

// packages/core/src/registry/registry.ts
var normalizeDefinition = (definition) => ({
  ...definition,
  extensions: definition.extensions.map(normalizeFileExtension),
  enhancesExtensions: definition.enhancesExtensions?.map(normalizeFileExtension)
});
var createRendererRegistry = (initialDefinitions = DEFAULT_RENDERER_DEFINITIONS) => {
  const byId = /* @__PURE__ */ new Map();
  const byExtension = /* @__PURE__ */ new Map();
  const register = (definition) => {
    const normalized = normalizeDefinition(definition);
    const existing = byId.get(normalized.id);
    if (existing) {
      existing.extensions.forEach((extension) => {
        if (byExtension.get(extension)?.id === existing.id) {
          byExtension.delete(extension);
        }
      });
    }
    byId.set(normalized.id, normalized);
    normalized.extensions.forEach((extension) => {
      const owner = byExtension.get(extension);
      if (owner && owner.id !== normalized.id) {
        throw new Error(`File extension "${extension}" is already registered by renderer "${owner.id}".`);
      }
      byExtension.set(extension, normalized);
    });
  };
  initialDefinitions.forEach(register);
  return {
    register,
    unregister(id) {
      const existing = byId.get(id);
      if (!existing) {
        return false;
      }
      existing.extensions.forEach((extension) => {
        if (byExtension.get(extension)?.id === id) {
          byExtension.delete(extension);
        }
      });
      byId.delete(id);
      return true;
    },
    getById(id) {
      return byId.get(id);
    },
    getByExtension(extension) {
      return byExtension.get(normalizeFileExtension(extension));
    },
    hasExtension(extension) {
      return byExtension.has(normalizeFileExtension(extension));
    },
    list() {
      return Array.from(byId.values());
    },
    listExtensions() {
      return Array.from(byExtension.keys()).sort();
    }
  };
};

// packages/core/src/rendering/dispatcher.ts
var resolveFileViewerRendererRedirectId = (error) => {
  if (!error || typeof error !== "object" || !("actualRendererId" in error)) {
    return void 0;
  }
  const rendererId = String(error.actualRendererId || "").trim();
  return rendererId || void 0;
};
var createFileViewerRendererDispatcher = ({
  registry = createRendererRegistry(DEFAULT_RENDERER_DEFINITIONS),
  handlers,
  fallbackHandler,
  fallbackKey = "error"
}) => {
  const handlersByRendererId = Array.from(handlers).reduce((result, entry) => {
    result.set(entry.rendererId, entry.handler);
    return result;
  }, /* @__PURE__ */ new Map());
  const handlersByExtension = /* @__PURE__ */ new Map();
  const missingRendererIds = [];
  registry.list().forEach((definition) => {
    const handler = handlersByRendererId.get(definition.id);
    if (!handler) {
      missingRendererIds.push(definition.id);
      return;
    }
    definition.extensions.forEach((extension) => {
      handlersByExtension.set(normalizeFileExtension(extension), handler);
    });
  });
  if (fallbackHandler && fallbackKey) {
    handlersByExtension.set(normalizeFileExtension(fallbackKey), fallbackHandler);
  }
  const get = (extension) => {
    return handlersByExtension.get(normalizeFileExtension(extension));
  };
  return {
    handlersByRendererId,
    handlersByExtension,
    missingRendererIds,
    get,
    resolve(extension) {
      return get(extension) || (fallbackKey ? get(fallbackKey) : void 0);
    },
    has(extension) {
      return handlersByExtension.has(normalizeFileExtension(extension));
    },
    listExtensions() {
      return Array.from(handlersByExtension.keys()).sort();
    }
  };
};

// packages/core/src/viewer/state.ts
var FILE_VIEWER_ERROR_MESSAGE = "fileViewerErrorMessage";
var FILE_VIEWER_PREVIEW_MESSAGES = Object.freeze({
  downloading: "\u6B63\u5728\u4E0B\u8F7D\u6587\u4EF6\u8D44\u6E90...",
  streamingPdf: "\u6B63\u5728\u5EFA\u7ACB PDF \u6D41\u5F0F\u9884\u89C8...",
  reading: "\u6B63\u5728\u89E3\u6790\u6587\u4EF6\u5185\u5BB9..."
});
var DEFAULT_FILE_VIEWER_STATE_THEME = Object.freeze({
  accent: "#5f6f82",
  soft: "rgba(95, 111, 130, 0.12)",
  badge: "DOC",
  label: "\u6587\u4EF6\u5185\u5BB9",
  hint: "\u6B63\u5728\u6574\u7406\u5185\u5BB9\u7ED3\u6784\u5E76\u751F\u6210\u9884\u89C8\u3002"
});
var extensionLabel = (extension, i18n) => {
  const normalized = normalizeFileExtension(extension);
  if (normalized) {
    return `.${normalized}`;
  }
  const locale = resolveFileViewerLocale(i18n);
  if (locale === "zh-CN") {
    return "\u5F53\u524D\u6587\u4EF6";
  }
  if (locale === "ja-JP") {
    return "\u73FE\u5728\u306E\u30D5\u30A1\u30A4\u30EB";
  }
  if (locale === "de-DE") {
    return "aktuelle Datei";
  }
  return "current file";
};
var rendererPackageById = {
  "office-word-openxml": "@file-viewer/renderer-word",
  "office-word-binary": "@file-viewer/renderer-word",
  "office-presentation-binary": "@file-viewer/renderer-presentation",
  "office-presentation": "@file-viewer/renderer-presentation",
  "open-document": "@file-viewer/renderer-word",
  "spreadsheet-openxml": "@file-viewer/renderer-spreadsheet",
  pdf: "@file-viewer/renderer-pdf",
  ofd: "@file-viewer/renderer-ofd",
  typst: "@file-viewer/renderer-typst",
  archive: "@file-viewer/renderer-archive",
  chm: "@file-viewer/renderer-chm",
  email: "@file-viewer/renderer-email",
  eda: "@file-viewer/renderer-eda",
  cad: "@file-viewer/renderer-cad",
  model: "@file-viewer/renderer-3d",
  geo: "@file-viewer/renderer-geo",
  drawing: "@file-viewer/renderer-drawing",
  mindmap: "@file-viewer/renderer-mindmap",
  epub: "@file-viewer/renderer-epub",
  umd: "@file-viewer/renderer-epub",
  image: "@file-viewer/renderer-image",
  markdown: "@file-viewer/renderer-text",
  code: "@file-viewer/renderer-text",
  video: "@file-viewer/renderer-media",
  audio: "@file-viewer/renderer-media",
  "data-asset": "@file-viewer/renderer-data"
};
var officeRendererIds = /* @__PURE__ */ new Set([
  "office-word-openxml",
  "office-word-binary",
  "office-presentation-binary",
  "office-presentation",
  "open-document",
  "spreadsheet-openxml",
  "pdf",
  "ofd"
]);
var liteRendererIds = /* @__PURE__ */ new Set([
  "image",
  "markdown",
  "code",
  "video",
  "audio"
]);
var engineeringRendererIds = /* @__PURE__ */ new Set([
  "typst",
  "archive",
  "eda",
  "cad",
  "model",
  "geo",
  "drawing",
  "mindmap",
  "data-asset"
]);
var resolvePresetHint = (definition) => {
  if (officeRendererIds.has(definition.id)) {
    return {
      packageName: "@file-viewer/preset-office",
      vitePreset: "office",
      label: "Office preset"
    };
  }
  if (engineeringRendererIds.has(definition.id)) {
    return {
      packageName: "@file-viewer/preset-engineering",
      vitePreset: "engineering",
      label: "Engineering preset"
    };
  }
  if (liteRendererIds.has(definition.id)) {
    return {
      packageName: "@file-viewer/preset-lite",
      vitePreset: "lite",
      label: "Lite preset"
    };
  }
  return {
    packageName: "@file-viewer/preset-all",
    vitePreset: "all",
    label: "Full preset"
  };
};
var resolveFileViewerRendererInstallHint = (extension = "") => {
  const normalized = normalizeFileExtension(extension);
  const definition = DEFAULT_RENDERER_DEFINITIONS.find(
    (item) => item.extensions.map(normalizeFileExtension).includes(normalized)
  );
  if (!definition) {
    return null;
  }
  const preset = resolvePresetHint(definition);
  return {
    extension: normalized,
    rendererId: definition.id,
    rendererLabel: definition.label,
    rendererCategory: definition.category,
    rendererPackage: rendererPackageById[definition.id],
    presetPackage: preset.packageName,
    vitePreset: preset.vitePreset,
    presetLabel: preset.label
  };
};
var createFileViewerStateDescriptor = ({
  state,
  extension = "",
  title,
  message,
  description,
  theme = DEFAULT_FILE_VIEWER_STATE_THEME,
  recoverable
}) => ({
  state,
  extension: normalizeFileExtension(extension),
  title,
  message,
  description,
  theme,
  recoverable
});
var createFileViewerUnsupportedState = (extension = "", theme = DEFAULT_FILE_VIEWER_STATE_THEME, i18n) => {
  const label = extensionLabel(extension, i18n);
  const installHint = resolveFileViewerRendererInstallHint(extension);
  if (installHint) {
    const locale = resolveFileViewerLocale(i18n);
    const localeRendererTip = installHint.rendererPackage ? locale === "zh-CN" ? `\uFF1B\u5982\u679C\u9700\u8981\u6781\u81F4\u88C1\u526A\uFF0C\u4E5F\u53EF\u4EE5\u53EA\u5B89\u88C5 ${installHint.rendererPackage}` : locale === "ja-JP" ? `\uFF1B\u53B3\u5BC6\u306B\u6700\u5C0F\u69CB\u6210\u3078\u7D5E\u308B\u5834\u5408\u306F ${installHint.rendererPackage} \u306E\u307F\u3092\u30A4\u30F3\u30B9\u30C8\u30FC\u30EB\u3059\u308B\u3053\u3068\u3082\u3067\u304D\u307E\u3059` : locale === "de-DE" ? `; f\xFCr eine strikt minimale Konfiguration installieren Sie nur ${installHint.rendererPackage}` : `; for a strict custom cut, install only ${installHint.rendererPackage}` : "";
    return createFileViewerStateDescriptor({
      state: "unsupported",
      extension,
      title: translateFileViewerMessage(i18n, "state.unsupported.install.title"),
      message: translateFileViewerMessage(i18n, "state.unsupported.install.message", {
        extension: label,
        rendererLabel: installHint.rendererLabel
      }),
      description: translateFileViewerMessage(i18n, "state.unsupported.install.description", {
        extension: label,
        rendererLabel: installHint.rendererLabel,
        presetPackage: installHint.presetPackage,
        vitePreset: installHint.vitePreset,
        rendererTip: localeRendererTip
      }),
      theme,
      recoverable: true
    });
  }
  return createFileViewerStateDescriptor({
    state: "unsupported",
    extension,
    title: translateFileViewerMessage(i18n, "state.unsupported.title"),
    message: translateFileViewerMessage(i18n, "state.unsupported.message", {
      extension: label
    }),
    description: translateFileViewerMessage(i18n, "state.unsupported.description"),
    theme,
    recoverable: true
  });
};
var FILE_VIEWER_KNOWN_ERROR_MESSAGE_KEYS = {
  "Blob is not available in the current execution environment.": "error.blobUnavailable",
  "Unsupported file source input.": "error.sourceUnsupported",
  "Failed to read file as ArrayBuffer.": "error.fileReadArrayBuffer",
  "Failed to read file as data URL.": "error.fileReadDataUrl",
  "Failed to read file as text.": "error.fileReadText",
  "Unable to read image data URL.": "error.imageDataUrlRead",
  "\u6587\u4EF6\u4E0D\u662F\u6709\u6548\u7684 DOCX/OOXML \u538B\u7F29\u5305\uFF0C\u53EF\u80FD\u4E0B\u8F7D\u4E0D\u5B8C\u6574\u6216\u88AB\u670D\u52A1\u7AEF\u9519\u8BEF\u5185\u5BB9\u66FF\u6362\uFF0C\u8BF7\u91CD\u65B0\u4E0A\u4F20\u6216\u68C0\u67E5\u6587\u4EF6\u6E90\u3002": "word.error.invalidDocx",
  "ODF \u6587\u4EF6\u7F3A\u5C11 content.xml": "word.error.missingOdfContent",
  "ODF \u6587\u4EF6\u7F3A\u5C11 content.xml\u3002": "word.error.missingOdfContent",
  "ODF XML \u89E3\u6790\u5931\u8D25": "word.error.odfXmlParseFailed",
  "ODF XML \u89E3\u6790\u5931\u8D25\u3002": "word.error.odfXmlParseFailed",
  "OFD \u6587\u4EF6\u4E2D\u6CA1\u6709\u53EF\u6E32\u67D3\u7684\u6587\u6863": "ofd.error.empty",
  "OFD \u6587\u4EF6\u89E3\u6790\u5931\u8D25": "ofd.error.parseFailed",
  "IndexedDB \u4E0D\u53EF\u7528": "archive.error.indexedDbUnavailable",
  "Web Worker is not supported by this browser.": "archive.error.workerUnsupported"
};
var resolveKnownFileViewerErrorMessage = (message, i18n) => {
  const key = FILE_VIEWER_KNOWN_ERROR_MESSAGE_KEYS[message.trim()];
  return key ? translateFileViewerMessage(i18n, key) : message;
};
var readFileViewerErrorProperty = (error, key) => {
  try {
    return error[key];
  } catch {
    return void 0;
  }
};
var normalizeFileViewerErrorMessage = (error, i18n) => {
  if (error && typeof error === "object") {
    const presentedMessage = readFileViewerErrorProperty(error, FILE_VIEWER_ERROR_MESSAGE);
    if (typeof presentedMessage === "string" && presentedMessage.trim()) {
      return resolveKnownFileViewerErrorMessage(presentedMessage, i18n);
    }
  }
  if (error instanceof Error) {
    return resolveKnownFileViewerErrorMessage(error.message, i18n);
  }
  if (typeof error === "string") {
    return resolveKnownFileViewerErrorMessage(error, i18n);
  }
  if (error === void 0 || error === null) {
    return translateFileViewerMessage(i18n, "error.unknown");
  }
  if (typeof error === "object") {
    const message = readFileViewerErrorProperty(error, "message");
    if (typeof message === "string" && message.trim()) {
      return resolveKnownFileViewerErrorMessage(message, i18n);
    }
    const reason = readFileViewerErrorProperty(error, "reason");
    if (reason !== void 0 && reason !== error) {
      return normalizeFileViewerErrorMessage(reason, i18n);
    }
  }
  const fallback = String(error);
  return fallback === "[object Object]" ? translateFileViewerMessage(i18n, "error.unknown") : fallback;
};

// packages/core/src/source/loading.ts
var DEFAULT_PDF_RANGE_CHUNK_SIZE = 64 * 1024;

// packages/core/src/rendering/handler.ts
var createFileRenderHandlerRendererSession = (rendered, destroy) => ({
  rendered,
  destroy: () => {
    if (destroy) {
      return destroy();
    }
    return disposeFileViewerRendered(rendered);
  }
});
var disposeFileViewerRendered = (rendered) => {
  if (!rendered || typeof rendered !== "object") {
    return;
  }
  const disposable = rendered;
  if (typeof disposable.unmount === "function") {
    return disposable.unmount();
  }
  if (typeof disposable.$destroy === "function") {
    return disposable.$destroy();
  }
  if (typeof disposable.destroy === "function") {
    return disposable.destroy();
  }
};
var buildFileRenderContextFromLoadContext = ({
  source,
  surface,
  options,
  signal,
  registerExportAdapter,
  registerThumbnailAdapter,
  renderContext
}) => ({
  filename: source.filename,
  url: source.url,
  streamUrl: source.url,
  sourceFile: source.file,
  signal,
  options,
  surface,
  registerExportAdapter,
  registerThumbnailAdapter,
  ...renderContext
});
var renderFileViewerHandler = async ({
  dispatcher,
  buffer,
  target,
  type = "",
  context,
  throwOnMissingHandler = false
}) => {
  const normalizedType = normalizeFileExtension(type);
  const handler = dispatcher.resolve(normalizedType);
  if (!handler) {
    if (throwOnMissingHandler) {
      throw new Error(`No file viewer renderer is registered for "${normalizedType}".`);
    }
    return void 0;
  }
  try {
    return await handler(buffer, target, normalizedType, context);
  } catch (error) {
    const redirectedRendererId = resolveFileViewerRendererRedirectId(error);
    const redirectedHandler = redirectedRendererId ? dispatcher.handlersByRendererId.get(redirectedRendererId) : void 0;
    if (!redirectedHandler || redirectedHandler === handler) {
      throw error;
    }
    const redirectedType = DEFAULT_RENDERER_DEFINITIONS.find((definition) => definition.id === redirectedRendererId)?.extensions[0] || normalizedType;
    context?.options?.onDiagnostic?.({
      code: "renderer-content-signature-redirect",
      level: "warning",
      message: `File extension .${normalizedType} contains the ${redirectedRendererId} container and was routed as .${redirectedType}.`,
      detail: {
        declaredExtension: normalizedType,
        detectedRendererId: redirectedRendererId,
        routedExtension: redirectedType
      }
    });
    return await redirectedHandler(buffer, target, redirectedType, context);
  }
};
var createFileRenderHandlerLoader = ({
  handler,
  rendererId,
  allowUrlSource = false,
  getTarget = (context) => context.surface.container,
  createContext = buildFileRenderContextFromLoadContext,
  destroy
}) => {
  return async (context) => {
    const { source } = context;
    if (!source.buffer && !(allowUrlSource && (source.url || source.file))) {
      throw new Error("FileRenderHandler renderer requires an ArrayBuffer source.");
    }
    const buffer = source.buffer || new ArrayBuffer(0);
    const target = getTarget(context);
    const renderContext = createContext(context);
    const rendered = await handler(
      buffer,
      target,
      source.extension,
      renderContext
    );
    const existingProvider = findFileViewerViewStateProvider(target);
    const genericViewStateProvider = existingProvider ? null : registerFileViewerGenericViewStateProvider({
      host: target,
      renderer: rendererId || source.extension
    });
    const viewStateProvider = existingProvider || genericViewStateProvider?.provider || null;
    if (context.options.initialViewState && viewStateProvider?.applyState) {
      await viewStateProvider.applyState(context.options.initialViewState, {
        action: "restore",
        source: "initial"
      });
    }
    return createFileRenderHandlerRendererSession(rendered, () => {
      const destroyRendered = () => {
        if (destroy) {
          return destroy(rendered, context);
        }
        return disposeFileViewerRendered(rendered);
      };
      try {
        genericViewStateProvider?.destroy();
      } finally {
        return destroyRendered();
      }
    });
  };
};
var createFileRenderHandlerRegistry = ({
  definitions = DEFAULT_RENDERER_DEFINITIONS,
  handlers,
  getTarget,
  createContext,
  destroy
}) => {
  const baseRegistry = createRendererRegistry(definitions);
  const dispatcher = createFileViewerRendererDispatcher({
    registry: baseRegistry,
    handlers
  });
  const definitionsWithLoaders = baseRegistry.list().map((definition) => {
    const handler = dispatcher.handlersByRendererId.get(definition.id);
    if (!handler) {
      return definition;
    }
    return {
      ...definition,
      load: createFileRenderHandlerLoader({
        handler: (buffer, target, type, context) => renderFileViewerHandler({
          dispatcher,
          buffer,
          target,
          type,
          context,
          throwOnMissingHandler: true
        }),
        rendererId: definition.id,
        getTarget,
        createContext,
        destroy
      })
    };
  });
  return {
    registry: createRendererRegistry(definitionsWithLoaders),
    dispatcher,
    missingRendererIds: dispatcher.missingRendererIds
  };
};

// packages/core/src/renderers/index.ts
var createWrapper = (el) => ({
  $el: el,
  unmount() {
  }
});
var coreBrowserRendererHandlers = [
  {
    rendererId: "image",
    handler: async (buffer, target, type, context) => {
      const { default: renderImage } = await import("./image-DBKOAVSS.js");
      return renderImage(buffer, target, type, context);
    }
  }
];
var CORE_LITE_RENDERER_IDS = [
  "image"
];
var coreLiteBrowserRendererHandlers = coreBrowserRendererHandlers.filter(
  (handler) => CORE_LITE_RENDERER_IDS.includes(handler.rendererId)
);
var coreLiteRendererDefinitions = DEFAULT_RENDERER_DEFINITIONS.filter(
  (definition) => CORE_LITE_RENDERER_IDS.includes(definition.id)
);
var resolveCoreRendererDefinitions = (preset) => {
  if (preset === "none") {
    return [];
  }
  if (preset === "lite") {
    return coreLiteRendererDefinitions;
  }
  return DEFAULT_RENDERER_DEFINITIONS;
};
var resolveCoreRendererHandlers = (preset) => {
  if (preset === "none") {
    return [];
  }
  if (preset === "lite") {
    return coreLiteBrowserRendererHandlers;
  }
  return coreBrowserRendererHandlers;
};
var renderUnsupported = async (_buffer, target, type, context) => {
  const state = createFileViewerUnsupportedState(type, void 0, context?.options);
  const wrapper = document.createElement("div");
  wrapper.style.textAlign = "center";
  wrapper.style.marginTop = "80px";
  const message = document.createElement("div");
  message.textContent = state.message;
  wrapper.appendChild(message);
  if (state.description) {
    const description = document.createElement("div");
    description.textContent = state.description;
    wrapper.appendChild(description);
  }
  target.replaceChildren(wrapper);
  return createWrapper(target);
};
var createFileViewerCoreRendererRegistry = (options = {}) => {
  const preset = options.builtinRenderers || "all";
  const bridge = createFileRenderHandlerRegistry({
    definitions: resolveCoreRendererDefinitions(preset),
    handlers: resolveCoreRendererHandlers(preset)
  });
  return {
    ...bridge,
    dispatcher: createFileViewerRendererDispatcher({
      registry: bridge.registry,
      handlers: coreBrowserRendererHandlers,
      fallbackHandler: renderUnsupported
    })
  };
};
var fileViewerCoreRendererRegistryBridge = createFileViewerCoreRendererRegistry();
var fileViewerCoreRendererRegistry = fileViewerCoreRendererRegistryBridge.registry;
var fileViewerCoreRendererDispatcher = fileViewerCoreRendererRegistryBridge.dispatcher;
var missingFileViewerCoreRendererHandlers = fileViewerCoreRendererRegistryBridge.missingRendererIds;

// packages/core/src/config/options.ts
var normalizeFileViewerTheme = (theme) => {
  return theme === "light" || theme === "dark" || theme === "system" ? theme : "system";
};
var readSystemDarkMode = () => {
  return typeof globalThis.matchMedia === "function" && globalThis.matchMedia("(prefers-color-scheme: dark)").matches;
};
var resolveFileViewerColorScheme = (theme, systemDark = readSystemDarkMode()) => {
  const normalizedTheme = normalizeFileViewerTheme(theme);
  return normalizedTheme === "system" ? systemDark ? "dark" : "light" : normalizedTheme;
};

// packages/core/src/platform/worker.ts
var createFileViewerWorkerController = (factory, options = {}) => {
  const instance = factory();
  const eventHandlers = /* @__PURE__ */ new Map();
  const messageHooks = /* @__PURE__ */ new Set();
  const errorHooks = /* @__PURE__ */ new Set();
  const emit = (type, payload) => {
    instance?.postMessage({
      type,
      payload
    });
  };
  const handleMessage = (event) => {
    const { type, payload } = event.data || {};
    const handlers = eventHandlers.get(type);
    handlers?.forEach((handler) => handler(payload));
    messageHooks.forEach((hook) => hook(event));
  };
  const handleError = (event) => {
    if (options.logErrors !== false) {
      console.error(event);
    }
    errorHooks.forEach((hook) => hook(event));
  };
  instance?.addEventListener("message", handleMessage);
  instance?.addEventListener("error", handleError);
  const worker = {
    emit
  };
  return {
    instance,
    worker,
    emit,
    onWorkerMessage(hook) {
      messageHooks.add(hook);
      return () => {
        messageHooks.delete(hook);
      };
    },
    onWorkerError(hook) {
      errorHooks.add(hook);
      return () => {
        errorHooks.delete(hook);
      };
    },
    onWorkerEvent(type, hook) {
      let handlers = eventHandlers.get(type);
      if (!handlers) {
        handlers = /* @__PURE__ */ new Set();
        eventHandlers.set(type, handlers);
      }
      handlers.add(hook);
      return () => {
        handlers?.delete(hook);
        if (handlers?.size === 0) {
          eventHandlers.delete(type);
        }
      };
    },
    mapEvents(mappings) {
      if (Array.isArray(mappings)) {
        return mappings.reduce((result, key) => {
          result[key] = (payload) => emit(key, payload);
          return result;
        }, {});
      }
      return Object.keys(mappings).reduce((result, key) => {
        const name = mappings[key];
        result[name] = (payload) => emit(key, payload);
        return result;
      }, {});
    },
    destroy() {
      instance?.removeEventListener("message", handleMessage);
      instance?.removeEventListener("error", handleError);
      instance?.terminate();
      eventHandlers.clear();
      messageHooks.clear();
      errorHooks.clear();
    }
  };
};

// packages/core/src/platform/copiedAssets.ts
var MAX_MANIFEST_BYTES = 1024 * 1024;

export {
  resolveFileViewerRuntimeAssetBaseUrl,
  resolveFileViewerAssetUrl,
  resolveFileViewerPostscriptWorkerUrl,
  resolveFileViewerPostscriptWasmUrl,
  DEFAULT_RENDERER_DEFINITIONS,
  resolveFileViewerTextEncoding,
  decodeFileViewerTextBuffer,
  normalizeFileViewerErrorMessage,
  resolveFileViewerColorScheme,
  createFileViewerWorkerController
};
