// apps/viewer-demo/public/vendor/ppt/dist/pptjs.worker.js
var __PPT_MODULE_URL__ = globalThis.location?.href ?? "file:///pptjs.worker.js";
var System = /* @__PURE__ */ (() => {
  const records = /* @__PURE__ */ new Map();
  function load(name) {
    const record = records.get(name);
    if (!record)
      throw new Error(`Missing bundled module: ${name}`);
    if (record.state)
      return record.exports;
    record.state = 1;
    const declaration = record.declare((key, value) => {
      if (typeof key === "object")
        Object.assign(record.exports, key);
      else
        record.exports[key] = value;
      for (const listener of record.listeners)
        listener(record.exports);
      return value;
    }, { id: name, meta: { url: __PPT_MODULE_URL__ } });
    for (let i = 0; i < record.dependencies.length; i++) {
      const dependency = record.dependencies[i];
      const value = load(dependency);
      const setter = declaration.setters[i];
      if (setter) {
        setter(value);
        records.get(dependency).listeners.push(setter);
      }
    }
    declaration.execute();
    record.state = 2;
    return record.exports;
  }
  return {
    register(name, dependencies, declare) {
      if (records.has(name))
        throw new Error(`Duplicate bundled module: ${name}`);
      records.set(name, { dependencies, declare, exports: {}, listeners: [], state: 0 });
    },
    importSync: load
  };
})();
System.register("types", [], function(exports_1, context_1) {
  "use strict";
  var __moduleName = context_1 && context_1.id;
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("core/errors", [], function(exports_2, context_2) {
  "use strict";
  var PptError;
  var __moduleName = context_2 && context_2.id;
  return {
    setters: [],
    execute: function() {
      PptError = class PptError extends Error {
        code;
        offset;
        constructor(code, message, offset) {
          super(message);
          this.name = "PptError";
          this.code = code;
          this.offset = offset;
        }
      };
      exports_2("PptError", PptError);
    }
  };
});
System.register("core/cfb", ["core/errors"], function(exports_3, context_3) {
  "use strict";
  var errors_js_1, FREE, END, FAT, DIF, signature, CompoundFile;
  var __moduleName = context_3 && context_3.id;
  function toBytes(input) {
    if (input instanceof ArrayBuffer)
      return new Uint8Array(input);
    if (ArrayBuffer.isView(input))
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    throw new TypeError("Expected an ArrayBuffer or ArrayBufferView");
  }
  exports_3("toBytes", toBytes);
  return {
    setters: [
      function(errors_js_1_1) {
        errors_js_1 = errors_js_1_1;
      }
    ],
    execute: function() {
      FREE = 4294967295, END = 4294967294, FAT = 4294967293, DIF = 4294967292;
      signature = [208, 207, 17, 224, 161, 177, 26, 225];
      CompoundFile = class CompoundFile {
        entries = [];
        sectorSize;
        version;
        bytes;
        view;
        sectorCount;
        fat;
        miniFat;
        root;
        cache = /* @__PURE__ */ new Map();
        paths = /* @__PURE__ */ new Map();
        limits;
        constructor(input, limits, diagnostics = [], strict = false) {
          this.bytes = toBytes(input);
          this.limits = limits;
          if (this.bytes.length > limits.maxFileBytes)
            throw new errors_js_1.PptError("LIMIT_FILE", "File exceeds the configured byte limit");
          if (this.bytes.length < 512 || signature.some((v, i) => this.bytes[i] !== v))
            throw new errors_js_1.PptError("NOT_CFB", "Expected a PowerPoint 97\u20132003 .ppt compound file");
          this.view = new DataView(this.bytes.buffer, this.bytes.byteOffset, this.bytes.byteLength);
          this.version = this.view.getUint16(26, true);
          const shift = this.view.getUint16(30, true);
          if (this.view.getUint16(28, true) !== 65534 || !(this.version === 3 && shift === 9 || this.version === 4 && shift === 12) || this.view.getUint16(32, true) !== 6)
            throw new errors_js_1.PptError("CFB_HEADER", "Unsupported or invalid CFB header");
          this.sectorSize = 2 ** shift;
          this.sectorCount = Math.ceil(this.bytes.length / this.sectorSize) - 1;
          if (this.bytes.length < this.sectorSize || this.view.getUint32(56, true) !== 4096)
            throw new errors_js_1.PptError("CFB_HEADER", "Invalid CFB sector size or mini stream cutoff");
          const fatCount = this.view.getUint32(44, true), difCount = this.view.getUint32(72, true);
          if (fatCount > this.sectorCount || difCount > this.sectorCount)
            throw new errors_js_1.PptError("CFB_FAT", "FAT allocation exceeds physical file");
          const fatSectors = [];
          const addFat = (id) => {
            if (id !== FREE) {
              this.checkSector(id);
              if (fatSectors.length >= fatCount)
                throw new errors_js_1.PptError("CFB_FAT", "DIFAT lists more FAT sectors than the header declares");
              fatSectors.push(id);
            }
          };
          for (let i = 0; i < 109; i++)
            addFat(this.view.getUint32(76 + i * 4, true));
          let next = this.view.getUint32(68, true);
          const seenDif = /* @__PURE__ */ new Set();
          for (let i = 0; i < difCount; i++) {
            if (seenDif.has(next))
              throw new errors_js_1.PptError("CFB_CYCLE", "Cycle in DIFAT chain");
            seenDif.add(next);
            const sector = this.sector(next);
            const dv2 = new DataView(sector.buffer, sector.byteOffset, sector.length);
            for (let j = 0; j < this.sectorSize / 4 - 1; j++)
              addFat(dv2.getUint32(j * 4, true));
            next = dv2.getUint32(this.sectorSize - 4, true);
          }
          if (difCount > 0 && next !== END) {
            if (next === FREE && !strict)
              diagnostics.push({ code: "CFB_DIFAT_FREE_TERMINATOR", severity: "warning", message: "The final declared DIFAT sector uses FREESECT instead of the required ENDOFCHAIN; the declared FAT count and all sector bounds are still checked." });
            else
              throw new errors_js_1.PptError("CFB_DIFAT", "DIFAT does not terminate at declared sector count");
          }
          if (fatSectors.length < fatCount)
            throw new errors_js_1.PptError("CFB_FAT", "FAT sector list is truncated");
          if (new Set(fatSectors.slice(0, fatCount)).size !== fatCount)
            throw new errors_js_1.PptError("CFB_FAT", "Duplicate FAT sectors");
          const entriesPerSector = this.sectorSize / 4;
          if (fatCount * entriesPerSector * 4 > limits.maxStreamBytes)
            throw new errors_js_1.PptError("LIMIT_STREAM", "FAT exceeds configured stream budget");
          this.fat = new Uint32Array(fatCount * entriesPerSector);
          for (let i = 0; i < fatCount; i++) {
            const s = this.sector(fatSectors[i]);
            const v = new DataView(s.buffer, s.byteOffset, s.length);
            for (let j = 0; j < entriesPerSector; j++)
              this.fat[i * entriesPerSector + j] = v.getUint32(j * 4, true);
          }
          const dir = this.readChain(this.view.getUint32(48, true), void 0, this.fat, this.sectorSize);
          const dv = new DataView(dir.buffer, dir.byteOffset, dir.length);
          const utf16 = new TextDecoder("utf-16le");
          for (let p = 0; p + 128 <= dir.length; p += 128) {
            const type = dv.getUint8(p + 66), nameLen = dv.getUint16(p + 64, true);
            if (type !== 0 && (nameLen < 2 || nameLen > 64 || nameLen & 1))
              throw new errors_js_1.PptError("CFB_DIRECTORY", "Invalid directory name length", p);
            const size = dv.getUint32(p + 120, true) + (this.version === 4 ? dv.getUint32(p + 124, true) * 2 ** 32 : 0);
            if (!Number.isSafeInteger(size) || size > limits.maxStreamBytes)
              throw new errors_js_1.PptError("LIMIT_STREAM", "Directory declares an oversized stream", p);
            this.entries.push({ id: p / 128, name: type === 0 ? "" : utf16.decode(dir.subarray(p, p + nameLen - 2)), type, left: dv.getUint32(p + 68, true), right: dv.getUint32(p + 72, true), child: dv.getUint32(p + 76, true), start: dv.getUint32(p + 116, true), size, parent: null, path: "" });
          }
          const root = this.entries[0];
          if (!root || root.type !== 5)
            throw new errors_js_1.PptError("CFB_ROOT", "Compound file root entry is missing");
          this.root = root;
          this.attachDirectory(root, 0, /* @__PURE__ */ new Set());
          const miniCount = this.view.getUint32(64, true);
          if (miniCount > this.sectorCount || miniCount * this.sectorSize > limits.maxStreamBytes)
            throw new errors_js_1.PptError("CFB_MINIFAT", "Invalid MiniFAT count");
          const mb = miniCount ? this.readChain(this.view.getUint32(60, true), miniCount * this.sectorSize, this.fat, this.sectorSize) : new Uint8Array(0);
          this.miniFat = new Uint32Array(mb.length / 4);
          const mv = new DataView(mb.buffer, mb.byteOffset, mb.byteLength);
          for (let i = 0; i < this.miniFat.length; i++)
            this.miniFat[i] = mv.getUint32(i * 4, true);
          if (this.bytes.length % this.sectorSize)
            diagnostics.push({ code: "CFB_PARTIAL_TAIL", severity: "warning", message: "The final physical sector is partial; each logical stream remains checked against its declared size." });
        }
        checkSector(id) {
          if (!Number.isInteger(id) || id < 0 || id >= this.sectorCount)
            throw new errors_js_1.PptError("CFB_SECTOR", `Sector ${id} is outside the file`);
        }
        sector(id, length = this.sectorSize) {
          this.checkSector(id);
          const p = (id + 1) * this.sectorSize;
          if (p + length > this.bytes.length)
            throw new errors_js_1.PptError("CFB_TRUNCATED", "Sector payload is truncated", p);
          return this.bytes.subarray(p, p + length);
        }
        readChain(start, size, table, unit, mini) {
          if (size === 0)
            return new Uint8Array(0);
          const chain = [];
          const visited = /* @__PURE__ */ new Set();
          let id = start;
          const needed = size === void 0 ? Infinity : Math.ceil(size / unit);
          while (id !== END) {
            if (id === FREE || id === FAT || id === DIF || id >= table.length)
              throw new errors_js_1.PptError("CFB_CHAIN", "Broken sector chain");
            if (visited.has(id))
              throw new errors_js_1.PptError("CFB_CYCLE", "Cycle in sector chain");
            visited.add(id);
            if (!mini)
              this.checkSector(id);
            else if (id * unit >= mini.length)
              throw new errors_js_1.PptError("CFB_MINISTREAM", "Mini sector outside root stream");
            chain.push(id);
            if (chain.length * unit > this.limits.maxStreamBytes + unit)
              throw new errors_js_1.PptError("LIMIT_STREAM", "Sector chain exceeds configured budget");
            id = table[id];
            if (chain.length === needed)
              break;
          }
          const length = size ?? chain.length * unit;
          if (length > this.limits.maxStreamBytes)
            throw new errors_js_1.PptError("LIMIT_STREAM", "Stream exceeds configured byte limit");
          if (chain.length * unit < length)
            throw new errors_js_1.PptError("CFB_TRUNCATED", "Sector chain is shorter than the declared stream");
          const out = new Uint8Array(length);
          let offset = 0;
          for (const sid of chain) {
            const count = Math.min(unit, length - offset);
            const chunk = mini ? mini.subarray(sid * unit, sid * unit + count) : this.sector(sid, count);
            if (chunk.length !== count)
              throw new errors_js_1.PptError("CFB_TRUNCATED", "Truncated mini stream");
            out.set(chunk, offset);
            offset += count;
          }
          return out;
        }
        attachDirectory(parent, depth, assigned) {
          if (depth > this.limits.maxDepth)
            throw new errors_js_1.PptError("CFB_DEPTH", "Directory nesting exceeds configured limit");
          const stack = [parent.child];
          const siblings = /* @__PURE__ */ new Set();
          while (stack.length) {
            const id = stack.pop();
            if (id === FREE)
              continue;
            if (id >= this.entries.length || id === 0 || siblings.has(id) || assigned.has(id))
              throw new errors_js_1.PptError("CFB_DIRECTORY_CYCLE", "Invalid or cyclic directory tree");
            siblings.add(id);
            assigned.add(id);
            const entry = this.entries[id];
            if (entry.type !== 1 && entry.type !== 2)
              throw new errors_js_1.PptError("CFB_DIRECTORY", "Invalid directory object type");
            entry.parent = parent.id;
            entry.path = (parent.type === 5 ? "" : parent.path) + "/" + entry.name;
            if (this.paths.has(entry.path.toLowerCase()))
              throw new errors_js_1.PptError("CFB_DIRECTORY", "Duplicate stream path");
            this.paths.set(entry.path.toLowerCase(), entry);
            stack.push(entry.right, entry.left);
            if (entry.type === 1)
              this.attachDirectory(entry, depth + 1, assigned);
          }
        }
        getEntry(path) {
          return this.paths.get(("/" + path.replace(/^\/+/, "")).toLowerCase());
        }
        getStream(path) {
          const entry = this.getEntry(path);
          if (!entry || entry.type !== 2)
            return void 0;
          const cached = this.cache.get(entry.id);
          if (cached)
            return cached;
          let result;
          if (entry.size < 4096 && entry.size > 0) {
            let root = this.cache.get(this.root.id);
            if (!root) {
              root = this.readChain(this.root.start, this.root.size, this.fat, this.sectorSize);
              this.cache.set(this.root.id, root);
            }
            result = this.readChain(entry.start, entry.size, this.miniFat, 64, root);
          } else
            result = this.readChain(entry.start, entry.size, this.fat, this.sectorSize);
          this.cache.set(entry.id, result);
          return result;
        }
      };
      exports_3("CompoundFile", CompoundFile);
    }
  };
});
System.register("core/utils", [], function(exports_4, context_4) {
  "use strict";
  var __moduleName = context_4 && context_4.id;
  function trimTrailingNulls(value) {
    let end = value.length;
    while (end > 0 && value.charCodeAt(end - 1) === 0)
      end--;
    return end === value.length ? value : value.slice(0, end);
  }
  exports_4("trimTrailingNulls", trimTrailingNulls);
  function textDecoder(label = "utf-8") {
    return new TextDecoder(label, { fatal: false });
  }
  exports_4("textDecoder", textDecoder);
  function escapeHtml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }
  exports_4("escapeHtml", escapeHtml);
  function bytesToBase64(input) {
    const bytes = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    let text = "";
    for (let i = 0; i < bytes.length; i += 32768)
      text += String.fromCharCode(...bytes.subarray(i, i + 32768));
    return btoa(text);
  }
  exports_4("bytesToBase64", bytesToBase64);
  function dataUrlFromBytes(bytes, mime = "application/octet-stream") {
    return `data:${mime};base64,${bytesToBase64(bytes)}`;
  }
  exports_4("dataUrlFromBytes", dataUrlFromBytes);
  function escapeXmlText(text) {
    return escapeHtml(String(text).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, ""));
  }
  exports_4("escapeXmlText", escapeXmlText);
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("ppt/constants", [], function(exports_5, context_5) {
  "use strict";
  var RT, DEFAULT_LIMITS;
  var __moduleName = context_5 && context_5.id;
  return {
    setters: [],
    execute: function() {
      exports_5("RT", RT = {
        Document: 1e3,
        DocumentAtom: 1001,
        EndDocumentAtom: 1002,
        Slide: 1006,
        SlideAtom: 1007,
        Notes: 1008,
        NotesAtom: 1009,
        Environment: 1010,
        SlidePersistAtom: 1011,
        MainMaster: 1016,
        SSSlideInfoAtom: 1017,
        SlideViewInfo: 1018,
        VBAInfo: 1023,
        DocInfoList: 2e3,
        PPDrawingGroup: 1035,
        PPDrawing: 1036,
        List: 2e3,
        FontCollection: 2005,
        TextHeaderAtom: 3999,
        TextCharsAtom: 4e3,
        StyleTextPropAtom: 4001,
        TextMasterStyleAtom: 4003,
        TextCharFormatAtom: 4004,
        TextParagraphFormatAtom: 4005,
        TextRulerAtom: 4006,
        TextBookmarkAtom: 4007,
        TextBytesAtom: 4008,
        TextSpecInfoAtom: 4010,
        DefaultRulerAtom: 4011,
        FontEntityAtom: 4023,
        CString: 4026,
        ExternalObjectList: 1033,
        ExternalObjectRefAtom: 3009,
        SlideListWithText: 4080,
        UserEditAtom: 4085,
        CurrentUserAtom: 4086,
        DateTimeMCAtom: 4087,
        HeadersFooters: 4057,
        HeadersFootersAtom: 4058,
        ColorSchemeAtom: 2032,
        PersistDirectoryAtom: 6002,
        PersistDirectoryFullBlock: 6001,
        OfficeArtClientTextBox: 61453,
        OfficeArtDggContainer: 61440,
        OfficeArtBStoreContainer: 61441,
        OfficeArtDgContainer: 61442,
        OfficeArtSpgrContainer: 61443,
        OfficeArtSpContainer: 61444,
        OfficeArtFSPGR: 61449,
        OfficeArtFSP: 61450,
        OfficeArtFOPT: 61451,
        OfficeArtClientAnchor: 61456,
        OfficeArtChildAnchor: 61455,
        OfficeArtClientData: 61457,
        OfficeArtFBSE: 61447,
        OfficeArtSecondaryFOPT: 61729,
        OfficeArtTertiaryFOPT: 61730,
        OutlineTextRefAtom: 3998,
        OEPlaceholderAtom: 3011
      });
      exports_5("DEFAULT_LIMITS", DEFAULT_LIMITS = Object.freeze({ maxFileBytes: 256 * 1024 * 1024, maxStreamBytes: 256 * 1024 * 1024, maxRecords: 1e6, maxDepth: 64, maxSlides: 1e4, maxShapes: 2e5, maxAssetBytes: 128 * 1024 * 1024, maxTextLength: 16 * 1024 * 1024 }));
    }
  };
});
System.register("ppt/records", ["core/errors"], function(exports_6, context_6) {
  "use strict";
  var errors_js_2;
  var __moduleName = context_6 && context_6.id;
  function readRecord(ctx, offset, end = ctx.bytes.length, depth = 0) {
    if (depth > ctx.limits.maxDepth)
      throw new errors_js_2.PptError("LIMIT_DEPTH", "Record nesting exceeds the configured limit", offset);
    if (++ctx.count > ctx.limits.maxRecords)
      throw new errors_js_2.PptError("LIMIT_RECORDS", "Record count exceeds the configured limit", offset);
    if (!Number.isSafeInteger(offset) || offset < 0 || offset + 8 > end || end > ctx.bytes.length)
      throw new errors_js_2.PptError("RECORD_HEADER", "Truncated or invalid record header", offset);
    const v = new DataView(ctx.bytes.buffer, ctx.bytes.byteOffset + offset, 8);
    const vi = v.getUint16(0, true);
    const length = v.getUint32(4, true);
    const recordEnd = offset + 8 + length;
    if (recordEnd > end)
      throw new errors_js_2.PptError("RECORD_LENGTH", `Record payload exceeds its containing stream (${length} bytes)`, offset);
    const node = { type: v.getUint16(2, true), version: vi & 15, instance: vi >>> 4, offset, dataOffset: offset + 8, length, end: recordEnd, children: [] };
    if ([1038, 1059, 1063, 1064].includes(node.type) && node.version !== 0) {
      ctx.diagnostics.push({ code: "ROUNDTRIP_VERSION", severity: "info", message: "Treated a round-trip Office XML package as an opaque record despite its producer-specific record version.", offset });
    } else if (node.version === 15)
      node.children = readRecords(ctx, node.dataOffset, recordEnd, depth + 1);
    return node;
  }
  exports_6("readRecord", readRecord);
  function readRecords(ctx, start, end, depth = 0) {
    const result = [];
    let offset = start;
    while (offset + 8 <= end) {
      const node = readRecord(ctx, offset, end, depth);
      result.push(node);
      offset = node.end;
    }
    if (offset !== end) {
      const message = `${end - offset} trailing bytes in record container`;
      if (ctx.strict)
        throw new errors_js_2.PptError("RECORD_TAIL", message, offset);
      ctx.diagnostics.push({ code: "RECORD_TAIL", severity: "warning", message, offset });
    }
    return result;
  }
  exports_6("readRecords", readRecords);
  function* walkRecords(records) {
    for (const r of records) {
      yield r;
      yield* walkRecords(r.children);
    }
  }
  exports_6("walkRecords", walkRecords);
  function findRecord(records, type) {
    for (const r of walkRecords(records))
      if (r.type === type)
        return r;
    return void 0;
  }
  exports_6("findRecord", findRecord);
  function childrenOf(record, type) {
    return record.children.filter((r) => r.type === type);
  }
  exports_6("childrenOf", childrenOf);
  return {
    setters: [
      function(errors_js_2_1) {
        errors_js_2 = errors_js_2_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("ppt/interactions", ["ppt/records"], function(exports_7, context_7) {
  "use strict";
  var records_js_1, relative;
  var __moduleName = context_7 && context_7.id;
  function interactionHref(record, bytes, targets) {
    if (record.type !== 4083 || record.length !== 16)
      return void 0;
    const v = new DataView(bytes.buffer, bytes.byteOffset + record.dataOffset, 16), id = v.getUint32(4, true), action = v.getUint8(8), jump = v.getUint8(10), type = v.getUint8(12);
    if (action === 3) {
      if (jump >= 1 && jump <= 4)
        return relative[jump - 1];
      if (jump === 5)
        return "#pptjs-back";
      if (jump === 6)
        return "#pptjs-end";
      return void 0;
    }
    if (action === 4) {
      if (type <= 3)
        return relative[type];
      if (type === 7 || type === 8)
        return targets?.get(id);
    }
    return void 0;
  }
  exports_7("interactionHref", interactionHref);
  function resolveSlideLinks(links, slides, targets, diagnostics) {
    const byId = new Map(slides.map((s, index) => [s.id, index]));
    const unresolved = /* @__PURE__ */ new Map();
    for (const diagnostic of diagnostics)
      if (diagnostic.code === "INTERNAL_LINK_UNRESOLVED" && diagnostic.offset !== void 0 && !unresolved.has(diagnostic.offset))
        unresolved.set(diagnostic.offset, diagnostic);
    for (const link of links) {
      if (link.target.trim() || !link.location)
        continue;
      const text = link.location.trim();
      let index;
      const location = /^(\d+),(\d+),(.*)$/s.exec(text);
      if (location) {
        const id = Number(location[1]), number = Number(location[2]);
        index = byId.get(id);
        if (index === void 0 && id === 0 && number >= 1 && number <= slides.length)
          index = number - 1;
      } else if (/^\d+$/.test(text)) {
        const value = Number(text);
        index = byId.get(value);
        if (index === void 0 && value >= 1 && value <= slides.length)
          index = value - 1;
      }
      if (index === void 0)
        continue;
      const href = `#pptjs-slide=${index}`;
      link.href = href;
      link.blocked = false;
      targets.set(link.id, href);
      const prior = unresolved.get(link.sourceOffset);
      if (prior) {
        prior.code = "INTERNAL_LINK_RESOLVED";
        prior.severity = "info";
        prior.message = "Internal hyperlink resolved against the current slide order";
        prior.details = { slideIndex: index, slideId: slides[index].id };
      }
    }
  }
  exports_7("resolveSlideLinks", resolveSlideLinks);
  function bindShapeInteractions(records, bytes, shapes, extras, targets, diagnostics, slideId) {
    const byOffset = /* @__PURE__ */ new Map();
    for (const r of records_js_1.walkRecords(records))
      byOffset.set(r.offset, r);
    const mediaById = new Map(extras.media.map((m) => [m.id, m])), soundById = new Map(extras.sounds.map((s) => [s.id, s]));
    const visit = (items) => {
      for (const shape of items) {
        if (shape.children)
          visit(shape.children);
        const node = shape.source ? byOffset.get(shape.source.offset) : void 0;
        const clients = node?.children.filter((n) => n.type === 61457) ?? [];
        for (const client of clients) {
          const click = client.children.find((r) => r.type === 4082 && r.instance === 0), atom = click?.children.find((r) => r.type === 4083);
          if (atom) {
            shape.hyperlink = interactionHref(atom, bytes, targets);
            if (!shape.hyperlink && atom.length >= 16) {
              const action = bytes[atom.dataOffset + 8];
              if (action && action !== 6)
                diagnostics.push({ code: "INTERACTION_UNSUPPORTED", severity: "warning", message: "The source click action is retained as metadata and has no preview action", slideId, shapeId: shape.id, offset: atom.offset, details: { action } });
            }
          }
          const ref = client.children.find((r) => r.type === 3009);
          if (!ref || ref.length < 4)
            continue;
          const id = new DataView(bytes.buffer, bytes.byteOffset + ref.dataOffset, 4).getUint32(0, true), media = mediaById.get(id);
          if (!media)
            continue;
          const sound = media.soundId === void 0 ? void 0 : soundById.get(media.soundId);
          shape.media = { mediaId: id, kind: media.kind, assetId: sound?.assetId, posterAssetId: shape.image?.assetId, loop: media.loop };
          if (!sound?.assetId)
            diagnostics.push({ code: "MEDIA_SOURCE_UNAVAILABLE", severity: "warning", message: "The media source is external or has no supported embedded payload", slideId, shapeId: shape.id, offset: ref.offset, details: { mediaId: id } });
        }
      }
    };
    visit(shapes);
  }
  exports_7("bindShapeInteractions", bindShapeInteractions);
  return {
    setters: [
      function(records_js_1_1) {
        records_js_1 = records_js_1_1;
      }
    ],
    execute: function() {
      relative = ["#pptjs-next", "#pptjs-previous", "#pptjs-first", "#pptjs-last"];
    }
  };
});
System.register("ppt/text", ["core/errors", "ppt/interactions", "ppt/constants", "ppt/records"], function(exports_8, context_8) {
  "use strict";
  var errors_js_3, interactions_js_1, constants_js_1, records_js_2, Cursor, EAST_ASIAN, parseTextBodies;
  var __moduleName = context_8 && context_8.id;
  function warn(ctx, code, message, offset) {
    ctx.diagnostics.push({ code, severity: "warning", message, offset });
  }
  function failure(ctx, error, record) {
    if (error instanceof errors_js_3.PptError && error.code.startsWith("LIMIT_"))
      throw error;
    warn(ctx, error instanceof errors_js_3.PptError ? error.code : "TEXT_FORMAT", error instanceof Error ? error.message : String(error), error instanceof errors_js_3.PptError ? error.offset : record.offset);
  }
  function rgb(value) {
    return "#" + [value & 255, value >>> 8 & 255, value >>> 16 & 255].map((n) => n.toString(16).padStart(2, "0")).join("");
  }
  function textColor(value, ctx) {
    const index = value >>> 24;
    if (index <= 7)
      return { colorIndex: index, color: rgb(ctx.colors[index] ?? (index === 0 ? 16777215 : 0)) };
    if (index === 254)
      return { color: rgb(value) };
    if (index !== 255)
      warn(ctx, "TEXT_COLOR_INDEX", `Invalid text color scheme index ${index}; using stored RGB components`);
    return index === 255 ? {} : { color: rgb(value) };
  }
  function fontName(id, ctx) {
    return ctx.fonts.find((f) => f.id === id)?.name;
  }
  function mergeCharacter(base, own) {
    const merged = { ...base, ...Object.fromEntries(Object.entries(own).filter(([, value]) => value !== void 0)) };
    if (own.color !== void 0 && own.colorIndex === void 0)
      delete merged.colorIndex;
    return merged;
  }
  function mergeParagraph(base, own) {
    const merged = { ...base, ...own };
    if (own.wrapFlags !== void 0) {
      const mask = (own.wrapFlagsMask ?? 7) & 7;
      merged.wrapFlags = (base.wrapFlags ?? 0) & ~mask | own.wrapFlags & mask;
      merged.wrapFlagsMask = ((base.wrapFlagsMask ?? (base.wrapFlags === void 0 ? 0 : 7)) | mask) & 7;
    }
    if (base.bullet || own.bullet) {
      merged.bullet = { ...base.bullet, ...own.bullet, text: own.bullet?.text || base.bullet?.text || "\u2022" };
      if (own.bullet?.color !== void 0 && own.bullet.colorIndex === void 0)
        delete merged.bullet.colorIndex;
      if (own.bullet?.size !== void 0)
        delete merged.bullet.sizePercent;
      if (own.bullet?.sizePercent !== void 0)
        delete merged.bullet.size;
    }
    if (own.lineHeight !== void 0)
      delete merged.lineHeightPoints;
    if (own.lineHeightPoints !== void 0)
      delete merged.lineHeight;
    if (own.spaceBefore !== void 0)
      delete merged.spaceBeforePercent;
    if (own.spaceBeforePercent !== void 0)
      delete merged.spaceBefore;
    if (own.spaceAfter !== void 0)
      delete merged.spaceAfterPercent;
    if (own.spaceAfterPercent !== void 0)
      delete merged.spaceAfter;
    return merged;
  }
  function readCF(c, ctx) {
    const maskOffset = c.at;
    const mask = c.u32();
    if (mask & 118489088)
      throw new errors_js_3.PptError("TEXT_CF_EXTENSION", `Unsupported extension bits in base character formatting: 0x${mask.toString(16)}`, maskOffset);
    const out = {};
    if (mask & 16055) {
      const flags = c.u16();
      if (mask & 1)
        out.bold = !!(flags & 1);
      if (mask & 2)
        out.italic = !!(flags & 2);
      if (mask & 4)
        out.underline = !!(flags & 4);
      if (mask & 16)
        out.shadow = !!(flags & 16);
      if (mask & 512)
        out.emboss = !!(flags & 512);
    }
    if (mask & 65536) {
      out.fontId = c.u16();
      out.fontFamily = fontName(out.fontId, ctx);
    }
    if (mask & 2097152) {
      out.eastAsianFontId = c.u16();
      out.eastAsianFontFamily = fontName(out.eastAsianFontId, ctx);
    }
    if (mask & 4194304) {
      out.ansiFontId = c.u16();
      out.ansiFontFamily = fontName(out.ansiFontId, ctx);
    }
    if (mask & 8388608) {
      out.symbolFontId = c.u16();
      out.symbolFontFamily = fontName(out.symbolFontId, ctx);
    }
    if (mask & 131072) {
      const size = c.i16();
      if (size < 1 || size > 4e3)
        warn(ctx, "TEXT_FONT_SIZE", `Invalid font size ${size} points`, c.at - 2);
      else
        out.fontSize = size * 4 / 3;
    }
    if (mask & 262144)
      Object.assign(out, textColor(c.u32(), ctx));
    if (mask & 524288)
      out.baseline = c.i16();
    return out;
  }
  function readTabs(c, ctx) {
    const count = c.u16();
    c.need(count * 4);
    const tabs = [];
    for (let i = 0; i < count; i++) {
      const position = c.i16() / 6;
      const kind = c.u16();
      if (kind > 3)
        warn(ctx, "TEXT_TAB_ALIGNMENT", `Unknown tab alignment ${kind}`, c.at - 2);
      tabs.push({ position, alignment: ["left", "center", "right", "decimal"][kind] ?? "left" });
    }
    return tabs;
  }
  function spacing(out, property, value) {
    if (property === "lineHeight") {
      if (value < 0)
        out.lineHeightPoints = -value / 6;
      else
        out.lineHeight = value / 100;
    } else if (property === "spaceBefore") {
      if (value < 0)
        out.spaceBefore = -value / 6;
      else
        out.spaceBeforePercent = value / 100;
    } else {
      if (value < 0)
        out.spaceAfter = -value / 6;
      else
        out.spaceAfterPercent = value / 100;
    }
  }
  function readPF(c, ctx) {
    const maskOffset = c.at;
    const mask = c.u32();
    if (mask & 58720256)
      throw new errors_js_3.PptError("TEXT_PF_EXTENSION", `Unsupported extension bits in base paragraph formatting: 0x${mask.toString(16)}`, maskOffset);
    const out = {};
    const bullet = { text: "" };
    if (mask & 15) {
      const flags = c.u16();
      if (mask & 1)
        out.bulletEnabled = !!(flags & 1);
      if (mask & 2)
        bullet.useFont = !!(flags & 2);
      if (mask & 4)
        bullet.useColor = !!(flags & 4);
      if (mask & 8)
        bullet.useSize = !!(flags & 8);
    }
    if (mask & 128)
      bullet.text = String.fromCharCode(c.u16());
    if (mask & 16) {
      bullet.fontId = c.u16();
      bullet.fontFamily = fontName(bullet.fontId, ctx);
    }
    if (mask & 64) {
      const size = c.i16();
      if (size < 0)
        bullet.size = -size * 4 / 3;
      else
        bullet.sizePercent = size / 100;
    }
    if (mask & 32)
      Object.assign(bullet, textColor(c.u32(), ctx));
    if (mask & 255)
      out.bullet = bullet;
    if (mask & 2048) {
      const align = c.u16();
      out.alignment = ["left", "center", "right", "justify", "distributed", "justify", "justify"][align] ?? "left";
      if (align === 5 || align === 6)
        warn(ctx, "TEXT_DISTRIBUTED_ALIGNMENT", `Text alignment ${align} is approximated as justified`, c.at - 2);
      else if (align > 6)
        warn(ctx, "TEXT_ALIGNMENT", `Unknown text alignment ${align}; using left alignment`, c.at - 2);
    }
    if (mask & 4096)
      spacing(out, "lineHeight", c.i16());
    if (mask & 8192)
      spacing(out, "spaceBefore", c.i16());
    if (mask & 16384)
      spacing(out, "spaceAfter", c.i16());
    if (mask & 256)
      out.marginLeft = c.i16() / 6;
    if (mask & 1024)
      out.firstLinePosition = c.i16() / 6;
    if (mask & 32768)
      out.defaultTabSize = c.i16() / 6;
    if (mask & 1048576) {
      out.tabStops = readTabs(c, ctx);
      if (mask & 256)
        for (const stop of out.tabStops)
          stop.origin = "paragraph";
    }
    if (mask & 65536) {
      out.fontAlignment = c.u16();
      if (out.fontAlignment > 3)
        warn(ctx, "TEXT_FONT_ALIGNMENT", `Unknown font alignment ${out.fontAlignment}; using the font baseline`, c.at - 2);
    }
    if (mask & 917504) {
      out.wrapFlags = c.u16() & 7;
      out.wrapFlagsMask = mask >>> 17 & 7;
    }
    if (mask & 2097152)
      out.direction = c.u16() === 1 ? "rtl" : "ltr";
    return out;
  }
  function readRuler(record, ctx) {
    const c = new Cursor(ctx.bytes, record);
    const flags = c.u32();
    const result = { common: {}, levels: Array.from({ length: 5 }, () => ({})) };
    if (flags & ~8191)
      warn(ctx, "TEXT_RULER_RESERVED", "Reserved text-ruler bits are set", record.offset);
    if (flags & 2) {
      const levels = c.i16();
      if (levels < 0 || levels > 5)
        warn(ctx, "TEXT_RULER_LEVELS", `Invalid text-ruler level count ${levels}`, c.at - 2);
    }
    if (flags & 1)
      result.common.defaultTabSize = c.i16() / 6;
    if (flags & 4)
      result.common.tabStops = readTabs(c, ctx);
    for (let level = 0; level < 5; level++) {
      if (flags & 1 << 3 + level)
        result.levels[level].marginLeft = c.i16() / 6;
      if (flags & 1 << 8 + level)
        result.levels[level].firstLinePosition = c.i16() / 6;
    }
    return result;
  }
  function decodeChars(record, ctx) {
    if (record.length / 2 > ctx.limits.maxTextLength)
      throw new errors_js_3.PptError("LIMIT_TEXT", "Text body exceeds the configured character limit", record.offset);
    if (record.length % 2 !== 0)
      warn(ctx, "TEXT_ODD_UTF16", "An odd trailing byte in UTF-16 text was ignored", record.end - 1);
    const count = Math.floor(record.length / 2);
    const v = new DataView(ctx.bytes.buffer, ctx.bytes.byteOffset, ctx.bytes.byteLength);
    const parts = [];
    for (let i = 0; i < count; i += 8192) {
      const chars = [];
      for (let j = i; j < Math.min(count, i + 8192); j++)
        chars.push(v.getUint16(record.dataOffset + j * 2, true));
      parts.push(String.fromCharCode(...chars));
    }
    return parts.join("");
  }
  function decodeBytes(record, ctx) {
    if (record.length > ctx.limits.maxTextLength)
      throw new errors_js_3.PptError("LIMIT_TEXT", "Text body exceeds the configured character limit", record.offset);
    const data = ctx.bytes.subarray(record.dataOffset, record.end);
    const parts = [];
    for (let i = 0; i < data.length; i += 8192)
      parts.push(String.fromCharCode(...data.subarray(i, i + 8192)));
    return parts.join("");
  }
  function checkCount(count, covered, length, offset) {
    if (count === 0 || count > length - covered)
      throw new errors_js_3.PptError("TEXT_RUN_COVERAGE", `Invalid text run length ${count}; ${length - covered} UTF-16 code units remain`, offset);
  }
  function parseRuns(record, length, ctx) {
    const c = new Cursor(ctx.bytes, record);
    const paragraphs = [], characters = [];
    try {
      let count = 0;
      while (count < length) {
        if (paragraphs.length >= ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many paragraph formatting runs", c.at);
        const start = count, size = c.u32();
        checkCount(size, count, length, c.at - 4);
        const rawLevel = c.u16();
        if (rawLevel > 4)
          warn(ctx, "TEXT_INDENT_LEVEL", `Paragraph indent level ${rawLevel} exceeds 4`, c.at - 2);
        const style = readPF(c, ctx);
        count += size;
        paragraphs.push({ start, end: count, level: Math.min(4, rawLevel), style });
      }
      count = 0;
      while (count < length) {
        if (characters.length >= ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many character formatting runs", c.at);
        const start = count, size = c.u32();
        checkCount(size, count, length, c.at - 4);
        const style = readCF(c, ctx);
        count += size;
        characters.push({ start, end: count, style });
      }
      if (c.at !== c.end)
        warn(ctx, "TEXT_STYLE_TAIL", `${c.end - c.at} unused bytes in text formatting`, c.at);
    } catch (error) {
      failure(ctx, error, record);
    }
    return { paragraphs, characters };
  }
  function readSI(c, ctx) {
    const mask = c.u32(), style = {};
    if (mask & 1)
      c.u16();
    if (mask & 2)
      style.language = c.u16();
    if (mask & 4)
      style.alternateLanguage = c.u16();
    if (mask & 64)
      c.u16();
    if (mask & 32)
      c.u32();
    if (mask & 512) {
      const count = c.u32();
      if (count > ctx.limits.maxRecords)
        throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many smart-tag indices", c.at - 4);
      c.need(count * 4);
      c.at += count * 4;
    }
    for (const language of [style.language, style.alternateLanguage]) {
      if (language !== void 0 && language !== 0 && language !== 19 && language < 1024)
        warn(ctx, "TEXT_LANGUAGE", `Invalid text language identifier 0x${language.toString(16)}`, c.at);
    }
    return style;
  }
  function parseSpecialInfo(record, length, ctx) {
    const c = new Cursor(ctx.bytes, record), ranges = [];
    let covered = 0;
    try {
      while (covered < length) {
        if (ranges.length >= ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many text language runs", c.at);
        const start = covered, count = c.u32();
        checkCount(count, covered, length, c.at - 4);
        const style = readSI(c, ctx);
        covered += count;
        ranges.push({ start, end: covered, style });
      }
      if (c.at !== c.end)
        warn(ctx, "TEXT_SI_TAIL", `${c.end - c.at} unused bytes in text language properties`, c.at);
    } catch (error) {
      failure(ctx, error, record);
    }
    return ranges;
  }
  function baseTextType(textType) {
    return textType === 6 ? 0 : textType === 5 || textType === 7 || textType === 8 ? 1 : void 0;
  }
  function masterLevel(ctx, textType, level) {
    const defaultLevels = ctx.masterStyles?.get(4);
    const defaults = defaultLevels?.[level] ?? defaultLevels?.[0];
    const baseType = baseTextType(textType);
    const baseLevels = baseType === void 0 ? void 0 : ctx.masterStyles?.get(baseType);
    const base = baseLevels?.[level] ?? baseLevels?.[0];
    const levels = ctx.masterStyles?.get(textType);
    const selected = levels?.[level] ?? levels?.[0];
    return {
      paragraph: mergeParagraph(mergeParagraph(mergeParagraph({ bulletEnabled: false }, defaults?.paragraph ?? {}), base?.paragraph ?? {}), selected?.paragraph ?? {}),
      character: mergeCharacter(mergeCharacter({ fontFamily: ctx.fonts[0]?.name ?? "Arial", fontSize: 24, color: "#000000" }, ctx.defaultStyle ?? {}), mergeCharacter(mergeCharacter(defaults?.character ?? {}, base?.character ?? {}), selected?.character ?? {}))
    };
  }
  function resolveCharacter(style, ctx) {
    const s = { ...style };
    if (s.fontId !== void 0)
      s.fontFamily = fontName(s.fontId, ctx) ?? s.fontFamily;
    if (s.eastAsianFontId !== void 0)
      s.eastAsianFontFamily = fontName(s.eastAsianFontId, ctx) ?? s.eastAsianFontFamily;
    if (s.ansiFontId !== void 0)
      s.ansiFontFamily = fontName(s.ansiFontId, ctx) ?? s.ansiFontFamily;
    if (s.symbolFontId !== void 0)
      s.symbolFontFamily = fontName(s.symbolFontId, ctx) ?? s.symbolFontFamily;
    if (s.colorIndex !== void 0)
      s.color = rgb(ctx.colors[s.colorIndex] ?? 0);
    return s;
  }
  function resolveParagraph(style, firstStyle, ctx) {
    const s = mergeParagraph({}, style);
    if (s.firstLinePosition !== void 0)
      s.indent = s.firstLinePosition - (s.marginLeft ?? 0);
    if (s.bulletEnabled === false || s.bulletEnabled === void 0 && !s.bullet?.text)
      delete s.bullet;
    else if (s.bullet) {
      const bullet = s.bullet;
      bullet.text ||= "\u2022";
      if (bullet.useFont === false) {
        delete bullet.fontId;
        delete bullet.fontFamily;
      } else if (bullet.fontId !== void 0)
        bullet.fontFamily = fontName(bullet.fontId, ctx) ?? bullet.fontFamily;
      if (bullet.useColor === false) {
        delete bullet.color;
        delete bullet.colorIndex;
      } else if (bullet.colorIndex !== void 0)
        bullet.color = rgb(ctx.colors[bullet.colorIndex] ?? 0);
      if (bullet.useSize === false) {
        delete bullet.size;
        delete bullet.sizePercent;
      } else if (bullet.sizePercent !== void 0)
        bullet.size = (firstStyle.fontSize ?? 24) * bullet.sizePercent;
    }
    return s;
  }
  function splitScriptRun(text, style, start, maxRuns) {
    if (maxRuns < 1)
      throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many rendered text runs");
    if (!style.eastAsianFontFamily && !style.ansiFontFamily && !style.symbolFontFamily)
      return [{ text: text.replace(/\u000b/g, "\n"), style, sourceStart: start, sourceEnd: start + text.length }];
    const result = [];
    let previousFamily;
    let from = 0;
    for (let i = 0; i <= text.length; ) {
      const code = text.codePointAt(i) ?? 0;
      const char = i === text.length ? void 0 : String.fromCodePoint(code);
      const family = char === void 0 ? void 0 : code >= 61440 && code <= 61695 && style.symbolFontFamily ? style.symbolFontFamily : EAST_ASIAN.test(char) ? style.eastAsianFontFamily ?? style.fontFamily : style.ansiFontFamily ?? style.fontFamily;
      if (i === 0)
        previousFamily = family;
      if (i === text.length || family !== previousFamily) {
        if (result.length >= maxRuns)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many rendered text runs");
        result.push({ text: text.slice(from, i).replace(/\u000b/g, "\n"), style: { ...style, fontFamily: previousFamily }, sourceStart: start + from, sourceEnd: start + i });
        from = i;
        previousFamily = family;
      }
      if (i === text.length)
        break;
      i += code > 65535 ? 2 : 1;
    }
    return result;
  }
  function parseHyperlinkRanges(records, length, ctx) {
    const ranges = [];
    let pending;
    for (const record of records) {
      if (record.type === 4082 && record.instance === 0) {
        pending = void 0;
        const atom = record.children.find((child) => child.type === 4083);
        if (!atom)
          continue;
        try {
          const c = new Cursor(ctx.bytes, atom);
          c.need(16);
          pending = interactions_js_1.interactionHref(atom, ctx.bytes, ctx.hyperlinkTargets);
        } catch (error) {
          failure(ctx, error, atom);
        }
      } else if (record.type === 4063 && record.instance === 0) {
        const href = pending;
        pending = void 0;
        if (!href)
          continue;
        try {
          const c = new Cursor(ctx.bytes, record);
          const start = c.u32(), end = c.u32();
          if (start >= end || end > length)
            throw new errors_js_3.PptError("TEXT_HYPERLINK_RANGE", `Invalid hyperlink range ${start}..${end} for ${length} UTF-16 code units`, record.offset);
          if (ranges.length >= ctx.limits.maxRecords)
            throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many text hyperlink ranges", record.offset);
          ranges.push({ start, end, href, offset: record.offset });
        } catch (error) {
          failure(ctx, error, record);
        }
      }
    }
    ranges.sort((a, b) => a.start - b.start || a.offset - b.offset);
    const result = [];
    for (const range of ranges) {
      const previous = result[result.length - 1];
      if (previous && range.start < previous.end) {
        warn(ctx, "TEXT_HYPERLINK_OVERLAP", "Overlapping text hyperlink range was ignored", range.offset);
        continue;
      }
      result.push(range);
    }
    return result;
  }
  function parseFields(records, text, ctx) {
    const fields = [];
    const positions = /* @__PURE__ */ new Set();
    for (const record of records) {
      const type = record.type === 4056 ? "slideNumber" : record.type === 4087 || record.type === 4117 ? "dateTime" : record.type === 4088 ? "genericDate" : record.type === 4089 ? "header" : record.type === 4090 ? "footer" : void 0;
      if (!type)
        continue;
      try {
        const c = new Cursor(ctx.bytes, record);
        const position = c.u32();
        if (position > text.length)
          throw new errors_js_3.PptError("TEXT_FIELD_POSITION", `Metacharacter position ${position} exceeds its text body`, record.offset);
        if (positions.has(position))
          throw new errors_js_3.PptError("TEXT_FIELD_DUPLICATE", `More than one metacharacter occupies UTF-16 position ${position}`, record.offset);
        const field = { position, type };
        if (record.type === 4087) {
          c.need(4);
          field.format = c.view.getUint8(c.at);
          c.at += 4;
          if (field.format > 12)
            warn(ctx, "TEXT_DATE_FORMAT", `Unsupported date metacharacter format ${field.format}`, record.offset);
        } else if (record.type === 4117) {
          c.need(128);
          let format = "";
          for (let i = 0; i < 64; i++) {
            const unit = c.view.getUint16(c.at + i * 2, true);
            if (!unit)
              break;
            format += String.fromCharCode(unit);
          }
          field.format = format;
          c.at += 128;
        }
        if (c.at !== c.end)
          warn(ctx, "TEXT_FIELD_LENGTH", "Extra bytes in a text metacharacter record were ignored", c.at);
        if (position === text.length)
          warn(ctx, "TEXT_FIELD_TERMINAL", "Metacharacter refers to the implicit terminal paragraph mark", record.offset);
        if (fields.length >= ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_FIELDS", "Too many text metacharacters", record.offset);
        positions.add(position);
        fields.push(field);
      } catch (error) {
        failure(ctx, error, record);
      }
    }
    return fields.sort((a, b) => a.position - b.position);
  }
  function parseMasterIndent(record, length, ctx) {
    const c = new Cursor(ctx.bytes, record), result = [];
    let covered = 0;
    try {
      while (covered < length) {
        if (result.length >= ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many master indent runs", c.at);
        const start = covered, count = c.u32();
        checkCount(count, covered, length, c.at - 4);
        const level = c.u16();
        covered += count;
        result.push({ start, end: covered, level: Math.min(level, 4), style: {} });
      }
    } catch (error) {
      failure(ctx, error, record);
    }
    return result;
  }
  function frameFromRecords(records, ctx) {
    const header = records.find((r) => r.type === constants_js_1.RT.TextHeaderAtom);
    const textRecord = records.find((r) => r.type === constants_js_1.RT.TextCharsAtom || r.type === constants_js_1.RT.TextBytesAtom);
    if (!header && !textRecord)
      return void 0;
    let textType = 4;
    if (header) {
      try {
        textType = new Cursor(ctx.bytes, header).u32();
      } catch (error) {
        failure(ctx, error, header);
      }
    }
    const text = textRecord ? textRecord.type === constants_js_1.RT.TextCharsAtom ? decodeChars(textRecord, ctx) : decodeBytes(textRecord, ctx) : "";
    const length = text.length + 1;
    if (length - 1 > ctx.limits.maxTextLength)
      throw new errors_js_3.PptError("LIMIT_TEXT", "Text body exceeds configured limit", textRecord?.offset);
    const styleRecord = records.find((r) => r.type === constants_js_1.RT.StyleTextPropAtom);
    const ranges = styleRecord ? parseRuns(styleRecord, length, ctx) : { paragraphs: [], characters: [] };
    const specialInfoRecord = records.find((r) => r.type === constants_js_1.RT.TextSpecInfoAtom);
    const specialInfo = specialInfoRecord ? parseSpecialInfo(specialInfoRecord, length, ctx) : [];
    const hyperlinks = parseHyperlinkRanges(records, length, ctx);
    const fields = parseFields(records, text, ctx);
    const indentRecord = records.find((r) => r.type === 4002);
    if (!ranges.paragraphs.length && indentRecord)
      ranges.paragraphs = parseMasterIndent(indentRecord, length, ctx);
    let ruler;
    const rulerRecord = records.find((r) => r.type === constants_js_1.RT.TextRulerAtom);
    if (rulerRecord) {
      try {
        ruler = readRuler(rulerRecord, ctx);
      } catch (error) {
        failure(ctx, error, rulerRecord);
      }
    }
    const paragraphs = [];
    let pfIndex = 0, cfIndex = 0, siIndex = 0, linkIndex = 0, outputRunCount = 0, from = 0;
    for (let to = 0; to <= text.length; to++) {
      if (to !== text.length && text.charCodeAt(to) !== 13)
        continue;
      if (paragraphs.length >= ctx.limits.maxRecords)
        throw new errors_js_3.PptError("LIMIT_TEXT_PARAGRAPHS", "Too many text paragraphs", textRecord?.offset);
      while (pfIndex + 1 < ranges.paragraphs.length && ranges.paragraphs[pfIndex].end <= from)
        pfIndex++;
      const pf = ranges.paragraphs[pfIndex];
      const level = pf && pf.start <= from && pf.end > from ? pf.level : 0;
      const inherited = masterLevel(ctx, textType, level);
      let paragraphStyle = mergeParagraph(inherited.paragraph, pf && pf.start <= from && pf.end > from ? pf.style : {});
      if (ruler)
        paragraphStyle = mergeParagraph(paragraphStyle, mergeParagraph(ruler.common, ruler.levels[level] ?? {}));
      const runs = [];
      let at = from;
      while (at < to) {
        while (cfIndex < ranges.characters.length && ranges.characters[cfIndex].end <= at)
          cfIndex++;
        const cf = ranges.characters[cfIndex];
        const active = cf && cf.start <= at && cf.end > at ? cf : void 0;
        while (siIndex < specialInfo.length && specialInfo[siIndex].end <= at)
          siIndex++;
        const si = specialInfo[siIndex];
        const activeSI = si && si.start <= at && si.end > at ? si : void 0;
        while (linkIndex < hyperlinks.length && hyperlinks[linkIndex].end <= at)
          linkIndex++;
        const link = hyperlinks[linkIndex];
        const activeLink = link && link.start <= at && link.end > at ? link : void 0;
        const end = Math.min(to, active?.end ?? (cf && cf.start > at ? cf.start : to), activeSI?.end ?? (si && si.start > at ? si.start : to), activeLink?.end ?? (link && link.start > at ? link.start : to));
        const style = resolveCharacter(mergeCharacter(mergeCharacter(inherited.character, active?.style ?? {}), activeSI?.style ?? {}), ctx);
        if (activeLink)
          style.hyperlink = activeLink.href;
        const scriptRuns = splitScriptRun(text.slice(at, end), style, at, ctx.limits.maxRecords - outputRunCount);
        outputRunCount += scriptRuns.length;
        for (const run of scriptRuns)
          runs.push(run);
        at = end;
      }
      if (!runs.length) {
        if (++outputRunCount > ctx.limits.maxRecords)
          throw new errors_js_3.PptError("LIMIT_TEXT_RUNS", "Too many rendered text runs", textRecord?.offset);
        while (cfIndex < ranges.characters.length && ranges.characters[cfIndex].end <= from)
          cfIndex++;
        const cf = ranges.characters[cfIndex];
        while (siIndex < specialInfo.length && specialInfo[siIndex].end <= from)
          siIndex++;
        const si = specialInfo[siIndex];
        const style = mergeCharacter(mergeCharacter(inherited.character, cf && cf.start <= from ? cf.style : {}), si && si.start <= from ? si.style : {});
        runs.push({ text: "", style: resolveCharacter(style, ctx), sourceStart: from, sourceEnd: from });
      }
      paragraphs.push({ level, runs, style: resolveParagraph(paragraphStyle, runs[0].style, ctx) });
      from = to + 1;
    }
    for (const r of records) {
      if ([4012, 4017, 4022].includes(r.type))
        warn(ctx, "TEXT_EXTENDED_STYLE", `Extended text formatting record 0x${r.type.toString(16)} is preserved only as a diagnostic`, r.offset);
    }
    return { paragraphs, margins: { left: 9.6, right: 9.6, top: 4.8, bottom: 4.8 }, verticalAlignment: "top", wrap: true, textType, sourceText: text, ...fields.length ? { fields } : {} };
  }
  function parseTextFrames(records, ctx) {
    const result = [];
    let body = [];
    const flush = () => {
      if (!body.length)
        return;
      const frame = frameFromRecords(body, ctx);
      if (frame)
        result.push(frame);
      body = [];
    };
    for (const record of records) {
      if (record.type === constants_js_1.RT.TextHeaderAtom || record.type === constants_js_1.RT.SlidePersistAtom)
        flush();
      if (record.type !== constants_js_1.RT.SlidePersistAtom)
        body.push(record);
    }
    flush();
    return result;
  }
  exports_8("parseTextFrames", parseTextFrames);
  function parseDefaultTextStyle(records, ctx) {
    for (const record of records_js_2.walkRecords(records)) {
      if (record.type !== 4009)
        continue;
      try {
        return readSI(new Cursor(ctx.bytes, record), ctx);
      } catch (error) {
        failure(ctx, error, record);
        return {};
      }
    }
    return {};
  }
  exports_8("parseDefaultTextStyle", parseDefaultTextStyle);
  function parseMasterTextStyles(records, ctx) {
    const result = /* @__PURE__ */ new Map();
    for (const [type, levels] of ctx.masterStyles ?? [])
      result.set(type, levels.map((level) => ({ paragraph: mergeParagraph({}, level.paragraph), character: { ...level.character } })));
    for (const record of records_js_2.walkRecords(records)) {
      if (record.type !== constants_js_1.RT.TextMasterStyleAtom)
        continue;
      const levels = result.get(record.instance)?.slice() ?? [];
      try {
        const c = new Cursor(ctx.bytes, record);
        const count = c.u16();
        if (count > 5)
          throw new errors_js_3.PptError("TEXT_MASTER_LEVELS", `Master style has ${count} levels; at most five are valid`, record.offset);
        for (let i = 0; i < count; i++) {
          const level = record.instance >= 5 ? c.u16() : i;
          if (level >= count)
            throw new errors_js_3.PptError("TEXT_MASTER_LEVEL", `Invalid master style level ${level}`, c.at - 2);
          const paragraph = readPF(c, ctx), character = readCF(c, ctx);
          const inherited = levels[level];
          levels[level] = { paragraph: mergeParagraph(inherited?.paragraph ?? {}, paragraph), character: mergeCharacter(inherited?.character ?? {}, character) };
        }
        if (c.at !== c.end)
          warn(ctx, "TEXT_MASTER_TAIL", `${c.end - c.at} unused bytes in master text style`, c.at);
      } catch (error) {
        failure(ctx, error, record);
      }
      result.set(record.instance, levels);
    }
    return result;
  }
  exports_8("parseMasterTextStyles", parseMasterTextStyles);
  function parseFonts(records, bytes) {
    const fonts = [];
    let fontIndex = 0;
    for (const record of records_js_2.walkRecords(records)) {
      if (record.type !== constants_js_1.RT.FontEntityAtom)
        continue;
      const id = fontIndex++;
      if (record.length < 68 || record.dataOffset < 0 || record.end > bytes.length)
        continue;
      const view = new DataView(bytes.buffer, bytes.byteOffset + record.dataOffset, record.length);
      let name = "";
      for (let i = 0; i < 32; i++) {
        const unit = view.getUint16(i * 2, true);
        if (!unit)
          break;
        name += String.fromCharCode(unit);
      }
      fonts.push({ id, name: name || "Arial", charset: view.getUint8(64) });
    }
    return fonts;
  }
  exports_8("parseFonts", parseFonts);
  return {
    setters: [
      function(errors_js_3_1) {
        errors_js_3 = errors_js_3_1;
      },
      function(interactions_js_1_1) {
        interactions_js_1 = interactions_js_1_1;
      },
      function(constants_js_1_1) {
        constants_js_1 = constants_js_1_1;
      },
      function(records_js_2_1) {
        records_js_2 = records_js_2_1;
      }
    ],
    execute: function() {
      Cursor = class Cursor {
        view;
        at;
        end;
        constructor(bytes, record) {
          this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
          this.at = record.dataOffset;
          this.end = record.end;
          if (this.at < 0 || this.end > bytes.length || this.at > this.end)
            throw new errors_js_3.PptError("TEXT_BOUNDS", "Text record lies outside its stream", record.offset);
        }
        need(size) {
          if (!Number.isSafeInteger(size) || size < 0 || this.at + size > this.end)
            throw new errors_js_3.PptError("TEXT_TRUNCATED", "Truncated text formatting field", this.at);
        }
        u16() {
          this.need(2);
          const n = this.view.getUint16(this.at, true);
          this.at += 2;
          return n;
        }
        i16() {
          this.need(2);
          const n = this.view.getInt16(this.at, true);
          this.at += 2;
          return n;
        }
        u32() {
          this.need(4);
          const n = this.view.getUint32(this.at, true);
          this.at += 4;
          return n;
        }
      };
      EAST_ASIAN = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Bopomofo}\u3000-\u303f\uff01-\uffef]/u;
      exports_8("parseTextBodies", parseTextBodies = parseTextFrames);
    }
  };
});
System.register("ppt/geometry", [], function(exports_9, context_9) {
  "use strict";
  var __moduleName = context_9 && context_9.id;
  function officeArray(bytes) {
    if (bytes.length < 6)
      return void 0;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const count = view.getUint16(0, true), rawSize = view.getUint16(4, true), size = rawSize === 65520 ? 4 : rawSize;
    if (!size || count > view.getUint16(2, true) || 6 + count * size > bytes.length)
      return void 0;
    return { view, count, size };
  }
  exports_9("officeArray", officeArray);
  function evaluateGuides(bytes, values, geometry, bounds) {
    const arr = officeArray(bytes);
    if (!arr || arr.size !== 8 || arr.count > 128)
      return void 0;
    const guides = [], rad = Math.PI / (180 * 65536);
    const reference = (n) => {
      if (n >= 1024 && n <= 1151)
        return guides[n - 1024];
      if (n >= 327 && n <= 334)
        return (values.get(n) ?? 0) | 0;
      if (n === 339 || n === 340)
        return (values.get(n) ?? 2147483648) | 0;
      switch (n) {
        case 320:
          return geometry.x + geometry.width / 2;
        case 321:
          return geometry.y + geometry.height / 2;
        case 322:
          return geometry.width;
        case 323:
          return geometry.height;
        case 508: {
          const b = values.get(511);
          return b !== void 0 && b & 524288 ? b & 8 ? 1 : 0 : 1;
        }
        case 1271:
          return (values.get(459) ?? 9525) / 9525;
        case 1272:
          return bounds?.width;
        case 1273:
          return bounds?.height;
        case 1276:
          return bounds ? bounds.width * 9525 : void 0;
        case 1277:
          return bounds ? bounds.height * 9525 : void 0;
        case 1278:
          return bounds ? bounds.width * 9525 / 2 : void 0;
        case 1279:
          return bounds ? bounds.height * 9525 / 2 : void 0;
        default:
          return void 0;
      }
    };
    for (let i = 0; i < arr.count; i++) {
      const at = 6 + i * 8, flags = arr.view.getUint16(at, true), params = [];
      for (let p = 0; p < 3; p++) {
        const raw = arr.view.getUint16(at + 2 + p * 2, true), value = flags & 1 << 13 + p ? reference(raw) : raw;
        if (value === void 0)
          return void 0;
        params.push(value);
      }
      const [a, b, c] = params;
      let result;
      switch (flags & 8191) {
        case 0:
          result = a + b - c;
          break;
        case 1:
          result = a * b / c;
          break;
        case 2:
          result = (a + b) / 2;
          break;
        case 3:
          result = Math.abs(a);
          break;
        case 4:
          result = Math.min(a, b);
          break;
        case 5:
          result = Math.max(a, b);
          break;
        case 6:
          result = a > 0 ? b : c;
          break;
        case 7:
          result = Math.hypot(a, b, c);
          break;
        case 8:
          result = Math.atan2(b, a) / rad;
          break;
        case 9:
          result = a * Math.sin(b * rad);
          break;
        case 10:
          result = a * Math.cos(b * rad);
          break;
        case 11:
          result = a * Math.cos(Math.atan2(c, b));
          break;
        case 12:
          result = a * Math.sin(Math.atan2(c, b));
          break;
        case 13:
          result = Math.sqrt(a);
          break;
        case 14:
          result = a + (b + c) * 65536;
          break;
        case 15:
          result = c * Math.sqrt(1 - (a / b) ** 2);
          break;
        case 16:
          result = a * Math.tan(b * rad);
          break;
        default:
          return void 0;
      }
      if (!Number.isFinite(result))
        return void 0;
      guides.push(result);
    }
    return guides;
  }
  exports_9("evaluateGuides", evaluateGuides);
  function customGeometry(values, complex, diagnostics, shapeId, offset, bounds) {
    const raw = complex.get(325);
    if (!raw)
      return {};
    const arr = officeArray(raw);
    if (!arr || arr.size !== 4 && arr.size !== 8) {
      diagnostics.push({ code: "GEOMETRY_VERTICES", severity: "warning", message: "Invalid OfficeArt vertices array", shapeId, offset });
      return {};
    }
    const left = (values.get(320) ?? 0) | 0, top = (values.get(321) ?? 0) | 0;
    const right = (values.get(322) ?? 21600) | 0, bottom = (values.get(323) ?? 21600) | 0;
    const pathBounds = { x: left, y: top, width: right - left || 21600, height: bottom - top || 21600 };
    const recoverX = right === left, recoverY = bottom === top, recover = recoverX || recoverY;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    const include = (p) => {
      if (recover) {
        minX = Math.min(minX, p[0]);
        maxX = Math.max(maxX, p[0]);
        minY = Math.min(minY, p[1]);
        maxY = Math.max(maxY, p[1]);
      }
    };
    const guidesBytes = complex.get(342), guides = guidesBytes ? evaluateGuides(guidesBytes, values, pathBounds, bounds) : void 0;
    const resolveCoordinate = (n) => n >= -2147483648 && n <= -2147483521 ? guides?.[n + 2147483648] : n;
    const points = [];
    for (let i = 0; i < arr.count; i++) {
      const p = 6 + i * arr.size;
      const x = resolveCoordinate(arr.size === 4 ? arr.view.getInt16(p, true) : arr.view.getInt32(p, true));
      const y = resolveCoordinate(arr.size === 4 ? arr.view.getInt16(p + 2, true) : arr.view.getInt32(p + 4, true));
      if (x === void 0 || y === void 0) {
        diagnostics.push({ code: "GEOMETRY_GUIDE", severity: "warning", message: "Custom path references an invalid or unsupported formula guide", shapeId, offset });
        return {};
      }
      points.push([x, y]);
    }
    if (!points.length)
      return {};
    const segBytes = complex.get(326), segments = segBytes ? officeArray(segBytes) : void 0;
    if (segBytes && !segments) {
      diagnostics.push({ code: "GEOMETRY_SEGMENTS", severity: "warning", message: "Invalid OfficeArt segment array; custom path is not guessed from vertices alone", shapeId, offset });
      return {};
    }
    let parts = [];
    let index = 0, noFill = false, noLine = false, valid = true;
    const pathParts = [];
    let current, start;
    const finish = () => {
      if (parts.length)
        pathParts.push({ path: parts.join(" "), noFill, noLine });
      parts = [];
      noFill = false;
      noLine = false;
      current = void 0;
      start = void 0;
    };
    const next = () => {
      const p = points[index++];
      if (!p) {
        valid = false;
        return [0, 0];
      }
      return p;
    };
    const format = (p) => `${Math.round(p[0] * 1e6) / 1e6} ${Math.round(p[1] * 1e6) / 1e6}`;
    const point = () => {
      current = next();
      include(current);
      return format(current);
    };
    const begin = (p, connect = false) => {
      if (connect && current)
        parts.push(`L${format(p)}`);
      else {
        parts.push(`M${format(p)}`);
        start = p;
      }
      current = p;
      include(p);
    };
    const cubic = () => {
      const a = next(), b = next(), end = next(), origin = current;
      if (!origin) {
        valid = false;
        return;
      }
      include(end);
      if (recover)
        for (let axis = 0; axis < 2; axis++) {
          const p0 = origin[axis], p1 = a[axis], p2 = b[axis], p3 = end[axis], aa = -p0 + 3 * p1 - 3 * p2 + p3, bb = 2 * (p0 - 2 * p1 + p2), cc = p1 - p0;
          const discriminant = bb * bb - 4 * aa * cc;
          const roots = Math.abs(aa) < 1e-12 ? Math.abs(bb) > 1e-12 ? [-cc / bb] : [] : discriminant >= 0 ? [(-bb - Math.sqrt(discriminant)) / (2 * aa), (-bb + Math.sqrt(discriminant)) / (2 * aa)] : [];
          for (const t of roots)
            if (t > 0 && t < 1) {
              const s = 1 - t;
              include([s * s * s * origin[0] + 3 * s * s * t * a[0] + 3 * s * t * t * b[0] + t * t * t * end[0], s * s * s * origin[1] + 3 * s * s * t * a[1] + 3 * s * t * t * b[1] + t * t * t * end[1]]);
            }
        }
      parts.push(`C${format(a)} ${format(b)} ${format(end)}`);
      current = end;
    };
    const arc = (escape, count) => {
      if (escape >= 3 && escape <= 6) {
        if (count % 4) {
          valid = false;
          return;
        }
        for (let j = 0; j < count / 4; j++) {
          const p0 = next(), p1 = next(), a = next(), b = next(), cx = (p0[0] + p1[0]) / 2, cy = (p0[1] + p1[1]) / 2, rx = Math.abs(p1[0] - p0[0]) / 2, ry = Math.abs(p1[1] - p0[1]) / 2;
          if (!rx || !ry) {
            valid = false;
            return;
          }
          const t0 = Math.atan2((a[1] - cy) / ry, (a[0] - cx) / rx), t1 = Math.atan2((b[1] - cy) / ry, (b[0] - cx) / rx);
          const start2 = [cx + rx * Math.cos(t0), cy + ry * Math.sin(t0)], end = [cx + rx * Math.cos(t1), cy + ry * Math.sin(t1)];
          const clockwise = escape >= 5, sweep = clockwise ? 1 : 0, tau = Math.PI * 2, delta = ((clockwise ? t1 - t0 : t0 - t1) % tau + tau) % tau;
          begin(start2, escape === 3 || escape === 5);
          include(end);
          if (recover)
            for (let k = 0; k < 4; k++) {
              const angle = k * Math.PI / 2, distance = ((clockwise ? angle - t0 : t0 - angle) % tau + tau) % tau;
              if (delta < 1e-9 || distance <= delta + 1e-9)
                include([cx + rx * Math.cos(angle), cy + ry * Math.sin(angle)]);
            }
          if (delta < 1e-9) {
            const middle = [2 * cx - start2[0], 2 * cy - start2[1]];
            parts.push(`A${rx} ${ry} 0 0 ${sweep} ${format(middle)}`);
            parts.push(`A${rx} ${ry} 0 0 ${sweep} ${format(end)}`);
          } else
            parts.push(`A${rx} ${ry} 0 ${delta > Math.PI ? 1 : 0} ${sweep} ${format(end)}`);
          current = end;
        }
      } else if (escape === 7 || escape === 8) {
        for (let j = 0; j < count; j++) {
          if (!current) {
            valid = false;
            return;
          }
          const end = next(), dx = end[0] - current[0], dy = end[1] - current[1];
          const sweep = escape === 7 ? dx * dy > 0 ? 1 : 0 : dx * dy < 0 ? 1 : 0;
          if (dx === 0 || dy === 0)
            parts.push(`L${format(end)}`);
          else
            parts.push(`A${Math.abs(dx)} ${Math.abs(dy)} 0 0 ${sweep} ${format(end)}`);
          current = end;
          include(end);
        }
      } else if (escape === 9) {
        if (count < 2 || index + count > points.length) {
          valid = false;
          return;
        }
        const vertices = points.slice(index, index + count);
        index += count;
        const end = vertices[count - 1], closed = !current;
        if (closed)
          begin(end);
        for (let j = 0; j < count - 1; j++) {
          const control = vertices[j], following = vertices[j + 1];
          const endpoint = j === count - 2 ? end : [(control[0] + following[0]) / 2, (control[1] + following[1]) / 2];
          include(endpoint);
          if (recover && current)
            for (let axis = 0; axis < 2; axis++) {
              const divisor = current[axis] - 2 * control[axis] + endpoint[axis], t = divisor ? (current[axis] - control[axis]) / divisor : 0;
              if (t > 0 && t < 1) {
                const s = 1 - t;
                include([s * s * current[0] + 2 * s * t * control[0] + t * t * endpoint[0], s * s * current[1] + 2 * s * t * control[1] + t * t * endpoint[1]]);
              }
            }
          parts.push(`Q${format(control)} ${format(endpoint)}`);
          current = endpoint;
        }
        if (closed) {
          parts.push("Z");
          current = start;
        }
      } else
        valid = false;
    };
    if (!segments) {
      begin(next());
      const pathType = values.get(324) ?? 1;
      if (pathType === 2 || pathType === 3) {
        if ((points.length - index) % 3)
          valid = false;
        else
          while (index + 2 < points.length)
            cubic();
      } else if (pathType === 0 || pathType === 1)
        while (index < points.length)
          parts.push(`L${point()}`);
      else {
        diagnostics.push({ code: "GEOMETRY_SEGMENTS", severity: "warning", message: "A complex shapePath requires its segment array; geometry is not inferred from vertices alone", shapeId, offset });
        valid = false;
      }
      if (pathType === 1 || pathType === 3)
        parts.push("Z");
    } else if (segments.size === 2) {
      for (let i = 0; i < segments.count && valid; i++) {
        const segment = segments.view.getUint16(6 + i * 2, true), op = segment >>> 13, count = segment & 8191;
        if (op === 0)
          for (let n = 0; n < count; n++)
            parts.push(`L${point()}`);
        else if (op === 1)
          for (let n = 0; n < count && valid; n++)
            cubic();
        else if (op === 2)
          begin(next());
        else if (op === 3) {
          parts.push("Z");
          current = start;
        } else if (op === 4)
          finish();
        else if (op === 5 && (segment >>> 8 & 31) === 10)
          noFill = true;
        else if (op === 5 && (segment >>> 8 & 31) === 11)
          noLine = true;
        else if (op === 5 && (segment >>> 8 & 31) >= 3 && (segment >>> 8 & 31) <= 9)
          arc(segment >>> 8 & 31, segment & 255);
        else if (op === 5 && (segment >>> 8 & 31) >= 12 && (segment >>> 8 & 31) <= 20) {
        } else {
          diagnostics.push({ code: "GEOMETRY_SEGMENT", severity: "warning", message: `Custom path opcode ${op}/${segment >>> 8 & 31} requires an unsupported geometry escape`, shapeId, offset });
          valid = false;
        }
      }
    } else
      valid = false;
    if (!valid) {
      diagnostics.push({ code: "GEOMETRY_INCOMPLETE", severity: "warning", message: "Custom path could not be rendered completely; shape geometry fallback will be used", shapeId, offset });
      return {};
    }
    if (recover) {
      if (recoverX && Number.isFinite(minX) && maxX > minX) {
        pathBounds.x = minX;
        pathBounds.width = maxX - minX;
      }
      if (recoverY && Number.isFinite(minY) && maxY > minY) {
        pathBounds.y = minY;
        pathBounds.height = maxY - minY;
      }
      diagnostics.push({ code: "GEOMETRY_BOUNDS_RECOVERED", severity: "warning", message: "Zero-size geometry axes use the saved path extent; the original coordinate-system mapping is not specified", shapeId, offset, details: { x: recoverX, y: recoverY } });
    }
    finish();
    return { path: pathParts.map((p) => p.path).join(" "), pathParts, pathBounds, noFill: pathParts.every((p) => p.noFill), noLine: pathParts.every((p) => p.noLine) };
  }
  exports_9("customGeometry", customGeometry);
  function adjustedPresetGeometry(preset, values, bounds) {
    if (!Array.from({ length: 8 }, (_, i) => values.has(327 + i)).some(Boolean))
      return void 0;
    const size = 21600, half = 10800, clamp = (v, min = 0, max = size) => Math.max(min, Math.min(max, v));
    const a = (i, fallback, min = 0, max = size) => clamp((values.get(327 + i) ?? fallback) | 0, min, max);
    const pathBounds = { x: 0, y: 0, width: size, height: size };
    const result = (path, approximate = true) => ({ path, pathBounds, approximate });
    const polygon = (points, approximate = true) => result("M" + points.map((p) => p.join(" ")).join(" L") + " Z", approximate);
    if (preset === 2) {
      const amount = a(0, 2592, 0, half), min = Math.max(0, Math.min(bounds.width, bounds.height)), rx = bounds.width ? amount * min / bounds.width : amount, ry = bounds.height ? amount * min / bounds.height : amount;
      return result(`M${rx} 0 H${size - rx} A${rx} ${ry} 0 0 1 ${size} ${ry} V${size - ry} A${rx} ${ry} 0 0 1 ${size - rx} ${size} H${rx} A${rx} ${ry} 0 0 1 0 ${size - ry} V${ry} A${rx} ${ry} 0 0 1 ${rx} 0 Z`, false);
    }
    if (preset === 5)
      return polygon([[a(0, half), 0], [size, size], [0, size]]);
    if (preset === 7) {
      const x = a(0, 5400, 0, half);
      return polygon([[x, 0], [size, 0], [size - x, size], [0, size]]);
    }
    if (preset === 8) {
      const x = a(0, 5400, 0, half);
      return polygon([[x, 0], [size - x, 0], [size, size], [0, size]]);
    }
    if (preset === 9) {
      const x = a(0, 5400, 0, half);
      return polygon([[x, 0], [size - x, 0], [size, half], [size - x, size], [x, size], [0, half]]);
    }
    if (preset === 10) {
      const x = a(0, 6326, 0, half);
      return polygon([[x, 0], [size - x, 0], [size, x], [size, size - x], [size - x, size], [x, size], [0, size - x], [0, x]]);
    }
    if (preset === 11) {
      const x = a(0, 5400, 0, half), r = size - x;
      return polygon([[x, 0], [r, 0], [r, x], [size, x], [size, r], [r, r], [r, size], [x, size], [x, r], [0, r], [0, x], [x, x]]);
    }
    if (preset === 13) {
      const neck = a(0, 16200), shaft = a(1, 5400, 0, half);
      return polygon([[neck, 0], [neck, shaft], [0, shaft], [0, size - shaft], [neck, size - shaft], [neck, size], [size, half]], false);
    }
    if (preset === 15) {
      const neck = a(0, 16200);
      return polygon([[0, 0], [neck, 0], [size, half], [neck, size], [0, size]]);
    }
    if (preset === 66) {
      const neck = a(0, 5400), shaft = a(1, 5400, 0, half);
      return polygon([[neck, 0], [neck, shaft], [size, shaft], [size, size - shaft], [neck, size - shaft], [neck, size], [0, half]]);
    }
    if (preset === 67) {
      const neck = a(0, 16200), shaft = a(1, 5400, 0, half);
      return polygon([[shaft, 0], [size - shaft, 0], [size - shaft, neck], [size, neck], [half, size], [0, neck], [shaft, neck]]);
    }
    if (preset === 68) {
      const neck = a(0, 5400), shaft = a(1, 5400, 0, half);
      return polygon([[shaft, size], [size - shaft, size], [size - shaft, neck], [size, neck], [half, 0], [0, neck], [shaft, neck]]);
    }
    if (preset === 69) {
      const neck = a(0, 5400, 0, half), shaft = a(1, 5400, 0, half);
      return polygon([[0, half], [neck, 0], [neck, shaft], [size - neck, shaft], [size - neck, 0], [size, half], [size - neck, size], [size - neck, size - shaft], [neck, size - shaft], [neck, size]]);
    }
    if (preset === 70) {
      const shaft = a(0, 5400, 0, half), neck = a(1, 5400, 0, half);
      return polygon([[half, 0], [size, neck], [size - shaft, neck], [size - shaft, size - neck], [size, size - neck], [half, size], [0, size - neck], [shaft, size - neck], [shaft, neck], [0, neck]]);
    }
    if (preset === 55) {
      const x = a(0, 5400, 0, half);
      return polygon([[0, 0], [size - x, 0], [size, half], [size - x, size], [0, size], [x, half]]);
    }
    if (preset === 23) {
      const inset = a(0, 5400, 0, half), r = half - inset;
      if (!r)
        return result(`M${half} 0 A${half} ${half} 0 1 1 ${half} ${size} A${half} ${half} 0 1 1 ${half} 0 Z`);
      return result(`M${half} 0 A${half} ${half} 0 1 1 ${half} ${size} A${half} ${half} 0 1 1 ${half} 0 Z M${half} ${inset} A${r} ${r} 0 1 0 ${half} ${size - inset} A${r} ${r} 0 1 0 ${half} ${inset} Z`);
    }
    if (preset >= 34 && preset <= 36) {
      const x = a(0, half, -size, size * 2), y = a(1, half, -size, size * 2), z = a(2, half, -size, size * 2);
      return result(preset === 34 ? `M0 0 H${x} V${size} H${size}` : preset === 35 ? `M0 0 H${x} V${y} H${size} V${size}` : `M0 0 H${x} V${y} H${z} V${size} H${size}`);
    }
    if (preset === 37 || preset === 38) {
      const x = a(0, half, -size, size * 2);
      return result(`M0 0 C${x} 0 ${x} ${size} ${size} ${size}`);
    }
    return void 0;
  }
  exports_9("adjustedPresetGeometry", adjustedPresetGeometry);
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("core/inflate", [], function(exports_10, context_10) {
  "use strict";
  var InflateError, BitReader, ByteSink, LENGTH_BASE, LENGTH_EXTRA, DISTANCE_BASE, DISTANCE_EXTRA, fixedLiteralLengthTable, fixedDistanceTable, CODE_LENGTH_ORDER;
  var __moduleName = context_10 && context_10.id;
  function buildHuffmanTable(lengths) {
    const maxBits = Math.max(0, ...lengths);
    if (maxBits === 0)
      throw new InflateError("Empty Huffman table");
    const blCount = new Array(maxBits + 1).fill(0);
    for (const length of lengths) {
      if (length < 0 || length > maxBits)
        throw new InflateError("Invalid code length");
      if (length)
        blCount[length] = (blCount[length] ?? 0) + 1;
    }
    const nextCode = new Array(maxBits + 1).fill(0);
    let code = 0;
    for (let bits = 1; bits <= maxBits; bits += 1) {
      code = code + (blCount[bits - 1] ?? 0) << 1;
      nextCode[bits] = code;
    }
    const maps = Array.from({ length: maxBits + 1 }, () => /* @__PURE__ */ new Map());
    for (let symbol = 0; symbol < lengths.length; symbol += 1) {
      const length = lengths[symbol] ?? 0;
      if (!length)
        continue;
      const canonical = nextCode[length] ?? 0;
      nextCode[length] = canonical + 1;
      maps[length].set(canonical, symbol);
    }
    return { maps, maxBits };
  }
  function decodeSymbol(reader, table) {
    let code = 0;
    for (let length = 1; length <= table.maxBits; length += 1) {
      code = code << 1 | reader.readBit();
      const hit = table.maps[length]?.get(code);
      if (hit != null)
        return hit;
    }
    throw new InflateError("Invalid Huffman code");
  }
  function getFixedTables() {
    if (!fixedLiteralLengthTable) {
      const lengths = new Array(288).fill(0);
      for (let i = 0; i <= 143; i += 1)
        lengths[i] = 8;
      for (let i = 144; i <= 255; i += 1)
        lengths[i] = 9;
      for (let i = 256; i <= 279; i += 1)
        lengths[i] = 7;
      for (let i = 280; i <= 287; i += 1)
        lengths[i] = 8;
      fixedLiteralLengthTable = buildHuffmanTable(lengths);
      fixedDistanceTable = buildHuffmanTable(new Array(32).fill(5));
    }
    return { literalLength: fixedLiteralLengthTable, distance: fixedDistanceTable };
  }
  function readDynamicTables(reader) {
    const hlit = reader.readBits(5) + 257;
    const hdist = reader.readBits(5) + 1;
    const hclen = reader.readBits(4) + 4;
    const codeLengthLengths = new Array(19).fill(0);
    for (let i = 0; i < hclen; i += 1) {
      codeLengthLengths[CODE_LENGTH_ORDER[i]] = reader.readBits(3);
    }
    const codeLengthTable = buildHuffmanTable(codeLengthLengths);
    const lengths = [];
    while (lengths.length < hlit + hdist) {
      const symbol = decodeSymbol(reader, codeLengthTable);
      if (symbol <= 15) {
        lengths.push(symbol);
      } else if (symbol === 16) {
        if (!lengths.length)
          throw new InflateError("Repeat code length without previous value");
        const repeat = reader.readBits(2) + 3;
        const previous = lengths[lengths.length - 1] ?? 0;
        for (let i = 0; i < repeat; i += 1)
          lengths.push(previous);
      } else if (symbol === 17) {
        const repeat = reader.readBits(3) + 3;
        for (let i = 0; i < repeat; i += 1)
          lengths.push(0);
      } else if (symbol === 18) {
        const repeat = reader.readBits(7) + 11;
        for (let i = 0; i < repeat; i += 1)
          lengths.push(0);
      } else {
        throw new InflateError("Invalid code length symbol");
      }
    }
    const literalLengths = lengths.slice(0, hlit);
    const distanceLengths = lengths.slice(hlit, hlit + hdist);
    if (!literalLengths[256])
      throw new InflateError("Missing end-of-block code");
    if (!distanceLengths.some(Boolean))
      distanceLengths[0] = 1;
    return {
      literalLength: buildHuffmanTable(literalLengths),
      distance: buildHuffmanTable(distanceLengths)
    };
  }
  function inflateHuffmanBlock(reader, sink, literalLength, distance) {
    for (; ; ) {
      const symbol = decodeSymbol(reader, literalLength);
      if (symbol < 256) {
        sink.push(symbol);
        continue;
      }
      if (symbol === 256)
        return;
      if (symbol < 257 || symbol > 285)
        throw new InflateError("Invalid length symbol");
      const lengthIndex = symbol - 257;
      let length = LENGTH_BASE[lengthIndex] ?? 0;
      const lengthExtra = LENGTH_EXTRA[lengthIndex] ?? 0;
      if (lengthExtra)
        length += reader.readBits(lengthExtra);
      const distSymbol = decodeSymbol(reader, distance);
      if (distSymbol < 0 || distSymbol >= DISTANCE_BASE.length)
        throw new InflateError("Invalid distance symbol");
      let dist = DISTANCE_BASE[distSymbol] ?? 0;
      const distExtra = DISTANCE_EXTRA[distSymbol] ?? 0;
      if (distExtra)
        dist += reader.readBits(distExtra);
      sink.copyFromBack(dist, length);
    }
  }
  function inflateDeflate(deflateBytes, expectedLength, maxLength = 128 * 1024 * 1024) {
    const reader = new BitReader(deflateBytes);
    const sink = new ByteSink(Math.min(expectedLength && expectedLength > 0 ? expectedLength : 32768, 32768), expectedLength == null ? maxLength : Math.min(expectedLength, maxLength));
    let final = false;
    while (!final) {
      final = reader.readBit() === 1;
      const type = reader.readBits(2);
      if (type === 0) {
        reader.alignToByte();
        const len = reader.readByte() | reader.readByte() << 8;
        const nlen = reader.readByte() | reader.readByte() << 8;
        if (((len ^ 65535) & 65535) !== nlen)
          throw new InflateError("Invalid stored block length");
        const chunk = new Uint8Array(len);
        for (let i = 0; i < len; i += 1)
          chunk[i] = reader.readByte();
        sink.pushBytes(chunk);
      } else if (type === 1) {
        const fixed = getFixedTables();
        inflateHuffmanBlock(reader, sink, fixed.literalLength, fixed.distance);
      } else if (type === 2) {
        const dynamic = readDynamicTables(reader);
        inflateHuffmanBlock(reader, sink, dynamic.literalLength, dynamic.distance);
      } else {
        throw new InflateError("Reserved deflate block type");
      }
    }
    return sink.toUint8Array(expectedLength);
  }
  function adler32(bytes) {
    let a = 1;
    let b = 0;
    for (const byte of bytes) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    return (b << 16 | a) >>> 0;
  }
  function inflateRaw(bytes, expectedLength, maxLength = 128 * 1024 * 1024) {
    if (!Number.isSafeInteger(expectedLength) || expectedLength < 0 || !Number.isSafeInteger(maxLength) || maxLength < 0 || expectedLength > maxLength)
      return null;
    try {
      const inflated = inflateDeflate(bytes, expectedLength, maxLength);
      return inflated.length === expectedLength ? inflated : null;
    } catch {
      return null;
    }
  }
  exports_10("inflateRaw", inflateRaw);
  function inflateZlib(bytes, expectedLength, maxLength = 128 * 1024 * 1024) {
    if (bytes.length < 6)
      return null;
    const cmf = bytes[0] ?? 0;
    const flg = bytes[1] ?? 0;
    if ((cmf & 15) !== 8)
      return null;
    if (cmf >>> 4 > 7)
      return null;
    if (((cmf << 8) + flg) % 31 !== 0)
      return null;
    if (flg & 32)
      return null;
    try {
      const deflateBytes = bytes.subarray(2, Math.max(2, bytes.length - 4));
      if (!Number.isSafeInteger(maxLength) || maxLength <= 0 || expectedLength != null && (!Number.isSafeInteger(expectedLength) || expectedLength < 0 || expectedLength > maxLength))
        return null;
      const inflated = inflateDeflate(deflateBytes, expectedLength, maxLength);
      if (expectedLength != null && inflated.length !== expectedLength)
        return null;
      const expectedAdler = (bytes[bytes.length - 4] ?? 0) << 24 | (bytes[bytes.length - 3] ?? 0) << 16 | (bytes[bytes.length - 2] ?? 0) << 8 | (bytes[bytes.length - 1] ?? 0);
      if (expectedAdler >>> 0) {
        const actual = adler32(inflated);
        if (actual !== expectedAdler >>> 0)
          return null;
      }
      return inflated;
    } catch {
      return null;
    }
  }
  exports_10("inflateZlib", inflateZlib);
  return {
    setters: [],
    execute: function() {
      InflateError = class InflateError extends Error {
        name = "InflateError";
      };
      BitReader = class BitReader {
        bytes;
        byteOffset = 0;
        bitBuffer = 0;
        bitCount = 0;
        constructor(bytes) {
          this.bytes = bytes;
        }
        readBits(count) {
          if (count < 0 || count > 24)
            throw new InflateError("Invalid bit count");
          while (this.bitCount < count) {
            if (this.byteOffset >= this.bytes.length)
              throw new InflateError("Unexpected end of deflate stream");
            this.bitBuffer |= (this.bytes[this.byteOffset++] ?? 0) << this.bitCount;
            this.bitCount += 8;
          }
          const mask = count === 0 ? 0 : (1 << count) - 1;
          const value = this.bitBuffer & mask;
          this.bitBuffer >>>= count;
          this.bitCount -= count;
          return value;
        }
        readBit() {
          return this.readBits(1);
        }
        alignToByte() {
          this.bitBuffer = 0;
          this.bitCount = 0;
        }
        readByte() {
          return this.readBits(8);
        }
      };
      ByteSink = class ByteSink {
        buffer;
        maxLength;
        length = 0;
        constructor(initialCapacity = 32768, maxLength = 128 * 1024 * 1024) {
          this.maxLength = maxLength;
          this.buffer = new Uint8Array(Math.min(Math.max(1, initialCapacity), maxLength));
        }
        reserve(extra) {
          const required = this.length + extra;
          if (required > this.maxLength)
            throw new InflateError("Inflated data exceeds declared size or configured limit");
          if (required <= this.buffer.length)
            return;
          let next = this.buffer.length;
          while (next < required)
            next *= 2;
          const grown = new Uint8Array(Math.min(next, this.maxLength));
          grown.set(this.buffer.subarray(0, this.length));
          this.buffer = grown;
        }
        push(value) {
          this.reserve(1);
          this.buffer[this.length++] = value & 255;
        }
        pushBytes(bytes) {
          this.reserve(bytes.length);
          this.buffer.set(bytes, this.length);
          this.length += bytes.length;
        }
        copyFromBack(distance, length) {
          if (distance <= 0 || distance > this.length)
            throw new InflateError("Invalid back-reference distance");
          this.reserve(length);
          for (let i = 0; i < length; i += 1) {
            this.buffer[this.length] = this.buffer[this.length - distance] ?? 0;
            this.length += 1;
          }
        }
        toUint8Array(expectedLength) {
          const out = this.buffer.slice(0, this.length);
          if (expectedLength != null && expectedLength >= 0 && out.length !== expectedLength) {
            return out;
          }
          return out;
        }
      };
      LENGTH_BASE = [
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        13,
        15,
        17,
        19,
        23,
        27,
        31,
        35,
        43,
        51,
        59,
        67,
        83,
        99,
        115,
        131,
        163,
        195,
        227,
        258
      ];
      LENGTH_EXTRA = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        2,
        2,
        2,
        2,
        3,
        3,
        3,
        3,
        4,
        4,
        4,
        4,
        5,
        5,
        5,
        5,
        0
      ];
      DISTANCE_BASE = [
        1,
        2,
        3,
        4,
        5,
        7,
        9,
        13,
        17,
        25,
        33,
        49,
        65,
        97,
        129,
        193,
        257,
        385,
        513,
        769,
        1025,
        1537,
        2049,
        3073,
        4097,
        6145,
        8193,
        12289,
        16385,
        24577
      ];
      DISTANCE_EXTRA = [
        0,
        0,
        0,
        0,
        1,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
        5,
        5,
        6,
        6,
        7,
        7,
        8,
        8,
        9,
        9,
        10,
        10,
        11,
        11,
        12,
        12,
        13,
        13
      ];
      fixedLiteralLengthTable = null;
      fixedDistanceTable = null;
      CODE_LENGTH_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
    }
  };
});
System.register("core/binary", ["core/utils"], function(exports_11, context_11) {
  "use strict";
  var utils_js_1, utf16leDecoder, latin1Decoder, BinaryReader;
  var __moduleName = context_11 && context_11.id;
  function toUint8Array(input) {
    if (input instanceof Uint8Array)
      return input;
    if (input instanceof ArrayBuffer)
      return new Uint8Array(input);
    if (ArrayBuffer.isView(input))
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    throw new TypeError("Unsupported binary input");
  }
  exports_11("toUint8Array", toUint8Array);
  return {
    setters: [
      function(utils_js_1_1) {
        utils_js_1 = utils_js_1_1;
      }
    ],
    execute: function() {
      utf16leDecoder = utils_js_1.textDecoder("utf-16le");
      latin1Decoder = typeof TextDecoder !== "undefined" ? utils_js_1.textDecoder("windows-1252") : utils_js_1.textDecoder("latin1");
      BinaryReader = class BinaryReader {
        bytes;
        view;
        length;
        constructor(input) {
          if (input instanceof Uint8Array) {
            this.bytes = input;
          } else if (input instanceof ArrayBuffer) {
            this.bytes = new Uint8Array(input);
          } else if (ArrayBuffer.isView(input)) {
            this.bytes = new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
          } else {
            throw new TypeError("BinaryReader expects ArrayBuffer or Uint8Array");
          }
          this.view = new DataView(this.bytes.buffer, this.bytes.byteOffset, this.bytes.byteLength);
          this.length = this.bytes.byteLength;
        }
        ensure(offset, size = 1) {
          return offset >= 0 && offset + size <= this.length;
        }
        u8(offset) {
          return this.ensure(offset, 1) ? this.view.getUint8(offset) : 0;
        }
        i8(offset) {
          return this.ensure(offset, 1) ? this.view.getInt8(offset) : 0;
        }
        u16(offset) {
          return this.ensure(offset, 2) ? this.view.getUint16(offset, true) : 0;
        }
        i16(offset) {
          return this.ensure(offset, 2) ? this.view.getInt16(offset, true) : 0;
        }
        u32(offset) {
          return this.ensure(offset, 4) ? this.view.getUint32(offset, true) : 0;
        }
        i32(offset) {
          return this.ensure(offset, 4) ? this.view.getInt32(offset, true) : 0;
        }
        u64(offset) {
          const lo = this.u32(offset);
          const hi = this.u32(offset + 4);
          return hi * 4294967296 + lo;
        }
        slice(offset, length) {
          if (!this.ensure(offset, length)) {
            return new Uint8Array(0);
          }
          return this.bytes.subarray(offset, offset + length);
        }
        array(offset, count, readFn) {
          const out = [];
          const width = readFn.byteWidth ?? 1;
          for (let i = 0; i < count; i += 1) {
            out.push(readFn.call(this, offset + i * width));
          }
          return out;
        }
        utf16le(offset, byteLength) {
          if (!this.ensure(offset, byteLength))
            return "";
          return utf16leDecoder.decode(this.slice(offset, byteLength));
        }
        latin1(offset, byteLength) {
          if (!this.ensure(offset, byteLength))
            return "";
          return latin1Decoder.decode(this.slice(offset, byteLength));
        }
        ascii(offset, byteLength) {
          if (!this.ensure(offset, byteLength))
            return "";
          let out = "";
          const view = this.slice(offset, byteLength);
          for (let i = 0; i < view.length; i += 1)
            out += String.fromCharCode(view[i] ?? 0);
          return out;
        }
        utf16z(offset, byteLength) {
          const raw = this.slice(offset, byteLength);
          let end = raw.length;
          for (let i = 0; i + 1 < raw.length; i += 2) {
            if (raw[i] === 0 && raw[i + 1] === 0) {
              end = i;
              break;
            }
          }
          return utf16leDecoder.decode(raw.subarray(0, end));
        }
      };
      exports_11("BinaryReader", BinaryReader);
      BinaryReader.prototype.u8.byteWidth = 1;
      BinaryReader.prototype.i8.byteWidth = 1;
      BinaryReader.prototype.u16.byteWidth = 2;
      BinaryReader.prototype.i16.byteWidth = 2;
      BinaryReader.prototype.u32.byteWidth = 4;
      BinaryReader.prototype.i32.byteWidth = 4;
    }
  };
});
System.register("core/xml-text", ["core/utils"], function(exports_12, context_12) {
  "use strict";
  var utils_js_2;
  var __moduleName = context_12 && context_12.id;
  function escapeXmlText(value) {
    const legalText = value.replace(/[^\u0009\u000a\u000d\u0020-\ud7ff\ue000-\ufffd\u{10000}-\u{10ffff}]/gu, "\uFFFD");
    return utils_js_2.escapeHtml(legalText);
  }
  exports_12("escapeXmlText", escapeXmlText);
  return {
    setters: [
      function(utils_js_2_1) {
        utils_js_2 = utils_js_2_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("core/vector-font", [], function(exports_13, context_13) {
  "use strict";
  var __moduleName = context_13 && context_13.id;
  function readEmfFont(record) {
    if (!record.ensure(12, 92))
      return null;
    const family = new TextDecoder("utf-16le").decode(record.slice(40, 64)).split("\0")[0] || "sans-serif";
    return {
      family,
      size: Math.abs(record.i32(12)) || 12,
      escapement: record.i32(20),
      weight: record.i32(28),
      italic: Boolean(record.u8(32)),
      underline: Boolean(record.u8(33)),
      strike: Boolean(record.u8(34))
    };
  }
  exports_13("readEmfFont", readEmfFont);
  function readWmfFont(record) {
    if (!record.ensure(6, 18))
      return null;
    const family = new TextDecoder("windows-1252").decode(record.slice(24, Math.min(32, record.length - 24))).split("\0")[0] || "sans-serif";
    return {
      family,
      size: Math.abs(record.i16(6)) || 12,
      escapement: record.i16(10),
      weight: record.i16(14),
      italic: Boolean(record.u8(16)),
      underline: Boolean(record.u8(17)),
      strike: Boolean(record.u8(18))
    };
  }
  exports_13("readWmfFont", readWmfFont);
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("core/raster", ["core/errors"], function(exports_14, context_14) {
  "use strict";
  var errors_js_4, crcTable;
  var __moduleName = context_14 && context_14.id;
  function decodeBgraBitmap(width, signedHeight, bits, perPixelAlpha, maxBytes = 128 * 1024 * 1024) {
    const height = Math.abs(signedHeight), length = width * height * 4;
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(signedHeight) || width <= 0 || height <= 0 || !Number.isSafeInteger(length) || length > maxBytes)
      throw new errors_js_4.PptError("LIMIT_ASSETS", "BGRA bitmap exceeds the decoded byte budget");
    if (bits.length < length)
      throw new errors_js_4.PptError("METAFILE_BITMAP", "Truncated BGRA scan lines");
    const rgba = new Uint8Array(length);
    for (let y = 0; y < height; y++)
      for (let x = 0; x < width; x++) {
        const p = ((signedHeight > 0 ? height - 1 - y : y) * width + x) * 4, q = (y * width + x) * 4, a = perPixelAlpha ? bits[p + 3] : 255;
        for (let c = 0; c < 3; c++) {
          const value = bits[p + 2 - c];
          rgba[q + c] = perPixelAlpha ? a ? Math.min(255, Math.round(value * 255 / a)) : 0 : value;
        }
        rgba[q + 3] = a;
      }
    return rgba;
  }
  exports_14("decodeBgraBitmap", decodeBgraBitmap);
  function unpackBits(input, expected, unit = 1) {
    if (!Number.isSafeInteger(expected) || expected < 0 || expected > 256 * 1024 * 1024 || unit !== 1 && unit !== 2)
      throw new errors_js_4.PptError("RASTER_SIZE", "Invalid PackBits output size");
    const out = new Uint8Array(expected);
    let p = 0, q = 0;
    while (p < input.length) {
      const control = input[p++];
      if (control === 128)
        continue;
      const count = (control < 128 ? control + 1 : 257 - control) * unit;
      if (q + count > expected)
        throw new errors_js_4.PptError("PACKBITS_LENGTH", "PackBits expands beyond the declared row/strip");
      if (control < 128) {
        if (p + count > input.length)
          throw new errors_js_4.PptError("PACKBITS_TRUNCATED", "Truncated PackBits literal");
        out.set(input.subarray(p, p + count), q);
        p += count;
      } else {
        if (p + unit > input.length)
          throw new errors_js_4.PptError("PACKBITS_TRUNCATED", "Truncated PackBits repeat");
        for (let i = 0; i < count; i++)
          out[q + i] = input[p + i % unit];
        p += unit;
      }
      q += count;
    }
    if (q !== expected)
      throw new errors_js_4.PptError("PACKBITS_LENGTH", "PackBits does not fill the declared row/strip");
    return out;
  }
  exports_14("unpackBits", unpackBits);
  function crc(bytes) {
    let c = 4294967295;
    for (const b of bytes)
      c = crcTable[(c ^ b) & 255] ^ c >>> 8;
    return (c ^ 4294967295) >>> 0;
  }
  function encodeRgbaPng(width, height, rgba, maxBytes = 128 * 1024 * 1024) {
    const row = width * 4, rawLength = (row + 1) * height;
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 || rgba.length !== row * height || rawLength > maxBytes)
      throw new errors_js_4.PptError("LIMIT_ASSETS", "Raster dimensions exceed the configured byte budget");
    const blocks = Math.ceil(rawLength / 65535), zlen = 2 + rawLength + blocks * 5 + 4, total = 57 + zlen;
    if (total > maxBytes)
      throw new errors_js_4.PptError("LIMIT_ASSETS", "PNG output exceeds the configured byte budget");
    const raw = new Uint8Array(rawLength);
    for (let y = 0; y < height; y++)
      raw.set(rgba.subarray(y * row, (y + 1) * row), y * (row + 1) + 1);
    const out = new Uint8Array(total), view = new DataView(out.buffer);
    out.set([137, 80, 78, 71, 13, 10, 26, 10]);
    let at = 8;
    const chunk = (type, data) => {
      view.setUint32(at, data.length);
      for (let i = 0; i < 4; i++)
        out[at + 4 + i] = type.charCodeAt(i);
      out.set(data, at + 8);
      view.setUint32(at + 8 + data.length, crc(out.subarray(at + 4, at + 8 + data.length)));
      at += data.length + 12;
    };
    const header = new Uint8Array(13), hv = new DataView(header.buffer);
    hv.setUint32(0, width);
    hv.setUint32(4, height);
    header[8] = 8;
    header[9] = 6;
    chunk("IHDR", header);
    const z = new Uint8Array(zlen), zv = new DataView(z.buffer);
    z[0] = 120;
    z[1] = 1;
    let p = 2, a = 1, b = 0;
    for (let from = 0; from < raw.length; from += 65535) {
      const size = Math.min(65535, raw.length - from);
      z[p++] = from + size === raw.length ? 1 : 0;
      zv.setUint16(p, size, true);
      zv.setUint16(p + 2, ~size & 65535, true);
      p += 4;
      z.set(raw.subarray(from, from + size), p);
      p += size;
    }
    for (let i = 0; i < raw.length; i++) {
      a = (a + raw[i]) % 65521;
      b = (b + a) % 65521;
    }
    zv.setUint32(p, (b << 16 | a) >>> 0);
    chunk("IDAT", z);
    chunk("IEND", new Uint8Array());
    return out;
  }
  exports_14("encodeRgbaPng", encodeRgbaPng);
  return {
    setters: [
      function(errors_js_4_1) {
        errors_js_4 = errors_js_4_1;
      }
    ],
    execute: function() {
      crcTable = Uint32Array.from({ length: 256 }, (_, i) => {
        let c = i;
        for (let b = 0; b < 8; b++)
          c = c & 1 ? c >>> 1 ^ 3988292384 : c >>> 1;
        return c >>> 0;
      });
    }
  };
});
System.register("core/vector", ["core/binary", "core/utils", "core/xml-text", "core/vector-font", "core/errors", "core/raster"], function(exports_15, context_15) {
  "use strict";
  var binary_js_1, utils_js_3, xml_text_js_1, vector_font_js_1, errors_js_5, raster_js_1, DEFAULT_VECTOR_LIMITS, DEFAULT_PEN, DEFAULT_BRUSH, DEFAULT_FONT, IDENTITY_MATRIX, PLACEABLE_WMF_KEY, WMF_HEADER_SIZE, WMF_RECORD, EMF_RECORD, WMF_MIN_BYTES, EMF_MIN_BYTES, STOCK_OBJECT_BASE, STOCK_OBJECT, MODIFY_WORLD_TRANSFORM;
  var __moduleName = context_15 && context_15.id;
  function numberCss(value) {
    if (!Number.isFinite(value))
      throw new errors_js_5.PptError("METAFILE_COORDINATE", "Metafile contains a non-finite transformed coordinate");
    const rounded = Math.round(value * 100) / 100;
    return Number.isInteger(rounded) ? String(rounded) : String(rounded);
  }
  function rectWidth(rect) {
    return Math.max(1, rect.right - rect.left || 0);
  }
  function rectHeight(rect) {
    return Math.max(1, rect.bottom - rect.top || 0);
  }
  function normalizeRect(rect) {
    return {
      left: Math.min(rect.left, rect.right),
      top: Math.min(rect.top, rect.bottom),
      right: Math.max(rect.left, rect.right),
      bottom: Math.max(rect.top, rect.bottom)
    };
  }
  function updateBounds(ctx, points) {
    for (const point of points) {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y))
        continue;
      if (!ctx.contentBounds) {
        ctx.contentBounds = { left: point.x, top: point.y, right: point.x, bottom: point.y };
        continue;
      }
      ctx.contentBounds.left = Math.min(ctx.contentBounds.left, point.x);
      ctx.contentBounds.top = Math.min(ctx.contentBounds.top, point.y);
      ctx.contentBounds.right = Math.max(ctx.contentBounds.right, point.x);
      ctx.contentBounds.bottom = Math.max(ctx.contentBounds.bottom, point.y);
    }
  }
  function colorRefToCss(colorRef) {
    const red = colorRef & 255;
    const green = colorRef >>> 8 & 255;
    const blue = colorRef >>> 16 & 255;
    return `#${red.toString(16).padStart(2, "0")}${green.toString(16).padStart(2, "0")}${blue.toString(16).padStart(2, "0")}`;
  }
  function createBitmapFileHeader(pixelOffset, fileSize) {
    const header = new Uint8Array(14);
    const view = new DataView(header.buffer);
    header[0] = 66;
    header[1] = 77;
    view.setUint32(2, fileSize >>> 0, true);
    view.setUint32(10, pixelOffset >>> 0, true);
    return header;
  }
  function bitmapInfoToBmp(bmi, bits) {
    if (bmi.length < 12 || !bits.length)
      return null;
    const pixelOffset = 14 + bmi.length;
    const fileSize = pixelOffset + bits.length;
    const out = new Uint8Array(fileSize);
    out.set(createBitmapFileHeader(pixelOffset, fileSize), 0);
    out.set(bmi, 14);
    out.set(bits, pixelOffset);
    return out;
  }
  function penStyleFromCode(style, width, color) {
    const normalizedWidth = Math.max(1, Math.abs(width) || 1);
    const base = { color, width: normalizedWidth };
    switch (style & 15) {
      case 1:
        return { ...base, dasharray: `${normalizedWidth * 4} ${normalizedWidth * 2}` };
      case 2:
        return { ...base, dasharray: `${normalizedWidth} ${normalizedWidth * 2}` };
      case 3:
        return { ...base, dasharray: `${normalizedWidth * 4} ${normalizedWidth * 2} ${normalizedWidth} ${normalizedWidth * 2}` };
      case 4:
        return { ...base, dasharray: `${normalizedWidth * 4} ${normalizedWidth * 2} ${normalizedWidth} ${normalizedWidth * 2} ${normalizedWidth} ${normalizedWidth * 2}` };
      case 5:
        return { ...base, none: true };
      default:
        return base;
    }
  }
  function brushStyleFromCode(style, color, hatch = 0) {
    if (style === 1)
      return { color, none: true };
    if (style === 2 && hatch <= 5)
      return { color, hatch };
    return { color };
  }
  function cloneGraphicsState(state) {
    return {
      ...state,
      windowOrg: { ...state.windowOrg },
      windowExt: { ...state.windowExt },
      viewportOrg: { ...state.viewportOrg },
      viewportExt: { ...state.viewportExt },
      worldTransform: { ...state.worldTransform },
      currentPosition: { ...state.currentPosition },
      pen: { ...state.pen },
      brush: { ...state.brush },
      font: { ...state.font },
      clips: state.clips.map((c) => ({ ...c }))
    };
  }
  function readXForm(reader, offset) {
    const view = reader.view;
    return {
      m11: reader.ensure(offset, 4) ? view.getFloat32(offset, true) : 1,
      m12: reader.ensure(offset + 4, 4) ? view.getFloat32(offset + 4, true) : 0,
      m21: reader.ensure(offset + 8, 4) ? view.getFloat32(offset + 8, true) : 0,
      m22: reader.ensure(offset + 12, 4) ? view.getFloat32(offset + 12, true) : 1,
      dx: reader.ensure(offset + 16, 4) ? view.getFloat32(offset + 16, true) : 0,
      dy: reader.ensure(offset + 20, 4) ? view.getFloat32(offset + 20, true) : 0
    };
  }
  function multiplyMatrix(left, right) {
    return {
      m11: left.m11 * right.m11 + left.m12 * right.m21,
      m12: left.m11 * right.m12 + left.m12 * right.m22,
      m21: left.m21 * right.m11 + left.m22 * right.m21,
      m22: left.m21 * right.m12 + left.m22 * right.m22,
      dx: left.dx * right.m11 + left.dy * right.m21 + right.dx,
      dy: left.dx * right.m12 + left.dy * right.m22 + right.dy
    };
  }
  function transformPoint(matrix, point) {
    return {
      x: point.x * matrix.m11 + point.y * matrix.m21 + matrix.dx,
      y: point.x * matrix.m12 + point.y * matrix.m22 + matrix.dy
    };
  }
  function transformVector(matrix, vector) {
    return {
      x: vector.x * matrix.m11 + vector.y * matrix.m21,
      y: vector.x * matrix.m12 + vector.y * matrix.m22
    };
  }
  function defaultContext(width, height, viewBox, limits, objectCount) {
    if (objectCount > limits.maxObjects)
      throw new errors_js_5.PptError("METAFILE_OBJECT_LIMIT", "Metafile object table exceeds the configured handle limit");
    return {
      width,
      height,
      viewBox,
      recordCount: 0,
      unresolvedGlyphRuns: 0,
      contentBounds: null,
      nodes: [],
      defs: [],
      defSequence: 0,
      patternIds: /* @__PURE__ */ new Map(),
      stateStack: [],
      capturePath: false,
      pathData: [],
      pathPoints: [],
      objects: new Array(objectCount).fill(null),
      limits,
      outputBytes: 0,
      pathBytes: 0,
      pointCount: 0,
      freeObjectSlots: Array.from({ length: objectCount }, (_, index) => index),
      unsupportedRecordTypes: /* @__PURE__ */ new Set(),
      activeRecordType: 0,
      state: {
        windowOrg: { x: viewBox.left, y: viewBox.top },
        windowExt: { x: rectWidth(viewBox), y: rectHeight(viewBox) },
        viewportOrg: { x: viewBox.left, y: viewBox.top },
        viewportExt: { x: rectWidth(viewBox), y: rectHeight(viewBox) },
        worldTransform: { ...IDENTITY_MATRIX },
        currentPosition: { x: 0, y: 0 },
        pen: { ...DEFAULT_PEN },
        brush: { ...DEFAULT_BRUSH },
        font: { ...DEFAULT_FONT },
        textColor: "#000000",
        bkColor: "#ffffff",
        bkMode: 1,
        textAlign: 0,
        polygonFillMode: 1,
        arcDirection: 1,
        clips: []
      }
    };
  }
  function mapPoint(ctx, point) {
    const transformed = transformPoint(ctx.state.worldTransform, point);
    const windowExtX = ctx.state.windowExt.x || rectWidth(ctx.viewBox) || 1;
    const windowExtY = ctx.state.windowExt.y || rectHeight(ctx.viewBox) || 1;
    const viewportExtX = ctx.state.viewportExt.x || rectWidth(ctx.viewBox) || 1;
    const viewportExtY = ctx.state.viewportExt.y || rectHeight(ctx.viewBox) || 1;
    return {
      x: ctx.state.viewportOrg.x + (transformed.x - ctx.state.windowOrg.x) * viewportExtX / windowExtX,
      y: ctx.state.viewportOrg.y + (transformed.y - ctx.state.windowOrg.y) * viewportExtY / windowExtY
    };
  }
  function mapVector(ctx, vector) {
    const transformed = transformVector(ctx.state.worldTransform, vector);
    const windowExtX = ctx.state.windowExt.x || rectWidth(ctx.viewBox) || 1;
    const windowExtY = ctx.state.windowExt.y || rectHeight(ctx.viewBox) || 1;
    const viewportExtX = ctx.state.viewportExt.x || rectWidth(ctx.viewBox) || 1;
    const viewportExtY = ctx.state.viewportExt.y || rectHeight(ctx.viewBox) || 1;
    return {
      x: transformed.x * viewportExtX / windowExtX,
      y: transformed.y * viewportExtY / windowExtY
    };
  }
  function mapRect(ctx, rect) {
    const points = [
      mapPoint(ctx, { x: rect.left, y: rect.top }),
      mapPoint(ctx, { x: rect.right, y: rect.top }),
      mapPoint(ctx, { x: rect.right, y: rect.bottom }),
      mapPoint(ctx, { x: rect.left, y: rect.bottom })
    ];
    return normalizeRect({
      left: Math.min(...points.map((point) => point.x)),
      top: Math.min(...points.map((point) => point.y)),
      right: Math.max(...points.map((point) => point.x)),
      bottom: Math.max(...points.map((point) => point.y))
    });
  }
  function pointAttr(point) {
    return `${numberCss(point.x)},${numberCss(point.y)}`;
  }
  function effectivePenWidth(ctx, pen) {
    const width = Math.max(1, Math.abs(pen.width) || 1);
    const vx = mapVector(ctx, { x: width, y: 0 });
    const vy = mapVector(ctx, { x: 0, y: width });
    const sx = Math.hypot(vx.x, vx.y);
    const sy = Math.hypot(vy.x, vy.y);
    const scaled = (sx + sy) / 2;
    if (!Number.isFinite(scaled) || scaled <= 0)
      return width;
    return Math.max(0.5, scaled);
  }
  function scaledDashArray(ctx, pen) {
    if (!pen.dasharray)
      return void 0;
    const baseWidth = Math.max(1, Math.abs(pen.width) || 1);
    const scale = effectivePenWidth(ctx, pen) / baseWidth;
    return pen.dasharray.split(/\s+/).map((part) => Number(part)).filter((value) => Number.isFinite(value) && value > 0).map((value) => numberCss(value * scale)).join(" ") || void 0;
  }
  function strokeAttributes(ctx, pen) {
    if (pen.none)
      return 'stroke="none"';
    const attrs = [`stroke="${utils_js_3.escapeHtml(pen.color)}"`, `stroke-width="${numberCss(effectivePenWidth(ctx, pen))}"`, 'fill="none"'];
    const dasharray = scaledDashArray(ctx, pen);
    if (dasharray)
      attrs.push(`stroke-dasharray="${utils_js_3.escapeHtml(dasharray)}"`);
    return attrs.join(" ");
  }
  function fillAttributes(ctx) {
    const attrs = [ctx.state.pen.none ? 'stroke="none"' : `stroke="${utils_js_3.escapeHtml(ctx.state.pen.color)}"`, ctx.state.pen.none ? "" : `stroke-width="${numberCss(effectivePenWidth(ctx, ctx.state.pen))}"`].filter(Boolean);
    const dasharray = scaledDashArray(ctx, ctx.state.pen);
    if (dasharray && !ctx.state.pen.none)
      attrs.push(`stroke-dasharray="${utils_js_3.escapeHtml(dasharray)}"`);
    attrs.push(brushFill(ctx));
    attrs.push(`fill-rule="${ctx.state.polygonFillMode === 2 ? "nonzero" : "evenodd"}"`);
    return attrs.join(" ");
  }
  function fillOnlyAttributes(ctx) {
    const attrs = ['stroke="none"'];
    attrs.push(brushFill(ctx));
    attrs.push(`fill-rule="${ctx.state.polygonFillMode === 2 ? "nonzero" : "evenodd"}"`);
    return attrs.join(" ");
  }
  function addDefinition(ctx, markup) {
    const bytes = utf8Length(markup) + 1;
    if (bytes > ctx.limits.maxOutputBytes - ctx.outputBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Metafile definitions exceed the SVG output budget");
    ctx.outputBytes += bytes;
    ctx.defs.push(markup);
  }
  function brushFill(ctx) {
    const brush = ctx.state.brush;
    if (brush.none)
      return 'fill="none"';
    if (brush.hatch === void 0)
      return `fill="${utils_js_3.escapeHtml(brush.color)}"`;
    const key = `${brush.hatch}:${brush.color}:${ctx.state.bkMode}:${ctx.state.bkColor}`;
    let id = ctx.patternIds.get(key);
    if (!id) {
      id = `mf-pattern-${++ctx.defSequence}`;
      const paths = ["M0 4H8", "M4 0V8", "M-2 2L2 -2M0 8L8 0M6 10L10 6", "M-2 6L2 10M0 0L8 8M6 -2L10 2", "M0 4H8M4 0V8", "M-2 2L2 -2M0 8L8 0M6 10L10 6M-2 6L2 10M0 0L8 8M6 -2L10 2"];
      const background = ctx.state.bkMode === 2 ? `<rect width="8" height="8" fill="${ctx.state.bkColor}"/>` : "";
      addDefinition(ctx, `<pattern id="${id}" patternUnits="userSpaceOnUse" width="8" height="8">${background}<path d="${paths[brush.hatch]}" fill="none" stroke="${brush.color}" stroke-width="1"/></pattern>`);
      ctx.patternIds.set(key, id);
    }
    return `fill="url(#${id})"`;
  }
  function clipPath(ctx, path, mode) {
    if (![1, 4, 5].includes(mode))
      return false;
    if (mode === 5)
      ctx.state.clips = [];
    if (ctx.state.clips.length >= Math.min(256, ctx.limits.maxStateDepth))
      throw new errors_js_5.PptError("METAFILE_CLIP_LIMIT", "Metafile clipping stack exceeds its limit");
    const id = `mf-clip-${++ctx.defSequence}`, mask = mode === 4;
    if (mask) {
      const r = ctx.viewBox;
      addDefinition(ctx, `<mask id="${id}" maskUnits="userSpaceOnUse" x="${numberCss(r.left)}" y="${numberCss(r.top)}" width="${numberCss(rectWidth(r))}" height="${numberCss(rectHeight(r))}" style="mask-type:luminance"><rect x="${numberCss(r.left)}" y="${numberCss(r.top)}" width="${numberCss(rectWidth(r))}" height="${numberCss(rectHeight(r))}" fill="white"/><path d="${path}" fill="black" fill-rule="${ctx.state.polygonFillMode === 2 ? "nonzero" : "evenodd"}"/></mask>`);
    } else
      addDefinition(ctx, `<clipPath id="${id}" clipPathUnits="userSpaceOnUse"><path d="${path}" clip-rule="${ctx.state.polygonFillMode === 2 ? "nonzero" : "evenodd"}"/></clipPath>`);
    ctx.state.clips.push({ id, mask });
    return true;
  }
  function rectanglePath(ctx, rect) {
    const points = [{ x: rect.left, y: rect.top }, { x: rect.right, y: rect.top }, { x: rect.right, y: rect.bottom }, { x: rect.left, y: rect.bottom }].map((p) => mapPoint(ctx, p));
    return { path: `M${points.map(pointAttr).join("L")}Z`, points };
  }
  function saveState(ctx) {
    if (ctx.stateStack.length >= ctx.limits.maxStateDepth)
      throw new errors_js_5.PptError("METAFILE_STATE_LIMIT", "Metafile graphics-state stack exceeds its depth limit");
    ctx.stateStack.push(cloneGraphicsState(ctx.state));
  }
  function restoreState(ctx, saved) {
    const index = saved < 0 ? ctx.stateStack.length + saved : saved - 1;
    if (index < 0 || index >= ctx.stateStack.length)
      return;
    const state = ctx.stateStack[index];
    ctx.stateStack.length = index;
    ctx.state = cloneGraphicsState(state);
  }
  function ensureObjectSlot(ctx) {
    const heap = ctx.freeObjectSlots, first = heap[0];
    if (first === void 0)
      throw new errors_js_5.PptError("METAFILE_OBJECT_LIMIT", "Metafile creates more objects than its header declares");
    const last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let at = 0;
      while (at * 2 + 1 < heap.length) {
        let child = at * 2 + 1;
        if (child + 1 < heap.length && heap[child + 1] < heap[child])
          child++;
        if (heap[at] <= heap[child])
          break;
        [heap[at], heap[child]] = [heap[child], heap[at]];
        at = child;
      }
    }
    return first;
  }
  function setObject(ctx, index, value) {
    if (!Number.isInteger(index) || index < 0 || index >= ctx.objects.length)
      throw new errors_js_5.PptError("METAFILE_OBJECT_HANDLE", "Metafile object handle exceeds its declared table");
    ctx.objects[index] = value;
  }
  function deleteObject(ctx, index) {
    if (index < 0 || index >= ctx.objects.length || !ctx.objects[index])
      return;
    ctx.objects[index] = null;
    const heap = ctx.freeObjectSlots;
    let at = heap.length;
    heap.push(index);
    while (at > 0) {
      const parent = at - 1 >>> 1;
      if (heap[parent] <= index)
        break;
      heap[at] = heap[parent];
      at = parent;
      heap[at] = index;
    }
  }
  function utf8Length(value) {
    let bytes = 0;
    for (let i = 0; i < value.length; i++) {
      const c = value.charCodeAt(i);
      if (c < 128)
        bytes++;
      else if (c < 2048)
        bytes += 2;
      else if (c >= 55296 && c <= 56319 && i + 1 < value.length && value.charCodeAt(i + 1) >= 56320 && value.charCodeAt(i + 1) <= 57343) {
        bytes += 4;
        i++;
      } else
        bytes += 3;
    }
    return bytes;
  }
  function claimPoints(ctx, count) {
    if (!Number.isSafeInteger(count) || count < 0 || count > ctx.limits.maxPoints - ctx.pointCount)
      throw new errors_js_5.PptError("METAFILE_POINT_LIMIT", "Metafile exceeds its point budget");
    ctx.pointCount += count;
  }
  function countRecord(ctx) {
    if (++ctx.recordCount > ctx.limits.maxRecords)
      throw new errors_js_5.PptError("METAFILE_RECORD_LIMIT", "Metafile exceeds its record budget");
  }
  function selectStockObject(ctx, index) {
    switch (index >>> 0) {
      case STOCK_OBJECT.WHITE_BRUSH:
        ctx.state.brush = { color: "#ffffff" };
        return true;
      case STOCK_OBJECT.LTGRAY_BRUSH:
        ctx.state.brush = { color: "#c0c0c0" };
        return true;
      case STOCK_OBJECT.GRAY_BRUSH:
        ctx.state.brush = { color: "#808080" };
        return true;
      case STOCK_OBJECT.DKGRAY_BRUSH:
        ctx.state.brush = { color: "#404040" };
        return true;
      case STOCK_OBJECT.BLACK_BRUSH:
        ctx.state.brush = { color: "#000000" };
        return true;
      case STOCK_OBJECT.NULL_BRUSH:
        ctx.state.brush = { color: "none", none: true };
        return true;
      case STOCK_OBJECT.WHITE_PEN:
        ctx.state.pen = { color: "#ffffff", width: 1 };
        return true;
      case STOCK_OBJECT.BLACK_PEN:
        ctx.state.pen = { color: "#000000", width: 1 };
        return true;
      case STOCK_OBJECT.NULL_PEN:
        ctx.state.pen = { color: "none", width: 1, none: true };
        return true;
      default:
        return false;
    }
  }
  function selectObject(ctx, index) {
    if (selectStockObject(ctx, index))
      return;
    const object = ctx.objects[index] || null;
    if (!object)
      return;
    if (object.kind === "pen")
      ctx.state.pen = { ...object.value };
    if (object.kind === "brush")
      ctx.state.brush = { ...object.value };
    if (object.kind === "font")
      ctx.state.font = { ...object.value };
  }
  function addNode(ctx, svg, points) {
    if (ctx.state.clips.length)
      svg = ctx.state.clips.map((c) => `<g ${c.mask ? "mask" : "clip-path"}="url(#${c.id})">`).join("") + svg + "</g>".repeat(ctx.state.clips.length);
    const bytes = utf8Length(svg) + 1;
    if (bytes > ctx.limits.maxOutputBytes - ctx.outputBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Converted metafile exceeds the remaining asset byte budget");
    ctx.outputBytes += bytes;
    ctx.nodes.push(svg);
    updateBounds(ctx, points);
  }
  function addPathFragment(ctx, fragment, points) {
    if (!fragment)
      return;
    const bytes = utf8Length(fragment) + 1;
    if (bytes > ctx.limits.maxOutputBytes - ctx.outputBytes - ctx.pathBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Metafile path exceeds the remaining asset byte budget");
    ctx.pathBytes += bytes;
    ctx.pathData.push(fragment);
    for (const point of points)
      ctx.pathPoints.push(point);
  }
  function flushPath(ctx, attrs) {
    if (!ctx.pathData.length)
      return;
    addNode(ctx, `<path d="${ctx.pathData.join(" ")}" ${attrs} />`, ctx.pathPoints);
    ctx.pathData = [];
    ctx.pathPoints = [];
    ctx.pathBytes = 0;
    ctx.capturePath = false;
  }
  function addLine(ctx, start, end) {
    const a = mapPoint(ctx, start);
    const b = mapPoint(ctx, end);
    ctx.state.currentPosition = { ...end };
    if (ctx.capturePath) {
      addPathFragment(ctx, `${ctx.pathData.length ? "" : `M ${pointAttr(a)}`} L ${pointAttr(b)}`.trim(), [a, b]);
      return;
    }
    addNode(ctx, `<line x1="${numberCss(a.x)}" y1="${numberCss(a.y)}" x2="${numberCss(b.x)}" y2="${numberCss(b.y)}" ${strokeAttributes(ctx, ctx.state.pen)} />`, [a, b]);
  }
  function addPolyline(ctx, points, closed) {
    if (!points.length)
      return;
    const mapped = points.map((point) => mapPoint(ctx, point));
    ctx.state.currentPosition = { ...points[points.length - 1] };
    const attr = mapped.map(pointAttr).join(" ");
    if (ctx.capturePath) {
      const commands = [`M ${pointAttr(mapped[0])}`, ...mapped.slice(1).map((point) => `L ${pointAttr(point)}`)];
      if (closed)
        commands.push("Z");
      addPathFragment(ctx, commands.join(" "), mapped);
      return;
    }
    const tag = closed ? "polygon" : "polyline";
    const styleAttrs = closed ? fillAttributes(ctx) : strokeAttributes(ctx, ctx.state.pen);
    addNode(ctx, `<${tag} points="${attr}" ${styleAttrs} />`, mapped);
  }
  function addCompoundPolygons(ctx, polygons) {
    const points = [], parts = [];
    for (const polygon of polygons) {
      if (!polygon.length)
        continue;
      const mapped = polygon.map((p) => mapPoint(ctx, p));
      parts.push(`M${mapped.map(pointAttr).join("L")}Z`);
      for (const point of mapped)
        points.push(point);
    }
    if (!parts.length)
      return;
    if (ctx.capturePath)
      addPathFragment(ctx, parts.join(" "), points);
    else
      addNode(ctx, `<path d="${parts.join(" ")}" ${fillAttributes(ctx)}/>`, points);
  }
  function addBezierPath(ctx, points, relativeToCurrent = false) {
    const logical = relativeToCurrent ? [{ ...ctx.state.currentPosition }, ...points] : points;
    if (logical.length < 4)
      return;
    const mapped = logical.map((point) => mapPoint(ctx, point));
    let path = `M ${pointAttr(mapped[0])}`;
    for (let i = 1; i + 2 < mapped.length; i += 3) {
      path += ` C ${pointAttr(mapped[i])} ${pointAttr(mapped[i + 1])} ${pointAttr(mapped[i + 2])}`;
    }
    ctx.state.currentPosition = { ...logical[logical.length - 1] };
    if (ctx.capturePath) {
      addPathFragment(ctx, path, mapped);
      return;
    }
    addNode(ctx, `<path d="${path}" ${strokeAttributes(ctx, ctx.state.pen)} />`, mapped);
  }
  function addRect(ctx, rect, radius) {
    if (ctx.capturePath || ctx.state.worldTransform.m12 !== 0 || ctx.state.worldTransform.m21 !== 0) {
      const r = normalizeRect(rect), rx = Math.min((r.right - r.left) / 2, Math.abs(radius?.x ?? 0) / 2), ry = Math.min((r.bottom - r.top) / 2, Math.abs(radius?.y ?? 0) / 2), points = [], map = (x, y) => {
        const p = mapPoint(ctx, { x, y });
        points.push(p);
        return pointAttr(p);
      };
      let path;
      if (rx && ry) {
        const k = 0.5522847498307936;
        path = `M${map(r.left + rx, r.top)} L${map(r.right - rx, r.top)} C${map(r.right - rx + k * rx, r.top)} ${map(r.right, r.top + ry - k * ry)} ${map(r.right, r.top + ry)} L${map(r.right, r.bottom - ry)} C${map(r.right, r.bottom - ry + k * ry)} ${map(r.right - rx + k * rx, r.bottom)} ${map(r.right - rx, r.bottom)} L${map(r.left + rx, r.bottom)} C${map(r.left + rx - k * rx, r.bottom)} ${map(r.left, r.bottom - ry + k * ry)} ${map(r.left, r.bottom - ry)} L${map(r.left, r.top + ry)} C${map(r.left, r.top + ry - k * ry)} ${map(r.left + rx - k * rx, r.top)} ${map(r.left + rx, r.top)} Z`;
      } else {
        const outline = rectanglePath(ctx, r);
        path = outline.path;
        points.push(...outline.points);
      }
      claimPoints(ctx, points.length);
      if (ctx.capturePath)
        addPathFragment(ctx, path, points);
      else
        addNode(ctx, `<path d="${path}" ${fillAttributes(ctx)}/>`, points);
      return;
    }
    const mapped = mapRect(ctx, rect);
    const attrs = [
      `x="${numberCss(mapped.left)}"`,
      `y="${numberCss(mapped.top)}"`,
      `width="${numberCss(rectWidth(mapped))}"`,
      `height="${numberCss(rectHeight(mapped))}"`
    ];
    if (radius) {
      const rx = mapVector(ctx, { x: radius.x / 2, y: 0 }), ry = mapVector(ctx, { x: 0, y: radius.y / 2 });
      attrs.push(`rx="${numberCss(Math.hypot(rx.x, rx.y))}"`);
      attrs.push(`ry="${numberCss(Math.hypot(ry.x, ry.y))}"`);
    }
    if (ctx.capturePath) {
      addPathFragment(ctx, `M ${numberCss(mapped.left)},${numberCss(mapped.top)} L ${numberCss(mapped.right)},${numberCss(mapped.top)} L ${numberCss(mapped.right)},${numberCss(mapped.bottom)} L ${numberCss(mapped.left)},${numberCss(mapped.bottom)} Z`, [
        { x: mapped.left, y: mapped.top },
        { x: mapped.right, y: mapped.bottom }
      ]);
      return;
    }
    addNode(ctx, `<rect ${attrs.join(" ")} ${fillAttributes(ctx)} />`, [
      { x: mapped.left, y: mapped.top },
      { x: mapped.right, y: mapped.bottom }
    ]);
  }
  function addEllipse(ctx, rect) {
    if (ctx.capturePath || ctx.state.worldTransform.m12 !== 0 || ctx.state.worldTransform.m21 !== 0) {
      addArc(ctx, rect, { x: rect.right, y: (rect.top + rect.bottom) / 2 }, { x: rect.right, y: (rect.top + rect.bottom) / 2 }, "chord");
      return;
    }
    const mapped = mapRect(ctx, rect);
    const cx = (mapped.left + mapped.right) / 2;
    const cy = (mapped.top + mapped.bottom) / 2;
    const rx = rectWidth(mapped) / 2;
    const ry = rectHeight(mapped) / 2;
    if (ctx.capturePath) {
      addPathFragment(ctx, `M ${numberCss(cx - rx)},${numberCss(cy)} A ${numberCss(rx)},${numberCss(ry)} 0 1 0 ${numberCss(cx + rx)},${numberCss(cy)} A ${numberCss(rx)},${numberCss(ry)} 0 1 0 ${numberCss(cx - rx)},${numberCss(cy)} Z`, [
        { x: mapped.left, y: mapped.top },
        { x: mapped.right, y: mapped.bottom }
      ]);
      return;
    }
    addNode(ctx, `<ellipse cx="${numberCss(cx)}" cy="${numberCss(cy)}" rx="${numberCss(rx)}" ry="${numberCss(ry)}" ${fillAttributes(ctx)} />`, [
      { x: mapped.left, y: mapped.top },
      { x: mapped.right, y: mapped.bottom }
    ]);
  }
  function addArc(ctx, rect, start, end, kind) {
    const box = normalizeRect(rect), rx = (box.right - box.left) / 2, ry = (box.bottom - box.top) / 2, cx = (box.left + box.right) / 2, cy = (box.top + box.bottom) / 2;
    if (!rx || !ry)
      return;
    const theta = Math.atan2((start.y - cy) / ry, (start.x - cx) / rx), finish = Math.atan2((end.y - cy) / ry, (end.x - cx) / rx), clockwise = ctx.state.arcDirection === 2, tau = Math.PI * 2;
    let delta = ((clockwise ? finish - theta : theta - finish) % tau + tau) % tau;
    if (delta < 1e-10)
      delta = tau;
    if (!clockwise)
      delta = -delta;
    const steps = Math.max(1, Math.ceil(Math.abs(delta) / (Math.PI / 2))), points = [], logical = (a) => ({ x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) }), map = (p) => {
      const transformed = mapPoint(ctx, p);
      points.push(transformed);
      return pointAttr(transformed);
    }, first = logical(theta);
    let path = kind === "pie" ? `M${map({ x: cx, y: cy })} L${map(first)}` : kind === "arcTo" ? `M${map(ctx.state.currentPosition)} L${map(first)}` : `M${map(first)}`;
    for (let i = 0; i < steps; i++) {
      const a = theta + delta * i / steps, b = theta + delta * (i + 1) / steps, k = 4 / 3 * Math.tan((b - a) / 4), p0 = logical(a), p3 = logical(b), p1 = { x: p0.x - k * rx * Math.sin(a), y: p0.y + k * ry * Math.cos(a) }, p2 = { x: p3.x + k * rx * Math.sin(b), y: p3.y - k * ry * Math.cos(b) };
      path += ` C${map(p1)} ${map(p2)} ${map(p3)}`;
    }
    if (kind === "chord" || kind === "pie")
      path += " Z";
    claimPoints(ctx, points.length);
    if (ctx.capturePath)
      addPathFragment(ctx, path, points);
    else
      addNode(ctx, `<path d="${path}" ${kind === "arc" || kind === "arcTo" ? strokeAttributes(ctx, ctx.state.pen) : fillAttributes(ctx)}/>`, points);
    if (kind === "arcTo")
      ctx.state.currentPosition = logical(theta + delta);
  }
  function addRasterImage(ctx, dest, image, source, sourceTransform = IDENTITY_MATRIX, opacity = 1) {
    const sw = source.right - source.left, sh = source.bottom - source.top, dw = dest.right - dest.left, dh = dest.bottom - dest.top;
    if (!sw || !sh || !dw || !dh || opacity === 0)
      return;
    const { m11: a, m12: b, m21: c, m22: d, dx: tx, dy: ty } = sourceTransform, det = a * d - b * c;
    if (![a, b, c, d, tx, ty, det].every(Number.isFinite) || !det)
      throw new errors_js_5.PptError("METAFILE_BITMAP_TRANSFORM", "Invalid or singular source bitmap transform");
    const inverse = { m11: d / det, m12: -b / det, m21: -c / det, m22: a / det, dx: (c * ty - d * tx) / det, dy: (b * tx - a * ty) / det };
    const sampling = [inverse.m11 / sw, inverse.m12 / sh, inverse.m21 / sw, inverse.m22 / sh, (inverse.dx - source.left) / sw, (inverse.dy - source.top) / sh];
    const p = mapPoint(ctx, { x: dest.left, y: dest.top }), vx = mapVector(ctx, { x: dw, y: 0 }), vy = mapVector(ctx, { x: 0, y: dh });
    if (Math.ceil(image.bytes.length / 3) * 4 + 700 > ctx.limits.maxOutputBytes - ctx.outputBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Metafile bitmap exceeds the remaining SVG output budget");
    const href = utils_js_3.dataUrlFromBytes(image.bytes, image.mime), transform = [vx.x, vx.y, vy.x, vy.y, p.x, p.y].map(numberCss).join(" ");
    const svg = `<g transform="matrix(${transform})"${opacity < 1 ? ` opacity="${opacity}"` : ""}><svg x="0" y="0" width="1" height="1" viewBox="0 0 1 1" preserveAspectRatio="none" overflow="hidden"><image x="0" y="0" width="${image.width}" height="${image.height}" transform="matrix(${sampling.map((value) => String(Number(value.toPrecision(12)))).join(" ")})" xlink:href="${href}" preserveAspectRatio="none" /></svg></g>`;
    addNode(ctx, svg, [p, { x: p.x + vx.x, y: p.y + vx.y }, { x: p.x + vy.x, y: p.y + vy.y }, { x: p.x + vx.x + vy.x, y: p.y + vx.y + vy.y }]);
  }
  function decodeAnsi(bytes, charset = 0) {
    const labels = { 0: "windows-1252", 128: "shift_jis", 129: "euc-kr", 134: "gbk", 136: "big5", 161: "windows-1253", 162: "windows-1254", 163: "windows-1258", 177: "windows-1255", 178: "windows-1256", 186: "windows-1257", 204: "windows-1251", 222: "windows-874", 238: "windows-1250" };
    return utils_js_3.trimTrailingNulls(new TextDecoder(labels[charset] ?? "windows-1252").decode(bytes));
  }
  function decodeUtf16(bytes) {
    return utils_js_3.trimTrailingNulls(new TextDecoder("utf-16le").decode(bytes));
  }
  function textAnchor(textAlign) {
    const horizontal = textAlign & 6;
    if (horizontal === 2)
      return "end";
    if (horizontal === 6)
      return "middle";
    return "start";
  }
  function dominantBaseline(textAlign) {
    const vertical = textAlign & 24;
    if (vertical === 8)
      return "text-after-edge";
    if (vertical === 24)
      return "alphabetic";
    return "text-before-edge";
  }
  function addText(ctx, point, text, glyphIndices, textOptions = {}) {
    if (!text && !glyphIndices?.length && !(textOptions.rectangle && (textOptions.options ?? 0) & 2))
      return;
    if (text.length * (textOptions.advances ? 96 : 6) + (glyphIndices?.length ?? 0) * 8 > ctx.limits.maxOutputBytes - ctx.outputBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Metafile text exceeds the remaining SVG output budget");
    const logical = ctx.state.textAlign & 1 ? ctx.state.currentPosition : point, mapped = mapPoint(ctx, logical), angle = -(ctx.state.font.escapement ?? 0) * Math.PI / 1800, cos = Math.cos(angle), sin = Math.sin(angle), vx = mapVector(ctx, { x: cos, y: sin }), vy = mapVector(ctx, { x: -sin, y: cos });
    const fontSize = Math.max(1, Math.abs(ctx.state.font.size) || 12), options = textOptions.options ?? 0;
    const previousClips = [...ctx.state.clips];
    if (textOptions.rectangle && options & 2) {
      const r = rectanglePath(ctx, textOptions.rectangle);
      addNode(ctx, `<path d="${r.path}" fill="${ctx.state.bkColor}" stroke="none"/>`, r.points);
    }
    if (textOptions.rectangle && options & 4)
      clipPath(ctx, rectanglePath(ctx, textOptions.rectangle).path, 1);
    const attrs = [
      'x="0"',
      'y="0"',
      `transform="matrix(${[vx.x, vx.y, vy.x, vy.y, mapped.x, mapped.y].map(numberCss).join(" ")})"`,
      `fill="${utils_js_3.escapeHtml(ctx.state.textColor)}"`,
      `font-size="${numberCss(fontSize)}"`,
      `font-family="${xml_text_js_1.escapeXmlText(ctx.state.font.family)}"`,
      `text-anchor="${textOptions.advances ? "start" : textAnchor(ctx.state.textAlign)}"`,
      `dominant-baseline="${dominantBaseline(ctx.state.textAlign)}"`
    ];
    if (options & 128)
      attrs.push('direction="rtl" unicode-bidi="bidi-override"');
    if (ctx.state.font.weight && ctx.state.font.weight >= 600)
      attrs.push('font-weight="700"');
    if (ctx.state.font.italic)
      attrs.push('font-style="italic"');
    const decorations = [ctx.state.font.underline ? "underline" : "", ctx.state.font.strike ? "line-through" : ""].filter(Boolean);
    if (decorations.length)
      attrs.push(`text-decoration="${decorations.join(" ")}"`);
    if (glyphIndices?.length) {
      attrs.push(`data-msdoc-glyph-indices="${glyphIndices.join(" ")}"`);
      ctx.unresolvedGlyphRuns += 1;
    }
    let body = glyphIndices ? "" : xml_text_js_1.escapeXmlText(text), extent = { x: 0, y: 0 };
    if (textOptions.advances) {
      extent = textOptions.advances.reduce((p, d) => ({ x: p.x + d.x, y: p.y + d.y }), { x: 0, y: 0 });
      const alignment = textAnchor(ctx.state.textAlign), factor = alignment === "middle" ? 0.5 : alignment === "end" ? 1 : 0;
      let x = -extent.x * factor, y = -extent.y * factor, index = 0;
      const spans = [];
      for (const character of Array.from(text)) {
        spans.push(`<tspan x="${numberCss(x)}" y="${numberCss(y)}">${xml_text_js_1.escapeXmlText(character)}</tspan>`);
        for (let k = 0; k < character.length; k++) {
          const d = textOptions.advances[index++];
          if (d) {
            x += d.x;
            y += d.y;
          }
        }
      }
      if (!glyphIndices)
        body = spans.join("");
    } else if (ctx.state.textAlign & 1) {
      extent.x = Array.from(text).length * fontSize * 0.55;
      ctx.unsupportedRecordTypes.add(ctx.activeRecordType);
    }
    if (ctx.state.font.charset === 2 || ctx.state.font.charset === 255 || ctx.state.font.charset === 130)
      ctx.unsupportedRecordTypes.add(ctx.activeRecordType);
    addNode(ctx, `<text ${attrs.join(" ")}>${body}</text>`, [mapped]);
    ctx.state.clips = previousClips;
    if (ctx.state.textAlign & 1)
      ctx.state.currentPosition = { x: logical.x + extent.x * cos - extent.y * sin, y: logical.y + extent.x * sin + extent.y * cos };
  }
  function finalizeSvg(ctx, sourceMime) {
    if (!ctx.nodes.length)
      return null;
    const fallback = ctx.contentBounds ? normalizeRect(ctx.contentBounds) : normalizeRect(ctx.viewBox);
    const viewBox = normalizeRect({
      left: Number.isFinite(ctx.viewBox.left) ? ctx.viewBox.left : fallback.left,
      top: Number.isFinite(ctx.viewBox.top) ? ctx.viewBox.top : fallback.top,
      right: Number.isFinite(ctx.viewBox.right) ? ctx.viewBox.right : fallback.right,
      bottom: Number.isFinite(ctx.viewBox.bottom) ? ctx.viewBox.bottom : fallback.bottom
    });
    const width = Math.max(1, Math.round(rectWidth(viewBox)));
    const height = Math.max(1, Math.round(rectHeight(viewBox)));
    const start = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${width}" height="${height}" viewBox="${numberCss(viewBox.left)} ${numberCss(viewBox.top)} ${numberCss(rectWidth(viewBox))} ${numberCss(rectHeight(viewBox))}" preserveAspectRatio="xMinYMin meet">
`;
    if (utf8Length(start) + ctx.outputBytes + 6 + (ctx.defs.length ? 14 : 0) > ctx.limits.maxOutputBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Converted SVG exceeds the remaining asset byte budget");
    const svg = `${start}${ctx.defs.length ? `<defs>${ctx.defs.join("\n")}</defs>
` : ""}${ctx.nodes.join("\n")}
</svg>`;
    const encoded = new TextEncoder().encode(svg);
    return {
      mime: "image/svg+xml",
      bytes: encoded,
      dataUrl: utils_js_3.dataUrlFromBytes(encoded, "image/svg+xml"),
      width,
      height,
      sourceMime,
      recordCount: ctx.recordCount,
      unresolvedGlyphRuns: ctx.unresolvedGlyphRuns,
      unsupportedRecordTypes: [...ctx.unsupportedRecordTypes].sort((a, b) => a - b)
    };
  }
  function parseWmf(bytes, limits) {
    const reader = new binary_js_1.BinaryReader(bytes);
    let offset = 0;
    let placeableBounds = null;
    if (reader.u32(0) === PLACEABLE_WMF_KEY && bytes.length >= 22) {
      placeableBounds = normalizeRect({
        left: reader.i16(6),
        top: reader.i16(8),
        right: reader.i16(10),
        bottom: reader.i16(12)
      });
      offset = 22;
    }
    if (offset + WMF_HEADER_SIZE > bytes.length)
      return null;
    const header = new binary_js_1.BinaryReader(bytes.subarray(offset));
    const headerSizeWords = header.u16(2);
    const numberOfObjects = header.u16(10);
    const recordOffset = offset + headerSizeWords * 2;
    if (headerSizeWords < 9 || recordOffset > bytes.length)
      throw new errors_js_5.PptError("METAFILE_HEADER", "Invalid WMF header length");
    const viewBox = placeableBounds || { left: 0, top: 0, right: 1e3, bottom: 1e3 };
    const ctx = defaultContext(rectWidth(viewBox), rectHeight(viewBox), viewBox, limits, numberOfObjects);
    if (placeableBounds) {
      ctx.state.windowOrg = { x: placeableBounds.left, y: placeableBounds.top };
      ctx.state.windowExt = { x: rectWidth(placeableBounds), y: rectHeight(placeableBounds) };
      ctx.state.viewportOrg = { x: placeableBounds.left, y: placeableBounds.top };
      ctx.state.viewportExt = { x: rectWidth(placeableBounds), y: rectHeight(placeableBounds) };
    }
    let cursor = recordOffset;
    while (cursor + 6 <= bytes.length) {
      const sizeWords = reader.u32(cursor);
      const recordSize = sizeWords * 2;
      if (recordSize < 6 || cursor + recordSize > bytes.length)
        throw new errors_js_5.PptError("METAFILE_RECORD_LENGTH", "WMF record exceeds its payload", cursor);
      const recordReader = new binary_js_1.BinaryReader(bytes.subarray(cursor, cursor + recordSize));
      const fn = recordReader.u16(4);
      if (recordSize < (WMF_MIN_BYTES[fn] ?? 6))
        throw new errors_js_5.PptError("METAFILE_RECORD_LENGTH", `WMF record 0x${fn.toString(16)} has a truncated fixed prefix`, cursor);
      countRecord(ctx);
      ctx.activeRecordType = fn;
      switch (fn) {
        case WMF_RECORD.META_EOF:
          cursor += recordSize;
          return finalizeSvg(ctx, "image/wmf");
        case WMF_RECORD.META_SAVEDC:
          saveState(ctx);
          break;
        case WMF_RECORD.META_RESTOREDC:
          restoreState(ctx, recordReader.i16(6));
          break;
        case WMF_RECORD.META_SETTEXTALIGN:
          ctx.state.textAlign = recordReader.u16(6);
          break;
        case WMF_RECORD.META_INTERSECTCLIPRECT:
        case WMF_RECORD.META_EXCLUDECLIPRECT: {
          const r = { left: recordReader.i16(12), top: recordReader.i16(10), right: recordReader.i16(8), bottom: recordReader.i16(6) };
          clipPath(ctx, rectanglePath(ctx, r).path, fn === WMF_RECORD.META_INTERSECTCLIPRECT ? 1 : 4);
          break;
        }
        case WMF_RECORD.META_SETWINDOWORG:
          ctx.state.windowOrg = { x: recordReader.i16(8), y: recordReader.i16(6) };
          break;
        case WMF_RECORD.META_SETWINDOWEXT:
          ctx.state.windowExt = { x: recordReader.i16(8), y: recordReader.i16(6) };
          break;
        case WMF_RECORD.META_SETVIEWPORTORG:
          ctx.state.viewportOrg = { x: recordReader.i16(8), y: recordReader.i16(6) };
          break;
        case WMF_RECORD.META_SETVIEWPORTEXT:
          ctx.state.viewportExt = { x: recordReader.i16(8), y: recordReader.i16(6) };
          break;
        case WMF_RECORD.META_OFFSETWINDOWORG:
          ctx.state.windowOrg = { x: ctx.state.windowOrg.x + recordReader.i16(8), y: ctx.state.windowOrg.y + recordReader.i16(6) };
          break;
        case WMF_RECORD.META_OFFSETVIEWPORTORG:
          ctx.state.viewportOrg = { x: ctx.state.viewportOrg.x + recordReader.i16(8), y: ctx.state.viewportOrg.y + recordReader.i16(6) };
          break;
        case WMF_RECORD.META_SETBKMODE:
          ctx.state.bkMode = recordReader.u16(6);
          break;
        case WMF_RECORD.META_SETPOLYFILLMODE:
          ctx.state.polygonFillMode = recordReader.u16(6);
          break;
        case WMF_RECORD.META_SETBKCOLOR:
          ctx.state.bkColor = colorRefToCss(recordReader.u32(6));
          break;
        case WMF_RECORD.META_SETTEXTCOLOR:
          ctx.state.textColor = colorRefToCss(recordReader.u32(6));
          break;
        case WMF_RECORD.META_MOVETO:
          ctx.state.currentPosition = { x: recordReader.i16(8), y: recordReader.i16(6) };
          break;
        case WMF_RECORD.META_LINETO: {
          const end = { x: recordReader.i16(8), y: recordReader.i16(6) };
          addLine(ctx, ctx.state.currentPosition, end);
          break;
        }
        case WMF_RECORD.META_POLYLINE:
        case WMF_RECORD.META_POLYGON: {
          const count = recordReader.u16(6);
          if (!recordReader.ensure(8, count * 4))
            throw new errors_js_5.PptError("METAFILE_POINTS", "WMF point array exceeds its own record", cursor);
          claimPoints(ctx, count);
          const points = [];
          let pointOffset = 8;
          for (let i = 0; i < count && pointOffset + 4 <= recordSize; i += 1) {
            points.push({ x: recordReader.i16(pointOffset), y: recordReader.i16(pointOffset + 2) });
            pointOffset += 4;
          }
          addPolyline(ctx, points, fn === WMF_RECORD.META_POLYGON);
          break;
        }
        case WMF_RECORD.META_POLYPOLYGON: {
          const polygons = recordReader.u16(6);
          if (!recordReader.ensure(8, polygons * 2))
            throw new errors_js_5.PptError("METAFILE_POINTS", "WMF polygon counts exceed their own record", cursor);
          const counts = [];
          let dataOffset = 8;
          for (let i = 0; i < polygons && dataOffset + 2 <= recordSize; i += 1) {
            counts.push(recordReader.u16(dataOffset));
            dataOffset += 2;
          }
          const total = counts.reduce((sum, count) => sum + count, 0);
          if (!recordReader.ensure(dataOffset, total * 4))
            throw new errors_js_5.PptError("METAFILE_POINTS", "WMF polygon points exceed their own record", cursor);
          claimPoints(ctx, total);
          const polygonPoints = [];
          for (const count of counts) {
            const points = [];
            for (let i = 0; i < count && dataOffset + 4 <= recordSize; i += 1) {
              points.push({ x: recordReader.i16(dataOffset), y: recordReader.i16(dataOffset + 2) });
              dataOffset += 4;
            }
            polygonPoints.push(points);
          }
          addCompoundPolygons(ctx, polygonPoints);
          break;
        }
        case WMF_RECORD.META_RECTANGLE: {
          addRect(ctx, {
            left: recordReader.i16(12),
            top: recordReader.i16(10),
            right: recordReader.i16(8),
            bottom: recordReader.i16(6)
          });
          break;
        }
        case WMF_RECORD.META_ELLIPSE: {
          addEllipse(ctx, {
            left: recordReader.i16(12),
            top: recordReader.i16(10),
            right: recordReader.i16(8),
            bottom: recordReader.i16(6)
          });
          break;
        }
        case WMF_RECORD.META_ROUNDRECT: {
          addRect(ctx, {
            left: recordReader.i16(16),
            top: recordReader.i16(14),
            right: recordReader.i16(12),
            bottom: recordReader.i16(10)
          }, {
            x: recordReader.i16(8),
            y: recordReader.i16(6)
          });
          break;
        }
        case WMF_RECORD.META_ARC:
        case WMF_RECORD.META_CHORD:
        case WMF_RECORD.META_PIE: {
          const end = { x: recordReader.i16(8), y: recordReader.i16(6) }, start = { x: recordReader.i16(12), y: recordReader.i16(10) }, box = { left: recordReader.i16(20), top: recordReader.i16(18), right: recordReader.i16(16), bottom: recordReader.i16(14) };
          addArc(ctx, box, start, end, fn === WMF_RECORD.META_CHORD ? "chord" : fn === WMF_RECORD.META_PIE ? "pie" : "arc");
          break;
        }
        case WMF_RECORD.META_TEXTOUT: {
          const length = recordReader.u16(6);
          const textOffset = 8;
          const paddedLength = length + length % 2;
          if (!recordReader.ensure(textOffset, paddedLength + 4))
            throw new errors_js_5.PptError("METAFILE_TEXT", "WMF text exceeds its own record", cursor);
          const text = decodeAnsi(recordReader.slice(textOffset, Math.min(length, Math.max(0, recordSize - textOffset - 4))), ctx.state.font.charset);
          const yOffset = textOffset + paddedLength;
          const y = recordReader.i16(yOffset);
          const x = recordReader.i16(yOffset + 2);
          addText(ctx, { x, y }, text);
          break;
        }
        case WMF_RECORD.META_EXTTEXTOUT: {
          const point = { x: recordReader.i16(8), y: recordReader.i16(6) }, length = recordReader.i16(10), options = recordReader.u16(12), hasRect = (options & 6) !== 0, textOffset = hasRect ? 22 : 14;
          if (length < 0 || !recordReader.ensure(textOffset, length + length % 2))
            throw new errors_js_5.PptError("METAFILE_TEXT", "WMF extended text exceeds its own record", cursor);
          const rectangle = hasRect ? { left: recordReader.i16(14), top: recordReader.i16(16), right: recordReader.i16(18), bottom: recordReader.i16(20) } : void 0;
          const dxOffset = textOffset + length + length % 2;
          let advances;
          if (dxOffset < recordSize) {
            if (!recordReader.ensure(dxOffset, length * 2))
              throw new errors_js_5.PptError("METAFILE_TEXT", "WMF character spacing exceeds its own record", cursor);
            claimPoints(ctx, length);
            advances = Array.from({ length }, (_, i) => ({ x: recordReader.i16(dxOffset + i * 2), y: 0 }));
          }
          const text = decodeAnsi(recordReader.slice(textOffset, length), ctx.state.font.charset);
          addText(ctx, point, text, void 0, { advances, rectangle, options });
          break;
        }
        case WMF_RECORD.META_CREATEPENINDIRECT: {
          const style = recordReader.u16(6);
          const width = recordReader.i16(8);
          const color = colorRefToCss(recordReader.u32(12));
          const index = ensureObjectSlot(ctx);
          setObject(ctx, index, { kind: "pen", value: penStyleFromCode(style, width, color) });
          break;
        }
        case WMF_RECORD.META_CREATEBRUSHINDIRECT: {
          const style = recordReader.u16(6);
          if (style > 2 || style === 2 && recordReader.u16(12) > 5)
            ctx.unsupportedRecordTypes.add(fn);
          const color = colorRefToCss(recordReader.u32(8));
          const index = ensureObjectSlot(ctx);
          setObject(ctx, index, { kind: "brush", value: brushStyleFromCode(style, color, recordReader.u16(12)) });
          break;
        }
        case WMF_RECORD.META_CREATEFONTINDIRECT: {
          const font = vector_font_js_1.readWmfFont(new binary_js_1.BinaryReader(recordReader.slice(0, recordSize)));
          if (font)
            setObject(ctx, ensureObjectSlot(ctx), { kind: "font", value: { ...font, charset: recordReader.u8(19) } });
          break;
        }
        case WMF_RECORD.META_SELECTOBJECT:
          selectObject(ctx, recordReader.u16(6));
          break;
        case WMF_RECORD.META_DELETEOBJECT: {
          const index = recordReader.u16(6);
          deleteObject(ctx, index);
          break;
        }
        default:
          ctx.unsupportedRecordTypes.add(fn);
          break;
      }
      cursor += recordSize;
    }
    return finalizeSvg(ctx, "image/wmf");
  }
  function readEmfPointArray(ctx, reader, offset, count, pointSize) {
    if (!reader.ensure(offset, count * pointSize))
      throw new errors_js_5.PptError("METAFILE_POINTS", "EMF point array exceeds its own record");
    claimPoints(ctx, count);
    const points = [];
    for (let i = 0; i < count; i += 1) {
      const pointOffset = offset + i * pointSize;
      if (pointSize === 8) {
        points.push({ x: reader.i32(pointOffset), y: reader.i32(pointOffset + 4) });
      } else {
        points.push({ x: reader.i16(pointOffset), y: reader.i16(pointOffset + 2) });
      }
    }
    return points;
  }
  function parseEmfText(ctx, reader, unicode) {
    if (!reader.ensure(36, 24))
      throw new errors_js_5.PptError("METAFILE_TEXT", "EMF text object exceeds its record");
    const point = { x: reader.i32(36), y: reader.i32(40) };
    const chars = reader.u32(44);
    const offString = reader.u32(48);
    const options = reader.u32(52), hasRect = (options & 256) === 0, offDxField = hasRect ? 72 : 56;
    if (!reader.ensure(offDxField, 4))
      throw new errors_js_5.PptError("METAFILE_TEXT", "EMF text rectangle or spacing offset exceeds its record");
    const rectangle = hasRect ? { left: reader.i32(56), top: reader.i32(60), right: reader.i32(64), bottom: reader.i32(68) } : void 0;
    const byteLength = unicode ? chars * 2 : chars, offDx = reader.u32(offDxField), stride = options & 8192 ? 8 : 4;
    if (chars && (!offString || !reader.ensure(offString, byteLength)))
      throw new errors_js_5.PptError("METAFILE_TEXT", "EMF text bytes exceed their own record");
    let advances;
    if (offDx && chars) {
      if (!reader.ensure(offDx, chars * stride))
        throw new errors_js_5.PptError("METAFILE_TEXT", "EMF character spacing exceeds its own record");
      claimPoints(ctx, chars);
      advances = Array.from({ length: chars }, (_, i) => ({ x: reader.i32(offDx + i * stride), y: stride === 8 ? reader.i32(offDx + i * stride + 4) : 0 }));
    }
    if (options & 3072)
      ctx.unsupportedRecordTypes.add(ctx.activeRecordType);
    const bytes = reader.slice(offString, byteLength);
    if (options & 16) {
      claimPoints(ctx, chars);
      const glyphIndices = unicode ? Array.from({ length: chars }, (_, index) => reader.u16(offString + index * 2)) : Array.from(bytes);
      return { point, text: "", glyphIndices, advances, options, rectangle };
    }
    const text = unicode ? decodeUtf16(bytes) : decodeAnsi(bytes, ctx.state.font.charset);
    return { point, text, advances, options, rectangle };
  }
  function parseSmallEmfText(ctx, reader) {
    if (!reader.ensure(8, 28))
      throw new errors_js_5.PptError("METAFILE_TEXT", "Small EMF text has a truncated prefix");
    const point = { x: reader.i32(8), y: reader.i32(12) };
    const chars = reader.u32(16);
    const options = reader.u32(20);
    const hasRect = (options & 256) === 0, textOffset = hasRect ? 52 : 36, small = (options & 512) !== 0;
    if (!reader.ensure(textOffset, chars * (small ? 1 : 2)))
      throw new errors_js_5.PptError("METAFILE_TEXT", "Small EMF text exceeds its own record");
    const rectangle = hasRect ? { left: reader.i32(36), top: reader.i32(40), right: reader.i32(44), bottom: reader.i32(48) } : void 0;
    if (options & 16) {
      claimPoints(ctx, chars);
      return { point, text: "", options, rectangle, glyphIndices: Array.from({ length: chars }, (_, i) => small ? reader.u8(textOffset + i) : reader.u16(textOffset + i * 2)) };
    }
    const text = small ? Array.from(reader.slice(textOffset, chars), (value) => String.fromCharCode(value)).join("") : decodeUtf16(reader.slice(textOffset, chars * 2));
    return { point, text, options, rectangle };
  }
  function readEmfEmbeddedBmp(record, offBmiOffset, cbBmiOffset, offBitsOffset, cbBitsOffset, remainingBytes, perPixelAlpha) {
    const offBmi = record.u32(offBmiOffset);
    const cbBmi = record.u32(cbBmiOffset);
    const offBits = record.u32(offBitsOffset);
    const cbBits = record.u32(cbBitsOffset);
    if (!offBmi && !cbBmi && !offBits && !cbBits)
      return null;
    if (!offBmi || !cbBmi || !offBits || !cbBits || !record.ensure(offBmi, cbBmi) || !record.ensure(offBits, cbBits))
      throw new errors_js_5.PptError("METAFILE_BITMAP", "Embedded bitmap exceeds its own record");
    if (Math.ceil((cbBmi + cbBits + 14) / 3) * 4 + 256 > remainingBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Embedded metafile bitmap exceeds the SVG output budget");
    const bmi = record.slice(offBmi, cbBmi), bits = record.slice(offBits, cbBits), header = new binary_js_1.BinaryReader(bmi), size = header.u32(0);
    if (size !== 12 && size < 40 || !header.ensure(0, size))
      throw new errors_js_5.PptError("METAFILE_BITMAP", "Invalid embedded bitmap header");
    const width = size === 12 ? header.u16(4) : header.i32(4), signedHeight = size === 12 ? header.u16(6) : header.i32(8), height = Math.abs(signedHeight), depth = header.u16(size === 12 ? 10 : 14), compression = size === 12 ? 0 : header.u32(16);
    if (width <= 0 || height <= 0 || width * height * 4 > remainingBytes)
      throw new errors_js_5.PptError("LIMIT_ASSETS", "Embedded bitmap dimensions exceed the decoded byte budget");
    let data, mime = "image/bmp";
    if (perPixelAlpha !== void 0 && depth === 32 && compression === 0) {
      data = raster_js_1.encodeRgbaPng(width, height, raster_js_1.decodeBgraBitmap(width, signedHeight, bits, perPixelAlpha, remainingBytes), remainingBytes);
      mime = "image/png";
    } else if (perPixelAlpha || perPixelAlpha === false && (depth === 32 || compression === 5)) {
      return null;
    } else if (compression === 4 || compression === 5) {
      data = bits;
      mime = compression === 4 ? "image/jpeg" : "image/png";
    } else {
      const bmp = bitmapInfoToBmp(bmi, bits);
      if (!bmp)
        return null;
      data = bmp;
    }
    return { bytes: data, mime, width, height, bottomUp: signedHeight > 0 };
  }
  function addEmfStretchDibits(ctx, record) {
    if (!record.ensure(24, 56))
      return;
    const bmp = readEmfEmbeddedBmp(record, 48, 52, 56, 60, ctx.limits.maxOutputBytes - ctx.outputBytes);
    if (!bmp)
      return;
    const y = record.i32(36), cy = record.i32(44), sourceY = bmp.bottomUp ? bmp.height - y - cy : y;
    addRasterImage(ctx, {
      left: record.i32(24),
      top: record.i32(28),
      right: record.i32(24) + record.i32(72),
      bottom: record.i32(28) + record.i32(76)
    }, bmp, { left: record.i32(32), top: sourceY, right: record.i32(32) + record.i32(40), bottom: sourceY + cy });
  }
  function addEmfBltBitmap(ctx, record) {
    if (!record.ensure(24, 76))
      return;
    const alpha = ctx.activeRecordType === EMF_RECORD.EMR_ALPHABLEND;
    if (alpha && (record.u8(40) !== 0 || record.u8(43) > 1)) {
      ctx.unsupportedRecordTypes.add(ctx.activeRecordType);
      return;
    }
    const bmp = readEmfEmbeddedBmp(record, 84, 88, 92, 96, ctx.limits.maxOutputBytes - ctx.outputBytes, alpha ? record.u8(43) === 1 : void 0);
    if (!bmp) {
      ctx.unsupportedRecordTypes.add(ctx.activeRecordType);
      return;
    }
    const sw = ctx.activeRecordType === EMF_RECORD.EMR_BITBLT ? record.i32(32) : record.i32(100), sh = ctx.activeRecordType === EMF_RECORD.EMR_BITBLT ? record.i32(36) : record.i32(104);
    if (alpha && (sw <= 0 || sh <= 0 || record.i32(32) <= 0 || record.i32(36) <= 0))
      throw new errors_js_5.PptError("METAFILE_BITMAP", "AlphaBlend source and destination extents must be positive");
    addRasterImage(ctx, {
      left: record.i32(24),
      top: record.i32(28),
      right: record.i32(24) + record.i32(32),
      bottom: record.i32(28) + record.i32(36)
    }, bmp, { left: record.i32(44), top: record.i32(48), right: record.i32(44) + sw, bottom: record.i32(48) + sh }, readXForm(record, 52), alpha ? record.u8(42) / 255 : 1);
  }
  function closeCurrentPathFigure(ctx) {
    if (!ctx.pathData.length)
      return;
    addPathFragment(ctx, "Z", []);
  }
  function parseEmf(bytes, limits) {
    const reader = new binary_js_1.BinaryReader(bytes);
    if (!reader.ensure(0, 88) || reader.u32(0) !== EMF_RECORD.EMR_HEADER)
      return null;
    const bounds = normalizeRect({
      left: reader.i32(8),
      top: reader.i32(12),
      right: reader.i32(16),
      bottom: reader.i32(20)
    });
    const viewBox = rectWidth(bounds) > 0 && rectHeight(bounds) > 0 ? bounds : { left: 0, top: 0, right: 1e3, bottom: 1e3 };
    const ctx = defaultContext(rectWidth(viewBox), rectHeight(viewBox), viewBox, limits, reader.u16(56));
    ctx.state.windowOrg = { x: viewBox.left, y: viewBox.top };
    ctx.state.windowExt = { x: rectWidth(viewBox), y: rectHeight(viewBox) };
    ctx.state.viewportOrg = { x: viewBox.left, y: viewBox.top };
    ctx.state.viewportExt = { x: rectWidth(viewBox), y: rectHeight(viewBox) };
    let cursor = 0;
    while (cursor + 8 <= bytes.length) {
      const type = reader.u32(cursor);
      const size = reader.u32(cursor + 4);
      if (size < 8 || size % 4 !== 0 || cursor + size > bytes.length || size < (EMF_MIN_BYTES[type] ?? 8))
        throw new errors_js_5.PptError("METAFILE_RECORD_LENGTH", `EMF record ${type} exceeds its payload or has a truncated fixed prefix`, cursor);
      const record = new binary_js_1.BinaryReader(bytes.subarray(cursor, cursor + size));
      countRecord(ctx);
      ctx.activeRecordType = type;
      switch (type) {
        case EMF_RECORD.EMR_HEADER:
          break;
        case EMF_RECORD.EMR_EOF:
          cursor += size;
          return finalizeSvg(ctx, "image/emf");
        case EMF_RECORD.EMR_SETWINDOWORGEX:
          ctx.state.windowOrg = { x: record.i32(8), y: record.i32(12) };
          break;
        case EMF_RECORD.EMR_SETWINDOWEXTEX:
          ctx.state.windowExt = { x: record.i32(8), y: record.i32(12) };
          break;
        case EMF_RECORD.EMR_SETVIEWPORTORGEX:
          ctx.state.viewportOrg = { x: record.i32(8), y: record.i32(12) };
          break;
        case EMF_RECORD.EMR_SETVIEWPORTEXTEX:
          ctx.state.viewportExt = { x: record.i32(8), y: record.i32(12) };
          break;
        case EMF_RECORD.EMR_SETBKMODE:
          ctx.state.bkMode = record.u32(8);
          break;
        case EMF_RECORD.EMR_SETPOLYFILLMODE:
          ctx.state.polygonFillMode = record.u32(8);
          break;
        case EMF_RECORD.EMR_SETTEXTALIGN:
          ctx.state.textAlign = record.u32(8);
          break;
        case EMF_RECORD.EMR_SETTEXTCOLOR:
          ctx.state.textColor = colorRefToCss(record.u32(8));
          break;
        case EMF_RECORD.EMR_SETBKCOLOR:
          ctx.state.bkColor = colorRefToCss(record.u32(8));
          break;
        case EMF_RECORD.EMR_SETARCDIRECTION:
          ctx.state.arcDirection = record.u32(8) === 2 ? 2 : 1;
          break;
        case EMF_RECORD.EMR_INTERSECTCLIPRECT:
        case EMF_RECORD.EMR_EXCLUDECLIPRECT: {
          const r = { left: record.i32(8), top: record.i32(12), right: record.i32(16), bottom: record.i32(20) };
          clipPath(ctx, rectanglePath(ctx, r).path, type === EMF_RECORD.EMR_INTERSECTCLIPRECT ? 1 : 4);
          break;
        }
        case EMF_RECORD.EMR_SAVEDC:
          saveState(ctx);
          break;
        case EMF_RECORD.EMR_RESTOREDC: {
          restoreState(ctx, record.i32(8));
          break;
        }
        case EMF_RECORD.EMR_SETWORLDTRANSFORM:
          ctx.state.worldTransform = readXForm(record, 8);
          break;
        case EMF_RECORD.EMR_MODIFYWORLDTRANSFORM: {
          const xform = readXForm(record, 8);
          const mode = record.u32(32);
          if (mode === MODIFY_WORLD_TRANSFORM.MWT_IDENTITY)
            ctx.state.worldTransform = { ...IDENTITY_MATRIX };
          else if (mode === MODIFY_WORLD_TRANSFORM.MWT_SET)
            ctx.state.worldTransform = xform;
          else if (mode === MODIFY_WORLD_TRANSFORM.MWT_LEFTMULTIPLY)
            ctx.state.worldTransform = multiplyMatrix(xform, ctx.state.worldTransform);
          else if (mode === MODIFY_WORLD_TRANSFORM.MWT_RIGHTMULTIPLY)
            ctx.state.worldTransform = multiplyMatrix(ctx.state.worldTransform, xform);
          break;
        }
        case EMF_RECORD.EMR_MOVETOEX:
          ctx.state.currentPosition = { x: record.i32(8), y: record.i32(12) };
          break;
        case EMF_RECORD.EMR_LINETO: {
          const end = { x: record.i32(8), y: record.i32(12) };
          addLine(ctx, ctx.state.currentPosition, end);
          break;
        }
        case EMF_RECORD.EMR_POLYLINE:
        case EMF_RECORD.EMR_POLYGON:
        case EMF_RECORD.EMR_POLYLINE16:
        case EMF_RECORD.EMR_POLYGON16: {
          const count = record.u32(24);
          const pointOffset = 28;
          const pointSize = type === EMF_RECORD.EMR_POLYLINE16 || type === EMF_RECORD.EMR_POLYGON16 ? 4 : 8;
          const points = readEmfPointArray(ctx, record, pointOffset, count, pointSize);
          addPolyline(ctx, points, type === EMF_RECORD.EMR_POLYGON || type === EMF_RECORD.EMR_POLYGON16);
          break;
        }
        case EMF_RECORD.EMR_POLYBEZIER:
        case EMF_RECORD.EMR_POLYBEZIER16: {
          const count = record.u32(24);
          const pointOffset = 28;
          const pointSize = type === EMF_RECORD.EMR_POLYBEZIER16 ? 4 : 8;
          const points = readEmfPointArray(ctx, record, pointOffset, count, pointSize);
          addBezierPath(ctx, points, false);
          break;
        }
        case EMF_RECORD.EMR_POLYBEZIERTO:
        case EMF_RECORD.EMR_POLYBEZIERTO16: {
          const count = record.u32(24);
          const pointOffset = 28;
          const pointSize = type === EMF_RECORD.EMR_POLYBEZIERTO16 ? 4 : 8;
          const points = readEmfPointArray(ctx, record, pointOffset, count, pointSize);
          addBezierPath(ctx, points, true);
          break;
        }
        case EMF_RECORD.EMR_POLYLINETO:
        case EMF_RECORD.EMR_POLYLINETO16: {
          const count = record.u32(24);
          const pointOffset = 28;
          const pointSize = type === EMF_RECORD.EMR_POLYLINETO16 ? 4 : 8;
          const points = readEmfPointArray(ctx, record, pointOffset, count, pointSize);
          addPolyline(ctx, [{ ...ctx.state.currentPosition }, ...points], false);
          break;
        }
        case EMF_RECORD.EMR_POLYPOLYLINE:
        case EMF_RECORD.EMR_POLYPOLYGON:
        case EMF_RECORD.EMR_POLYPOLYLINE16:
        case EMF_RECORD.EMR_POLYPOLYGON16: {
          const polygonCount = record.u32(24);
          const pointCount = record.u32(28);
          const countsOffset = 32;
          const pointSize = type === EMF_RECORD.EMR_POLYPOLYLINE16 || type === EMF_RECORD.EMR_POLYPOLYGON16 ? 4 : 8;
          const pointsOffset = countsOffset + polygonCount * 4;
          if (!record.ensure(countsOffset, polygonCount * 4) || !record.ensure(pointsOffset, pointCount * pointSize))
            throw new errors_js_5.PptError("METAFILE_POINTS", "EMF polygon counts or points exceed their own record", cursor);
          if (polygonCount > limits.maxPoints)
            throw new errors_js_5.PptError("METAFILE_POINT_LIMIT", "EMF polygon count exceeds the configured limit", cursor);
          const counts = [];
          for (let i = 0; i < polygonCount; i += 1)
            counts.push(record.u32(countsOffset + i * 4));
          if (counts.reduce((sum, count) => sum + count, 0) !== pointCount)
            throw new errors_js_5.PptError("METAFILE_POINTS", "EMF polygon counts disagree with the declared point count", cursor);
          const points = readEmfPointArray(ctx, record, pointsOffset, pointCount, pointSize);
          let index = 0;
          const polygons = [], closed = type === EMF_RECORD.EMR_POLYPOLYGON || type === EMF_RECORD.EMR_POLYPOLYGON16;
          for (const count of counts) {
            if (closed)
              polygons.push(points.slice(index, index + count));
            else
              addPolyline(ctx, points.slice(index, index + count), false);
            index += count;
          }
          if (closed)
            addCompoundPolygons(ctx, polygons);
          break;
        }
        case EMF_RECORD.EMR_RECTANGLE:
          addRect(ctx, { left: record.i32(8), top: record.i32(12), right: record.i32(16), bottom: record.i32(20) });
          break;
        case EMF_RECORD.EMR_ELLIPSE:
          addEllipse(ctx, { left: record.i32(8), top: record.i32(12), right: record.i32(16), bottom: record.i32(20) });
          break;
        case EMF_RECORD.EMR_ROUNDRECT:
          addRect(ctx, { left: record.i32(8), top: record.i32(12), right: record.i32(16), bottom: record.i32(20) }, { x: record.i32(24), y: record.i32(28) });
          break;
        case EMF_RECORD.EMR_ARC:
        case EMF_RECORD.EMR_ARCTO:
        case EMF_RECORD.EMR_CHORD:
        case EMF_RECORD.EMR_PIE:
          addArc(ctx, { left: record.i32(8), top: record.i32(12), right: record.i32(16), bottom: record.i32(20) }, { x: record.i32(24), y: record.i32(28) }, { x: record.i32(32), y: record.i32(36) }, type === EMF_RECORD.EMR_ARCTO ? "arcTo" : type === EMF_RECORD.EMR_CHORD ? "chord" : type === EMF_RECORD.EMR_PIE ? "pie" : "arc");
          break;
        case EMF_RECORD.EMR_BEGINPATH:
          ctx.capturePath = true;
          ctx.pathData = [];
          ctx.pathPoints = [];
          ctx.pathBytes = 0;
          break;
        case EMF_RECORD.EMR_ENDPATH:
          ctx.capturePath = false;
          break;
        case EMF_RECORD.EMR_CLOSEFIGURE:
          closeCurrentPathFigure(ctx);
          break;
        case EMF_RECORD.EMR_FILLPATH:
          flushPath(ctx, fillOnlyAttributes(ctx));
          break;
        case EMF_RECORD.EMR_STROKEANDFILLPATH:
          flushPath(ctx, fillAttributes(ctx));
          break;
        case EMF_RECORD.EMR_STROKEPATH:
          flushPath(ctx, strokeAttributes(ctx, ctx.state.pen));
          break;
        case EMF_RECORD.EMR_SELECTCLIPPATH:
          if (!ctx.pathData.length || !clipPath(ctx, ctx.pathData.join(" "), record.u32(8)))
            ctx.unsupportedRecordTypes.add(type);
          ctx.capturePath = false;
          ctx.pathData = [];
          ctx.pathPoints = [];
          ctx.pathBytes = 0;
          break;
        case EMF_RECORD.EMR_CREATEPEN: {
          const index = record.u32(8);
          const style = record.u32(12);
          const width = record.i32(16);
          const color = colorRefToCss(record.u32(24));
          setObject(ctx, index, { kind: "pen", value: penStyleFromCode(style, width, color) });
          break;
        }
        case EMF_RECORD.EMR_CREATEBRUSHINDIRECT: {
          const index = record.u32(8);
          const style = record.u32(12);
          if (style > 2 || style === 2 && record.u32(20) > 5)
            ctx.unsupportedRecordTypes.add(type);
          const color = colorRefToCss(record.u32(16));
          setObject(ctx, index, { kind: "brush", value: brushStyleFromCode(style, color, record.u32(20)) });
          break;
        }
        case EMF_RECORD.EMR_EXTCREATEPEN: {
          const index = record.u32(8);
          const style = record.u32(28);
          const width = record.i32(32);
          const brushStyle = record.u32(36);
          if (brushStyle > 1 || (style & 15) > 5)
            ctx.unsupportedRecordTypes.add(type);
          const color = brushStyle === 1 ? "none" : colorRefToCss(record.u32(40));
          setObject(ctx, index, { kind: "pen", value: brushStyle === 1 ? { color, width, none: true } : penStyleFromCode(style, width, color) });
          break;
        }
        case EMF_RECORD.EMR_EXTCREATEFONTINDIRECTW: {
          const index = record.u32(8);
          const font = vector_font_js_1.readEmfFont(new binary_js_1.BinaryReader(record.slice(0, size)));
          if (font)
            setObject(ctx, index, { kind: "font", value: { ...font, charset: record.u8(35) } });
          break;
        }
        case EMF_RECORD.EMR_SELECTOBJECT:
          selectObject(ctx, record.u32(8));
          break;
        case EMF_RECORD.EMR_DELETEOBJECT: {
          const index = record.u32(8);
          deleteObject(ctx, index);
          break;
        }
        case EMF_RECORD.EMR_EXTTEXTOUTA: {
          const parsed = parseEmfText(ctx, record, false);
          if (parsed)
            addText(ctx, parsed.point, parsed.text, parsed.glyphIndices, parsed);
          break;
        }
        case EMF_RECORD.EMR_EXTTEXTOUTW: {
          const parsed = parseEmfText(ctx, record, true);
          if (parsed)
            addText(ctx, parsed.point, parsed.text, parsed.glyphIndices, parsed);
          break;
        }
        case EMF_RECORD.EMR_SMALLTEXTOUT: {
          const parsed = parseSmallEmfText(ctx, record);
          if (parsed)
            addText(ctx, parsed.point, parsed.text, parsed.glyphIndices, parsed);
          break;
        }
        case EMF_RECORD.EMR_STRETCHDIBITS:
          if (record.u32(68) !== 13369376 || record.u32(64) !== 0)
            ctx.unsupportedRecordTypes.add(type);
          addEmfStretchDibits(ctx, record);
          break;
        case EMF_RECORD.EMR_BITBLT:
        case EMF_RECORD.EMR_STRETCHBLT:
        case EMF_RECORD.EMR_ALPHABLEND:
          if (type !== EMF_RECORD.EMR_ALPHABLEND && record.u32(40) !== 13369376 || record.u32(80) !== 0)
            ctx.unsupportedRecordTypes.add(type);
          addEmfBltBitmap(ctx, record);
          break;
        default:
          ctx.unsupportedRecordTypes.add(type);
          break;
      }
      cursor += size;
    }
    return finalizeSvg(ctx, "image/emf");
  }
  function convertMetafileToSvg(mime, bytes, options = {}) {
    if (!bytes.length)
      return null;
    const limits = { ...DEFAULT_VECTOR_LIMITS, ...options };
    for (const value of Object.values(limits))
      if (!Number.isSafeInteger(value) || value < 0)
        throw new RangeError("Vector conversion limits must be nonnegative safe integers");
    limits.maxObjects = Math.min(limits.maxObjects, 65536);
    if (/image\/emf/i.test(mime))
      return parseEmf(bytes, limits);
    if (/image\/wmf/i.test(mime))
      return parseWmf(bytes, limits);
    return null;
  }
  exports_15("convertMetafileToSvg", convertMetafileToSvg);
  return {
    setters: [
      function(binary_js_1_1) {
        binary_js_1 = binary_js_1_1;
      },
      function(utils_js_3_1) {
        utils_js_3 = utils_js_3_1;
      },
      function(xml_text_js_1_1) {
        xml_text_js_1 = xml_text_js_1_1;
      },
      function(vector_font_js_1_1) {
        vector_font_js_1 = vector_font_js_1_1;
      },
      function(errors_js_5_1) {
        errors_js_5 = errors_js_5_1;
      },
      function(raster_js_1_1) {
        raster_js_1 = raster_js_1_1;
      }
    ],
    execute: function() {
      DEFAULT_VECTOR_LIMITS = { maxOutputBytes: 32 * 1024 * 1024, maxRecords: 1e5, maxPoints: 5e5, maxObjects: 65536, maxStateDepth: 1024 };
      DEFAULT_PEN = { color: "#000000", width: 1 };
      DEFAULT_BRUSH = { color: "#ffffff", none: true };
      DEFAULT_FONT = { family: "sans-serif", size: 12 };
      IDENTITY_MATRIX = { m11: 1, m12: 0, m21: 0, m22: 1, dx: 0, dy: 0 };
      PLACEABLE_WMF_KEY = 2596720087;
      WMF_HEADER_SIZE = 18;
      WMF_RECORD = {
        META_EOF: 0,
        META_SAVEDC: 30,
        META_RESTOREDC: 295,
        META_SETTEXTALIGN: 302,
        META_SETBKMODE: 258,
        META_SETPOLYFILLMODE: 262,
        META_SETBKCOLOR: 513,
        META_SETTEXTCOLOR: 521,
        META_SETWINDOWORG: 523,
        META_SETWINDOWEXT: 524,
        META_SETVIEWPORTORG: 525,
        META_SETVIEWPORTEXT: 526,
        META_OFFSETWINDOWORG: 527,
        META_OFFSETVIEWPORTORG: 529,
        META_LINETO: 531,
        META_MOVETO: 532,
        META_POLYGON: 804,
        META_POLYLINE: 805,
        META_TEXTOUT: 1313,
        META_POLYPOLYGON: 1336,
        META_ELLIPSE: 1048,
        META_RECTANGLE: 1051,
        META_ROUNDRECT: 1564,
        META_ARC: 2071,
        META_PIE: 2074,
        META_CHORD: 2096,
        META_INTERSECTCLIPRECT: 1046,
        META_EXCLUDECLIPRECT: 1045,
        META_EXTTEXTOUT: 2610,
        META_CREATEBRUSHINDIRECT: 764,
        META_CREATEPENINDIRECT: 762,
        META_CREATEFONTINDIRECT: 763,
        META_SELECTOBJECT: 301,
        META_DELETEOBJECT: 496
      };
      EMF_RECORD = {
        EMR_HEADER: 1,
        EMR_POLYBEZIER: 2,
        EMR_POLYGON: 3,
        EMR_POLYLINE: 4,
        EMR_POLYBEZIERTO: 5,
        EMR_POLYLINETO: 6,
        EMR_POLYPOLYLINE: 7,
        EMR_POLYPOLYGON: 8,
        EMR_SETWINDOWEXTEX: 9,
        EMR_SETWINDOWORGEX: 10,
        EMR_SETVIEWPORTEXTEX: 11,
        EMR_SETVIEWPORTORGEX: 12,
        EMR_EOF: 14,
        EMR_SETBKMODE: 18,
        EMR_SETPOLYFILLMODE: 19,
        EMR_SETTEXTALIGN: 22,
        EMR_SETTEXTCOLOR: 24,
        EMR_SETBKCOLOR: 25,
        EMR_MOVETOEX: 27,
        EMR_SAVEDC: 33,
        EMR_RESTOREDC: 34,
        EMR_SETWORLDTRANSFORM: 35,
        EMR_MODIFYWORLDTRANSFORM: 36,
        EMR_SELECTOBJECT: 37,
        EMR_CREATEPEN: 38,
        EMR_CREATEBRUSHINDIRECT: 39,
        EMR_DELETEOBJECT: 40,
        EMR_ELLIPSE: 42,
        EMR_RECTANGLE: 43,
        EMR_ROUNDRECT: 44,
        EMR_ARC: 45,
        EMR_CHORD: 46,
        EMR_PIE: 47,
        EMR_ARCTO: 55,
        EMR_SETARCDIRECTION: 57,
        EMR_INTERSECTCLIPRECT: 30,
        EMR_EXCLUDECLIPRECT: 29,
        EMR_BEGINPATH: 59,
        EMR_ENDPATH: 60,
        EMR_CLOSEFIGURE: 61,
        EMR_FILLPATH: 62,
        EMR_STROKEANDFILLPATH: 63,
        EMR_STROKEPATH: 64,
        EMR_SELECTCLIPPATH: 67,
        EMR_LINETO: 54,
        EMR_BITBLT: 76,
        EMR_STRETCHBLT: 77,
        EMR_STRETCHDIBITS: 81,
        EMR_EXTCREATEFONTINDIRECTW: 82,
        EMR_EXTTEXTOUTA: 83,
        EMR_EXTTEXTOUTW: 84,
        EMR_POLYBEZIER16: 85,
        EMR_POLYGON16: 86,
        EMR_POLYLINE16: 87,
        EMR_POLYBEZIERTO16: 88,
        EMR_POLYLINETO16: 89,
        EMR_POLYPOLYLINE16: 90,
        EMR_POLYPOLYGON16: 91,
        EMR_EXTCREATEPEN: 95,
        EMR_SMALLTEXTOUT: 108,
        EMR_ALPHABLEND: 114
      };
      WMF_MIN_BYTES = { 0: 6, 258: 8, 262: 8, 513: 10, 521: 10, 523: 10, 524: 10, 525: 10, 526: 10, 527: 10, 529: 10, 531: 10, 532: 10, 804: 8, 805: 8, 1313: 12, 1336: 8, 1048: 14, 1051: 14, 1564: 18, 764: 14, 762: 16, 763: 24, 301: 8, 496: 8 };
      EMF_MIN_BYTES = { 1: 88, 2: 28, 3: 28, 4: 28, 5: 28, 6: 28, 7: 32, 8: 32, 9: 16, 10: 16, 11: 16, 12: 16, 14: 20, 18: 12, 19: 12, 22: 12, 24: 12, 25: 12, 27: 16, 33: 8, 34: 12, 35: 32, 36: 36, 37: 12, 38: 28, 39: 24, 40: 12, 42: 24, 43: 24, 44: 32, 54: 16, 59: 8, 60: 8, 61: 8, 62: 24, 63: 24, 64: 24, 67: 12, 76: 100, 77: 108, 81: 80, 82: 104, 83: 76, 84: 76, 85: 28, 86: 28, 87: 28, 88: 28, 89: 28, 90: 32, 91: 32, 95: 52, 108: 36, 114: 108 };
      Object.assign(WMF_MIN_BYTES, { 30: 6, 295: 8, 302: 8, 2071: 22, 2074: 22, 2096: 22, 1045: 14, 1046: 14, 2610: 14 });
      Object.assign(EMF_MIN_BYTES, { 29: 24, 30: 24, 45: 40, 46: 40, 47: 40, 55: 40, 57: 12, 83: 60, 84: 60 });
      STOCK_OBJECT_BASE = 2147483648;
      STOCK_OBJECT = {
        WHITE_BRUSH: STOCK_OBJECT_BASE,
        LTGRAY_BRUSH: STOCK_OBJECT_BASE + 1,
        GRAY_BRUSH: STOCK_OBJECT_BASE + 2,
        DKGRAY_BRUSH: STOCK_OBJECT_BASE + 3,
        BLACK_BRUSH: STOCK_OBJECT_BASE + 4,
        NULL_BRUSH: STOCK_OBJECT_BASE + 5,
        WHITE_PEN: STOCK_OBJECT_BASE + 6,
        BLACK_PEN: STOCK_OBJECT_BASE + 7,
        NULL_PEN: STOCK_OBJECT_BASE + 8
      };
      MODIFY_WORLD_TRANSFORM = {
        MWT_IDENTITY: 1,
        MWT_LEFTMULTIPLY: 2,
        MWT_RIGHTMULTIPLY: 3,
        MWT_SET: 4
      };
    }
  };
});
System.register("core/pict", ["core/errors", "core/raster", "core/utils"], function(exports_16, context_16) {
  "use strict";
  var errors_js_6, raster_js_2, utils_js_4, f, legacyColors;
  var __moduleName = context_16 && context_16.id;
  function pictToSvg(bytes, options = {}) {
    const maxOutput = options.maxOutputBytes ?? 128 * 1024 * 1024, maxDecoded = options.maxDecodedBytes ?? 128 * 1024 * 1024, maxRecords = options.maxRecords ?? 2e5;
    if (![maxOutput, maxDecoded, maxRecords].every((x) => Number.isSafeInteger(x) && x > 0))
      throw new errors_js_6.PptError("INVALID_LIMIT", "Invalid PICT resource limit");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.length);
    let p = 0, records = 0, outputSize = 0;
    const need = (n) => {
      if (!Number.isSafeInteger(n) || n < 0 || p + n > bytes.length)
        throw new errors_js_6.PptError("PICT_TRUNCATED", "PICT operation exceeds its input", p);
    };
    const skip = (n) => {
      need(n);
      p += n;
    }, u8 = () => {
      need(1);
      return bytes[p++];
    }, i8 = () => {
      const v = u8();
      return v & 128 ? v - 256 : v;
    }, u16 = () => {
      need(2);
      const v = view.getUint16(p);
      p += 2;
      return v;
    }, i16 = () => {
      const v = u16();
      return v & 32768 ? v - 65536 : v;
    }, u32 = () => {
      need(4);
      const v = view.getUint32(p);
      p += 4;
      return v;
    };
    const point = () => {
      const y = i16(), x = i16();
      return { x, y };
    }, rect = () => {
      const top = i16(), left = i16(), bottom = i16(), right = i16();
      return { x: left, y: top, width: right - left, height: bottom - top };
    };
    const versionAt = (at) => at + 12 <= bytes.length && (bytes[at + 10] === 0 && bytes[at + 11] === 17 && bytes[at + 12] === 2 && bytes[at + 13] === 255 || bytes[at + 10] === 17 && bytes[at + 11] === 1);
    if (!versionAt(0)) {
      if (versionAt(512))
        p = 512;
      else
        throw new errors_js_6.PptError("PICT_HEADER", "PICT version header is missing");
    }
    const start = p;
    skip(2);
    const frame = rect();
    if (frame.width <= 0 || frame.height <= 0 || frame.width > 1e6 || frame.height > 1e6)
      throw new errors_js_6.PptError("PICT_SIZE", "Invalid PICT frame");
    const v2 = bytes[p] === 0;
    if (v2)
      skip(4);
    else
      skip(2);
    let fg = "#000000", bg = "#ffffff", pen = { x: 1, y: 1 }, oval = { x: 16, y: 16 }, loc = { x: 0, y: 0 }, textLoc = { x: 0, y: 0 }, origin = { x: 0, y: 0 }, font = "Arial", fontSize = 12, face = 0, mode = 8, clip = "", ended = false;
    const defs = [], body = [], unsupported = /* @__PURE__ */ new Set(), warnings = /* @__PURE__ */ new Set(), lastRect = /* @__PURE__ */ new Map();
    let lastPoly = [], lastRegion = "";
    const append = (value, target = body) => {
      outputSize += value.length;
      if (outputSize > maxOutput)
        throw new errors_js_6.PptError("LIMIT_ASSETS", "PICT SVG exceeds the configured output budget");
      target.push(value);
    };
    const rgb = () => `#${[u16(), u16(), u16()].map((v) => Math.round(v / 257).toString(16).padStart(2, "0")).join("")}`;
    const oldColor = () => legacyColors[u32()] ?? "#000000";
    const pattern = (data) => {
      if (data.every((x) => x === 255))
        return fg;
      if (data.every((x) => x === 0))
        return bg;
      const id = "pict-pattern-" + defs.length;
      let pixels2 = "";
      for (let y = 0; y < 8; y++)
        for (let x = 0; x < 8; x++)
          if (data[y] & 128 >> x)
            pixels2 += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
      append(`<pattern id="${id}" patternUnits="userSpaceOnUse" width="8" height="8"><rect width="8" height="8" fill="${bg}"/><g fill="${fg}">${pixels2}</g></pattern>`, defs);
      return `url(#${id})`;
    };
    let penPattern, fillPattern, bgPattern;
    const attrs = (verb) => {
      const fill = verb === 0 ? "none" : verb === 2 ? bgPattern ? pattern(bgPattern) : bg : verb === 4 ? fillPattern ? pattern(fillPattern) : fg : fg;
      if (verb === 3)
        warnings.add("PICT_INVERT_APPROXIMATION");
      if (mode !== 8 && mode !== 0)
        warnings.add("PICT_TRANSFER_MODE_APPROXIMATION");
      return `fill="${fill}" stroke="${verb === 0 ? penPattern ? pattern(penPattern) : fg : "none"}" stroke-width="${f(Math.max(pen.x, pen.y))}"`;
    };
    const draw = (content) => append(`<g${clip ? ` clip-path="url(#${clip})"` : ""} transform="translate(${origin.x} ${origin.y})">${content}</g>`);
    function region() {
      const begin = p, size = u16();
      if (size < 10 || size % 2)
        throw new errors_js_6.PptError("PICT_REGION", "Invalid QuickDraw region size", begin);
      need(size - 2);
      const end = begin + size, b = rect();
      if (size === 10)
        return `<rect x="${b.x}" y="${b.y}" width="${Math.max(0, b.width)}" height="${Math.max(0, b.height)}"/>`;
      const active = /* @__PURE__ */ new Set();
      let previousY = b.y, out2 = "", done = false;
      while (p < end) {
        const y = i16();
        if (y === 32767) {
          done = true;
          break;
        }
        if (y < previousY)
          throw new errors_js_6.PptError("PICT_REGION", "QuickDraw region rows are unordered", p);
        const edges = [...active].sort((a, b2) => a - b2);
        if (edges.length % 2)
          throw new errors_js_6.PptError("PICT_REGION", "QuickDraw region has unpaired scanline edges", p);
        for (let i = 0; i < edges.length; i += 2)
          if (y > previousY)
            out2 += `<rect x="${edges[i]}" y="${previousY}" width="${edges[i + 1] - edges[i]}" height="${y - previousY}"/>`;
        if (out2.length > maxOutput)
          throw new errors_js_6.PptError("LIMIT_ASSETS", "PICT region exceeds the output budget");
        let terminated = false;
        while (p < end) {
          const x = i16();
          if (x === 32767) {
            terminated = true;
            break;
          }
          if (active.has(x))
            active.delete(x);
          else
            active.add(x);
        }
        if (!terminated)
          throw new errors_js_6.PptError("PICT_REGION", "QuickDraw region row is unterminated", p);
        previousY = y;
      }
      if (!done || p !== end)
        throw new errors_js_6.PptError("PICT_REGION", "QuickDraw region terminator is invalid", p);
      return out2;
    }
    function pixmap(direct) {
      if (direct)
        skip(4);
      const rowWord = u16(), rowBytes = rowWord & 16383, bounds = rect(), indexed = !!(rowWord & 32768);
      let depth = 1, pack = 0, components = 1, palette = [bg, fg];
      if (indexed || direct) {
        skip(2);
        pack = u16();
        skip(12);
        const pixelType = u16();
        depth = u16();
        components = u16();
        const componentBits = u16();
        skip(12);
        if (![0, 16].includes(pixelType) || ![1, 2, 4, 8, 16, 32].includes(depth) || depth >= 16 && !([3, 4].includes(components) && [5, 8].includes(componentBits)))
          throw new errors_js_6.PptError("PICT_PIXMAP", "Unsupported QuickDraw pixel layout");
      }
      if (indexed && !direct) {
        skip(4);
        const flags = u16(), count = u16() + 1;
        if (count > 256)
          throw new errors_js_6.PptError("PICT_PALETTE", "QuickDraw palette is too large");
        palette = [];
        for (let i = 0; i < count; i++) {
          const key = u16(), value = rgb();
          palette[flags & 32768 ? i : key] = value;
        }
      }
      if (!rowBytes || bounds.width <= 0 || bounds.height <= 0 || rowBytes < Math.ceil(bounds.width * depth / 8) || bounds.width * bounds.height * 4 > maxDecoded || rowBytes * bounds.height > maxDecoded)
        throw new errors_js_6.PptError("LIMIT_ASSETS", "QuickDraw bitmap dimensions exceed the allocation budget");
      return { rowBytes, bounds, depth, pack, components, palette };
    }
    function pixels(info, packed) {
      const { rowBytes, bounds, depth, components, palette } = info;
      let pack = info.pack;
      if (!pack)
        pack = depth === 16 ? 3 : depth === 32 ? 4 : packed ? 4 : 1;
      if (rowBytes < 8)
        pack = 1;
      if (depth < 16)
        pack = packed && rowBytes >= 8 ? 4 : 1;
      if (![1, 2, 3, 4].includes(pack) || pack === 2 && depth !== 32 || pack === 3 && depth !== 16)
        throw new errors_js_6.PptError("PICT_PACKING", "Unsupported QuickDraw pixel packing");
      const rgba = new Uint8Array(bounds.width * bounds.height * 4);
      for (let y = 0; y < bounds.height; y++) {
        const expected = pack === 2 ? rowBytes / 4 * 3 : pack === 4 && depth === 32 ? rowBytes / 4 * components : rowBytes;
        if (!Number.isInteger(expected))
          throw new errors_js_6.PptError("PICT_PIXMAP", "Invalid row byte count");
        let row;
        if (pack === 1 || pack === 2) {
          need(expected);
          row = bytes.subarray(p, p + expected);
          p += expected;
        } else {
          const count = rowBytes > 250 ? u16() : u8();
          need(count);
          row = raster_js_2.unpackBits(bytes.subarray(p, p + count), expected, pack === 3 ? 2 : 1);
          p += count;
        }
        for (let x = 0; x < bounds.width; x++) {
          const q = (y * bounds.width + x) * 4;
          let r = 0, g = 0, b = 0, a = 255;
          if (depth === 32) {
            if (pack === 4) {
              const span = rowBytes / 4, offset = components === 4 ? span : 0;
              r = row[offset + x];
              g = row[offset + span + x];
              b = row[offset + span * 2 + x];
            } else {
              const pos = x * (pack === 2 ? 3 : 4) + (pack === 2 ? 0 : 1);
              r = row[pos];
              g = row[pos + 1];
              b = row[pos + 2];
            }
          } else if (depth === 16) {
            const v = row[x * 2] << 8 | row[x * 2 + 1];
            r = Math.round((v >>> 10 & 31) * 255 / 31);
            g = Math.round((v >>> 5 & 31) * 255 / 31);
            b = Math.round((v & 31) * 255 / 31);
          } else {
            const bit = x * depth, value = row[bit >>> 3] >>> 8 - depth - (bit & 7) & (1 << depth) - 1, c = palette[value];
            if (!c)
              throw new errors_js_6.PptError("PICT_PALETTE", "Bitmap references a missing palette entry");
            r = parseInt(c.slice(1, 3), 16);
            g = parseInt(c.slice(3, 5), 16);
            b = parseInt(c.slice(5, 7), 16);
          }
          rgba.set([r, g, b, a], q);
        }
      }
      return rgba;
    }
    function bitmap(op) {
      const info = pixmap(op === 154 || op === 155), src = rect(), dst = rect(), transfer = u16();
      let mask = "";
      if (op & 1)
        mask = region();
      const rgba = pixels(info, op >= 152);
      if (src.width <= 0 || src.height <= 0 || dst.width <= 0 || dst.height <= 0)
        return;
      if (transfer !== 0 && transfer !== 64) {
        unsupported.add(op);
        warnings.add("PICT_TRANSFER_MODE_APPROXIMATION");
      }
      const png = raster_js_2.encodeRgbaPng(info.bounds.width, info.bounds.height, rgba, maxOutput - outputSize), url = "data:image/png;base64," + utils_js_4.bytesToBase64(png);
      if (mask) {
        const id = "pict-mask-" + defs.length;
        append(`<clipPath id="${id}">${mask}</clipPath>`, defs);
        draw(`<g clip-path="url(#${id})"><svg x="${dst.x}" y="${dst.y}" width="${dst.width}" height="${dst.height}" viewBox="${src.x} ${src.y} ${src.width} ${src.height}" preserveAspectRatio="none"><image x="${info.bounds.x}" y="${info.bounds.y}" width="${info.bounds.width}" height="${info.bounds.height}" xlink:href="${url}"/></svg></g>`);
      } else
        draw(`<svg x="${dst.x}" y="${dst.y}" width="${dst.width}" height="${dst.height}" viewBox="${src.x} ${src.y} ${src.width} ${src.height}" preserveAspectRatio="none"><image x="${info.bounds.x}" y="${info.bounds.y}" width="${info.bounds.width}" height="${info.bounds.height}" xlink:href="${url}"/></svg>`);
    }
    const textDecoder = new TextDecoder("macintosh");
    while (p < bytes.length) {
      if (++records > maxRecords)
        throw new errors_js_6.PptError("LIMIT_RECORDS", "PICT operation count exceeds its configured budget");
      if (v2 && (p - start) % 2)
        skip(1);
      const opcode = v2 ? u16() : u8();
      if (opcode === 255) {
        ended = true;
        break;
      }
      switch (opcode) {
        case 0:
        case 28:
        case 30:
          break;
        case 1: {
          const r = region();
          clip = "pict-clip-" + defs.length;
          append(`<clipPath id="${clip}">${r}</clipPath>`, defs);
          break;
        }
        case 2:
        case 9:
        case 10: {
          need(8);
          const data = new Uint8Array(bytes.subarray(p, p + 8));
          p += 8;
          if (opcode === 2)
            bgPattern = data;
          else if (opcode === 9)
            penPattern = data;
          else
            fillPattern = data;
          break;
        }
        case 3: {
          const id = u16();
          font = { 0: "Chicago", 1: "Geneva", 2: "New York", 3: "Geneva", 4: "Monaco", 20: "Times", 21: "Helvetica", 22: "Courier" }[id] ?? "Arial";
          break;
        }
        case 4:
          face = u8();
          break;
        case 5:
        case 21:
        case 22:
          skip(2);
          unsupported.add(opcode);
          break;
        case 6:
          skip(4);
          unsupported.add(opcode);
          break;
        case 7:
          pen = point();
          break;
        case 8:
          mode = u16();
          break;
        case 11:
          oval = point();
          break;
        case 12: {
          origin.x += i16();
          origin.y += i16();
          warnings.add("PICT_ORIGIN_APPROXIMATION");
          break;
        }
        case 13:
          fontSize = u16();
          break;
        case 14:
          fg = oldColor();
          break;
        case 15:
          bg = oldColor();
          break;
        case 16:
          skip(8);
          unsupported.add(opcode);
          break;
        case 18:
        case 19:
        case 20: {
          const type = u16();
          skip(8);
          if (type === 2) {
            const value = rgb();
            if (opcode === 18)
              bg = value;
            else
              fg = value;
          } else if (type === 1) {
            const info = pixmap(false);
            pixels(info, true);
            unsupported.add(opcode);
          } else
            throw new errors_js_6.PptError("PICT_PATTERN", "Unsupported QuickDraw pixel pattern");
          break;
        }
        case 26:
          fg = rgb();
          break;
        case 27:
          bg = rgb();
          break;
        case 29:
        case 31:
          skip(6);
          unsupported.add(opcode);
          break;
        case 32:
        case 33:
        case 34:
        case 35: {
          if (opcode === 32 || opcode === 34)
            loc = point();
          const old = { ...loc };
          if (opcode <= 33)
            loc = point();
          else {
            loc.x += i8();
            loc.y += i8();
          }
          draw(`<path d="M${old.x} ${old.y} L${loc.x} ${loc.y}" ${attrs(0)}/>`);
          break;
        }
        case 40:
        case 41:
        case 42:
        case 43: {
          if (opcode === 40)
            textLoc = point();
          if (opcode === 41 || opcode === 43)
            textLoc.x += u8();
          if (opcode === 42 || opcode === 43)
            textLoc.y += u8();
          const len = u8();
          need(len);
          const text = textDecoder.decode(bytes.subarray(p, p + len));
          p += len;
          draw(`<text x="${textLoc.x}" y="${textLoc.y}" fill="${fg}" font-family="${utils_js_4.escapeXmlText(font)}" font-size="${fontSize}"${face & 1 ? ' font-weight="bold"' : ""}${face & 2 ? ' font-style="italic"' : ""}${face & 4 ? ' text-decoration="underline"' : ""}>${utils_js_4.escapeXmlText(text)}</text>`);
          textLoc.x += text.length * fontSize * 0.6;
          warnings.add("PICT_FONT_METRICS_APPROXIMATION");
          break;
        }
        case 44: {
          const size = u16(), end = p + size;
          need(size);
          skip(2);
          const n = u8();
          need(n);
          if (p + n > end)
            throw new errors_js_6.PptError("PICT_FONT", "PICT font name exceeds its record");
          font = textDecoder.decode(bytes.subarray(p, p + n));
          p = end;
          break;
        }
        case 144:
        case 145:
        case 152:
        case 153:
        case 154:
        case 155:
          bitmap(opcode);
          break;
        case 160:
          skip(2);
          break;
        case 161:
          skip(2);
          skip(u16());
          break;
        default: {
          if (opcode >= 48 && opcode < 112) {
            const group = opcode & 240, verb = opcode & 7, same = !!(opcode & 8);
            let box = same ? lastRect.get(group) : rect();
            if (box && !same)
              lastRect.set(group, box);
            let startAngle = 0, arc = 0;
            if (group === 96) {
              startAngle = i16();
              arc = i16();
            }
            if (!box || verb > 4)
              break;
            const b = box, a = attrs(verb);
            if (group === 80)
              draw(`<ellipse cx="${f(b.x + b.width / 2)}" cy="${f(b.y + b.height / 2)}" rx="${f(Math.max(0, b.width / 2))}" ry="${f(Math.max(0, b.height / 2))}" ${a}/>`);
            else if (group === 96) {
              if (arc === 0 || b.width <= 0 || b.height <= 0)
                break;
              const cx = b.x + b.width / 2, cy = b.y + b.height / 2, rx = b.width / 2, ry = b.height / 2;
              if (Math.abs(arc) >= 360)
                draw(`<ellipse cx="${f(cx)}" cy="${f(cy)}" rx="${f(rx)}" ry="${f(ry)}" ${a}/>`);
              else {
                const r1 = (startAngle - 90) * Math.PI / 180, r2 = (startAngle + arc - 90) * Math.PI / 180, x1 = cx + rx * Math.cos(r1), y1 = cy + ry * Math.sin(r1), x2 = cx + rx * Math.cos(r2), y2 = cy + ry * Math.sin(r2);
                draw(`<path d="${verb === 0 ? "" : `M${f(cx)} ${f(cy)} L`}${verb === 0 ? "M" : ""}${f(x1)} ${f(y1)} A${f(rx)} ${f(ry)} 0 ${Math.abs(arc) > 180 ? 1 : 0} ${arc >= 0 ? 1 : 0} ${f(x2)} ${f(y2)}${verb === 0 ? "" : " Z"}" ${a}/>`);
              }
            } else
              draw(`<rect x="${b.x}" y="${b.y}" width="${Math.max(0, b.width)}" height="${Math.max(0, b.height)}"${group === 64 ? ` rx="${f(oval.x / 2)}" ry="${f(oval.y / 2)}"` : ""} ${a}/>`);
          } else if (opcode >= 112 && opcode < 128) {
            const verb = opcode & 7;
            if (!(opcode & 8)) {
              const begin = p, size = u16();
              if (size < 10 || (size - 10) % 4)
                throw new errors_js_6.PptError("PICT_POLYGON", "Invalid QuickDraw polygon");
              need(size - 2);
              rect();
              lastPoly = [];
              while (p < begin + size)
                lastPoly.push(point());
            }
            if (verb <= 4 && lastPoly.length)
              draw(`<polygon points="${lastPoly.map((q) => q.x + "," + q.y).join(" ")}" ${attrs(verb)}/>`);
          } else if (opcode >= 128 && opcode < 144) {
            if (!(opcode & 8))
              lastRegion = region();
            const verb = opcode & 7;
            if (verb <= 4)
              draw(`<g ${attrs(verb)}>${lastRegion}</g>`);
          } else if (opcode === 3072)
            skip(24);
          else if (opcode >= 256 && opcode <= 32767)
            skip((opcode >>> 8) * 2);
          else if (opcode >= 32768 && opcode <= 33023 || opcode >= 176 && opcode <= 207) {
          } else if (opcode >= 33024 || opcode >= 208 && opcode <= 254) {
            skip(u32());
            if (opcode === 33280 || opcode === 33281)
              unsupported.add(opcode);
          } else if (opcode >= 36 && opcode <= 39 || opcode >= 45 && opcode <= 47 || opcode >= 146 && opcode <= 151 || opcode >= 156 && opcode <= 159 || opcode >= 162 && opcode <= 175) {
            skip(u16());
            if (opcode === 45 || opcode === 46)
              unsupported.add(opcode);
          } else
            throw new errors_js_6.PptError("PICT_OPCODE", `PICT opcode 0x${opcode.toString(16)} has no safely known length`, p);
        }
      }
    }
    if (!ended)
      throw new errors_js_6.PptError("PICT_END", "PICT end-of-picture opcode is missing");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${frame.width}" height="${frame.height}" viewBox="${frame.x} ${frame.y} ${frame.width} ${frame.height}"><defs>${defs.join("")}</defs>${body.join("")}</svg>`, out = new TextEncoder().encode(svg);
    if (out.length > maxOutput)
      throw new errors_js_6.PptError("LIMIT_ASSETS", "PICT SVG exceeds the configured byte budget");
    return { bytes: out, mimeType: "image/svg+xml", width: frame.width, height: frame.height, unsupportedOpcodes: [...unsupported], warnings: [...warnings] };
  }
  exports_16("pictToSvg", pictToSvg);
  return {
    setters: [
      function(errors_js_6_1) {
        errors_js_6 = errors_js_6_1;
      },
      function(raster_js_2_1) {
        raster_js_2 = raster_js_2_1;
      },
      function(utils_js_4_1) {
        utils_js_4 = utils_js_4_1;
      }
    ],
    execute: function() {
      f = (v) => String(Math.round(v * 1e4) / 1e4);
      legacyColors = { 30: "#ffffff", 33: "#000000", 69: "#ffff00", 137: "#ff00ff", 205: "#ff0000", 273: "#00ffff", 341: "#00ff00", 409: "#0000ff" };
    }
  };
});
System.register("core/tiff", ["core/errors", "core/inflate", "core/raster"], function(exports_17, context_17) {
  "use strict";
  var errors_js_7, inflate_js_1, raster_js_3;
  var __moduleName = context_17 && context_17.id;
  function decodeTiffLzw(bytes, expected) {
    if (!Number.isSafeInteger(expected) || expected < 0 || expected > 256 * 1024 * 1024)
      throw new errors_js_7.PptError("LIMIT_ASSETS", "LZW output exceeds the raster limit");
    const out = new Uint8Array(expected), prefix = new Int16Array(4096), suffix = new Uint8Array(4096), stack = new Uint8Array(4097);
    let bit = 0, bits = 9, next = 258, previous = -1, q = 0, ended = false;
    const code = () => {
      if (bit + bits > bytes.length * 8)
        throw new errors_js_7.PptError("TIFF_LZW", "Truncated LZW code");
      let value = 0;
      for (let i = 0; i < bits; i++, bit++)
        value = value << 1 | bytes[bit >>> 3] >> 7 - (bit & 7) & 1;
      return value;
    };
    const expand = (value) => {
      let length = 0;
      while (value >= 256) {
        if (value >= next || length >= 4096)
          throw new errors_js_7.PptError("TIFF_LZW", "Invalid LZW dictionary reference");
        stack[length++] = suffix[value];
        value = prefix[value];
      }
      stack[length++] = value;
      return length;
    };
    if (code() !== 256)
      throw new errors_js_7.PptError("TIFF_LZW", "LZW strip must start with a clear code");
    while (bit + bits <= bytes.length * 8) {
      const value = code();
      if (value === 257) {
        ended = true;
        break;
      }
      if (value === 256) {
        bits = 9;
        next = 258;
        previous = -1;
        continue;
      }
      if (value > next || value === next && previous < 0)
        throw new errors_js_7.PptError("TIFF_LZW", "Invalid LZW code");
      const special = value === next, length = expand(special ? previous : value), first = stack[length - 1];
      if (q + length + (special ? 1 : 0) > expected)
        throw new errors_js_7.PptError("TIFF_LZW", "LZW expands beyond the declared strip");
      for (let i = length - 1; i >= 0; i--)
        out[q++] = stack[i];
      if (special)
        out[q++] = first;
      if (previous >= 0 && next < 4096) {
        prefix[next] = previous;
        suffix[next] = first;
        next++;
        if (next === (1 << bits) - 1 && bits < 12)
          bits++;
      }
      previous = value;
    }
    if (!ended || q !== expected)
      throw new errors_js_7.PptError("TIFF_LZW", "LZW end marker or decoded size is invalid");
    return out;
  }
  exports_17("decodeTiffLzw", decodeTiffLzw);
  function decodeTiff(bytes, options = {}) {
    const limit = options.maxDecodedBytes ?? 128 * 1024 * 1024;
    if (!Number.isSafeInteger(limit) || limit < 1)
      throw new errors_js_7.PptError("INVALID_LIMIT", "Invalid TIFF byte budget");
    if (bytes.length < 8)
      throw new errors_js_7.PptError("TIFF_HEADER", "Truncated TIFF header");
    const little = bytes[0] === 73 && bytes[1] === 73;
    if (!little && !(bytes[0] === 77 && bytes[1] === 77))
      throw new errors_js_7.PptError("TIFF_HEADER", "TIFF must start with II or MM");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.length);
    const need = (at2, size) => {
      if (!Number.isSafeInteger(at2) || !Number.isSafeInteger(size) || at2 < 0 || size < 0 || at2 + size > bytes.length)
        throw new errors_js_7.PptError("TIFF_BOUNDS", "TIFF field points outside the image", at2);
    };
    const u16 = (at2) => {
      need(at2, 2);
      return view.getUint16(at2, little);
    }, u32 = (at2) => {
      need(at2, 4);
      return view.getUint32(at2, little);
    };
    if (u16(2) !== 42)
      throw new errors_js_7.PptError("TIFF_VERSION", "BigTIFF and unknown TIFF versions are not supported");
    const offsets = [], seen = /* @__PURE__ */ new Set();
    let at = u32(4);
    while (at) {
      if (seen.has(at))
        throw new errors_js_7.PptError("TIFF_IFD_CYCLE", "Cycle in TIFF image directories", at);
      if (offsets.length >= 4096)
        throw new errors_js_7.PptError("LIMIT_ASSETS", "Too many TIFF image directories");
      seen.add(at);
      offsets.push(at);
      const count = u16(at);
      need(at + 2, count * 12 + 4);
      at = u32(at + 2 + count * 12);
    }
    const page = options.page ?? 0;
    if (!Number.isInteger(page) || page < 0 || page >= offsets.length)
      throw new errors_js_7.PptError("TIFF_PAGE", "TIFF page is out of range");
    at = offsets[page];
    const tags = /* @__PURE__ */ new Map(), fieldSizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8];
    for (let i = 0, count = u16(at); i < count; i++) {
      const p = at + 2 + i * 12, tag = u16(p), type = u16(p + 2), count2 = u32(p + 4), unit = fieldSizes[type];
      if (!unit)
        continue;
      const size = count2 * unit, base = size <= 4 ? p + 8 : u32(p + 8);
      need(base, size);
      if (![256, 257, 258, 259, 262, 266, 273, 274, 277, 278, 279, 284, 317, 320, 322, 323, 324, 325, 338, 339].includes(tag))
        continue;
      if (count2 > Math.min(1e6, limit / 8))
        throw new errors_js_7.PptError("LIMIT_ASSETS", "TIFF numeric field exceeds the metadata budget");
      if (![1, 3, 4].includes(type))
        throw new errors_js_7.PptError("TIFF_FIELD", "Unsupported type for a required numeric TIFF field", p);
      if (tags.has(tag))
        throw new errors_js_7.PptError("TIFF_FIELD", "Duplicate required TIFF field", p);
      tags.set(tag, Array.from({ length: count2 }, (_, j) => type === 1 ? bytes[base + j] : type === 3 ? u16(base + j * 2) : u32(base + j * 4)));
    }
    const get = (id, fallback = 0) => tags.get(id)?.[0] ?? fallback;
    const width = get(256), height = get(257), samples = get(277, 1), bits = tags.get(258) ?? [1], photo = get(262), compression = get(259, 1), planar = get(284, 1), predictor = get(317, 1), orientation = get(274, 1), fillOrder = get(266, 1), warnings = [];
    if (!width || !height || width > 1e6 || height > 1e6 || samples < 1 || samples > 8 || width * height * (4 + samples * 2) > limit)
      throw new errors_js_7.PptError("LIMIT_ASSETS", "TIFF raster exceeds the configured allocation budget");
    if (bits.length !== 1 && bits.length !== samples || bits.some((b) => ![1, 2, 4, 8, 16].includes(b)) || bits.some((b) => b !== bits[0]))
      throw new errors_js_7.PptError("TIFF_BITS", "Unsupported mixed or non-integer TIFF component depth");
    if (![0, 1, 2, 3, 5].includes(photo))
      throw new errors_js_7.PptError("TIFF_COLORSPACE", `TIFF photometric interpretation ${photo} is not supported`);
    if (photo === 2 && samples < 3 || photo === 5 && samples < 4 || photo === 3 && bits[0] > 8)
      throw new errors_js_7.PptError("TIFF_SAMPLES", "Invalid TIFF component count or palette depth");
    if (![1, 2].includes(planar) || ![1, 2].includes(predictor) || ![1, 2].includes(fillOrder) || orientation < 1 || orientation > 8 || (tags.get(339) ?? [1]).some((x) => x !== 1))
      throw new errors_js_7.PptError("TIFF_LAYOUT", "Unsupported TIFF planar, predictor, orientation, or sample layout");
    if (![1, 5, 8, 32946, 32773].includes(compression))
      throw new errors_js_7.PptError("TIFF_COMPRESSION", `TIFF compression ${compression} is not implemented`);
    const depth = bits[0], components = new Uint16Array(width * height * samples), tiled = tags.has(324), bw = tiled ? get(322) : width, bh = tiled ? get(323) : Math.min(height, get(278, height)), positions = tags.get(tiled ? 324 : 273), counts = tags.get(tiled ? 325 : 279);
    if (!bw || !bh || !positions || !counts || positions.length !== counts.length)
      throw new errors_js_7.PptError("TIFF_STRIPS", "Missing or inconsistent TIFF strips/tiles");
    const nx = Math.ceil(width / bw), ny = Math.ceil(height / bh), perPlane = nx * ny, planes = planar === 2 ? samples : 1;
    if (perPlane * planes !== positions.length)
      throw new errors_js_7.PptError("TIFF_STRIPS", "TIFF strip/tile count does not match dimensions");
    const channels = planar === 2 ? 1 : samples, rowBytes = Math.ceil(bw * channels * depth / 8);
    for (let block = 0; block < positions.length; block++) {
      const plane = Math.floor(block / perPlane), index = block % perPlane, x0 = index % nx * bw, y0 = Math.floor(index / nx) * bh, rows = tiled ? bh : Math.min(bh, height - y0), expected = rowBytes * rows;
      if (expected > limit)
        throw new errors_js_7.PptError("LIMIT_ASSETS", "TIFF tile/strip exceeds the raster budget");
      need(positions[block], counts[block]);
      let raw = bytes.subarray(positions[block], positions[block] + counts[block]);
      if (compression === 1) {
        if (raw.length !== expected)
          throw new errors_js_7.PptError("TIFF_STRIPS", "Uncompressed TIFF strip has an inconsistent byte count");
        raw = new Uint8Array(raw);
      } else if (compression === 32773)
        raw = raster_js_3.unpackBits(raw, expected);
      else if (compression === 5)
        raw = decodeTiffLzw(raw, expected);
      else {
        const decoded = inflate_js_1.inflateZlib(raw, expected, expected);
        if (!decoded || decoded.length !== expected)
          throw new errors_js_7.PptError("TIFF_DEFLATE", "Invalid Deflate TIFF strip");
        raw = decoded;
      }
      if (fillOrder === 2) {
        for (let k = 0; k < raw.length; k++) {
          let b = raw[k];
          b = (b & 85) << 1 | b >>> 1 & 85;
          b = (b & 51) << 2 | b >>> 2 & 51;
          raw[k] = (b & 15) << 4 | b >>> 4;
        }
      }
      const rv = new DataView(raw.buffer, raw.byteOffset, raw.length), mask = 2 ** depth - 1, previous = new Uint16Array(channels);
      for (let y = 0; y < rows; y++) {
        previous.fill(0);
        for (let x = 0; x < bw; x++)
          for (let c = 0; c < channels; c++) {
            const bpos = (x * channels + c) * depth, byte = y * rowBytes + (bpos >>> 3);
            let value = depth === 16 ? rv.getUint16(byte, little) : depth === 8 ? raw[byte] : raw[byte] >>> 8 - depth - (bpos & 7) & mask;
            if (predictor === 2) {
              value = value + previous[c] & mask;
              previous[c] = value;
            }
            if (x + x0 < width && y + y0 < height)
              components[((y + y0) * width + x + x0) * samples + (planar === 2 ? plane : c)] = value;
          }
      }
    }
    const rotated = orientation >= 5, outWidth = rotated ? height : width, outHeight = rotated ? width : height, rgba = new Uint8Array(width * height * 4), max = 2 ** depth - 1, palette = tags.get(320), baseSamples = photo === 2 ? 3 : photo === 5 ? 4 : 1, extra = tags.get(338) ?? [], alphaIndex = extra.findIndex((v) => v === 1 || v === 2), hasAlpha = alphaIndex >= 0 && baseSamples + alphaIndex < samples;
    if (photo === 3 && (!palette || palette.length !== 3 * 2 ** depth))
      throw new errors_js_7.PptError("TIFF_PALETTE", "TIFF color table is missing or incomplete");
    if (photo === 5)
      warnings.push("TIFF_CMYK_APPROXIMATION");
    for (let y = 0; y < height; y++)
      for (let x = 0; x < width; x++) {
        let ox = x, oy = y;
        switch (orientation) {
          case 2:
            ox = width - 1 - x;
            break;
          case 3:
            ox = width - 1 - x;
            oy = height - 1 - y;
            break;
          case 4:
            oy = height - 1 - y;
            break;
          case 5:
            ox = y;
            oy = x;
            break;
          case 6:
            ox = height - 1 - y;
            oy = x;
            break;
          case 7:
            ox = height - 1 - y;
            oy = width - 1 - x;
            break;
          case 8:
            ox = y;
            oy = width - 1 - x;
            break;
        }
        const p = (y * width + x) * samples, q = (oy * outWidth + ox) * 4, val = (c) => components[p + c] / max * 255;
        let r = 0, g = 0, b = 0;
        if (photo === 2) {
          r = val(0);
          g = val(1);
          b = val(2);
        } else if (photo === 5) {
          const k = val(3) / 255;
          r = (255 - val(0)) * (1 - k);
          g = (255 - val(1)) * (1 - k);
          b = (255 - val(2)) * (1 - k);
        } else if (photo === 3) {
          const index = components[p], size = 2 ** depth;
          r = palette[index] >>> 8;
          g = palette[index + size] >>> 8;
          b = palette[index + size * 2] >>> 8;
        } else
          r = g = b = photo === 0 ? 255 - val(0) : val(0);
        const a = hasAlpha ? val(baseSamples + alphaIndex) : 255;
        if (hasAlpha && extra[alphaIndex] === 1) {
          const alpha = components[p + baseSamples + alphaIndex];
          if (photo === 2) {
            r = alpha ? components[p] / alpha * 255 : 0;
            g = alpha ? components[p + 1] / alpha * 255 : 0;
            b = alpha ? components[p + 2] / alpha * 255 : 0;
          } else {
            r = a ? r * 255 / a : 0;
            g = a ? g * 255 / a : 0;
            b = a ? b * 255 / a : 0;
          }
        }
        rgba.set([Math.round(Math.min(255, r)), Math.round(Math.min(255, g)), Math.round(Math.min(255, b)), Math.round(a)], q);
      }
    if (offsets.length > 1)
      warnings.push("TIFF_MULTIPAGE");
    return { width: outWidth, height: outHeight, rgba, pageCount: offsets.length, warnings };
  }
  exports_17("decodeTiff", decodeTiff);
  function tiffToPng(bytes, options = {}) {
    const { rgba, ...image } = decodeTiff(bytes, options);
    return { ...image, bytes: raster_js_3.encodeRgbaPng(image.width, image.height, rgba, options.maxOutputBytes), mimeType: "image/png" };
  }
  exports_17("tiffToPng", tiffToPng);
  return {
    setters: [
      function(errors_js_7_1) {
        errors_js_7 = errors_js_7_1;
      },
      function(inflate_js_1_1) {
        inflate_js_1 = inflate_js_1_1;
      },
      function(raster_js_3_1) {
        raster_js_3 = raster_js_3_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("ppt/pictures", ["core/errors", "core/inflate", "core/vector", "core/pict", "core/tiff", "ppt/records", "ppt/constants"], function(exports_18, context_18) {
  "use strict";
  var errors_js_8, inflate_js_2, vector_js_1, pict_js_1, tiff_js_1, records_js_3, constants_js_2;
  var __moduleName = context_18 && context_18.id;
  function header(bytes, offset, end = bytes.length) {
    if (!Number.isSafeInteger(offset) || offset < 0 || offset + 8 > end)
      throw new errors_js_8.PptError("BLIP_HEADER", "Truncated BLIP header", offset);
    const view = new DataView(bytes.buffer, bytes.byteOffset + offset, 8);
    const vi = view.getUint16(0, true), length = view.getUint32(4, true);
    if (offset + 8 + length > end)
      throw new errors_js_8.PptError("BLIP_LENGTH", "BLIP exceeds its containing stream", offset);
    return { offset, dataOffset: offset + 8, end: offset + 8 + length, length, type: view.getUint16(2, true), version: vi & 15, instance: vi >>> 4, children: [] };
  }
  function dibToBmp(bytes) {
    if (bytes.length < 12)
      throw new errors_js_8.PptError("DIB_HEADER", "Truncated DIB");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const size = view.getUint32(0, true);
    if (size !== 12 && size < 40 || size > bytes.length)
      throw new errors_js_8.PptError("DIB_HEADER", "Invalid DIB header size");
    const bits = view.getUint16(size === 12 ? 10 : 14, true);
    const compression = size >= 40 ? view.getUint32(16, true) : 0;
    const used = size >= 40 ? view.getUint32(32, true) : 0;
    const palette = (used || (bits <= 8 ? 2 ** bits : 0)) * (size === 12 ? 3 : 4);
    const masks = size === 40 && (compression === 3 || compression === 6) ? compression === 6 ? 16 : 12 : 0;
    const pixelOffset = 14 + size + palette + masks;
    if (pixelOffset > bytes.length + 14)
      throw new errors_js_8.PptError("DIB_PALETTE", "DIB palette exceeds the image");
    const out = new Uint8Array(bytes.length + 14), dest = new DataView(out.buffer);
    dest.setUint16(0, 19778, true);
    dest.setUint32(2, out.length, true);
    dest.setUint32(10, pixelOffset, true);
    out.set(bytes, 14);
    return out;
  }
  exports_18("dibToBmp", dibToBmp);
  function pngDimensions(bytes) {
    if (bytes.length < 24 || bytes[0] !== 137 || bytes[1] !== 80 || bytes[2] !== 78 || bytes[3] !== 71)
      return {};
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  function decodeBlip(bytes, record, id, diagnostics, limit) {
    const base = record.dataOffset;
    const uidBytes = record.instance & 1 ? 32 : 16;
    if (record.length < uidBytes)
      throw new errors_js_8.PptError("BLIP_UID", "Truncated BLIP identifier", record.offset);
    let data, mimeType, unsupported = false, width, height;
    if (record.type >= 61466 && record.type <= 61468) {
      if (record.length < uidBytes + 34)
        throw new errors_js_8.PptError("METAFILE_HEADER", "Truncated OfficeArt metafile header", record.offset);
      const view = new DataView(bytes.buffer, bytes.byteOffset + base + uidBytes, 34);
      const expected = view.getUint32(0, true), stored = view.getUint32(28, true), compression = view.getUint8(32);
      if (expected > limit || stored > limit)
        throw new errors_js_8.PptError("LIMIT_ASSETS", "Metafile exceeds the asset byte budget", record.offset);
      if (base + uidBytes + 34 + stored > record.end)
        throw new errors_js_8.PptError("METAFILE_LENGTH", "Metafile payload exceeds the BLIP", record.offset);
      const raw = bytes.subarray(base + uidBytes + 34, base + uidBytes + 34 + stored);
      if (compression === 0) {
        const inflated = inflate_js_2.inflateZlib(raw, expected);
        if (!inflated || inflated.length !== expected)
          throw new errors_js_8.PptError("METAFILE_DEFLATE", "Cannot decompress OfficeArt metafile", record.offset);
        data = inflated;
      } else if (compression === 254) {
        if (raw.byteLength !== expected)
          throw new errors_js_8.PptError("METAFILE_LENGTH", "Uncompressed metafile length differs from its declared size", record.offset);
        data = raw;
      } else
        throw new errors_js_8.PptError("METAFILE_COMPRESSION", `Unsupported metafile compression ${compression}`, record.offset);
      width = Math.abs(view.getInt32(20, true)) / 9525;
      height = Math.abs(view.getInt32(24, true)) / 9525;
      mimeType = record.type === 61466 ? "image/emf" : record.type === 61467 ? "image/wmf" : "image/x-pict";
      if (record.type === 61468) {
        try {
          const pict = pict_js_1.pictToSvg(data, { maxOutputBytes: limit, maxDecodedBytes: limit });
          data = pict.bytes;
          mimeType = pict.mimeType;
          width = pict.width;
          height = pict.height;
          if (pict.unsupportedOpcodes.length || pict.warnings.length)
            diagnostics.push({ code: "PICT_PARTIAL", severity: "warning", message: "PICT preview contains operations that require a documented approximation or are preserved without display", offset: record.offset, details: { assetId: id, opcodes: pict.unsupportedOpcodes, warnings: pict.warnings } });
        } catch (error) {
          if (error instanceof errors_js_8.PptError && error.code.startsWith("LIMIT_"))
            throw error;
          unsupported = true;
          diagnostics.push({ code: error instanceof errors_js_8.PptError ? error.code : "PICT_INVALID", severity: "warning", message: error instanceof Error ? error.message : String(error), offset: record.offset, details: { assetId: id } });
        }
      }
      const converted = record.type === 61468 ? null : vector_js_1.convertMetafileToSvg(mimeType, data, { maxOutputBytes: limit });
      if (converted) {
        data = converted.bytes;
        mimeType = "image/svg+xml";
        width = converted.width;
        height = converted.height;
        if (converted.unresolvedGlyphRuns)
          diagnostics.push({ code: "METAFILE_GLYPHS", severity: "warning", message: "Metafile contains glyph-index text whose source font cannot be resolved", offset: record.offset, details: { assetId: id, runs: converted.unresolvedGlyphRuns } });
        if (converted.unsupportedRecordTypes.length)
          diagnostics.push({ code: "METAFILE_PARTIAL", severity: "warning", message: "Metafile preview includes the supported drawing subset; some records require an unsupported or approximated operation", offset: record.offset, details: { assetId: id, sourceMime: converted.sourceMime, recordTypes: converted.unsupportedRecordTypes } });
      } else if (record.type !== 61468)
        unsupported = true;
    } else {
      if (record.length < uidBytes + 1)
        throw new errors_js_8.PptError("BLIP_DATA", "Truncated raster BLIP", record.offset);
      data = bytes.subarray(base + uidBytes + 1, record.end);
      if (data.byteLength + (record.type === 61471 ? 14 : 0) > limit)
        throw new errors_js_8.PptError("LIMIT_ASSETS", "Raster image exceeds the asset byte budget", record.offset);
      switch (record.type) {
        case 61469:
        case 61482:
          mimeType = "image/jpeg";
          break;
        case 61470:
          mimeType = "image/png";
          ({ width, height } = pngDimensions(data));
          break;
        case 61471:
          data = dibToBmp(data);
          mimeType = "image/bmp";
          break;
        case 61481:
          mimeType = "image/tiff";
          try {
            const tiff = tiff_js_1.tiffToPng(data, { maxOutputBytes: limit, maxDecodedBytes: limit });
            data = tiff.bytes;
            mimeType = tiff.mimeType;
            width = tiff.width;
            height = tiff.height;
            for (const code of tiff.warnings)
              diagnostics.push({ code, severity: "warning", message: code === "TIFF_MULTIPAGE" ? "The first TIFF image directory is displayed; remaining pages stay in the source package" : "TIFF CMYK colors are converted without an ICC color-management engine", offset: record.offset, details: { assetId: id, pages: tiff.pageCount } });
          } catch (error) {
            if (error instanceof errors_js_8.PptError && error.code.startsWith("LIMIT_"))
              throw error;
            unsupported = true;
            diagnostics.push({ code: error instanceof errors_js_8.PptError ? error.code : "TIFF_INVALID", severity: "warning", message: error instanceof Error ? error.message : String(error), offset: record.offset, details: { assetId: id } });
          }
          break;
        default:
          mimeType = "application/octet-stream";
          unsupported = true;
      }
    }
    if (data.byteLength > limit)
      throw new errors_js_8.PptError("LIMIT_ASSETS", "Decoded image exceeds the asset byte budget", record.offset);
    if (unsupported)
      diagnostics.push({ code: "IMAGE_FORMAT_UNSUPPORTED", severity: "warning", message: `Image ${mimeType} is preserved but not browser-renderable`, offset: record.offset, details: { assetId: id } });
    return { id, mimeType, bytes: data, width, height, sourceOffset: record.offset, unsupported };
  }
  function parseInlinePicture(bytes, offset, length, id, diagnostics, remainingBytes) {
    return decodeBlip(bytes, header(bytes, offset, offset + length), id, diagnostics, remainingBytes);
  }
  exports_18("parseInlinePicture", parseInlinePicture);
  function parsePictures(drawingGroup, documentBytes, picturesBytes, diagnostics, limits) {
    const assets = [], pictureIds = /* @__PURE__ */ new Map();
    if (!drawingGroup)
      return { assets, pictureIds };
    const ctx = { bytes: documentBytes, diagnostics, limits, count: 0 };
    const roots = drawingGroup.children.length ? drawingGroup.children : records_js_3.readRecords(ctx, drawingGroup.dataOffset, drawingGroup.end);
    const store = [...records_js_3.walkRecords(roots)].find((r) => r.type === constants_js_2.RT.OfficeArtBStoreContainer);
    if (!store)
      return { assets, pictureIds };
    const seen = /* @__PURE__ */ new Map();
    let budget = limits.maxAssetBytes;
    for (let i = 0; i < store.children.length; i++) {
      const entry = store.children[i];
      let record = entry, bytes = documentBytes, key = `document:${entry.offset}`;
      try {
        if (entry.type === constants_js_2.RT.OfficeArtFBSE) {
          if (entry.length < 36)
            throw new errors_js_8.PptError("FBSE_HEADER", "Truncated File BLIP Store Entry", entry.offset);
          const view = new DataView(documentBytes.buffer, documentBytes.byteOffset + entry.dataOffset, entry.length);
          if (!view.getUint32(24, true))
            continue;
          const embedded = entry.dataOffset + 36 + view.getUint8(33), delayed = view.getUint32(28, true);
          if (embedded + 8 <= entry.end)
            record = header(documentBytes, embedded, entry.end);
          else if (delayed !== 4294967295) {
            bytes = picturesBytes;
            record = header(bytes, delayed);
            key = `pictures:${delayed}`;
          } else {
            diagnostics.push({ code: "BLIP_MISSING", severity: "warning", message: "Referenced image has no embedded or delayed BLIP", offset: entry.offset });
            continue;
          }
        }
        const duplicate = seen.get(key);
        if (duplicate) {
          pictureIds.set(i + 1, duplicate);
          continue;
        }
        const id = `image-${i + 1}`, asset = decodeBlip(bytes, record, id, diagnostics, budget);
        budget -= asset.bytes.length;
        assets.push(asset);
        pictureIds.set(i + 1, id);
        seen.set(key, id);
      } catch (error) {
        if (error instanceof errors_js_8.PptError && error.code === "LIMIT_ASSETS")
          throw error;
        diagnostics.push({ code: error instanceof errors_js_8.PptError ? error.code : "BLIP_INVALID", severity: "warning", message: error instanceof Error ? error.message : String(error), offset: entry.offset, details: { pictureIndex: i + 1 } });
      }
    }
    return { assets, pictureIds };
  }
  exports_18("parsePictures", parsePictures);
  return {
    setters: [
      function(errors_js_8_1) {
        errors_js_8 = errors_js_8_1;
      },
      function(inflate_js_2_1) {
        inflate_js_2 = inflate_js_2_1;
      },
      function(vector_js_1_1) {
        vector_js_1 = vector_js_1_1;
      },
      function(pict_js_1_1) {
        pict_js_1 = pict_js_1_1;
      },
      function(tiff_js_1_1) {
        tiff_js_1 = tiff_js_1_1;
      },
      function(records_js_3_1) {
        records_js_3 = records_js_3_1;
      },
      function(constants_js_2_1) {
        constants_js_2 = constants_js_2_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("ppt/drawing", ["core/errors", "core/utils", "ppt/constants", "ppt/records", "ppt/geometry", "ppt/text", "ppt/pictures"], function(exports_19, context_19) {
  "use strict";
  var errors_js_9, utils_js_5, constants_js_3, records_js_4, geometry_js_1, text_js_1, pictures_js_1, boolProps, dataView, fixed, colorIndex, clamp, utf16, assetBudgets, defaultComplexProperties, shapeComplexProperties, arrayElementSizes;
  var __moduleName = context_19 && context_19.id;
  function warn(ctx, code, message, record, shapeId) {
    ctx.diagnostics.push({ code, severity: "warning", message, offset: record.offset, shapeId });
  }
  function mergeProperty(id, base, next) {
    if (base === void 0 || !boolProps.has(id))
      return next;
    const used = next >>> 16;
    return (base & 65535 & ~used | next & used | (base >>> 16 | used) << 16) >>> 0;
  }
  function readProperties(record, bytes, diagnostics) {
    const values = /* @__PURE__ */ new Map(), complex = /* @__PURE__ */ new Map();
    const count = record.instance;
    if (count * 6 > record.length) {
      diagnostics.push({ code: "FOPT_LENGTH", severity: "warning", message: "Property entries exceed FOPT payload", offset: record.offset });
      return { values, complex };
    }
    const view = dataView(bytes, record);
    let extra = record.dataOffset + count * 6;
    let declared = 0;
    for (let i = 0; i < count; i++)
      if (view.getUint16(i * 6, true) & 32768)
        declared += view.getUint32(i * 6 + 2, true);
    let spare = record.end - extra - declared;
    const recovered = [];
    for (let i = 0; i < count; i++) {
      const op = view.getUint16(i * 6, true), id = op & 16383, value = view.getUint32(i * 6 + 2, true);
      values.set(id, mergeProperty(id, values.get(id), value));
      complex.delete(id);
      if (op & 32768) {
        let length = value;
        if (spare >= 6 && extra + 6 <= record.end && arrayElementSizes.has(id)) {
          const at = extra - record.dataOffset, n = view.getUint16(at, true), allocated = view.getUint16(at + 2, true), rawSize = view.getUint16(at + 4, true), size = rawSize === 65520 ? 4 : rawSize;
          if (n <= allocated && arrayElementSizes.get(id).includes(rawSize) && n * size === value) {
            length += 6;
            spare -= 6;
            recovered.push(id);
          }
        }
        if (extra + length > record.end) {
          diagnostics.push({ code: "FOPT_COMPLEX_LENGTH", severity: "warning", message: `Complex property ${id} exceeds FOPT payload`, offset: record.offset });
          break;
        }
        complex.set(id, bytes.subarray(extra, extra + length));
        extra += length;
      }
    }
    if (recovered.length)
      diagnostics.push({ code: "FOPT_ARRAY_LENGTH_COMPAT", severity: "info", message: "OfficeArt array lengths exclude their six-byte headers; bounded array headers were included when locating complex properties", offset: record.offset, details: { properties: recovered } });
    return { values, complex };
  }
  exports_19("readProperties", readProperties);
  function nested(record, ctx) {
    if (record.children.length || !record.length)
      return record.children;
    const reader = { ...ctx, count: ctx.recordCount?.value ?? 0 };
    try {
      record.children = records_js_4.readRecords(reader, record.dataOffset, record.end);
      return record.children;
    } finally {
      if (ctx.recordCount)
        ctx.recordCount.value = reader.count;
    }
  }
  function readDrawingDefaults(drawingGroup, bytes, diagnostics, limits, recordCount) {
    const defaults = {};
    if (!drawingGroup)
      return defaults;
    const complex = /* @__PURE__ */ new Map();
    const roots = nested(drawingGroup, { bytes, diagnostics, limits, recordCount });
    const group = roots.find((r) => r.type === constants_js_3.RT.OfficeArtDggContainer);
    for (const r of group?.children ?? [])
      if (r.type === constants_js_3.RT.OfficeArtFOPT || r.type === constants_js_3.RT.OfficeArtTertiaryFOPT) {
        const properties = readProperties(r, bytes, diagnostics);
        for (const [id, value] of properties.values) {
          defaults[String(id)] = mergeProperty(id, defaults[String(id)], value);
          complex.delete(id);
        }
        for (const [id, blob] of properties.complex)
          complex.set(id, blob);
      }
    defaultComplexProperties.set(defaults, complex);
    return defaults;
  }
  exports_19("readDrawingDefaults", readDrawingDefaults);
  function boolValue(values, id, bit, fallback) {
    const flags = values.get(id);
    return flags !== void 0 && (flags & 1 << bit + 16) !== 0 ? (flags & 1 << bit) !== 0 : fallback;
  }
  function officeColor(value, colors, fallback = "#000000") {
    if (value & 134217728) {
      const scheme = colors[value & 255];
      if (scheme === void 0)
        return fallback;
      value = scheme;
    } else if (value & 268435456) {
      if ((value & 255) === 5)
        return "#ffffff";
      if ((value & 255) === 8)
        return "#000000";
      return fallback;
    }
    return "#" + [value & 255, value >>> 8 & 255, value >>> 16 & 255].map((x) => x.toString(16).padStart(2, "0")).join("");
  }
  exports_19("officeColor", officeColor);
  function inlinePicture(blob, ctx, record, property) {
    const offset = blob.byteOffset - ctx.bytes.byteOffset, id = `inline-image-${offset}-${property}`;
    let budget = assetBudgets.get(ctx.assets);
    if (!budget) {
      budget = { count: 0, bytes: 0, ids: /* @__PURE__ */ new Set() };
      assetBudgets.set(ctx.assets, budget);
    }
    while (budget.count < ctx.assets.length) {
      const asset = ctx.assets[budget.count++];
      budget.bytes += asset.bytes.byteLength;
      budget.ids.add(asset.id);
    }
    if (budget.ids.has(id))
      return id;
    try {
      const asset = pictures_js_1.parseInlinePicture(ctx.bytes, offset, blob.byteLength, id, ctx.diagnostics, ctx.limits.maxAssetBytes - budget.bytes);
      ctx.assets.push(asset);
      budget.count++;
      budget.bytes += asset.bytes.byteLength;
      budget.ids.add(id);
      return id;
    } catch (error) {
      if (error instanceof errors_js_9.PptError && error.code === "LIMIT_ASSETS")
        throw error;
      warn(ctx, "INLINE_BLIP_INVALID", error instanceof Error ? error.message : String(error), record);
      return void 0;
    }
  }
  function fill(values, complex, ctx, record, preset) {
    const open = preset === 20 || preset >= 32 && preset <= 40;
    if (!boolValue(values, 447, 4, !open && preset !== 202 && preset !== 75))
      return { kind: "none" };
    const rawColor = values.get(385) ?? 16777215, rawBack = values.get(387) ?? 16777215;
    const color = officeColor(rawColor, ctx.colors, "#ffffff"), opacity = clamp(fixed(values.get(386) ?? 65536));
    const type = values.get(384) ?? 0;
    if (type >= 1 && type <= 3) {
      const embedded = complex.get(390), assetId = embedded ? inlinePicture(embedded, ctx, record, 390) : ctx.pictureIds.get(values.get(390) ?? 0);
      if (assetId)
        return { kind: "image", assetId, opacity, imageStyle: type === 1 ? "pattern" : type === 2 ? "texture" : "picture", ...type === 1 ? { color, colorIndex: colorIndex(rawColor), backColor: officeColor(rawBack, ctx.colors, "#ffffff"), backColorIndex: colorIndex(rawBack), backOpacity: clamp(fixed(values.get(388) ?? 65536)) } : {} };
      warn(ctx, "FILL_IMAGE_MISSING", "Pattern or picture fill has no usable embedded image; using its saved foreground color", record);
    }
    if (type >= 4 && type <= 8) {
      const back = officeColor(rawBack, ctx.colors, "#ffffff"), backOpacity = clamp(fixed(values.get(388) ?? 65536));
      let stops = [{ position: 0, color, colorIndex: colorIndex(rawColor), opacity }, { position: 1, color: back, colorIndex: colorIndex(rawBack), opacity: backOpacity }];
      const shade = complex.get(407), arr = shade ? geometry_js_1.officeArray(shade) : void 0;
      if (arr && arr.size === 8) {
        stops = [];
        for (let i = 0; i < arr.count; i++) {
          const raw = arr.view.getUint32(6 + i * 8, true), position = clamp(fixed(arr.view.getUint32(6 + i * 8 + 4, true)));
          stops.push({ position, color: officeColor(raw, ctx.colors), colorIndex: colorIndex(raw), opacity: opacity + (backOpacity - opacity) * position });
        }
        stops.sort((a, b) => a.position - b.position);
        if (stops.length < 2)
          stops = [{ position: 0, color, colorIndex: colorIndex(rawColor), opacity }, { position: 1, color: back, colorIndex: colorIndex(rawBack), opacity: backOpacity }];
      }
      const focus = clamp((values.get(396) ?? 0) | 0, -100, 100);
      if (Math.abs(focus) === 100)
        stops = stops.map((s) => ({ ...s, position: 1 - s.position })).reverse();
      else if (focus !== 0) {
        const center = focus > 0 ? 1 - focus / 100 : -focus / 100;
        const left = focus > 0 ? stops : [...stops].reverse().map((s) => ({ ...s, position: 1 - s.position }));
        const right = [...left].reverse().map((s) => ({ ...s, position: 1 - s.position }));
        stops = [...left.map((s) => ({ ...s, position: s.position * center })), ...right.slice(1).map((s) => ({ ...s, position: center + s.position * (1 - center) }))];
      }
      const gradientRect = { left: clamp(fixed(values.get(397) ?? 0)), top: clamp(fixed(values.get(398) ?? 0)), right: clamp(fixed(values.get(399) ?? 0)), bottom: clamp(fixed(values.get(400) ?? 0)) };
      const gradientType = type === 5 ? "rectangular" : type === 6 ? "shape" : "linear";
      if (type === 8)
        warn(ctx, "FILL_GRADIENT_TITLE_APPROXIMATED", "Host-defined title gradient uses its saved linear angle and stops", record);
      if (type === 5 || type === 6)
        ctx.diagnostics.push({ code: "FILL_GRADIENT_SAMPLED", severity: "info", message: "Concentric gradient is rendered with 96 bounded color intervals", offset: record.offset, details: { fillType: type, steps: 96 } });
      return { kind: "gradient", gradientType, gradientScaled: type === 7, gradientRect, gradientCenter: { x: (gradientRect.left + gradientRect.right) / 2, y: (gradientRect.top + gradientRect.bottom) / 2 }, rotateWithShape: boolValue(values, 447, 5, false), angle: -90 - fixed(values.get(395) ?? 0), stops, opacity: 1 };
    }
    if (type === 9)
      return { kind: "none" };
    return { kind: "solid", color, colorIndex: colorIndex(rawColor), opacity };
  }
  function line(values, ctx, preset) {
    if (!boolValue(values, 511, 3, preset !== 202 && preset !== 75))
      return void 0;
    const width = Math.max(0, ((values.get(459) ?? 9525) | 0) / 9525);
    const rawColor = values.get(448) ?? 0;
    const result = { color: officeColor(rawColor, ctx.colors), colorIndex: colorIndex(rawColor), width, opacity: clamp(fixed(values.get(449) ?? 65536)) };
    const dashes = { 1: [3, 1], 2: [1, 1], 3: [3, 1, 1, 1], 4: [3, 1, 1, 1, 1, 1], 5: [1, 3], 6: [4, 3], 7: [8, 3], 8: [4, 3, 1, 3], 9: [8, 3, 1, 3], 10: [8, 3, 1, 3, 1, 3] };
    const dash = dashes[values.get(462) ?? 0];
    if (dash)
      result.dash = dash.map((x) => x * (width || 1));
    const arrows = { 1: "triangle", 2: "stealth", 3: "diamond", 4: "oval", 5: "open" };
    result.startArrow = arrows[values.get(464) ?? 0];
    result.endArrow = arrows[values.get(465) ?? 0];
    result.cap = values.get(471) === 0 ? "round" : values.get(471) === 1 ? "square" : "butt";
    return result;
  }
  function shadow(values, ctx) {
    if (!boolValue(values, 575, 1, false))
      return void 0;
    const type = values.get(512) ?? 0;
    if (![0, 1, 5].includes(type))
      return void 0;
    const rawColor = values.get(513) ?? 8421504;
    const offsetX = ((values.get(517) ?? 25400) | 0) / 9525, offsetY = ((values.get(518) ?? 25400) | 0) / 9525, highlight = values.get(514) ?? 13355979;
    if (type === 0 && !boolValue(values, 575, 0, false))
      return { type: 0, color: officeColor(rawColor, ctx.colors, "#808080"), colorIndex: colorIndex(rawColor), opacity: clamp(fixed(values.get(516) ?? 65536)), offsetX, offsetY, blur: 0 };
    return { type, color: officeColor(rawColor, ctx.colors, "#808080"), colorIndex: colorIndex(rawColor), opacity: clamp(fixed(values.get(516) ?? 65536)), offsetX, offsetY, blur: 0, secondOffsetX: type === 5 ? -offsetX : ((values.get(519) ?? 0) | 0) / 9525, secondOffsetY: type === 5 ? -offsetY : ((values.get(520) ?? 0) | 0) / 9525, highlightColor: officeColor(highlight, ctx.colors, "#cbcbcb"), highlightColorIndex: colorIndex(highlight), originX: fixed(values.get(528) ?? 0) / 9525, originY: fixed(values.get(529) ?? 0) / 9525, obscured: boolValue(values, 575, 0, false) };
  }
  function wordArt(values, complex, ctx, preset, record) {
    const bytes = complex.get(192);
    if (!bytes || !boolValue(values, 255, 14, true))
      return void 0;
    if (bytes.byteLength > ctx.limits.maxTextLength * 2)
      throw new errors_js_9.PptError("LIMIT_TEXT", "WordArt text exceeds the configured character limit", record.offset);
    const font = complex.get(197), align = values.get(194) ?? 1;
    return { text: utils_js_5.trimTrailingNulls(utf16.decode(bytes)), fontFamily: font ? utils_js_5.trimTrailingNulls(utf16.decode(font)) : "Arial", fontSize: Math.max(1, fixed(values.get(195) ?? 36 * 65536) * 4 / 3), spacing: clamp(fixed(values.get(196) ?? 65536), 0, 5), bold: boolValue(values, 255, 5, false), italic: boolValue(values, 255, 4, false), vertical: boolValue(values, 255, 13, false), alignment: align === 2 ? "left" : align === 3 ? "right" : align === 0 || align === 4 || align === 5 ? "justify" : "center", warpPreset: preset, adjustments: Array.from({ length: 8 }, (_, i) => (values.get(327 + i) ?? (i === 0 ? 5400 : 0)) | 0) };
  }
  function extrusion(values, ctx, record, id) {
    if (!boolValue(values, 703, 3, false))
      return void 0;
    const constrain = boolValue(values, 767, 4, true), parallel = boolValue(values, 767, 2, true), useColor = boolValue(values, 703, 1, false), rawColor = useColor ? values.get(647) ?? 268435703 : values.get(385) ?? 16777215, base = officeColor(values.get(385) ?? 16777215, ctx.colors, "#ffffff");
    const unsupported = [...values.keys()].filter((key) => key >= 640 && key <= 767 && ![641, 644, 645, 647, 703, 704, 705, 715, 716, 717, 718, 719, 720, 721, 722, 767].includes(key));
    if (!constrain || unsupported.length)
      ctx.diagnostics.push({ code: "EXTRUSION_PARAMETERS_UNSUPPORTED", severity: "warning", message: "Custom rotation axes, light vectors, bevel, or specular parameters are retained; supported extrusion uses constrained rotations and diffuse shading", offset: record.offset, shapeId: id, details: { properties: unsupported, constrainedRotation: constrain } });
    ctx.diagnostics.push({ code: "EXTRUSION_SHADING_APPROXIMATED", severity: "warning", message: "3D shape uses a tessellated side mesh with diffuse lighting; Office material and lighting parity is not claimed", offset: record.offset, shapeId: id });
    if (!parallel)
      ctx.diagnostics.push({ code: "EXTRUSION_CAMERA_UNITS_COMPAT", severity: "warning", message: "Perspective camera uses signed EMU magnitudes consistent with saved binary defaults; the published FixedPoint unit wording is ambiguous", offset: record.offset, shapeId: id });
    return { depth: clamp((values.get(645) ?? 457200) | 0, 0, 12192e4) / 9525, forward: clamp((values.get(644) ?? 0) | 0, 0, 762e4) / 9525, rotationY: constrain ? clamp(fixed(values.get(704) ?? 0), -90, 90) : 0, rotationX: constrain ? clamp(fixed(values.get(705) ?? 0), -90, 90) : 0, skewAngle: fixed(values.get(720) ?? 4286119936), skewAmount: clamp((values.get(721) ?? 50) | 0, -100, 100), color: officeColor(rawColor, ctx.colors, base), colorIndex: colorIndex(rawColor), ambient: clamp(fixed(values.get(722) ?? 2e4)), diffuse: clamp(fixed(values.get(641) ?? 65536)), metallic: boolValue(values, 703, 2, false), parallel, camera: parallel ? void 0 : { x: ((values.get(715) ?? 125e4) | 0) / 9525, y: ((values.get(716) ?? -125e4) | 0) / 9525, z: ((values.get(717) ?? 9e6) | 0) / 9525 }, origin: parallel ? void 0 : { x: fixed(values.get(718) ?? 32768), y: fixed(values.get(719) ?? -32768) } };
  }
  function readAnchor(record, bytes) {
    const v = dataView(bytes, record);
    let left, top, right, bottom;
    if (record.type === constants_js_3.RT.OfficeArtClientAnchor && record.length === 8) {
      top = v.getInt16(0, true);
      left = v.getInt16(2, true);
      right = v.getInt16(4, true);
      bottom = v.getInt16(6, true);
    } else if (record.length >= 16) {
      if (record.type === constants_js_3.RT.OfficeArtClientAnchor) {
        top = v.getInt32(0, true);
        left = v.getInt32(4, true);
      } else {
        left = v.getInt32(0, true);
        top = v.getInt32(4, true);
      }
      right = v.getInt32(8, true);
      bottom = v.getInt32(12, true);
    } else
      return void 0;
    return { x: left / 6, y: top / 6, width: (right - left) / 6, height: (bottom - top) / 6 };
  }
  exports_19("readAnchor", readAnchor);
  function cloneText(text) {
    return { ...text, margins: { ...text.margins }, paragraphs: text.paragraphs.map((p) => ({ ...p, style: { ...p.style, bullet: p.style.bullet ? { ...p.style.bullet } : void 0 }, runs: p.runs.map((r) => ({ ...r, style: { ...r.style } })) })) };
  }
  function textForShape(records, values, complex, ctx, record) {
    let frame;
    for (const box of records.filter((r) => r.type === constants_js_3.RT.OfficeArtClientTextBox)) {
      const content = nested(box, ctx), outline = content.find((r) => r.type === constants_js_3.RT.OutlineTextRefAtom);
      if (outline && outline.length >= 4) {
        const index = dataView(ctx.bytes, outline).getUint32(0, true), found = ctx.slideTexts[index];
        if (found)
          frame = cloneText(found);
        else
          warn(ctx, "OUTLINE_TEXT_MISSING", `Text outline index ${index} is not present in the slide text list`, outline);
      }
      const own = text_js_1.parseTextFrames(content, ctx);
      if (own.length)
        frame = own[0];
    }
    const wordart = complex.get(192);
    if (!frame && wordart) {
      if (wordart.byteLength > ctx.limits.maxTextLength * 2)
        throw new errors_js_9.PptError("LIMIT_TEXT", "WordArt text exceeds the configured character limit", record.offset);
      const text = utils_js_5.trimTrailingNulls(utf16.decode(wordart));
      const font = complex.get(197), fontFamily = font ? utils_js_5.trimTrailingNulls(utf16.decode(font)) : void 0;
      frame = { paragraphs: [{ level: 0, style: { alignment: "center" }, runs: [{ text, style: { fontFamily, fontSize: fixed(values.get(195) ?? 36 * 65536) * 4 / 3, color: officeColor(values.get(385) ?? 0, ctx.colors), colorIndex: colorIndex(values.get(385) ?? 0) } }] }], margins: { left: 0, top: 0, right: 0, bottom: 0 }, verticalAlignment: "middle", wrap: true, sourceText: text };
    }
    if (!frame)
      return void 0;
    for (const p of frame.paragraphs) {
      for (const r of p.runs)
        if (r.style.colorIndex !== void 0)
          r.style.color = officeColor(134217728 | r.style.colorIndex, ctx.colors, r.style.color);
      if (p.style.bullet?.colorIndex !== void 0)
        p.style.bullet.color = officeColor(134217728 | p.style.bullet.colorIndex, ctx.colors, p.style.bullet.color);
    }
    frame.margins = { left: ((values.get(129) ?? 91440) | 0) / 9525, top: ((values.get(130) ?? 45720) | 0) / 9525, right: ((values.get(131) ?? 91440) | 0) / 9525, bottom: ((values.get(132) ?? 45720) | 0) / 9525 };
    const anchor = values.get(135) ?? 0;
    frame.verticalAlignment = anchor === 1 || anchor === 4 ? "middle" : anchor === 2 || anchor === 5 || anchor === 7 || anchor === 9 ? "bottom" : "top";
    frame.wrap = (values.get(133) ?? 0) !== 2;
    frame.autofit = boolValue(values, 191, 1, false) ? "resize" : "none";
    const flow = values.get(136) ?? 0;
    if (flow === 1 || flow === 3 || flow === 5)
      frame.direction = "vertical";
    else if (flow === 2)
      frame.direction = "vertical270";
    return frame;
  }
  function getPlaceholder(records, ctx) {
    for (const client of records.filter((r) => r.type === constants_js_3.RT.OfficeArtClientData))
      for (const r of nested(client, ctx))
        if (r.type === constants_js_3.RT.OEPlaceholderAtom && r.length >= 8) {
          const v = dataView(ctx.bytes, r);
          return { position: v.getUint32(0, true), type: v.getUint8(4) };
        }
    return void 0;
  }
  function flatten(shapes) {
    const out = [];
    for (const s of shapes) {
      out.push(s);
      if (s.children)
        out.push(...flatten(s.children));
    }
    return out;
  }
  function shape(record, ctx, masters) {
    const records = record.children, fsp = records.find((r) => r.type === constants_js_3.RT.OfficeArtFSP);
    if (!fsp || fsp.length < 8) {
      warn(ctx, "SHAPE_HEADER", "Shape container is missing its OfficeArtFSP", record);
      return void 0;
    }
    if (++ctx.shapeCount.value > ctx.limits.maxShapes)
      throw new errors_js_9.PptError("LIMIT_SHAPES", "Shape count exceeds the configured limit", record.offset);
    const v = dataView(ctx.bytes, fsp), id = v.getUint32(0, true), flags = v.getUint32(4, true), preset = fsp.instance;
    if (flags & 8)
      return void 0;
    const values = /* @__PURE__ */ new Map(), complex = /* @__PURE__ */ new Map();
    const defaults = ctx.drawingDefaults;
    for (const [key, value] of Object.entries(defaults ?? {}))
      values.set(Number(key), value);
    for (const [key, blob] of defaults ? defaultComplexProperties.get(defaults) ?? [] : [])
      complex.set(key, blob);
    const own = { values: /* @__PURE__ */ new Map(), complex: /* @__PURE__ */ new Map() };
    for (const r of records)
      if (r.type === constants_js_3.RT.OfficeArtFOPT || r.type === constants_js_3.RT.OfficeArtSecondaryFOPT || r.type === constants_js_3.RT.OfficeArtTertiaryFOPT) {
        const prop = readProperties(r, ctx.bytes, ctx.diagnostics);
        for (const [key, value] of prop.values) {
          own.values.set(key, mergeProperty(key, own.values.get(key), value));
          own.complex.delete(key);
        }
        for (const [key, value] of prop.complex)
          own.complex.set(key, value);
      }
    const placeholder = getPlaceholder(records, ctx);
    const masterId = own.values.get(769) || void 0;
    const master = masters.find((s) => masterId !== void 0 ? s.id === masterId : placeholder && s.placeholder && s.placeholder.type === placeholder.type && (s.placeholder.position === placeholder.position || placeholder.position === 4294967295));
    for (const [key, value] of Object.entries(master?.source?.properties ?? {}))
      if (/^\d+$/.test(key)) {
        values.set(Number(key), mergeProperty(Number(key), values.get(Number(key)), value));
        complex.delete(Number(key));
      }
    if (master)
      for (const [key, blob] of shapeComplexProperties.get(ctx.bytes)?.get(master) ?? [])
        complex.set(key, blob);
    for (const [key, value] of own.values) {
      values.set(key, mergeProperty(key, values.get(key), value));
      complex.delete(key);
    }
    for (const [key, value] of own.complex)
      complex.set(key, value);
    const anchor = records.find((r) => r.type === constants_js_3.RT.OfficeArtChildAnchor) || records.find((r) => r.type === constants_js_3.RT.OfficeArtClientAnchor);
    const bounds = (anchor ? readAnchor(anchor, ctx.bytes) : void 0) ?? (master ? { ...master.bounds } : void 0) ?? { x: 0, y: 0, width: 0, height: 0 };
    if (!anchor && !master && !(flags & 5) && !(flags & 1024))
      warn(ctx, "SHAPE_ANCHOR_MISSING", "Shape has no usable anchor or matching master placeholder", record, id);
    let flipH = !!(flags & 64), flipV = !!(flags & 128);
    if (bounds.width < 0) {
      bounds.x += bounds.width;
      bounds.width = -bounds.width;
      flipH = !flipH;
    }
    if (bounds.height < 0) {
      bounds.y += bounds.height;
      bounds.height = -bounds.height;
      flipV = !flipV;
    }
    const nameBytes = complex.get(896), name = nameBytes ? utils_js_5.trimTrailingNulls(utf16.decode(nameBytes)) : void 0;
    const result = { id, kind: flags & 1 ? "group" : "shape", name, bounds, rotation: fixed(values.get(4) ?? 0), flipH, flipV, preset, fill: fill(values, complex, ctx, record, preset), line: line(values, ctx, preset), shadow: shadow(values, ctx), placeholder, hidden: boolValue(values, 959, 1, false), source: { offset: record.offset, recordType: record.type, shapeType: preset, properties: { ...Object.fromEntries(values), fspFlags: flags, hasAnchor: anchor ? 1 : 0 } } };
    const group = records.find((r) => r.type === constants_js_3.RT.OfficeArtFSPGR);
    if (group)
      result.groupBounds = readAnchor(group, ctx.bytes);
    result.text = textForShape(records, values, complex, ctx, record);
    result.wordArt = wordArt(values, complex, ctx, preset, record);
    if (result.wordArt)
      warn(ctx, "WORDART_ENVELOPE_APPROXIMATED", "WordArt is rendered by deforming browser glyphs through a bounded envelope mesh; Office-specific font fitting and custom envelope formulas are not fully reproduced", record, id);
    result.extrusion = extrusion(values, ctx, record, id);
    const geometry = geometry_js_1.customGeometry(values, complex, ctx.diagnostics, id, record.offset, bounds);
    if (geometry.path) {
      result.path = geometry.path;
      result.pathParts = geometry.pathParts;
      result.pathBounds = geometry.pathBounds;
    } else if (!result.wordArt) {
      const adjusted = geometry_js_1.adjustedPresetGeometry(preset, values, bounds);
      if (adjusted) {
        result.path = adjusted.path;
        result.pathBounds = adjusted.pathBounds;
        if (adjusted.approximate)
          warn(ctx, "PRESET_ADJUSTMENT_APPROXIMATED", `Preset ${preset} uses an analytic adjustable envelope; exact Office preset construction is not fully specified`, record, id);
      }
    }
    if (geometry.noFill)
      result.fill = { kind: "none" };
    if (geometry.noLine)
      result.line = void 0;
    const imageIndex = values.get(260), embeddedImage = complex.get(260);
    if (imageIndex || embeddedImage) {
      const assetId = embeddedImage ? inlinePicture(embeddedImage, ctx, record, 260) : ctx.pictureIds.get(imageIndex);
      if (assetId) {
        result.kind = "image";
        result.image = { assetId, crop: { top: fixed(values.get(256) ?? 0), bottom: fixed(values.get(257) ?? 0), left: fixed(values.get(258) ?? 0), right: fixed(values.get(259) ?? 0) }, brightness: clamp(((values.get(265) ?? 0) | 0) / 32768, -1, 1), contrast: Math.max(0, fixed(values.get(264) ?? 65536)) };
      } else {
        result.kind = "unsupported";
        warn(ctx, "SHAPE_IMAGE_MISSING", `Picture index ${imageIndex} has no available image bytes`, record, id);
      }
    }
    const shadowActive = boolValue(values, 575, 1, false);
    const shadowUnsupported = shadowActive && (!result.shadow || ![0, 1, 5].includes(result.shadow.type) || boolValue(values, 575, 0, false) && result.fill.kind === "none");
    const effectProperties = [...values.keys()].filter((key) => shadowUnsupported && key >= 512 && key <= 575);
    if (effectProperties.length) {
      result.source.unsupportedProperties = effectProperties;
      warn(ctx, "SHAPE_EFFECT_UNSUPPORTED", "Rich/shape/drawing shadow transforms or obscured unfilled interiors are preserved but not fully rendered", record, id);
    }
    if (own.complex.has(937))
      ctx.diagnostics.push({ code: "DRAWINGML_ALTERNATE_IGNORED", severity: "info", message: "Alternative DrawingML package is ignored as recommended by MS-ODRAW; its binary OfficeArt shape is used", offset: record.offset, shapeId: id, details: { property: 937, byteLength: own.complex.get(937).byteLength } });
    if (flags & 16)
      warn(ctx, "OLE_PREVIEW_ONLY", "OLE object uses its saved presentation preview; embedded application behavior is not executed", record, id);
    let cache = shapeComplexProperties.get(ctx.bytes);
    if (!cache) {
      cache = /* @__PURE__ */ new WeakMap();
      shapeComplexProperties.set(ctx.bytes, cache);
    }
    cache.set(result, complex);
    return result;
  }
  function parseDrawing(record, ctx) {
    const masters = flatten(ctx.masterShapes ?? []);
    const collect = (nodes, depth) => {
      if (depth > ctx.limits.maxDepth)
        throw new errors_js_9.PptError("LIMIT_DEPTH", "OfficeArt group nesting exceeds limit", record.offset);
      const out = [];
      for (const node of nodes) {
        if (node.type === constants_js_3.RT.OfficeArtSpgrContainer) {
          const first = node.children.find((r) => r.type === constants_js_3.RT.OfficeArtSpContainer), header = first ? shape(first, ctx, masters) : void 0;
          const children = collect(node.children.filter((r) => r !== first), depth + 1);
          if (header && !(header.source.properties.fspFlags & 4)) {
            header.kind = "group";
            header.children = children;
            header.fill = { kind: "none" };
            header.line = void 0;
            if (header.bounds.width === 0 && header.bounds.height === 0 && header.groupBounds)
              header.bounds = { ...header.groupBounds };
            out.push(header);
          } else
            out.push(...children);
        } else if (node.type === constants_js_3.RT.OfficeArtSpContainer) {
          const s = shape(node, ctx, masters);
          if (s)
            out.push(s);
        } else if (node.type === constants_js_3.RT.OfficeArtDgContainer || node.type === constants_js_3.RT.PPDrawing)
          out.push(...collect(nested(node, ctx), depth + 1));
      }
      return out;
    };
    return collect(record.type === constants_js_3.RT.OfficeArtDgContainer ? [record] : nested(record, ctx), 0);
  }
  exports_19("parseDrawing", parseDrawing);
  return {
    setters: [
      function(errors_js_9_1) {
        errors_js_9 = errors_js_9_1;
      },
      function(utils_js_5_1) {
        utils_js_5 = utils_js_5_1;
      },
      function(constants_js_3_1) {
        constants_js_3 = constants_js_3_1;
      },
      function(records_js_4_1) {
        records_js_4 = records_js_4_1;
      },
      function(geometry_js_1_1) {
        geometry_js_1 = geometry_js_1_1;
      },
      function(text_js_1_1) {
        text_js_1 = text_js_1_1;
      },
      function(pictures_js_1_1) {
        pictures_js_1 = pictures_js_1_1;
      }
    ],
    execute: function() {
      boolProps = /* @__PURE__ */ new Set([127, 191, 255, 319, 383, 447, 511, 575, 639, 703, 767, 831, 895, 959, 1023]);
      dataView = (bytes, record) => new DataView(bytes.buffer, bytes.byteOffset + record.dataOffset, record.length);
      fixed = (value) => (value | 0) / 65536;
      colorIndex = (value) => value & 134217728 ? value & 255 : void 0;
      clamp = (n, min = 0, max = 1) => Math.max(min, Math.min(max, n));
      utf16 = new TextDecoder("utf-16le");
      assetBudgets = /* @__PURE__ */ new WeakMap();
      defaultComplexProperties = /* @__PURE__ */ new WeakMap();
      shapeComplexProperties = /* @__PURE__ */ new WeakMap();
      arrayElementSizes = /* @__PURE__ */ new Map([[325, [4, 8, 65520]], [326, [2]], [337, [8, 65520]], [338, [4]], [341, [36]], [342, [8]], [343, [16]], [407, [8]]]);
    }
  };
});
System.register("ppt/extras", ["core/errors", "core/utils", "core/inflate", "ppt/records"], function(exports_20, context_20) {
  "use strict";
  var errors_js_10, utils_js_6, inflate_js_3, records_js_5, R, utf16;
  var __moduleName = context_20 && context_20.id;
  function warning(ctx, code, message, node) {
    ctx.diagnostics.push({ code, severity: "warning", message, offset: node.offset });
  }
  function string(ctx, node) {
    if (!node)
      return "";
    if (node.length % 2)
      warning(ctx, "EXTRA_STRING_LENGTH", "UTF-16 metadata string has an odd byte length", node);
    const length = Math.floor(node.length / 2);
    ctx.textLength += length;
    if (ctx.textLength > ctx.limits.maxTextLength)
      throw new errors_js_10.PptError("LIMIT_TEXT", "Metadata text exceeds the configured limit", node.offset);
    return utils_js_6.trimTrailingNulls(utf16.decode(ctx.bytes.subarray(node.dataOffset, node.dataOffset + length * 2)));
  }
  function cstring(ctx, node, instance) {
    return string(ctx, node.children.find((r) => r.type === R.CString && r.instance === instance));
  }
  function view(ctx, node) {
    return new DataView(ctx.bytes.buffer, ctx.bytes.byteOffset + node.dataOffset, node.length);
  }
  function* extendedRecords(nodes, ctx, depth = 0) {
    if (depth > ctx.limits.maxDepth)
      throw new errors_js_10.PptError("LIMIT_DEPTH", "Metadata extension nesting exceeds the configured limit");
    for (const node of nodes) {
      yield node;
      if (node.type === R.ProgBinaryTag) {
        const name = cstring(ctx, node, 0), blob = node.children.find((r) => r.type === R.BinaryTagData);
        if (blob && name === "___PPT10") {
          try {
            const extra = records_js_5.readRecords(ctx.recordContext, blob.dataOffset, blob.end, depth + 1);
            yield* extendedRecords(extra, ctx, depth + 1);
          } catch (error) {
            if (error instanceof errors_js_10.PptError && error.code.startsWith("LIMIT_"))
              throw error;
            warning(ctx, "PROGRAM_TAG_INVALID", "The ___PPT10 record sequence is malformed and could not be fully decoded", blob);
          }
        } else if (blob)
          warning(ctx, "PROGRAM_TAG_UNSUPPORTED", `Programmable tag ${name || "(unnamed)"} is not decoded by this build`, blob);
      }
      if (node.children.length)
        yield* extendedRecords(node.children, ctx, depth + 1);
    }
  }
  function safeHyperlinkTarget(target, location) {
    if (/[\u0000-\u001f\u007f]/.test(target))
      return void 0;
    const value = target.trim();
    if (/^https?:\/\//i.test(value)) {
      try {
        const url = new URL(value);
        if (!url.hostname)
          return void 0;
        if (location)
          url.hash = location;
        return url.href;
      } catch {
        return void 0;
      }
    }
    if (/^(?:mailto:|tel:|#)/i.test(value) && !/[\s]/.test(value))
      return value;
    return void 0;
  }
  exports_20("safeHyperlinkTarget", safeHyperlinkTarget);
  function hyperlink(node, ctx) {
    const atom = node.children.find((r) => r.type === R.HyperlinkAtom);
    if (!atom || atom.length < 4) {
      warning(ctx, "HYPERLINK_ATOM", "Hyperlink identifier is missing", node);
      return;
    }
    const id = view(ctx, atom).getUint32(0, true), target = cstring(ctx, node, 1), location = cstring(ctx, node, 3), friendlyName = cstring(ctx, node, 0);
    const href = safeHyperlinkTarget(target, location);
    if (!href && (target || location))
      warning(ctx, target ? "HYPERLINK_BLOCKED" : "INTERNAL_LINK_UNRESOLVED", target ? "A local, relative or unsafe hyperlink is preserved as metadata without an active link" : "An internal slide destination is preserved but has no resolved navigation target", node);
    return { id, friendlyName: friendlyName || void 0, target, location: location || void 0, href, blocked: !href, sourceOffset: node.offset };
  }
  function soundMime(bytes, extension) {
    const ascii = (offset, count) => String.fromCharCode(...bytes.subarray(offset, offset + count));
    if (ascii(0, 4) === "RIFF" && ascii(8, 4) === "WAVE")
      return "audio/wav";
    if (ascii(0, 4) === "FORM" && ["AIFF", "AIFC"].includes(ascii(8, 4)))
      return "audio/aiff";
    if ([".wav", "wave"].includes(extension.toLowerCase()))
      return "audio/wav";
    if ([".aif", "aiff"].includes(extension.toLowerCase()))
      return "audio/aiff";
    return "application/octet-stream";
  }
  function parseSound(node, ctx, assets, remaining) {
    const name = cstring(ctx, node, 0), extension = cstring(ctx, node, 1), idText = cstring(ctx, node, 2), builtin = cstring(ctx, node, 3), data = node.children.find((r) => r.type === R.SoundData);
    const id = Number(idText);
    if (!/^\d+$/.test(idText) || !Number.isSafeInteger(id) || id <= 0) {
      warning(ctx, "SOUND_ID", "Embedded sound has an invalid identifier", node);
      return;
    }
    const result = { id, name, extension: extension || void 0, builtinId: /^\d+$/.test(builtin) ? Number(builtin) : void 0, byteLength: data?.length ?? 0, sourceOffset: node.offset };
    if (data) {
      if (data.length > remaining)
        throw new errors_js_10.PptError("LIMIT_ASSETS", "Embedded sound data exceeds the configured asset limit", data.offset);
      const bytes = new Uint8Array(ctx.bytes.subarray(data.dataOffset, data.end)), mimeType = soundMime(bytes, extension);
      result.assetId = `sound-${id}-${node.offset}`;
      assets.push({ id: result.assetId, mimeType, bytes, sourceOffset: data.offset, unsupported: mimeType === "application/octet-stream" });
    } else
      warning(ctx, "SOUND_DATA_MISSING", "Embedded sound has no audio bytes", node);
    return result;
  }
  function parseMedia(node, ctx) {
    const atom = node.children.find((r) => r.type === R.MediaAtom);
    if (!atom || atom.length < 8) {
      warning(ctx, "MEDIA_ATOM", "External media identifier or flags are missing", node);
      return;
    }
    const v = view(ctx, atom), flags = v.getUint16(4, true), wav = node.children.find((r) => r.type === R.WavEmbeddedAtom), wv = wav && wav.length >= 8 ? view(ctx, wav) : void 0;
    const item = { id: v.getUint32(0, true), kind: node.type === R.Video ? "video" : "audio", sourceRecordType: node.type, path: cstring(ctx, node, 0) || void 0, soundId: wv?.getUint32(0, true), durationMs: wv ? Math.max(0, wv.getInt32(4, true)) : void 0, loop: !!(flags & 1), rewind: !!(flags & 2), narration: !!(flags & 4), sourceOffset: node.offset };
    if (!item.soundId)
      warning(ctx, "MEDIA_EXTERNAL_SOURCE", "External media is retained as metadata; its file path is not fetched by the preview", node);
    return item;
  }
  function parseOle(node, ctx) {
    const atom = node.children.find((r) => r.type === R.OleAtom);
    if (!atom || atom.length < 24) {
      warning(ctx, "OLE_ATOM", "OLE object metadata is missing or truncated", node);
      return;
    }
    const v = view(ctx, atom);
    warning(ctx, "OLE_METADATA_ONLY", "OLE application metadata is retained; only a saved picture preview can be displayed, and no embedded application is executed", node);
    return { id: v.getUint32(8, true), type: v.getUint32(4, true), subType: v.getUint32(12, true), drawAspect: v.getUint32(0, true), storagePersistId: v.getUint32(16, true), menuName: cstring(ctx, node, 1) || void 0, progId: cstring(ctx, node, 2) || void 0, clipboardName: cstring(ctx, node, 3) || void 0, sourceOffset: node.offset };
  }
  function dateTime(v, offset) {
    const year = v.getUint16(offset, true), month = v.getUint16(offset + 2, true), day = v.getUint16(offset + 6, true), hour = v.getUint16(offset + 8, true), minute = v.getUint16(offset + 10, true), second = v.getUint16(offset + 12, true), ms = v.getUint16(offset + 14, true);
    if (!year || month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59 || ms > 999)
      return void 0;
    const p = (n, length = 2) => String(n).padStart(length, "0");
    return `${p(year, 4)}-${p(month)}-${p(day)}T${p(hour)}:${p(minute)}:${p(second)}.${p(ms, 3)}`;
  }
  function parseComment(node, ctx) {
    const atom = node.children.find((r) => r.type === R.CommentAtom);
    if (!atom || atom.length < 28) {
      warning(ctx, "COMMENT_ATOM", "Presentation comment position or date is missing", node);
      return;
    }
    const v = view(ctx, atom);
    return { index: v.getInt32(0, true), author: cstring(ctx, node, 0), text: cstring(ctx, node, 1), initials: cstring(ctx, node, 2), createdAt: dateTime(v, 4), position: { x: v.getInt32(20, true) / 6, y: v.getInt32(24, true) / 6 }, sourceOffset: node.offset };
  }
  function parseDocumentExtras(records, bytes, limits, diagnostics) {
    const ctx = { bytes, limits, diagnostics, textLength: 0, recordContext: { bytes, limits, diagnostics, count: 0 } };
    const result = { hyperlinks: [], hyperlinkTargets: /* @__PURE__ */ new Map(), sounds: [], media: [], oleObjects: [], comments: [], assets: [], animationRecordTypes: [], additionalRecordCount: 0 };
    const ids = /* @__PURE__ */ new Set(), soundIds = /* @__PURE__ */ new Set(), animations = /* @__PURE__ */ new Set();
    let assetBytes = 0;
    for (const record of extendedRecords(records, ctx)) {
      if (record.type === R.Hyperlink) {
        const item = hyperlink(record, ctx);
        if (item) {
          if (ids.has(item.id)) {
            warning(ctx, "EXTERNAL_ID_DUPLICATE", "Duplicate external-object/hyperlink identifier was ignored", record);
            continue;
          }
          ids.add(item.id);
          result.hyperlinks.push(item);
          if (item.href)
            result.hyperlinkTargets.set(item.id, item.href);
        }
      } else if (record.type === R.Sound) {
        const item = parseSound(record, ctx, result.assets, limits.maxAssetBytes - assetBytes);
        if (item) {
          if (soundIds.has(item.id))
            warning(ctx, "SOUND_ID_DUPLICATE", "Duplicate sound identifier retained with a unique asset identifier", record);
          soundIds.add(item.id);
          result.sounds.push(item);
          assetBytes += item.byteLength;
        }
      } else if ([R.Video, R.Midi, R.Cd, R.WavEmbedded, R.WavLinked].includes(record.type)) {
        const item = parseMedia(record, ctx);
        if (item)
          result.media.push(item);
      } else if ([R.OleEmbedded, R.OleLinked, R.OleControl].includes(record.type)) {
        const item = parseOle(record, ctx);
        if (item)
          result.oleObjects.push(item);
      } else if (record.type === R.Comment) {
        const item = parseComment(record, ctx);
        if (item)
          result.comments.push(item);
      }
      if (record.type === R.AnimationInfo || record.type === R.AnimationInfoAtom || record.type >= 61733 && record.type <= 61765 || record.type >= 11010 && record.type <= 11021)
        animations.add(record.type);
    }
    result.animationRecordTypes = [...animations];
    result.additionalRecordCount = ctx.recordContext.count;
    if (animations.size)
      diagnostics.push({ code: "ANIMATION_RECORDS_PRESENT", severity: "info", message: "Animation/build records were identified; supported effects are mapped separately to the playback timeline", details: { recordTypes: [...animations] } });
    return result;
  }
  exports_20("parseDocumentExtras", parseDocumentExtras);
  function parseSlideExtras(records, bytes, limits, diagnostics, slideId) {
    const start = diagnostics.length, result = parseDocumentExtras(records, bytes, limits, diagnostics);
    for (const c of result.comments)
      c.slideId = slideId;
    for (let i = start; i < diagnostics.length; i++)
      diagnostics[i].slideId = slideId;
    return result;
  }
  exports_20("parseSlideExtras", parseSlideExtras);
  function extractOleStorage(record, bytes, maxBytes, diagnostics) {
    if (record.type !== 4113 || record.version !== 0 || record.instance !== 0 && record.instance !== 1) {
      diagnostics.push({ code: "OLE_STORAGE_TYPE", severity: "warning", message: "OLE storage reference has an unsupported record type", offset: record.offset });
      return;
    }
    let result = null;
    if (record.instance === 0) {
      if (record.length > maxBytes)
        throw new errors_js_10.PptError("LIMIT_ASSETS", "OLE storage exceeds the remaining asset limit", record.offset);
      result = new Uint8Array(bytes.subarray(record.dataOffset, record.end));
    } else if (record.length >= 4) {
      const size = new DataView(bytes.buffer, bytes.byteOffset + record.dataOffset, 4).getUint32(0, true);
      if (size > maxBytes)
        throw new errors_js_10.PptError("LIMIT_ASSETS", "Decompressed OLE storage exceeds the remaining asset limit", record.offset);
      result = inflate_js_3.inflateZlib(bytes.subarray(record.dataOffset + 4, record.end), size, maxBytes);
    }
    if (!result) {
      diagnostics.push({ code: "OLE_STORAGE_INVALID", severity: "warning", message: "OLE storage is truncated or its zlib payload could not be decoded", offset: record.offset });
      return;
    }
    return { id: `ole-storage-${record.offset}`, mimeType: "application/x-ole-storage", bytes: result, sourceOffset: record.offset, unsupported: true };
  }
  exports_20("extractOleStorage", extractOleStorage);
  return {
    setters: [
      function(errors_js_10_1) {
        errors_js_10 = errors_js_10_1;
      },
      function(utils_js_6_1) {
        utils_js_6 = utils_js_6_1;
      },
      function(inflate_js_3_1) {
        inflate_js_3 = inflate_js_3_1;
      },
      function(records_js_5_1) {
        records_js_5 = records_js_5_1;
      }
    ],
    execute: function() {
      R = { CString: 4026, Hyperlink: 4055, HyperlinkAtom: 4051, Sound: 2022, SoundData: 2023, MediaAtom: 4100, Video: 4101, Midi: 4109, Cd: 4110, WavEmbedded: 4111, WavLinked: 4112, WavEmbeddedAtom: 4115, OleAtom: 4035, OleEmbedded: 4044, OleLinked: 4046, OleControl: 4078, Comment: 12e3, CommentAtom: 12001, ProgBinaryTag: 5002, BinaryTagData: 5003, AnimationInfo: 4116, AnimationInfoAtom: 4081 };
      utf16 = new TextDecoder("utf-16le");
    }
  };
});
System.register("ppt/headers-footers", ["core/errors", "core/utils", "ppt/constants"], function(exports_21, context_21) {
  "use strict";
  var errors_js_11, utils_js_7, constants_js_4;
  var __moduleName = context_21 && context_21.id;
  function warning(ctx, code, message, record) {
    ctx.diagnostics.push({ code, severity: "warning", message, offset: record.offset });
  }
  function bounded(record, ctx, minimum) {
    if (record.dataOffset < 0 || record.end > ctx.bytes.length || record.end - record.dataOffset < minimum) {
      warning(ctx, "HEADER_FOOTER_TRUNCATED", "A header/footer record is truncated or outside its stream", record);
      return false;
    }
    return true;
  }
  function stringValue(record, ctx) {
    if (!bounded(record, ctx, 0))
      return void 0;
    if (record.length / 2 > ctx.limits.maxTextLength)
      throw new errors_js_11.PptError("LIMIT_TEXT", "Header/footer text exceeds the configured character limit", record.offset);
    if (record.length % 2)
      warning(ctx, "HEADER_FOOTER_UTF16", "An odd trailing byte in header/footer text was ignored", record);
    if (record.instance === 0 && record.length > 510)
      warning(ctx, "HEADER_FOOTER_DATE_LENGTH", "Custom date text exceeds the specification length of 255 UTF-16 units", record);
    const view = new DataView(ctx.bytes.buffer, ctx.bytes.byteOffset, ctx.bytes.byteLength);
    const pieces = [];
    const count = Math.floor(record.length / 2);
    for (let from = 0; from < count; from += 8192) {
      const values = [];
      for (let i = from; i < Math.min(count, from + 8192); i++)
        values.push(view.getUint16(record.dataOffset + i * 2, true));
      pieces.push(String.fromCharCode(...values));
    }
    return utils_js_7.trimTrailingNulls(pieces.join(""));
  }
  function parseHeaderFooter(records, ctx, instance = 0) {
    const containers = records.filter((record) => record.type === constants_js_4.RT.HeadersFooters && record.instance === instance);
    const container = containers[0];
    if (!container)
      return void 0;
    if (containers.length > 1)
      warning(ctx, "HEADER_FOOTER_DUPLICATE", "Duplicate header/footer containers were ignored", containers[1]);
    const atom = container.children.find((record) => record.type === constants_js_4.RT.HeadersFootersAtom);
    if (!atom) {
      warning(ctx, "HEADER_FOOTER_ATOM", "Header/footer options atom is missing", container);
      return void 0;
    }
    if (!bounded(atom, ctx, 4))
      return void 0;
    const view = new DataView(ctx.bytes.buffer, ctx.bytes.byteOffset + atom.dataOffset, 4);
    const format = view.getInt16(0, true), flags = view.getUint16(2, true);
    const result = {
      showDate: !!(flags & 1),
      useCurrentDate: !!(flags & 2),
      useUserDate: !!(flags & 4),
      showSlideNumber: !!(flags & 8),
      showHeader: instance !== 3 && !!(flags & 16),
      showFooter: !!(flags & 32),
      format
    };
    if (atom.length !== 4)
      warning(ctx, "HEADER_FOOTER_LENGTH", "Extra bytes in header/footer options were ignored", atom);
    if (result.useCurrentDate && (format < 0 || format > 13))
      warning(ctx, "HEADER_FOOTER_DATE_FORMAT", `Unsupported current-date format ${format}`, atom);
    if (result.useCurrentDate && result.useUserDate)
      warning(ctx, "HEADER_FOOTER_DATE_MODE", "Both current-date and custom-date flags are enabled", atom);
    const seen = /* @__PURE__ */ new Set();
    for (const record of container.children) {
      if (record.type !== constants_js_4.RT.CString || record.instance > 2)
        continue;
      if (seen.has(record.instance)) {
        warning(ctx, "HEADER_FOOTER_STRING_DUPLICATE", "Duplicate header/footer text record was ignored", record);
        continue;
      }
      seen.add(record.instance);
      const value = stringValue(record, ctx);
      if (value === void 0)
        continue;
      if (record.instance === 0)
        result.userDate = value;
      else if (record.instance === 1 && instance === 4)
        result.header = value;
      else if (record.instance === 2)
        result.footer = value;
    }
    return result;
  }
  exports_21("parseHeaderFooter", parseHeaderFooter);
  function resolveHeaderFooter(...levels) {
    let result;
    for (const level of levels) {
      if (!level)
        continue;
      result = { ...result, ...level };
    }
    return result;
  }
  exports_21("resolveHeaderFooter", resolveHeaderFooter);
  return {
    setters: [
      function(errors_js_11_1) {
        errors_js_11 = errors_js_11_1;
      },
      function(utils_js_7_1) {
        utils_js_7 = utils_js_7_1;
      },
      function(constants_js_4_1) {
        constants_js_4 = constants_js_4_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("ppt/animation", ["ppt/records"], function(exports_22, context_22) {
  "use strict";
  var records_js_6;
  var __moduleName = context_22 && context_22.id;
  function parseLegacyAnimations(records, bytes, shapes, diagnostics, slideId, hasModernTiming = false) {
    if (hasModernTiming) {
      diagnostics.push({ code: "ANIMATION_MODERN_TIMING_UNSUPPORTED", severity: "warning", message: "The modern binary TimeNode tree is retained but is not executed; a legacy fallback is not substituted for its effects", slideId });
      return [];
    }
    const byOffset = /* @__PURE__ */ new Map();
    for (const record of records_js_6.walkRecords(records))
      byOffset.set(record.offset, record);
    const result = [];
    const warning = (code, message, shape, offset, details) => diagnostics.push({ code, severity: code === "ANIMATION_DURATION_DEFAULT" ? "info" : "warning", message, shapeId: shape.id, slideId, offset, details });
    const visit = (list) => {
      for (const shape of list) {
        if (shape.children)
          visit(shape.children);
        const node = shape.source ? byOffset.get(shape.source.offset) : void 0, client = node?.children.find((r) => r.type === 61457);
        if (!client)
          continue;
        const atom = [...records_js_6.walkRecords(client.children)].find((r) => r.type === 4081);
        if (!atom)
          continue;
        if (atom.length !== 28 || atom.version !== 1) {
          warning("ANIMATION_ATOM_INVALID", "Legacy animation atom has an invalid version or payload size", shape, atom.offset);
          continue;
        }
        const v = new DataView(bytes.buffer, bytes.byteOffset + atom.dataOffset, 28), flags = v.getUint32(4, true), order = v.getInt16(16, true), build = v.getUint8(20), kind = v.getUint8(21), direction = v.getUint8(22), after = v.getUint8(23), sub = v.getUint8(24), automatic = (flags >>> 2 & 3) === 1;
        if (build === 0)
          continue;
        if ([0, 2, 4, 6, 8, 10, 12, 14].some((shift) => (flags >>> shift & 3) > 1)) {
          warning("ANIMATION_FLAG_INVALID", "A legacy animation two-bit Boolean contains an invalid value", shape, atom.offset);
          continue;
        }
        if (build !== 1 || order < 0 || sub !== 0 || (flags & 3) !== 0) {
          warning("ANIMATION_BUILD_UNSUPPORTED", "Only forward, whole-object legacy builds with explicit ordering are mapped", shape, atom.offset, { build, order, subEffect: sub, reverse: flags & 3 });
          continue;
        }
        if (shape.text && !shape.wordArt && (flags >>> 14 & 3) !== 1 && (shape.fill.kind !== "none" || (shape.line?.width ?? 0) > 0)) {
          warning("ANIMATION_TEXT_ONLY_UNSUPPORTED", "This legacy build animates text independently of its visible shape background", shape, atom.offset);
          continue;
        }
        let effect;
        const base = { targetShapeId: shape.id, phase: "entrance", trigger: automatic ? "afterPrevious" : "click", delayMs: automatic ? Math.max(0, v.getInt32(12, true)) : 0, durationMs: 500 };
        if (kind === 0 && (direction === 0 || direction === 2))
          effect = { ...base, kind: "appear", durationMs: 0 };
        else if (kind === 6 && direction === 0)
          effect = { ...base, kind: "fade" };
        else if (kind === 12 && direction <= 3)
          effect = { ...base, kind: "fly", direction: ["left", "up", "right", "down"][direction] };
        else if (kind === 12 && direction >= 16 && direction <= 19)
          effect = { ...base, kind: "zoom", fromScale: [0, 0.5, 4, 1.5][direction - 16], toScale: 1 };
        if (!effect) {
          warning("ANIMATION_EFFECT_UNSUPPORTED", "The legacy animation effect or direction is retained but has no playback mapping", shape, atom.offset, { effect: kind, direction });
          continue;
        }
        result.push({ order, effect });
        if (effect.durationMs)
          warning("ANIMATION_DURATION_DEFAULT", "The legacy record has no duration; this viewer uses a 500 ms application default", shape, atom.offset, { durationMs: 500 });
        if (after !== 0)
          warning("ANIMATION_AFTER_EFFECT_UNSUPPORTED", "The legacy after-effect is not applied by the supported playback subset", shape, atom.offset, { afterEffect: after });
        if ((flags >>> 4 & 3) === 1 || (flags >>> 6 & 3) === 1)
          warning("ANIMATION_SOUND_MANUAL", "Animation sound commands are retained; embedded media playback requires a user gesture", shape, atom.offset, { soundId: v.getUint32(8, true) });
      }
    };
    visit(shapes);
    return result.sort((a, b) => a.order - b.order).map((item) => item.effect);
  }
  exports_22("parseLegacyAnimations", parseLegacyAnimations);
  return {
    setters: [
      function(records_js_6_1) {
        records_js_6 = records_js_6_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("core/crypto", ["core/errors"], function(exports_23, context_23) {
  "use strict";
  var errors_js_12, rol, Rc4;
  var __moduleName = context_23 && context_23.id;
  function concatBytes(...items) {
    const out = new Uint8Array(items.reduce((n, x) => n + x.length, 0));
    let at = 0;
    for (const x of items) {
      out.set(x, at);
      at += x.length;
    }
    return out;
  }
  exports_23("concatBytes", concatBytes);
  function little32(value) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, value, true);
    return b;
  }
  exports_23("little32", little32);
  function passwordBytes(password) {
    if (password.length > 255)
      throw new errors_js_12.PptError("PASSWORD_LENGTH", "Office passwords may contain at most 255 UTF-16 code units");
    const b = new Uint8Array(password.length * 2), v = new DataView(b.buffer);
    for (let i = 0; i < password.length; i++)
      v.setUint16(i * 2, password.charCodeAt(i), true);
    return b;
  }
  exports_23("passwordBytes", passwordBytes);
  function equalBytes(a, b) {
    let difference = a.length ^ b.length;
    for (let i = 0; i < Math.max(a.length, b.length); i++)
      difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
    return difference === 0;
  }
  exports_23("equalBytes", equalBytes);
  function padded(data, block, lengthBytes) {
    const out = new Uint8Array(Math.ceil((data.length + 1 + lengthBytes) / block) * block);
    out.set(data);
    out[data.length] = 128;
    const v = new DataView(out.buffer);
    v.setUint32(out.length - 8, Math.floor(data.length / 536870912));
    v.setUint32(out.length - 4, data.length * 8 >>> 0);
    return out;
  }
  function sha1(data) {
    const bytes = padded(data, 64, 8), v = new DataView(bytes.buffer), w = new Uint32Array(80), h = new Uint32Array([1732584193, 4023233417, 2562383102, 271733878, 3285377520]);
    for (let at = 0; at < bytes.length; at += 64) {
      for (let i = 0; i < 16; i++)
        w[i] = v.getUint32(at + i * 4);
      for (let i = 16; i < 80; i++)
        w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      let [a, b, c, d, e] = h;
      for (let i = 0; i < 80; i++) {
        const f = i < 20 ? b & c | ~b & d : i < 40 ? b ^ c ^ d : i < 60 ? b & c | b & d | c & d : b ^ c ^ d, k = i < 20 ? 1518500249 : i < 40 ? 1859775393 : i < 60 ? 2400959708 : 3395469782, t = rol(a, 5) + f + e + k + w[i] >>> 0;
        e = d;
        d = c;
        c = rol(b, 30);
        b = a;
        a = t;
      }
      h[0] = h[0] + a >>> 0;
      h[1] = h[1] + b >>> 0;
      h[2] = h[2] + c >>> 0;
      h[3] = h[3] + d >>> 0;
      h[4] = h[4] + e >>> 0;
    }
    const out = new Uint8Array(20), ov = new DataView(out.buffer);
    for (let i = 0; i < 5; i++)
      ov.setUint32(i * 4, h[i]);
    return out;
  }
  exports_23("sha1", sha1);
  return {
    setters: [
      function(errors_js_12_1) {
        errors_js_12 = errors_js_12_1;
      }
    ],
    execute: function() {
      rol = (x, n) => x << n | x >>> 32 - n;
      Rc4 = class Rc4 {
        state = Uint8Array.from({ length: 256 }, (_, i) => i);
        i = 0;
        j = 0;
        constructor(key) {
          if (key.length < 1 || key.length > 256)
            throw new errors_js_12.PptError("CRYPTO_KEY", "Invalid RC4 key length");
          let j = 0;
          for (let i = 0; i < 256; i++) {
            j = j + this.state[i] + key[i % key.length] & 255;
            const t = this.state[i];
            this.state[i] = this.state[j];
            this.state[j] = t;
          }
        }
        crypt(bytes) {
          const out = new Uint8Array(bytes.length);
          for (let at = 0; at < bytes.length; at++) {
            this.i = this.i + 1 & 255;
            this.j = this.j + this.state[this.i] & 255;
            const t = this.state[this.i];
            this.state[this.i] = this.state[this.j];
            this.state[this.j] = t;
            out[at] = bytes[at] ^ this.state[this.state[this.i] + this.state[this.j] & 255];
          }
          return out;
        }
      };
      exports_23("Rc4", Rc4);
    }
  };
});
System.register("ppt/encryption", ["core/errors", "core/crypto"], function(exports_24, context_24) {
  "use strict";
  var errors_js_13, crypto_js_1, CURRENT_USER, USER_EDIT, PERSIST_DIRECTORY, PERSIST_FULL, CRYPT_SESSION, TOKEN_PLAIN, TOKEN_ENCRYPTED, view;
  var __moduleName = context_24 && context_24.id;
  function fail(code, message, offset) {
    throw new errors_js_13.PptError(code, message, offset);
  }
  function header(bytes, offset, limit = bytes.length) {
    if (!Number.isSafeInteger(offset) || offset < 0 || offset + 8 > limit || limit > bytes.length)
      fail("ENCRYPTION_RECORD", "Encrypted PPT record header is outside its stream", offset);
    const v = view(bytes), packed = v.getUint16(offset, true), length = v.getUint32(offset + 4, true), end = offset + 8 + length;
    if (end > limit)
      fail("ENCRYPTION_RECORD", "Encrypted PPT record length exceeds its available range", offset);
    return { offset, version: packed & 15, instance: packed >>> 4, type: v.getUint16(offset + 2, true), length, end };
  }
  function noOverlaps(spans) {
    spans.sort((a, b) => a.start - b.start || a.end - b.end);
    for (let i = 1; i < spans.length; i++)
      if (spans[i].start < spans[i - 1].end)
        fail("ENCRYPTION_OVERLAP", `${spans[i].label} overlaps ${spans[i - 1].label}`, spans[i].start);
  }
  function blockKey(passwordHash, block, keyBits) {
    const hash = crypto_js_1.sha1(crypto_js_1.concatBytes(passwordHash, crypto_js_1.little32(block)));
    if (keyBits === 40) {
      const key2 = new Uint8Array(16);
      key2.set(hash.subarray(0, 5));
      hash.fill(0);
      return key2;
    }
    const key = hash.slice(0, keyBits / 8);
    hash.fill(0);
    return key;
  }
  function cipher(passwordHash, block, keyBits) {
    const key = blockKey(passwordHash, block, keyBits);
    try {
      return new crypto_js_1.Rc4(key);
    } finally {
      key.fill(0);
    }
  }
  function readMetadata(document2, record, password) {
    const start = record.offset + 8, end = record.end, v = view(document2);
    if (record.version !== 15 || record.instance !== 0 || record.type !== CRYPT_SESSION || start + 12 > end)
      fail("ENCRYPTION_HEADER", "Invalid CryptSession10Container", record.offset);
    const major = v.getUint16(start, true), minor = v.getUint16(start + 2, true), outerFlags = v.getUint32(start + 4, true), size = v.getUint32(start + 8, true), at = start + 12;
    if (![2, 3, 4].includes(major) || minor !== 2)
      fail("ENCRYPTION_UNSUPPORTED", "Only Office Binary RC4 CryptoAPI encryption is supported", start);
    if (size < 32 || size & 1 || at + size + 60 > end)
      fail("ENCRYPTION_HEADER", "Truncated or invalid CryptoAPI header/verifier", at);
    const flags = v.getUint32(at, true), sizeExtra = v.getUint32(at + 4, true), algorithm = v.getUint32(at + 8, true), hashAlgorithm = v.getUint32(at + 12, true), keyBits = v.getUint32(at + 16, true) || 40, provider = v.getUint32(at + 20, true);
    if (flags !== outerFlags)
      fail("ENCRYPTION_HEADER", "The two CryptoAPI flag fields disagree", at);
    if (!(flags & 4) || flags & 48 || ![0, 26625].includes(algorithm) || ![0, 32772].includes(hashAlgorithm) || provider !== 1)
      fail("ENCRYPTION_UNSUPPORTED", "The PPT cryptographic header does not specify supported RC4/SHA-1 parameters", at);
    if (sizeExtra !== 0 || keyBits < 40 || keyBits > 128 || keyBits % 8)
      fail("ENCRYPTION_HEADER", "Invalid CryptoAPI key size or reserved length", at);
    if (size > 32) {
      let terminated = false;
      for (let p = at + 32; p + 1 < at + size; p += 2)
        if (v.getUint16(p, true) === 0) {
          terminated = true;
          break;
        }
      if (!terminated)
        fail("ENCRYPTION_HEADER", "CryptoAPI provider name is not null terminated", at + 32);
    }
    const verifier = at + size;
    if (v.getUint32(verifier, true) !== 16 || v.getUint32(verifier + 36, true) !== 20)
      fail("ENCRYPTION_VERIFIER", "RC4 CryptoAPI requires a 16-byte salt and 20-byte SHA-1 verifier hash", verifier);
    const passwordData = crypto_js_1.passwordBytes(password), salt = document2.subarray(verifier + 4, verifier + 20), passwordHash = crypto_js_1.sha1(crypto_js_1.concatBytes(salt, passwordData));
    passwordData.fill(0);
    const rc4 = cipher(passwordHash, 0, keyBits), plainVerifier = rc4.crypt(document2.subarray(verifier + 20, verifier + 36)), plainHash = rc4.crypt(document2.subarray(verifier + 40, verifier + 60)), computed = crypto_js_1.sha1(plainVerifier), valid = crypto_js_1.equalBytes(plainHash, computed);
    plainVerifier.fill(0);
    plainHash.fill(0);
    computed.fill(0);
    if (!valid) {
      passwordHash.fill(0);
      fail("PASSWORD_INVALID", "The supplied password does not match this presentation");
    }
    return { passwordHash, keyBits, flags };
  }
  function decryptPictures(input, metadata, limits, diagnostics) {
    if (input.length > limits.maxStreamBytes)
      fail("LIMIT_STREAM", "Encrypted Pictures stream exceeds the stream byte limit");
    const output = input.slice();
    let at = 0, count = 0;
    const field = (offset, length, end) => {
      if (!Number.isSafeInteger(length) || length < 0 || offset < 0 || offset + length > end)
        fail("ENCRYPTION_PICTURE", "Encrypted picture field exceeds its record", offset);
      if (length)
        output.set(cipher(metadata.passwordHash, 0, metadata.keyBits).crypt(input.subarray(offset, offset + length)), offset);
    };
    const rasterInstances = { 61469: [1130, 1131, 1762, 1763], 61482: [1130, 1131, 1762, 1763], 61470: [1760, 1761], 61471: [1960, 1961], 61481: [1764, 1765] };
    const metafileInstances = { 61466: [980, 981], 61467: [534, 535], 61468: [1346, 1347] };
    while (at < input.length) {
      if (++count > limits.maxRecords)
        fail("LIMIT_RECORDS", "Encrypted picture count exceeds the record budget");
      field(at, 8, input.length);
      const rh = header(output, at), end = rh.end;
      let p = at + 8;
      const known = rasterInstances[rh.type] ?? metafileInstances[rh.type];
      if (known && (!known.includes(rh.instance) || rh.version !== 0))
        fail("ENCRYPTION_PICTURE_UNSUPPORTED", "An encrypted BLIP uses an unsupported instance or version", at);
      if (known) {
        field(p, 16, end);
        p += 16;
        if (rh.instance & 1) {
          field(p, 16, end);
          p += 16;
        }
        if (metafileInstances[rh.type]) {
          field(p, 34, end);
          const size = view(output).getUint32(p + 28, true);
          p += 34;
          if (size !== end - p)
            fail("ENCRYPTION_PICTURE", "Metafile stored size disagrees with its encrypted BLIP length", p - 6);
        } else {
          field(p, 1, end);
          p++;
        }
        field(p, end - p, end);
      } else if (rh.type === 61447 && rh.version === 2) {
        for (const length of [1, 1, 16, 2, 4, 4, 4, 1, 1, 1, 1]) {
          field(p, length, end);
          p += length;
        }
        const nameLength = output[at + 41];
        if (nameLength & 1)
          fail("ENCRYPTION_PICTURE", "FBSE name byte count is not even", at + 41);
        field(p, nameLength, end);
        p += nameLength;
        if (p < end) {
          field(p, end - p, end);
          const embedded = header(output, p, end);
          if (embedded.end !== end || embedded.type < 61464 || embedded.type > 61719)
            fail("ENCRYPTION_PICTURE", "Invalid embedded BLIP inside encrypted FBSE", p);
        }
      } else {
        diagnostics.push({ code: "ENCRYPTED_PICTURE_UNSUPPORTED", severity: "warning", message: "An encrypted picture uses an unknown field layout; its ciphertext payload is retained and is not treated as a decoded image", offset: at, details: { recordType: rh.type, instance: rh.instance } });
      }
      at = end;
    }
    return output;
  }
  function decryptPptStreams(cfb, password, limits, diagnostics) {
    const document2 = cfb.getStream("PowerPoint Document"), currentUser = cfb.getStream("Current User");
    if (!document2 || !currentUser)
      return void 0;
    if (currentUser.length < 20)
      return void 0;
    const cv = view(currentUser);
    if (cv.getUint16(2, true) !== CURRENT_USER)
      return void 0;
    const token = cv.getUint32(12, true), encryptedToken = token === TOKEN_ENCRYPTED;
    if (encryptedToken && password === void 0)
      fail("ENCRYPTED_PPT", "This presentation is encrypted; supply its password");
    const editOffset = cv.getUint32(16, true);
    if (editOffset + 40 > document2.length) {
      if (encryptedToken)
        fail("ENCRYPTION_RECORD", "Encrypted UserEditAtom is truncated", editOffset);
      return void 0;
    }
    const dv = view(document2), editLength = dv.getUint32(editOffset + 4, true), editType = dv.getUint16(editOffset + 2, true);
    if (editType !== USER_EDIT || editLength < 32) {
      if (encryptedToken)
        fail("ENCRYPTION_HEADER", "Encrypted presentation has no encryption-session persist reference", editOffset);
      return void 0;
    }
    const cryptoId = dv.getUint32(editOffset + 36, true);
    if (!cryptoId) {
      if (encryptedToken)
        fail("ENCRYPTION_HEADER", "Encrypted presentation has a zero encryption-session persist reference", editOffset);
      return void 0;
    }
    if (password === void 0)
      fail("ENCRYPTED_PPT", "This presentation is encrypted; supply its password");
    if (document2.length > limits.maxStreamBytes || currentUser.length > limits.maxStreamBytes)
      fail("LIMIT_STREAM", "Encrypted PPT stream exceeds the configured limit");
    const current = header(currentUser, 0);
    if (current.type !== CURRENT_USER || current.length < 20 || ![TOKEN_ENCRYPTED, TOKEN_PLAIN].includes(token))
      fail("ENCRYPTION_HEADER", "Invalid encrypted CurrentUserAtom");
    const edit = header(document2, editOffset);
    if (edit.version !== 0 || edit.instance !== 0 || edit.length !== 32)
      fail("ENCRYPTION_HEADER", "Invalid encrypted UserEditAtom", editOffset);
    if (dv.getUint32(editOffset + 16, true) !== 0)
      fail("ENCRYPTION_EDIT_CHAIN", "An encrypted PPT must have exactly one UserEditAtom", editOffset);
    const dirOffset = dv.getUint32(editOffset + 20, true), directory = header(document2, dirOffset);
    if (![PERSIST_DIRECTORY, PERSIST_FULL].includes(directory.type) || directory.version !== 0)
      fail("ENCRYPTION_DIRECTORY", "Invalid unencrypted persist directory", dirOffset);
    const objects = /* @__PURE__ */ new Map();
    let at = dirOffset + 8;
    while (at < directory.end) {
      if (at + 4 > directory.end)
        fail("ENCRYPTION_DIRECTORY", "Truncated encrypted-document persist entry", at);
      const packed = dv.getUint32(at, true), start = packed & 1048575, count = packed >>> 20;
      at += 4;
      if (!start || !count || start + count > 1048576 || at + count * 4 > directory.end)
        fail("ENCRYPTION_DIRECTORY", "Invalid encrypted-document persist range", at - 4);
      if (objects.size + count > limits.maxRecords)
        fail("LIMIT_RECORDS", "Encrypted persist directory exceeds the record budget");
      for (let i = 0; i < count; i++) {
        const id = start + i, offset = dv.getUint32(at + i * 4, true);
        if (objects.has(id) || offset + 8 > document2.length)
          fail("ENCRYPTION_DIRECTORY", "Duplicate persist ID or invalid encrypted-object offset", at + i * 4);
        objects.set(id, offset);
      }
      at += count * 4;
    }
    const cryptOffset = objects.get(cryptoId);
    if (cryptOffset === void 0)
      fail("ENCRYPTION_HEADER", "Encryption-session persist object is missing");
    const crypt = header(document2, cryptOffset), protectedSpans = [{ start: editOffset, end: edit.end, label: "UserEditAtom" }, { start: dirOffset, end: directory.end, label: "PersistDirectoryAtom" }, { start: cryptOffset, end: crypt.end, label: "CryptSession10Container" }];
    noOverlaps([...protectedSpans]);
    const offsets = [...objects].map(([id, offset]) => ({ id, offset })).sort((a, b) => a.offset - b.offset);
    for (let i = 1; i < offsets.length; i++)
      if (offsets[i].offset === offsets[i - 1].offset)
        fail("ENCRYPTION_OVERLAP", "Different persist IDs alias the same encrypted bytes", offsets[i].offset);
    const metadata = readMetadata(document2, crypt, password);
    try {
      const spans = [...protectedSpans], decrypted = [];
      for (const entry of offsets) {
        if (entry.id === cryptoId)
          continue;
        const first = cipher(metadata.passwordHash, entry.id, metadata.keyBits).crypt(document2.subarray(entry.offset, entry.offset + 8)), length = view(first).getUint32(4, true), end = entry.offset + 8 + length;
        if (end > document2.length)
          fail("ENCRYPTION_RECORD", "Decrypted persist length exceeds its stream", entry.offset);
        spans.push({ start: entry.offset, end, label: `Persist object ${entry.id}` });
        decrypted.push({ id: entry.id, offset: entry.offset, length });
      }
      noOverlaps(spans);
      const output = document2.slice();
      for (const object of decrypted)
        output.set(cipher(metadata.passwordHash, object.id, metadata.keyBits).crypt(document2.subarray(object.offset, object.offset + 8 + object.length)), object.offset);
      view(output).setUint32(editOffset + 36, 0, true);
      const user = currentUser.slice();
      view(user).setUint32(12, TOKEN_PLAIN, true);
      const pictures = decryptPictures(cfb.getStream("Pictures") ?? new Uint8Array(), metadata, limits, diagnostics);
      if (!(metadata.flags & 8))
        diagnostics.push({ code: "ENCRYPTED_METADATA_UNSUPPORTED", severity: "info", message: "Encrypted summary properties are retained in the input file and are not exposed as document metadata" });
      diagnostics.push({ code: "PPT_DECRYPTED", severity: "info", message: "The presentation was decrypted with the supplied password using RC4 CryptoAPI", details: { keyBits: metadata.keyBits } });
      return { document: output, currentUser: user, pictures };
    } finally {
      metadata.passwordHash.fill(0);
    }
  }
  exports_24("decryptPptStreams", decryptPptStreams);
  return {
    setters: [
      function(errors_js_13_1) {
        errors_js_13 = errors_js_13_1;
      },
      function(crypto_js_1_1) {
        crypto_js_1 = crypto_js_1_1;
      }
    ],
    execute: function() {
      CURRENT_USER = 4086, USER_EDIT = 4085, PERSIST_DIRECTORY = 6002, PERSIST_FULL = 6001, CRYPT_SESSION = 12052;
      TOKEN_PLAIN = 3817979999, TOKEN_ENCRYPTED = 4090610911;
      view = (bytes) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    }
  };
});
System.register("ppt/parser", ["core/cfb", "core/errors", "core/utils", "ppt/constants", "ppt/records", "ppt/text", "ppt/drawing", "ppt/pictures", "ppt/extras", "ppt/headers-footers", "ppt/animation", "ppt/encryption", "ppt/interactions"], function(exports_25, context_25) {
  "use strict";
  var cfb_js_1, errors_js_14, utils_js_8, constants_js_5, records_js_7, text_js_2, drawing_js_1, pictures_js_2, extras_js_1, headers_footers_js_1, animation_js_1, encryption_js_1, interactions_js_2, VERSION, now;
  var __moduleName = context_25 && context_25.id;
  function dataView(bytes) {
    return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
  function readPersistDirectory(bytes, currentUser, ctx) {
    const cctx = { ...ctx, bytes: currentUser, count: 0 };
    const current = records_js_7.readRecord(cctx, 0);
    if (current.type !== constants_js_5.RT.CurrentUserAtom || current.length < 20)
      throw new errors_js_14.PptError("CURRENT_USER", "Invalid Current User stream");
    const cv = dataView(currentUser), token = cv.getUint32(current.dataOffset + 4, true);
    if (token === 4090610911)
      throw new errors_js_14.PptError("ENCRYPTED_PPT", "Decrypt this encrypted presentation with its supplied password before reading its persist graph");
    if (token !== 3817979999)
      throw new errors_js_14.PptError("CURRENT_USER", "Unrecognized PowerPoint Current User token");
    let edit = cv.getUint32(current.dataOffset + 8, true), documentId = 0, editCount = 0;
    const objects = /* @__PURE__ */ new Map(), seen = /* @__PURE__ */ new Set();
    const view = dataView(bytes);
    while (edit !== 0) {
      if (seen.has(edit))
        throw new errors_js_14.PptError("PERSIST_CYCLE", "Cycle in UserEdit chain", edit);
      seen.add(edit);
      const user = records_js_7.readRecord(ctx, edit);
      if (user.type !== constants_js_5.RT.UserEditAtom || user.length < 28)
        throw new errors_js_14.PptError("USER_EDIT", "Invalid UserEditAtom", edit);
      const p = user.dataOffset;
      if (user.length >= 32 && view.getUint32(p + 28, true) !== 0)
        throw new errors_js_14.PptError("ENCRYPTED_PPT", "Encrypted persist objects must be decrypted before reading the graph", edit);
      if (editCount++ === 0)
        documentId = view.getUint32(p + 16, true);
      const directory = records_js_7.readRecord(ctx, view.getUint32(p + 12, true));
      if (directory.type !== constants_js_5.RT.PersistDirectoryAtom && directory.type !== constants_js_5.RT.PersistDirectoryFullBlock)
        throw new errors_js_14.PptError("PERSIST_DIRECTORY", "UserEdit references an invalid persist directory", directory.offset);
      let at = directory.dataOffset;
      while (at < directory.end) {
        if (at + 4 > directory.end)
          throw new errors_js_14.PptError("PERSIST_DIRECTORY", "Truncated persist directory entry", at);
        const packed = view.getUint32(at, true), start = packed & 1048575, count = packed >>> 20;
        at += 4;
        if (count === 0 || start === 0 || start + count > 1048576 || at + count * 4 > directory.end)
          throw new errors_js_14.PptError("PERSIST_DIRECTORY", "Invalid persist directory range", at - 4);
        for (let i = 0; i < count; i++) {
          const offset = view.getUint32(at + i * 4, true);
          if (offset + 8 > bytes.length)
            throw new errors_js_14.PptError("PERSIST_OFFSET", "Persist object offset is outside PowerPoint Document", offset);
          if (!objects.has(start + i))
            objects.set(start + i, offset);
        }
        at += count * 4;
      }
      edit = view.getUint32(p + 8, true);
    }
    if (!documentId || !objects.has(documentId))
      throw new errors_js_14.PptError("PERSIST_DOCUMENT", "Current document persist object is missing");
    return { objects, documentId, editCount };
  }
  exports_25("readPersistDirectory", readPersistDirectory);
  function slideReferences(list, bytes) {
    if (!list)
      return [];
    const v = dataView(bytes), out = [];
    let ref;
    for (const record of list.children) {
      if (record.type === constants_js_5.RT.SlidePersistAtom) {
        if (record.length < 20)
          throw new errors_js_14.PptError("SLIDE_PERSIST", "Truncated SlidePersistAtom", record.offset);
        ref = { persistId: v.getUint32(record.dataOffset, true), id: v.getUint32(record.dataOffset + 12, true), textCount: v.getUint32(record.dataOffset + 8, true), texts: [] };
        out.push(ref);
      } else if (ref)
        ref.texts.push(record);
    }
    return out;
  }
  function scheme(records, bytes, fallback) {
    const choices = records.filter((r2) => r2.type === constants_js_5.RT.ColorSchemeAtom && r2.length >= 32);
    const r = choices.find((r2) => r2.instance === 1) ?? choices[0];
    if (!r)
      return fallback;
    const v = dataView(bytes);
    return Array.from({ length: 8 }, (_, i) => v.getUint32(r.dataOffset + i * 4, true) & 16777215);
  }
  function rgb(value) {
    return "#" + [value & 255, value >>> 8 & 255, value >>> 16 & 255].map((x) => x.toString(16).padStart(2, "0")).join("");
  }
  function frames(shapes) {
    const out = [];
    for (const shape of shapes) {
      if (shape.text)
        out.push(shape.text);
      if (shape.children)
        out.push(...frames(shape.children));
    }
    return out;
  }
  function validateLimits(options) {
    const limits = { ...constants_js_5.DEFAULT_LIMITS, ...options.limits };
    for (const [key, value] of Object.entries(limits))
      if (!Number.isSafeInteger(value) || value <= 0)
        throw new errors_js_14.PptError("INVALID_LIMIT", `Invalid parse limit ${key}`);
    return limits;
  }
  function summary(bytes) {
    const result = {};
    if (!bytes || bytes.length < 48)
      return result;
    try {
      const v = dataView(bytes);
      if (v.getUint16(0, true) !== 65534)
        return result;
      const p = v.getUint32(44, true);
      if (p + 8 > bytes.length)
        return result;
      const size = v.getUint32(p, true), count = v.getUint32(p + 4, true);
      if (p + size > bytes.length || 8 + count * 8 > size)
        return result;
      const map = /* @__PURE__ */ new Map();
      for (let i = 0; i < count; i++)
        map.set(v.getUint32(p + 8 + i * 8, true), p + v.getUint32(p + 12 + i * 8, true));
      let encoding = "windows-1252";
      const cp = map.get(1);
      if (cp !== void 0 && cp + 6 <= p + size && v.getUint32(cp, true) === 2) {
        const code = v.getUint16(cp + 4, true);
        encoding = code === 65001 ? "utf-8" : code === 936 ? "gbk" : code === 932 ? "shift_jis" : code === 949 ? "euc-kr" : "windows-1252";
      }
      for (const [id, key] of [[2, "title"], [3, "subject"], [4, "author"]]) {
        const at = map.get(id);
        if (at === void 0 || at + 8 > p + size)
          continue;
        const type = v.getUint32(at, true), n = v.getUint32(at + 4, true), length = type === 31 ? n * 2 : n;
        if (type !== 30 && type !== 31 || at + 8 + length > p + size)
          continue;
        result[key] = utils_js_8.trimTrailingNulls(new TextDecoder(type === 31 ? "utf-16le" : encoding).decode(bytes.subarray(at + 8, at + 8 + length)));
      }
    } catch {
    }
    return result;
  }
  function parsePpt(input, options = {}) {
    const started = now(), inputBytes = cfb_js_1.toBytes(input), limits = validateLimits(options), diagnostics = [];
    if (inputBytes[0] === 80 && inputBytes[1] === 75)
      throw new errors_js_14.PptError("UNSUPPORTED_PPTX", "This parser handles binary .ppt files. Use a separate OOXML parser for .pptx.");
    const cfb = new cfb_js_1.CompoundFile(inputBytes, limits, diagnostics, options.strict);
    const decrypted = encryption_js_1.decryptPptStreams(cfb, options.password, limits, diagnostics);
    const bytes = decrypted?.document ?? cfb.getStream("PowerPoint Document"), currentUser = decrypted?.currentUser ?? cfb.getStream("Current User");
    if (!bytes || !currentUser)
      throw new errors_js_14.PptError("NOT_PPT", "Required PowerPoint Document or Current User stream is missing");
    const rc = { bytes, limits, diagnostics, count: 0, strict: options.strict };
    const persist = readPersistDirectory(bytes, currentUser, rc);
    const cache = /* @__PURE__ */ new Map();
    const recordCount = { get value() {
      return rc.count;
    }, set value(value) {
      rc.count = value;
    } };
    const object = (id) => {
      let node = cache.get(id);
      if (node)
        return node;
      const offset = persist.objects.get(id);
      if (offset === void 0)
        throw new errors_js_14.PptError("PERSIST_MISSING", `Persist object ${id} is missing`);
      node = records_js_7.readRecord(rc, offset);
      cache.set(id, node);
      return node;
    };
    const document2 = object(persist.documentId);
    if (document2.type !== constants_js_5.RT.Document)
      throw new errors_js_14.PptError("DOCUMENT", "Document persist ID does not refer to a DocumentContainer");
    const da = document2.children.find((r) => r.type === constants_js_5.RT.DocumentAtom);
    if (!da || da.length < 40)
      throw new errors_js_14.PptError("DOCUMENT_ATOM", "Required DocumentAtom is missing or truncated");
    const dv = dataView(bytes);
    const size = { width: dv.getInt32(da.dataOffset, true) / 6, height: dv.getInt32(da.dataOffset + 4, true) / 6 };
    const notesSize = { width: dv.getInt32(da.dataOffset + 8, true) / 6, height: dv.getInt32(da.dataOffset + 12, true) / 6 }, notesMasterPersistId = dv.getUint32(da.dataOffset + 24, true);
    const firstSlideNumber = dv.getUint16(da.dataOffset + 32, true), omitTitlePlace = !!dv.getUint8(da.dataOffset + 37);
    if (firstSlideNumber >= 1e4)
      diagnostics.push({ code: "SLIDE_NUMBER_RANGE", severity: "warning", message: "Document first-slide number exceeds the specification range", offset: da.offset });
    const hfContext = { bytes, limits, diagnostics }, documentHeadersFooters = headers_footers_js_1.parseHeaderFooter(document2.children, hfContext, 3), notesHeadersFooters = headers_footers_js_1.parseHeaderFooter(document2.children, hfContext, 4);
    if (!(size.width > 0 && size.height > 0 && size.width <= 1e6 && size.height <= 1e6))
      throw new errors_js_14.PptError("SLIDE_SIZE", "Invalid slide dimensions");
    const lists = document2.children.filter((r) => r.type === constants_js_5.RT.SlideListWithText);
    const slideRefs = slideReferences(lists.find((r) => r.instance === 0), bytes), masterRefs = slideReferences(lists.find((r) => r.instance === 1), bytes), noteRefs = slideReferences(lists.find((r) => r.instance === 2), bytes);
    if (slideRefs.length > limits.maxSlides || masterRefs.length > limits.maxSlides || noteRefs.length > limits.maxSlides)
      throw new errors_js_14.PptError("LIMIT_SLIDES", "Presentation exceeds the slide count limit");
    const drawingGroup = document2.children.find((r) => r.type === constants_js_5.RT.PPDrawingGroup);
    const picturesBytes = decrypted?.pictures ?? cfb.getStream("Pictures") ?? new Uint8Array(0);
    const pictureResult = pictures_js_2.parsePictures(drawingGroup, bytes, picturesBytes, diagnostics, limits);
    const extras = { hyperlinks: [], sounds: [], media: [], oleObjects: [], comments: [], animationRecordTypes: [] };
    const hyperlinkTargets = /* @__PURE__ */ new Map(), oleStorage = /* @__PURE__ */ new Map();
    let assetCursor = 0, totalAssetBytes = 0;
    const assetSize = () => {
      while (assetCursor < pictureResult.assets.length)
        totalAssetBytes += pictureResult.assets[assetCursor++].bytes.length;
      return totalAssetBytes;
    };
    const remainingLimits = () => ({ ...limits, maxAssetBytes: Math.max(0, limits.maxAssetBytes - assetSize()), maxRecords: Math.max(0, limits.maxRecords - rc.count) });
    function mergeExtras(part) {
      rc.count += part.additionalRecordCount;
      if (rc.count > limits.maxRecords)
        throw new errors_js_14.PptError("LIMIT_RECORDS", "Presentation exceeds the aggregate record limit");
      pictureResult.assets.push(...part.assets);
      if (assetSize() > limits.maxAssetBytes)
        throw new errors_js_14.PptError("LIMIT_ASSETS", "Presentation exceeds the aggregate asset limit");
      interactions_js_2.resolveSlideLinks(part.hyperlinks, slideRefs, part.hyperlinkTargets, diagnostics);
      for (const [id, href] of part.hyperlinkTargets)
        if (!hyperlinkTargets.has(id))
          hyperlinkTargets.set(id, href);
      extras.hyperlinks.push(...part.hyperlinks);
      extras.sounds.push(...part.sounds);
      extras.media.push(...part.media);
      extras.comments.push(...part.comments);
      for (const type of part.animationRecordTypes)
        if (!extras.animationRecordTypes.includes(type))
          extras.animationRecordTypes.push(type);
      for (const embedded of part.oleObjects) {
        const id = embedded.storagePersistId;
        if (id) {
          const known = oleStorage.get(id);
          if (known)
            embedded.assetId = known;
          else if (persist.objects.has(id)) {
            const storage = extras_js_1.extractOleStorage(object(id), bytes, limits.maxAssetBytes - assetSize(), diagnostics);
            if (storage) {
              pictureResult.assets.push(storage);
              embedded.assetId = storage.id;
              oleStorage.set(id, storage.id);
            }
          } else
            diagnostics.push({ code: "OLE_STORAGE_MISSING", severity: "warning", message: "The embedded object storage persist ID is missing", offset: embedded.sourceOffset, details: { persistId: id } });
        }
        extras.oleObjects.push(embedded);
      }
    }
    mergeExtras(extras_js_1.parseDocumentExtras(document2.children, bytes, remainingLimits(), diagnostics));
    const fonts = text_js_2.parseFonts(document2.children, bytes);
    const baseColors = [16777215, 0, 8421504, 0, 16777215, 16711680, 255, 8388736];
    const tc = { bytes, fonts, colors: baseColors, diagnostics, limits, hyperlinkTargets };
    const environment = document2.children.find((r) => r.type === constants_js_5.RT.Environment);
    tc.defaultStyle = text_js_2.parseDefaultTextStyle(environment?.children ?? [], tc);
    const defaultStyles = text_js_2.parseMasterTextStyles(environment?.children ?? [], tc);
    const drawingDefaults = drawing_js_1.readDrawingDefaults(drawingGroup, bytes, diagnostics, limits, recordCount);
    const shapeCount = { value: 0 };
    const common = { ...tc, assets: pictureResult.assets, pictureIds: pictureResult.pictureIds, slideTexts: [], shapeCount, drawingDefaults, recordCount };
    const masters = [];
    const masterStyles = /* @__PURE__ */ new Map();
    const notes = /* @__PURE__ */ new Map();
    let notesMaster, notesMasterTextStyles;
    const masterReferences = new Map(masterRefs.map((ref, index) => [ref.id, { ref, index }]));
    const masterById = /* @__PURE__ */ new Map(), resolvingMasters = /* @__PURE__ */ new Set();
    function resolveMaster(id) {
      if (!id)
        return void 0;
      const cached = masterById.get(id);
      if (cached)
        return cached;
      const entry = masterReferences.get(id);
      if (!entry)
        return void 0;
      if (resolvingMasters.has(id))
        throw new errors_js_14.PptError("MASTER_CYCLE", "Cycle in slide master inheritance");
      if (resolvingMasters.size >= limits.maxDepth)
        throw new errors_js_14.PptError("LIMIT_DEPTH", "Slide master inheritance exceeds the configured nesting limit");
      resolvingMasters.add(id);
      const master = parseOne(entry.ref, entry.index, true);
      resolvingMasters.delete(id);
      masters.push(master);
      masterById.set(id, master);
      return master;
    }
    function parseOne(ref, index, isMaster = false, isNotesMaster = false) {
      const diagnosticStart = diagnostics.length;
      const node = object(ref.persistId);
      if (node.type !== constants_js_5.RT.Slide && node.type !== constants_js_5.RT.MainMaster && node.type !== constants_js_5.RT.Notes)
        throw new errors_js_14.PptError("SLIDE_OBJECT", "Slide list references a non-slide object", node.offset);
      const atom = node.children.find((r) => r.type === constants_js_5.RT.SlideAtom), masterId = atom && atom.length >= 20 ? dv.getUint32(atom.dataOffset + 12, true) : 0;
      const noteAtom = node.type === constants_js_5.RT.Notes ? node.children.find((r) => r.type === constants_js_5.RT.NotesAtom) : void 0;
      const flags = noteAtom && noteAtom.length >= 6 ? dv.getUint16(noteAtom.dataOffset + 4, true) : atom && atom.length >= 22 ? dv.getUint16(atom.dataOffset + 20, true) : 7;
      const master = node.type === constants_js_5.RT.Notes ? isNotesMaster ? void 0 : notesMaster : resolveMaster(masterId);
      const colors = flags & 2 && master?.colorScheme ? master.colorScheme : scheme(node.children, bytes, master?.colorScheme ?? baseColors);
      const slideExtras = extras_js_1.parseSlideExtras(node.children, bytes, remainingLimits(), diagnostics, ref.id);
      mergeExtras(slideExtras);
      const localContext = { ...tc, colors, masterStyles: (node.type === constants_js_5.RT.Notes ? notesMasterTextStyles : masterStyles.get(masterId)) ?? defaultStyles };
      if (isMaster) {
        const own = text_js_2.parseMasterTextStyles(node.children, localContext);
        const merged = new Map(localContext.masterStyles);
        for (const [key, value] of own)
          merged.set(key, value);
        localContext.masterStyles = merged;
        if (isNotesMaster)
          notesMasterTextStyles = merged;
        else
          masterStyles.set(ref.id, merged);
      }
      const slideTexts = text_js_2.parseTextFrames(ref.texts, localContext);
      const drawing = node.children.find((r) => r.type === constants_js_5.RT.PPDrawing);
      const shapes = drawing ? drawing_js_1.parseDrawing(drawing, { ...common, ...localContext, slideTexts, masterShapes: master?.shapes }) : [];
      interactions_js_2.bindShapeInteractions(node.children, bytes, shapes, extras, hyperlinkTargets, diagnostics, ref.id);
      let background = flags & 4 && master ? master.background : { kind: "solid", color: rgb(colors[0] ?? 16777215) };
      const visibleShapes = [];
      for (const shape of shapes) {
        if ((shape.source?.properties?.fspFlags ?? 0) & 1024) {
          if (!(flags & 4) || !master)
            background = shape.fill;
        } else
          visibleShapes.push(shape);
      }
      if (!drawing && slideTexts.length)
        diagnostics.push({ code: "SLIDE_NO_DRAWING", severity: "warning", message: "Text exists but the slide has no drawing container; original positioning is unavailable.", slideId: ref.id });
      const name = slideTexts.map((f) => f.sourceText ?? f.paragraphs.flatMap((p) => p.runs.map((r) => r.text)).join("")).find((t) => t.trim())?.slice(0, 200);
      const layoutType = atom && atom.length >= 4 ? dv.getUint32(atom.dataOffset, true) : void 0;
      const headersFooters = headers_footers_js_1.resolveHeaderFooter(node.type === constants_js_5.RT.Notes ? notesHeadersFooters : documentHeadersFooters, master?.headersFooters, headers_footers_js_1.parseHeaderFooter(node.children, hfContext));
      const slide = { id: ref.id, persistId: ref.persistId, index, name, size: node.type === constants_js_5.RT.Notes ? notesSize : size, masterId: masterId || void 0, shapes: visibleShapes, background, showMasterShapes: !!(flags & 1), colorScheme: colors, headersFooters, displayNumber: firstSlideNumber + index, layoutType, suppressHeaderFooter: !isMaster && node.type === constants_js_5.RT.Slide && layoutType === 0 && omitTitlePlace };
      const hasModernTiming = slideExtras.animationRecordTypes.some((t) => t >= 61733 && t <= 61765);
      const effects = animation_js_1.parseLegacyAnimations(node.children, bytes, shapes, diagnostics, ref.id, hasModernTiming);
      if (effects.length)
        slide.timeline = { effects };
      const show = node.children.find((r) => r.type === constants_js_5.RT.SSSlideInfoAtom);
      if (show && show.length >= 16) {
        const p = show.dataOffset, showFlags = dv.getUint16(p + 10, true);
        slide.transition = { type: dv.getUint8(p + 9), direction: dv.getUint8(p + 8), duration: [750, 500, 250][dv.getUint8(p + 12)], autoAdvanceAfterMs: showFlags & 1024 ? dv.getUint32(p, true) : void 0, manualAdvance: !!(showFlags & 1), soundId: dv.getUint32(p + 4, true), soundEnabled: !!(showFlags & 16), loopSound: !!(showFlags & 64) };
        slide.hidden = !!(showFlags & 4);
      }
      if (slideExtras.animationRecordTypes.length && (hasModernTiming || diagnostics.slice(diagnosticStart).some((d) => d.slideId === ref.id && d.severity === "warning" && d.code.startsWith("ANIMATION_"))))
        slide.unsupportedRecordTypes = slideExtras.animationRecordTypes;
      if (atom && atom.length >= 20) {
        const noteId = dv.getUint32(atom.dataOffset + 16, true);
        if (noteId && notes.has(noteId))
          slide.notes = notes.get(noteId);
      }
      for (let i = diagnosticStart; i < diagnostics.length; i++)
        if (diagnostics[i].slideId == null)
          diagnostics[i].slideId = ref.id;
      return slide;
    }
    for (const ref of masterRefs)
      resolveMaster(ref.id);
    masters.sort((a, b) => a.index - b.index);
    notesMasterTextStyles = masterRefs[0] ? masterStyles.get(masterRefs[0].id) : defaultStyles;
    if (notesMasterPersistId) {
      if (!persist.objects.has(notesMasterPersistId))
        diagnostics.push({ code: "NOTES_MASTER_MISSING", severity: "warning", message: "The notes master persist ID is missing", details: { persistId: notesMasterPersistId } });
      else if (object(notesMasterPersistId).type !== constants_js_5.RT.Notes)
        diagnostics.push({ code: "NOTES_MASTER_TYPE", severity: "warning", message: "The notes master persist ID does not refer to a NotesContainer", offset: object(notesMasterPersistId).offset });
      else
        notesMaster = parseOne({ persistId: notesMasterPersistId, id: 0, texts: [], textCount: 0 }, -1, true, true);
    }
    for (let i = 0; i < noteRefs.length; i++) {
      const note = parseOne(noteRefs[i], i);
      notes.set(note.id, frames(note.shapes));
    }
    const slides = slideRefs.map((ref, index) => parseOne(ref, index));
    if (slides.length === 0)
      diagnostics.push({ code: "EMPTY_PRESENTATION", severity: "info", message: "The current document slide list is empty." });
    let assetBytes = 0;
    for (const asset of pictureResult.assets) {
      if (!(asset.bytes.buffer instanceof ArrayBuffer) || asset.bytes.byteOffset !== 0 || asset.bytes.byteLength !== asset.bytes.buffer.byteLength)
        asset.bytes = new Uint8Array(asset.bytes);
      assetBytes += asset.bytes.length;
    }
    if (assetBytes > limits.maxAssetBytes)
      throw new errors_js_14.PptError("LIMIT_ASSETS", "Presentation exceeds the aggregate asset limit");
    return { format: "ppt", version: VERSION, size, slides, masters, fonts, assets: pictureResult.assets, extras, diagnostics, metadata: { ...summary(cfb.getStream("SummaryInformation")), firstSlideNumber, omitTitlePlace, slideCount: slides.length, source: "Microsoft PowerPoint 97\u20132003 binary format ([MS-PPT])" }, stats: { inputBytes: inputBytes.length, streamBytes: bytes.length + picturesBytes.length, recordCount: rc.count, shapeCount: shapeCount.value, parseTimeMs: now() - started, assetBytes } };
  }
  exports_25("parsePpt", parsePpt);
  return {
    setters: [
      function(cfb_js_1_1) {
        cfb_js_1 = cfb_js_1_1;
      },
      function(errors_js_14_1) {
        errors_js_14 = errors_js_14_1;
      },
      function(utils_js_8_1) {
        utils_js_8 = utils_js_8_1;
      },
      function(constants_js_5_1) {
        constants_js_5 = constants_js_5_1;
      },
      function(records_js_7_1) {
        records_js_7 = records_js_7_1;
      },
      function(text_js_2_1) {
        text_js_2 = text_js_2_1;
      },
      function(drawing_js_1_1) {
        drawing_js_1 = drawing_js_1_1;
      },
      function(pictures_js_2_1) {
        pictures_js_2 = pictures_js_2_1;
      },
      function(extras_js_1_1) {
        extras_js_1 = extras_js_1_1;
      },
      function(headers_footers_js_1_1) {
        headers_footers_js_1 = headers_footers_js_1_1;
      },
      function(animation_js_1_1) {
        animation_js_1 = animation_js_1_1;
      },
      function(encryption_js_1_1) {
        encryption_js_1 = encryption_js_1_1;
      },
      function(interactions_js_2_1) {
        interactions_js_2 = interactions_js_2_1;
      }
    ],
    execute: function() {
      exports_25("VERSION", VERSION = "1.0.2");
      now = () => typeof performance === "undefined" ? Date.now() : performance.now();
    }
  };
});
System.register("render/safe", [], function(exports_26, context_26) {
  "use strict";
  var base64Alphabet, base64Decoder;
  var __moduleName = context_26 && context_26.id;
  function escapeXml(value) {
    return String(value ?? "").replace(/\u000b/g, "\n").replace(/[\u0000-\u0008\u000c\u000e-\u001f\ufffe\uffff]/g, "\uFFFD").replace(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g, "\uFFFD").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }
  exports_26("escapeXml", escapeXml);
  function finite(value, fallback = 0) {
    return typeof value === "number" && Number.isFinite(value) ? value : fallback;
  }
  exports_26("finite", finite);
  function n(value) {
    return String(Math.round(finite(value) * 1e4) / 1e4);
  }
  exports_26("n", n);
  function transformNumber(value) {
    return String(finite(value));
  }
  exports_26("transformNumber", transformNumber);
  function color(value, fallback = "#000000") {
    const s = String(value ?? "");
    return /^(#[\da-f]{3,8}|transparent|none)$/i.test(s) ? s : fallback;
  }
  exports_26("color", color);
  function cssFont(value) {
    return `'${String(value ?? "Arial").replace(/[\u0000-\u001f\u007f]/g, "").replace(/\\/g, "\\\\").replace(/'/g, "\\'")}', sans-serif`;
  }
  exports_26("cssFont", cssFont);
  function imageUrl(value) {
    if (typeof value !== "string")
      return void 0;
    return /^(blob:|data:image\/(?:png|jpeg|gif|bmp|webp|tiff|svg\+xml);(?:base64,|charset=utf-8,))/i.test(value) ? value : void 0;
  }
  exports_26("imageUrl", imageUrl);
  function linkUrl(value) {
    if (typeof value !== "string" || /[\u0000-\u0020\u007f]/.test(value))
      return void 0;
    return /^(?:https?:\/\/|mailto:|tel:|#)/i.test(value) ? value : void 0;
  }
  exports_26("linkUrl", linkUrl);
  function base64(bytes) {
    if (bytes.length === 0)
      return "";
    const inputBlockSize = 49152;
    const output = new Uint8Array(Math.min(65536, Math.ceil(bytes.length / 3) * 4));
    const parts = [];
    for (let start = 0; start < bytes.length; start += inputBlockSize) {
      const end = Math.min(start + inputBlockSize, bytes.length);
      const completeEnd = end - (end - start) % 3;
      let input = start, written = 0;
      while (input < completeEnd) {
        const bits = bytes[input++] << 16 | bytes[input++] << 8 | bytes[input++];
        output[written++] = base64Alphabet[bits >>> 18];
        output[written++] = base64Alphabet[bits >>> 12 & 63];
        output[written++] = base64Alphabet[bits >>> 6 & 63];
        output[written++] = base64Alphabet[bits & 63];
      }
      if (input < end) {
        const first = bytes[input++];
        const hasSecond = input < end;
        const second = hasSecond ? bytes[input] : 0;
        output[written++] = base64Alphabet[first >>> 2];
        output[written++] = base64Alphabet[(first & 3) << 4 | second >>> 4];
        output[written++] = hasSecond ? base64Alphabet[(second & 15) << 2] : 61;
        output[written++] = 61;
      }
      parts.push(base64Decoder.decode(output.subarray(0, written)));
    }
    return parts.join("");
  }
  exports_26("base64", base64);
  return {
    setters: [],
    execute: function() {
      base64Alphabet = Uint8Array.from("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", (char) => char.charCodeAt(0));
      base64Decoder = new TextDecoder();
    }
  };
});
System.register("render/geometry", ["render/safe"], function(exports_27, context_27) {
  "use strict";
  var safe_js_1;
  var __moduleName = context_27 && context_27.id;
  function mapPathToBounds(path, source, width, height) {
    const tokens = path.match(/[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g) ?? [];
    const sx = source.width ? width / source.width : 1, sy = source.height ? height / source.height : 1;
    const counts = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7, Z: 0 };
    let command = "", position = 0;
    const out = [];
    for (const token of tokens) {
      if (/^[a-zA-Z]$/.test(token)) {
        command = token;
        position = 0;
        out.push(token);
        continue;
      }
      const upper = command.toUpperCase(), count = counts[upper];
      if (count == null || count === 0)
        return path;
      const relative = command !== upper, index = position++ % count, value = Number(token);
      let mapped = value;
      if (upper === "A") {
        if (index === 0)
          mapped = value * Math.abs(sx);
        else if (index === 1)
          mapped = value * Math.abs(sy);
        else if (index === 5)
          mapped = (value - (relative ? 0 : source.x)) * sx;
        else if (index === 6)
          mapped = (value - (relative ? 0 : source.y)) * sy;
      } else if (upper === "H")
        mapped = (value - (relative ? 0 : source.x)) * sx;
      else if (upper === "V")
        mapped = (value - (relative ? 0 : source.y)) * sy;
      else
        mapped = index % 2 ? (value - (relative ? 0 : source.y)) * sy : (value - (relative ? 0 : source.x)) * sx;
      out.push(safe_js_1.n(mapped));
    }
    return out.join(" ");
  }
  exports_27("mapPathToBounds", mapPathToBounds);
  function presetGeometry(preset, width, height, properties = {}) {
    const w = width, h = height, x = (p) => safe_js_1.n(w * p), y = (p) => safe_js_1.n(h * p);
    const path = (d, open = false) => ({ tag: "path", attrs: `d="${d}"`, supported: true, open });
    const polygon = (pts) => path(`M${pts.map((p) => `${x(p[0])} ${y(p[1])}`).join("L")}Z`);
    switch (preset ?? 1) {
      case 1:
      case 75:
      case 109:
      case 202:
        return { tag: "rect", attrs: `width="${safe_js_1.n(w)}" height="${safe_js_1.n(h)}"`, supported: true };
      // Same source adjustment convention as msdoc-viewer's officeArtRoundRectRadius.
      case 2:
        return { tag: "rect", attrs: `width="${safe_js_1.n(w)}" height="${safe_js_1.n(h)}" rx="${safe_js_1.n(Math.min(w, h) * Math.max(0, Math.min(properties["327"] ?? 2592, 10800)) / 21600)}"`, supported: true };
      case 3:
        return { tag: "ellipse", attrs: `cx="${x(0.5)}" cy="${y(0.5)}" rx="${x(0.5)}" ry="${y(0.5)}"`, supported: true };
      case 4:
        return polygon([[0.5, 0], [1, 0.5], [0.5, 1], [0, 0.5]]);
      case 5:
        return polygon([[0.5, 0], [1, 1], [0, 1]]);
      case 6:
        return polygon([[0, 0], [1, 1], [0, 1]]);
      case 7:
        return polygon([[0.2, 0], [1, 0], [0.8, 1], [0, 1]]);
      case 8:
        return polygon([[0.2, 0], [0.8, 0], [1, 1], [0, 1]]);
      case 9:
        return polygon([[0.25, 0], [0.75, 0], [1, 0.5], [0.75, 1], [0.25, 1], [0, 0.5]]);
      case 10:
        return polygon([[0.3, 0], [0.7, 0], [1, 0.3], [1, 0.7], [0.7, 1], [0.3, 1], [0, 0.7], [0, 0.3]]);
      case 11:
        return polygon([[0.333, 0], [0.667, 0], [0.667, 0.333], [1, 0.333], [1, 0.667], [0.667, 0.667], [0.667, 1], [0.333, 1], [0.333, 0.667], [0, 0.667], [0, 0.333], [0.333, 0.333]]);
      case 12:
      case 58:
      case 59:
      case 60:
      case 92: {
        const count = preset === 58 ? 8 : preset === 59 ? 16 : preset === 60 ? 32 : preset === 92 ? 24 : 5;
        const points = [];
        for (let i = 0; i < count * 2; i++) {
          const a = -Math.PI / 2 + i * Math.PI / count, r = i % 2 ? 0.21 : 0.5;
          points.push([0.5 + Math.cos(a) * r, 0.5 + Math.sin(a) * r]);
        }
        return polygon(points);
      }
      case 13:
        return polygon([[0, 0.25], [0.75, 0.25], [0.75, 0], [1, 0.5], [0.75, 1], [0.75, 0.75], [0, 0.75]]);
      case 14:
        return polygon([[0, 0.25], [0.4, 0.25], [0.4, 0], [1, 0.5], [0.4, 1], [0.4, 0.75], [0, 0.75], [0.2, 0.5]]);
      case 15:
        return polygon([[0, 0], [0.7, 0], [1, 0.5], [0.7, 1], [0, 1]]);
      case 16:
        return path(`M${x(0.2)} 0H${x(1)}V${y(0.8)}L${x(0.8)} ${y(1)}H0V${y(0.2)}Z M0 ${y(0.2)}H${x(0.8)}V${y(1)} M${x(0.8)} ${y(0.2)}L${x(1)} 0`);
      case 17:
      case 61:
        return polygon([[0, 0], [1, 0], [1, 0.75], [0.5, 0.75], [0.25, 1], [0.3, 0.75], [0, 0.75]]);
      case 22:
      case 132:
        return path(`M0 ${y(0.12)}C0 ${y(-0.04)} ${x(1)} ${y(-0.04)} ${x(1)} ${y(0.12)}V${y(0.88)}C${x(1)} ${y(1.04)} 0 ${y(1.04)} 0 ${y(0.88)}Z M0 ${y(0.12)}C0 ${y(0.28)} ${x(1)} ${y(0.28)} ${x(1)} ${y(0.12)}`);
      case 23:
        return { tag: "path", attrs: `d="M${x(0.5)} 0A${x(0.5)} ${y(0.5)} 0 1 1 ${x(0.4999)} 0Z M${x(0.5)} ${y(0.25)}A${x(0.25)} ${y(0.25)} 0 1 1 ${x(0.4999)} ${y(0.25)}Z" fill-rule="evenodd"`, supported: true };
      case 19:
        return path(`M0 ${y(1)}A${safe_js_1.n(w)} ${safe_js_1.n(h)} 0 0 1 ${x(1)} 0`, true);
      case 20:
      case 32:
        return path(`M0 0L${safe_js_1.n(w)} ${safe_js_1.n(h)}`, true);
      case 33:
        return path(`M0 0H${safe_js_1.n(w)}V${safe_js_1.n(h)}`, true);
      case 34:
        return path(`M0 0H${x(0.5)}V${safe_js_1.n(h)}H${safe_js_1.n(w)}`, true);
      case 35:
      case 36:
        return path(`M0 0H${x(0.333)}V${y(0.5)}H${x(0.667)}V${safe_js_1.n(h)}H${safe_js_1.n(w)}`, true);
      case 37:
      case 38:
      case 39:
      case 40:
        return path(`M0 0C${x(0.5)} 0 ${x(0.5)} ${safe_js_1.n(h)} ${safe_js_1.n(w)} ${safe_js_1.n(h)}`, true);
      case 55:
        return polygon([[0, 0], [0.75, 0], [1, 0.5], [0.75, 1], [0, 1], [0.25, 0.5]]);
      case 56:
        return polygon([[0.5, 0], [1, 0.382], [0.809, 1], [0.191, 1], [0, 0.382]]);
      case 64:
      case 122:
        return path(`M0 ${y(0.15)}Q${x(0.25)} 0 ${x(0.5)} ${y(0.15)}T${x(1)} ${y(0.15)}L${x(1)} ${y(0.85)}Q${x(0.75)} ${y(1)} ${x(0.5)} ${y(0.85)}T0 ${y(0.85)}Z`);
      case 65:
        return path(`M0 0H${safe_js_1.n(w)}V${y(0.8)}L${x(0.8)} ${safe_js_1.n(h)}H0Z M${safe_js_1.n(w)} ${y(0.8)}H${x(0.8)}V${safe_js_1.n(h)}`);
      case 66:
        return polygon([[1, 0.25], [0.35, 0.25], [0.35, 0], [0, 0.5], [0.35, 1], [0.35, 0.75], [1, 0.75]]);
      case 68:
        return polygon([[0.25, 1], [0.25, 0.35], [0, 0.35], [0.5, 0], [1, 0.35], [0.75, 0.35], [0.75, 1]]);
      case 67:
        return polygon([[0.25, 0], [0.25, 0.65], [0, 0.65], [0.5, 1], [1, 0.65], [0.75, 0.65], [0.75, 0]]);
      case 69:
        return polygon([[0, 0.5], [0.25, 0], [0.25, 0.3], [0.75, 0.3], [0.75, 0], [1, 0.5], [0.75, 1], [0.75, 0.7], [0.25, 0.7], [0.25, 1]]);
      case 70:
        return polygon([[0.5, 0], [1, 0.25], [0.7, 0.25], [0.7, 0.75], [1, 0.75], [0.5, 1], [0, 0.75], [0.3, 0.75], [0.3, 0.25], [0, 0.25]]);
      case 73:
        return polygon([[0.4, 0], [0.8, 0], [0.6, 0.4], [1, 0.4], [0.2, 1], [0.4, 0.6], [0, 0.6]]);
      case 74:
        return path(`M${x(0.5)} ${y(1)}C${x(0.4)} ${y(0.75)} 0 ${y(0.5)} 0 ${y(0.25)}C0 ${y(-0.05)} ${x(0.35)} ${y(-0.1)} ${x(0.5)} ${y(0.2)}C${x(0.65)} ${y(-0.1)} ${x(1)} ${y(-0.05)} ${x(1)} ${y(0.25)}C${x(1)} ${y(0.5)} ${x(0.6)} ${y(0.75)} ${x(0.5)} ${y(1)}Z`);
      case 85:
        return path(`M${x(0.15)} 0Q0 0 0 ${y(0.2)}V${y(0.8)}Q0 ${y(1)} ${x(0.15)} ${y(1)}`, true);
      case 86:
        return path(`M${x(0.85)} 0Q${x(1)} 0 ${x(1)} ${y(0.2)}V${y(0.8)}Q${x(1)} ${y(1)} ${x(0.85)} ${y(1)}`, true);
      case 87:
        return path(`M${x(0.8)} 0Q${x(0.5)} 0 ${x(0.5)} ${y(0.2)}V${y(0.35)}Q${x(0.5)} ${y(0.5)} 0 ${y(0.5)}Q${x(0.5)} ${y(0.5)} ${x(0.5)} ${y(0.65)}V${y(0.8)}Q${x(0.5)} ${y(1)} ${x(0.8)} ${y(1)}`, true);
      case 88:
        return path(`M${x(0.2)} 0Q${x(0.5)} 0 ${x(0.5)} ${y(0.2)}V${y(0.35)}Q${x(0.5)} ${y(0.5)} ${x(1)} ${y(0.5)}Q${x(0.5)} ${y(0.5)} ${x(0.5)} ${y(0.65)}V${y(0.8)}Q${x(0.5)} ${y(1)} ${x(0.2)} ${y(1)}`, true);
      case 110:
        return polygon([[0.5, 0], [1, 0.5], [0.5, 1], [0, 0.5]]);
      case 111:
        return polygon([[0.2, 0], [1, 0], [0.8, 1], [0, 1]]);
      case 112:
        return path(`M0 0H${safe_js_1.n(w)}V${safe_js_1.n(h)}H0Z M${x(0.15)} 0V${safe_js_1.n(h)} M${x(0.85)} 0V${safe_js_1.n(h)}`);
      case 113:
        return path(`M0 0H${safe_js_1.n(w)}V${safe_js_1.n(h)}H0Z M${x(0.15)} 0V${safe_js_1.n(h)} M0 ${y(0.15)}H${safe_js_1.n(w)}`);
      case 114:
        return path(`M0 0H${safe_js_1.n(w)}V${y(0.85)}Q${x(0.75)} ${y(0.65)} ${x(0.5)} ${y(0.85)}T0 ${y(0.85)}Z`);
      case 116:
      case 176:
        return { tag: "rect", attrs: `width="${safe_js_1.n(w)}" height="${safe_js_1.n(h)}" rx="${safe_js_1.n(Math.min(w, h) * 0.5)}"`, supported: true };
      case 117:
        return polygon([[0.2, 0], [0.8, 0], [1, 0.5], [0.8, 1], [0.2, 1], [0, 0.5]]);
      case 118:
        return polygon([[0, 0.2], [1, 0], [1, 1], [0, 1]]);
      case 119:
        return polygon([[0, 0], [1, 0], [0.8, 1], [0.2, 1]]);
      case 120:
        return { tag: "ellipse", attrs: `cx="${x(0.5)}" cy="${y(0.5)}" rx="${x(0.5)}" ry="${y(0.5)}"`, supported: true };
      case 121:
        return polygon([[0.25, 0], [1, 0], [1, 1], [0, 1], [0, 0.25]]);
      case 125:
        return polygon([[0, 0], [1, 0], [0, 1], [1, 1]]);
      case 126:
        return path(`M${x(0.5)} 0L${x(1)} ${y(0.5)}L${x(0.5)} ${y(1)}L0 ${y(0.5)}Z M0 ${y(0.5)}H${safe_js_1.n(w)}`);
      case 127:
        return polygon([[0.5, 0], [1, 1], [0, 1]]);
      case 128:
        return polygon([[0, 0], [1, 0], [0.5, 1]]);
      case 135:
        return path(`M0 0H${x(0.5)}A${x(0.5)} ${y(0.5)} 0 0 1 ${x(0.5)} ${y(1)}H0Z`);
      case 177:
        return polygon([[0, 0], [1, 0], [1, 0.6], [0.5, 1], [0, 0.6]]);
      default:
        return { tag: "rect", attrs: `width="${safe_js_1.n(w)}" height="${safe_js_1.n(h)}"`, supported: false };
    }
  }
  exports_27("presetGeometry", presetGeometry);
  return {
    setters: [
      function(safe_js_1_1) {
        safe_js_1 = safe_js_1_1;
      }
    ],
    execute: function() {
    }
  };
});
System.register("layout/measure", [], function(exports_28, context_28) {
  "use strict";
  var graphemeSegmenter, finite;
  var __moduleName = context_28 && context_28.id;
  function fontCss(style) {
    const family = (style.fontFamily ?? "Arial").replace(/[\u0000-\u001f\u007f]/g, "").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    return `${style.italic ? "italic" : "normal"} ${style.bold ? "700" : "400"} ${Math.max(0.1, finite(style.fontSize, 24))}px "${family}",sans-serif`;
  }
  exports_28("fontCss", fontCss);
  function createCanvasTextMeasurer(owner = typeof document === "undefined" ? void 0 : document) {
    let canvas, context;
    try {
      canvas = owner ? owner.createElement("canvas") : new OffscreenCanvas(1, 1);
      context = canvas.getContext("2d");
    } catch {
      return void 0;
    }
    if (!context?.measureText)
      return void 0;
    const ctx = context, cache = /* @__PURE__ */ new Map();
    return { measure(text, style) {
      const font = fontCss(style), spacing = finite(style.letterSpacing, 0), key = `${font}\0${spacing}\0${text}`;
      const existing = cache.get(key);
      if (existing)
        return existing;
      ctx.font = font;
      ctx.textBaseline = "alphabetic";
      ctx.direction = "ltr";
      const nativeSpacing = "letterSpacing" in ctx;
      if (nativeSpacing)
        ctx.letterSpacing = `${spacing}px`;
      const m = ctx.measureText(text || "Mg"), size = Math.max(0.1, finite(style.fontSize, 24));
      let count = 0;
      if (!nativeSpacing && spacing !== 0) {
        if (graphemeSegmenter) {
          for (const _ of graphemeSegmenter.segment(text))
            count++;
        } else {
          for (const _ of text)
            count++;
        }
      }
      const result = { width: text ? Math.max(0, m.width + (nativeSpacing ? 0 : count * spacing)) : 0, ascent: finite(m.fontBoundingBoxAscent, finite(m.actualBoundingBoxAscent, size * 0.8)), descent: finite(m.fontBoundingBoxDescent, finite(m.actualBoundingBoxDescent, size * 0.2)) };
      if (cache.size >= 12e3)
        cache.clear();
      cache.set(key, result);
      return result;
    }, clear() {
      cache.clear();
    } };
  }
  exports_28("createCanvasTextMeasurer", createCanvasTextMeasurer);
  return {
    setters: [],
    execute: function() {
      graphemeSegmenter = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(void 0, { granularity: "grapheme" }) : void 0;
      finite = (value, fallback) => Number.isFinite(value) ? value : fallback;
    }
  };
});
System.register("layout/text-layout", [], function(exports_29, context_29) {
  "use strict";
  var closes, opens, cjk, breakableSpace, breakAfter, nonBreaking, hangingPunctuation, segmenter, numeric;
  var __moduleName = context_29 && context_29.id;
  function* graphemes(text) {
    if (segmenter) {
      for (const value of segmenter.segment(text))
        yield value.segment;
    } else {
      yield* text;
    }
  }
  function paragraphWrapFlags(style) {
    const mask = (style.wrapFlagsMask ?? (style.wrapFlags === void 0 ? 0 : 7)) & 7;
    return (style.wrapFlags ?? 0) & mask | 3 & ~mask;
  }
  exports_29("paragraphWrapFlags", paragraphWrapFlags);
  function paragraphDefaultTabSize(style) {
    const value = numeric(style.defaultTabSize, 48);
    return value > 0 ? value : 48;
  }
  exports_29("paragraphDefaultTabSize", paragraphDefaultTabSize);
  function scaled(style, scale) {
    return { ...style, fontSize: Math.max(0.1, numeric(style.fontSize, 24) * scale), letterSpacing: style.letterSpacing == null ? void 0 : style.letterSpacing * scale };
  }
  function metric(measurer, text, style) {
    const value = measurer.measure(text, style);
    return { width: Math.max(0, numeric(value.width)), ascent: Math.max(0, numeric(value.ascent, numeric(style.fontSize, 24) * 0.8)), descent: Math.max(0, numeric(value.descent, numeric(style.fontSize, 24) * 0.2)), ...Number.isFinite(value.lineHeight) && value.lineHeight > 0 ? { lineHeight: value.lineHeight } : {} };
  }
  function tokens(paragraph, scale, measurer) {
    const out = [];
    let previous = "";
    const needsDecimal = paragraph.style.tabStops?.some((t) => t.alignment === "decimal") ?? false;
    const flags = paragraphWrapFlags(paragraph.style), characterBreaks = !(flags & 2), kinsoku = !!(flags & 1), splitCharacters = characterBreaks || paragraph.style.alignment === "distributed";
    for (const run of paragraph.runs) {
      const style = scaled(run.style, scale), eastAsianStyle = style.eastAsianFontFamily ? { ...style, fontFamily: style.eastAsianFontFamily } : style;
      let buffer = "";
      const push = (text, kind) => {
        if (!text && kind === "text")
          return;
        const selected = cjk.test(text) ? eastAsianStyle : style;
        const m = metric(measurer, kind === "text" || kind === "space" ? text : "", selected);
        const breakBefore = !!previous && (characterBreaks || breakAfter.test(previous) || cjk.test(previous) || cjk.test(text)) && (!kinsoku || !closes.test(text) && !opens.test(previous)) && !nonBreaking.test(previous.slice(-1)) && !nonBreaking.test(text.slice(0, 1));
        const comma = [1031, 1036, 1040, 1049, 1046, 2070, 1034, 3082].includes(selected.language ?? selected.alternateLanguage ?? 0), decimalAt = needsDecimal ? text.indexOf(comma ? "," : ".") : -1;
        out.push({ text, style: selected, kind, ...m, breakBefore, hasDecimal: decimalAt >= 0, decimalPrefix: decimalAt >= 0 ? metric(measurer, text.slice(0, decimalAt), selected).width : m.width });
        previous = text;
      };
      const flush = () => {
        if (buffer) {
          push(buffer, "text");
          buffer = "";
        }
      };
      for (const char of graphemes(run.text)) {
        if (char === "	" || char === "\n" || char === "\r" || char === "\v") {
          flush();
          push(char, char === "	" ? "tab" : "break");
        } else if (breakableSpace.test(char)) {
          flush();
          push(char, "space");
        } else if (splitCharacters || cjk.test(char) || closes.test(char) || opens.test(char) || char === "-" || char === "\u2010" || char === "/") {
          flush();
          push(char, "text");
        } else
          buffer += char;
      }
      flush();
    }
    return out;
  }
  function layoutOnce(frame, options, scale) {
    const innerWidth = Math.max(0, options.width - frame.margins.left - frame.margins.right), innerHeight = Math.max(0, options.height - frame.margins.top - frame.margins.bottom), lines = [];
    let y = 0, overflowX = false, lineMetricsApproximate = false;
    const spacingScale = Math.max(0.01, numeric(options.lineSpacingScale, 1));
    frame.paragraphs.forEach((paragraph, paragraphIndex) => {
      const s = paragraph.style, firstStyle = scaled(paragraph.runs[0]?.style ?? {}, scale), firstMetrics = metric(options.measurer, "Mg", firstStyle), wrapFlags = paragraphWrapFlags(s);
      const margin = numeric(s.marginLeft), indent = numeric(s.indent), bullet = !!s.bullet && s.bulletEnabled !== false;
      const tabs = (s.tabStops ?? []).map((t) => ({ alignment: t.alignment, position: t.position + (t.origin === "paragraph" ? margin : 0) })).filter((t) => Number.isFinite(t.position)).sort((a, b) => a.position - b.position);
      const defaultTab = paragraphDefaultTabSize(s);
      const nextTab = (x) => {
        let lo = 0, hi = tabs.length;
        while (lo < hi) {
          const mid = lo + Math.floor((hi - lo) / 2);
          if (tabs[mid].position <= x + 0.01)
            lo = mid + 1;
          else
            hi = mid;
        }
        return tabs[lo] ?? { position: (Math.floor(Math.max(0, x) / defaultTab) + 1) * defaultTab, alignment: "left" };
      };
      const tabOffset = (alignment, width, decimalWidth) => alignment === "right" ? width : alignment === "center" ? width / 2 : alignment === "decimal" ? decimalWidth : 0;
      const parts = tokens(paragraph, scale, options.measurer);
      let current = [], first = true, lastHeight = firstMetrics.lineHeight ?? firstStyle.fontSize, lastBreak = -1, emptyMetrics = firstMetrics, emptyStyle = firstStyle;
      const startX = () => margin + (first && !bullet ? indent : 0);
      let cursorX = startX(), field;
      const advanceCursor = (token) => {
        if (token.kind === "tab") {
          field = { left: cursorX, tab: nextTab(cursorX), width: 0, decimalWidth: 0, decimalFound: false };
          cursorX = Math.max(cursorX, field.tab.position);
          return;
        }
        if (!field) {
          cursorX += token.width;
          return;
        }
        field.width += token.width;
        if (!field.decimalFound) {
          field.decimalWidth += token.decimalPrefix;
          field.decimalFound = token.hasDecimal;
        }
        cursorX = Math.max(field.left, field.tab.position - tabOffset(field.tab.alignment, field.width, field.decimalWidth)) + field.width;
      };
      const rebuildCursor = () => {
        cursorX = startX();
        field = void 0;
        lastBreak = -1;
        for (let i = 0; i < current.length; i++) {
          current[i].hanging = false;
          if (i > 0 && current[i].breakBefore)
            lastBreak = i;
          advanceCursor(current[i]);
        }
      };
      const arrange = (items, firstLine) => {
        let x = margin + (firstLine && !bullet ? indent : 0);
        const result = [];
        if (firstLine && bullet && s.bullet) {
          const bs = scaled({ ...paragraph.runs[0]?.style, fontFamily: s.bullet.fontFamily ?? paragraph.runs[0]?.style.fontFamily, fontSize: s.bullet.size ?? numeric(paragraph.runs[0]?.style.fontSize, 24) * numeric(s.bullet.sizePercent, 1), color: s.bullet.color ?? paragraph.runs[0]?.style.color, colorIndex: s.bullet.color !== void 0 ? s.bullet.colorIndex : s.bullet.colorIndex ?? paragraph.runs[0]?.style.colorIndex }, scale), m = metric(options.measurer, s.bullet.text, bs);
          result.push({ text: s.bullet.text, style: bs, x: margin + indent, ...m, bullet: true });
        }
        for (let i = 0; i < items.length; i++) {
          const token = items[i];
          if (token.kind === "tab") {
            let width = 0, decimalWidth = 0, foundDecimal = false;
            for (let j = i + 1; j < items.length && items[j].kind !== "tab"; j++) {
              const next = items[j];
              width += next.width;
              if (!foundDecimal) {
                decimalWidth += next.decimalPrefix;
                foundDecimal = next.hasDecimal;
              }
            }
            const tab = nextTab(x);
            x = Math.max(x, tab.position - tabOffset(tab.alignment, width, decimalWidth));
            continue;
          }
          result.push({ text: token.text, style: token.style, x, width: token.width, ascent: token.ascent, descent: token.descent, ...token.lineHeight === void 0 ? {} : { lineHeight: token.lineHeight }, ...token.hanging ? { hanging: true } : {} });
          x += token.width;
        }
        return result;
      };
      const emit = (items, last) => {
        let end = items.length;
        while (end > 0 && items[end - 1].kind === "space")
          end--;
        items = items.slice(0, end);
        const fragments = arrange(items, first), left = margin + (first && !bullet ? indent : 0);
        let right = left, ascent = fragments.length ? 0 : emptyMetrics.ascent, descent = fragments.length ? 0 : emptyMetrics.descent, spaces = 0, normalAdvance = fragments.length ? 0 : emptyMetrics.lineHeight ?? emptyStyle.fontSize, missingAdvance = !fragments.length && emptyMetrics.lineHeight === void 0;
        for (const fragment of fragments) {
          const shift = (fragment.style.fontSize ?? 24) * numeric(fragment.style.baseline) / 100;
          ascent = Math.max(ascent, fragment.ascent + shift);
          descent = Math.max(descent, fragment.descent - shift);
          normalAdvance = Math.max(normalAdvance, fragment.lineHeight ?? fragment.style.fontSize ?? 24);
          missingAdvance ||= fragment.lineHeight === void 0;
          if (!fragment.bullet) {
            right = Math.max(right, fragment.x + (fragment.hanging ? 0 : fragment.width));
            if (breakableSpace.test(fragment.text))
              spaces++;
          }
        }
        const height = (s.lineHeightPoints != null ? Math.max(0.1, s.lineHeightPoints * scale) : normalAdvance * Math.max(0.1, numeric(s.lineHeight, 1.15))) * spacingScale;
        if (s.lineHeightPoints == null && missingAdvance)
          lineMetricsApproximate = true;
        if (first)
          y += Math.max(0, s.spaceBefore != null ? s.spaceBefore * scale : numeric(s.spaceBeforePercent) * height);
        const available = innerWidth - left, extent = right - left;
        let offset2 = 0;
        if (s.alignment === "right")
          offset2 = Math.max(0, available - extent);
        else if (s.alignment === "center")
          offset2 = Math.max(0, (available - extent) / 2);
        if (s.alignment === "distributed" && !items.some((t) => t.kind === "tab") && available > extent) {
          const body = fragments.filter((f) => !f.bullet && !f.hanging);
          if (body.length > 1) {
            const extra = (available - extent) / (body.length - 1);
            let advance = 0, index = 0;
            for (const fragment of fragments) {
              if (fragment.bullet)
                continue;
              fragment.x += advance;
              if (!fragment.hanging && ++index < body.length)
                advance += extra;
            }
          }
        } else if (s.alignment === "justify" && !last && !items.some((t) => t.kind === "tab") && spaces && available > extent) {
          const extra = (available - extent) / spaces;
          let advance = 0;
          for (const fragment of fragments) {
            if (fragment.bullet)
              continue;
            fragment.x += advance;
            if (breakableSpace.test(fragment.text)) {
              fragment.width += extra;
              advance += extra;
            }
          }
        } else if (offset2)
          for (const fragment of fragments)
            fragment.x += offset2;
        if (right > innerWidth + 0.1)
          overflowX = true;
        const baseline = y + (height - ascent - descent) / 2 + ascent;
        for (const fragment of fragments) {
          const h = fragment.ascent + fragment.descent;
          fragment.baseline = s.fontAlignment === 1 ? y + fragment.ascent : s.fontAlignment === 2 ? y + (height - h) / 2 + fragment.ascent : s.fontAlignment === 3 ? y + height - fragment.descent : baseline;
        }
        lines.push({ fragments, y, height, baseline, paragraphIndex, width: Math.max(0, right - left), last });
        y += height;
        lastHeight = height;
        first = false;
      };
      for (const token of parts) {
        if (token.kind === "break") {
          emptyMetrics = token;
          emptyStyle = token.style;
          emit(current, false);
          current = [];
          rebuildCursor();
          continue;
        }
        if (current.length && token.breakBefore)
          lastBreak = current.length;
        current.push(token);
        advanceCursor(token);
        if (frame.wrap && token.kind !== "space" && token.kind !== "tab")
          while (cursorX > innerWidth + 0.1) {
            if (wrapFlags & 4 && hangingPunctuation.test(token.text) && current.length > 1 && cursorX - token.width <= innerWidth + 0.1) {
              token.hanging = true;
              break;
            }
            if (lastBreak <= 0)
              break;
            const rest = current.slice(lastBreak);
            emit(current.slice(0, lastBreak), false);
            current = rest;
            rebuildCursor();
          }
      }
      emit(current, true);
      y += Math.max(0, s.spaceAfter != null ? s.spaceAfter * scale : numeric(s.spaceAfterPercent) * lastHeight);
    });
    const requiredHeight = y + frame.margins.top + frame.margins.bottom, overflowY = y > innerHeight + 0.1;
    const actualHeight = options.autofit === "resize" ? Math.max(options.height, requiredHeight) : options.height;
    const free = Math.max(0, actualHeight - frame.margins.top - frame.margins.bottom - y), offset = frame.verticalAlignment === "middle" ? free / 2 : frame.verticalAlignment === "bottom" ? free : 0;
    for (const line of lines) {
      line.y += frame.margins.top + offset;
      line.baseline += frame.margins.top + offset;
      for (const fragment of line.fragments) {
        fragment.x += frame.margins.left;
        if (fragment.baseline !== void 0)
          fragment.baseline += frame.margins.top + offset;
      }
    }
    return { lines, width: options.width, height: actualHeight, requiredHeight, scale, overflowX, overflowY: options.autofit === "resize" ? false : overflowY, lineMetricsApproximate };
  }
  function layoutText(frame, options) {
    const initial = Math.min(1, Math.max(0.05, numeric(options.scale, 1)));
    let result = layoutOnce(frame, options, initial);
    if (options.autofit !== "shrink" || !result.overflowX && !result.overflowY)
      return result;
    let low = Math.min(initial, Math.max(0.05, numeric(options.minScale, 0.2))), high = initial, best = layoutOnce(frame, options, low);
    if (best.overflowX || best.overflowY)
      return best;
    for (let i = 0; i < 10; i++) {
      const middle = (low + high) / 2, candidate = layoutOnce(frame, options, middle);
      if (candidate.overflowX || candidate.overflowY)
        high = middle;
      else {
        low = middle;
        best = candidate;
      }
    }
    return best;
  }
  exports_29("layoutText", layoutText);
  return {
    setters: [],
    execute: function() {
      closes = /^[\]\)\}、。，．！？：；％‰〉》」』】〕〗〙〛’”!?;:,%]/u;
      opens = /[\[\(\{〈《「『【〔〖〘〚‘“]$/u;
      cjk = /[\u2e80-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uffef\u{20000}-\u{3134f}]/u;
      breakableSpace = /^[ \u1680\u2000-\u2006\u2008-\u200a\u205f\u3000]+$/u;
      breakAfter = /[ \t\u1680\u2000-\u2006\u2008-\u200a\u205f\u3000\-\u2010/]$/u;
      nonBreaking = /[\u00a0\u202f\u2060\ufeff]/u;
      hangingPunctuation = /^[、。，．！？：；〉》」』】〕〗〙〛’”]$/u;
      segmenter = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(void 0, { granularity: "grapheme" }) : void 0;
      numeric = (value, fallback = 0) => Number.isFinite(value) ? value : fallback;
    }
  };
});
System.register("render/text", ["render/safe", "layout/measure", "layout/text-layout"], function(exports_30, context_30) {
  "use strict";
  var safe_js_2, measure_js_1, text_layout_js_1, textClipSequence;
  var __moduleName = context_30 && context_30.id;
  function schemeColor(value, index, colors) {
    const rgb = index == null ? void 0 : colors[index];
    return rgb == null ? value : `#${[rgb & 255, rgb >>> 8 & 255, rgb >>> 16 & 255].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
  }
  function textEffects(style) {
    const size = Math.max(0.1, safe_js_2.finite(style.fontSize, 24)), effects = [];
    if (style.shadow) {
      const offset = Math.max(0.5, size / 16);
      effects.push({ dx: offset, dy: offset, color: "#000000", opacity: 0.45 });
    }
    if (style.emboss) {
      const offset = Math.max(0.5, size / 32);
      effects.push({ dx: -offset, dy: -offset, color: "#ffffff", opacity: 0.8 }, { dx: offset, dy: offset, color: "#000000", opacity: 0.5 });
    }
    return effects;
  }
  function runHtml(run, colors, fontAlignment) {
    const s = run.style, styles = [];
    if (s.fontFamily)
      styles.push(`font-family:${safe_js_2.cssFont(s.fontFamily)}`);
    if (s.fontSize != null)
      styles.push(`font-size:${safe_js_2.n(Math.max(0.1, safe_js_2.finite(s.fontSize, 24)))}px`);
    const resolvedColor = schemeColor(s.color, s.colorIndex, colors);
    if (resolvedColor)
      styles.push(`color:${safe_js_2.color(resolvedColor)}`);
    if (s.bold != null)
      styles.push(`font-weight:${s.bold ? "700" : "400"}`);
    if (s.italic != null)
      styles.push(`font-style:${s.italic ? "italic" : "normal"}`);
    const decoration = [s.underline ? "underline" : "", s.strike ? "line-through" : ""].filter(Boolean).join(" ");
    if (decoration)
      styles.push(`text-decoration:${decoration}`);
    if (s.baseline)
      styles.push(`vertical-align:${safe_js_2.n(s.baseline)}%`);
    else if (fontAlignment != null && fontAlignment >= 1 && fontAlignment <= 3)
      styles.push(`vertical-align:${["baseline", "top", "middle", "bottom"][fontAlignment]}`);
    if (s.letterSpacing != null)
      styles.push(`letter-spacing:${safe_js_2.n(s.letterSpacing)}px`);
    const effects = textEffects(s);
    if (effects.length)
      styles.push(`text-shadow:${effects.map((effect) => `${safe_js_2.n(effect.dx)}px ${safe_js_2.n(effect.dy)}px 0 ${effect.color}${Math.round(effect.opacity * 255).toString(16).padStart(2, "0")}`).join(",")}`);
    const escaped = (text) => safe_js_2.escapeXml(text).replace(/\r\n|\r|\n|\u000b/g, "<br/>");
    const content = s.eastAsianFontFamily ? run.text.split(/([\u2e80-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uffef\u{20000}-\u{3134f}]+)/u).map((part, i) => i % 2 ? `<span style="${safe_js_2.escapeXml(`font-family:${safe_js_2.cssFont(s.eastAsianFontFamily)}`)}">${escaped(part)}</span>` : escaped(part)).join("") : escaped(run.text);
    const html = `<span style="${safe_js_2.escapeXml(styles.join(";"))}">${content}</span>`;
    const url = safe_js_2.linkUrl(s.hyperlink);
    return url ? `<a href="${safe_js_2.escapeXml(url)}"${url.startsWith("#") ? "" : ' target="_blank" rel="noopener noreferrer"'} style="color:inherit;text-decoration:inherit">${html}</a>` : html;
  }
  function paragraphHtml(paragraph, colors) {
    const s = paragraph.style;
    const styles = ["margin:0", "padding:0", "min-height:1em", "position:relative", "box-sizing:border-box"];
    if (s.alignment === "distributed")
      styles.push("text-align:justify", "text-align-last:justify", "text-justify:inter-character");
    else if (s.alignment)
      styles.push(`text-align:${["left", "right", "center", "justify"].includes(s.alignment) ? s.alignment : "left"}`);
    const wrapFlags = text_layout_js_1.paragraphWrapFlags(s);
    if (!(wrapFlags & 2))
      styles.push("word-break:break-all");
    if (!(wrapFlags & 1))
      styles.push("line-break:loose");
    if (wrapFlags & 4)
      styles.push("hanging-punctuation:allow-end");
    if (s.direction)
      styles.push(`direction:${s.direction === "rtl" ? "rtl" : "ltr"}`);
    if (s.marginLeft != null)
      styles.push(`margin-left:${safe_js_2.n(s.marginLeft)}px`);
    if (s.indent != null)
      styles.push(`text-indent:${safe_js_2.n(s.indent)}px`);
    const firstSize = paragraph.runs.find((r) => r.style.fontSize)?.style.fontSize ?? 24;
    styles.push(`font-size:${safe_js_2.n(Math.max(0.1, firstSize))}px`);
    const firstFont = paragraph.runs.find((r) => r.style.fontFamily)?.style.fontFamily;
    if (firstFont)
      styles.push(`font-family:${safe_js_2.cssFont(firstFont)}`);
    const lineHeight = s.lineHeightPoints ?? firstSize * (s.lineHeight ?? 1.15);
    if (s.spaceBefore != null || s.spaceBeforePercent != null)
      styles.push(`padding-top:${safe_js_2.n(Math.max(0, s.spaceBefore ?? safe_js_2.finite(s.spaceBeforePercent) * lineHeight))}px`);
    if (s.spaceAfter != null || s.spaceAfterPercent != null)
      styles.push(`padding-bottom:${safe_js_2.n(Math.max(0, s.spaceAfter ?? safe_js_2.finite(s.spaceAfterPercent) * lineHeight))}px`);
    if (s.defaultTabSize != null)
      styles.push(`tab-size:${safe_js_2.n(text_layout_js_1.paragraphDefaultTabSize(s))}px`);
    if (s.lineHeightPoints != null)
      styles.push(`line-height:${safe_js_2.n(Math.max(0.1, s.lineHeightPoints))}px`);
    else if (s.lineHeight != null)
      styles.push(`line-height:${safe_js_2.n(Math.max(0.1, s.lineHeight))}`);
    let bullet = "";
    if (s.bullet && s.bulletEnabled !== false) {
      const bs = [`display:inline-block`, `text-indent:0`, `min-width:${safe_js_2.n(Math.max(firstSize * 0.5, -safe_js_2.finite(s.indent)))}px`];
      if (s.bullet.fontFamily)
        bs.push(`font-family:${safe_js_2.cssFont(s.bullet.fontFamily)}`);
      const firstStyle = paragraph.runs[0]?.style;
      const bc = schemeColor(s.bullet.color, s.bullet.colorIndex, colors) ?? schemeColor(firstStyle?.color, firstStyle?.colorIndex, colors);
      if (bc)
        bs.push(`color:${safe_js_2.color(bc)}`);
      if (s.bullet.size != null || s.bullet.sizePercent != null)
        bs.push(`font-size:${safe_js_2.n(s.bullet.size ?? safe_js_2.finite(s.bullet.sizePercent, 1) * firstSize)}px`);
      bullet = `<span aria-hidden="true" style="${safe_js_2.escapeXml(bs.join(";"))}">${safe_js_2.escapeXml(s.bullet.text)}</span>`;
    }
    const runs = paragraph.runs.map((r) => runHtml(r, colors, s.fontAlignment)).join("");
    return `<div style="${safe_js_2.escapeXml(styles.join(";"))}">${bullet}${runs || "<br/>"}</div>`;
  }
  function textViewportWidth(layout) {
    let width = layout.width;
    for (const line of layout.lines)
      for (const fragment of line.fragments)
        if (fragment.hanging)
          width = Math.max(width, fragment.x + fragment.width);
    return width;
  }
  function svgText(layout, colors, frame) {
    const vertical = frame?.direction === "vertical" || frame?.direction === "vertical270";
    const viewportWidth = vertical ? layout.height : textViewportWidth(layout), viewportHeight = vertical ? layout.width : layout.height, clipId = `ppt-text-clip-${++textClipSequence}`;
    const lines = layout.lines.map((line) => `<g data-ppt-line="${line.paragraphIndex}">${line.fragments.map((fragment) => {
      const s = fragment.style, baseline = (fragment.baseline ?? line.baseline) - (s.fontSize ?? 24) * safe_js_2.finite(s.baseline) / 100;
      const decoration = [s.underline ? "underline" : "", s.strike ? "line-through" : ""].filter(Boolean).join(" ");
      const paragraph = frame?.paragraphs[line.paragraphIndex], rtl = paragraph?.style.direction === "rtl" || paragraph?.style.direction == null && /^[\s\d\p{P}]*[\p{Script=Arabic}\p{Script=Hebrew}]/u.test(paragraph?.runs.map((r) => r.text).join("") ?? "");
      const x = vertical ? layout.height - baseline : rtl ? layout.width - fragment.x : fragment.x, y = vertical ? fragment.x : baseline;
      const attrs = `font-family="${safe_js_2.escapeXml(safe_js_2.cssFont(s.fontFamily ?? "Arial"))}" font-size="${safe_js_2.n(Math.max(0.1, safe_js_2.finite(s.fontSize, 24)))}" font-weight="${s.bold ? "700" : "400"}" font-style="${s.italic ? "italic" : "normal"}"${vertical ? ' writing-mode="vertical-rl" text-orientation="mixed"' : ""}${rtl ? ' direction="rtl" unicode-bidi="plaintext" text-anchor="start"' : ""}${decoration ? ` text-decoration="${decoration}"` : ""}${s.letterSpacing != null ? ` letter-spacing="${safe_js_2.n(s.letterSpacing)}"` : ""} xml:space="preserve"`;
      const label = safe_js_2.escapeXml(fragment.text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, "\uFFFD").replace(/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g, "\uFFFD"));
      const effects = textEffects(s).map((effect) => `<text x="${safe_js_2.n(x + effect.dx)}" y="${safe_js_2.n(y + effect.dy)}" fill="${effect.color}" fill-opacity="${safe_js_2.n(effect.opacity)}" ${attrs} aria-hidden="true">${label}</text>`).join("");
      const glyphs = `${effects}<text x="${safe_js_2.n(x)}" y="${safe_js_2.n(y)}" fill="${safe_js_2.color(schemeColor(s.color, s.colorIndex, colors))}" ${attrs}${fragment.bullet ? ' aria-hidden="true"' : ""}>${label}</text>`;
      const url = safe_js_2.linkUrl(s.hyperlink);
      return url ? `<a href="${safe_js_2.escapeXml(url)}" xlink:href="${safe_js_2.escapeXml(url)}"${url.startsWith("#") ? "" : ' target="_blank" rel="noopener noreferrer"'}>${glyphs}</a>` : glyphs;
    }).join("")}</g>`).join("");
    return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0" y="0" width="${safe_js_2.n(viewportWidth)}" height="${safe_js_2.n(viewportHeight)}" overflow="hidden" data-ppt-layout="measured" data-ppt-text-output="svg" data-ppt-font-scale="${safe_js_2.n(layout.scale)}"><defs><clipPath id="${clipId}" clipPathUnits="userSpaceOnUse"><rect x="0" y="0" width="${safe_js_2.n(viewportWidth)}" height="${safe_js_2.n(viewportHeight)}"/></clipPath></defs><g clip-path="url(#${clipId})"${frame?.direction === "vertical270" ? ` transform="translate(${safe_js_2.n(viewportWidth)} ${safe_js_2.n(viewportHeight)}) rotate(180)"` : ""}>${lines}</g></svg>`;
  }
  function renderText(frame, width, height, colors = [], options = {}) {
    const warn = (code, message) => options.warnings?.push({ code, severity: "warning", message, slideId: options.slideId, shapeId: options.shapeId });
    if (frame.paragraphs.some((p) => p.runs.some((r) => r.style.shadow)))
      warn("TEXT_SHADOW_APPROXIMATED", "Character shadow uses a proportional offset and fixed opacity; exact Office shadow geometry is not reproduced");
    if (frame.paragraphs.some((p) => p.runs.some((r) => r.style.emboss)))
      warn("TEXT_EMBOSS_APPROXIMATED", "Character emboss uses opposing highlight/shadow offsets; exact Office lighting is not reproduced");
    if (frame.paragraphs.some((p) => p.style.defaultTabSize != null && !(p.style.defaultTabSize > 0) && p.runs.some((r) => r.text.includes("	"))))
      warn("TEXT_TAB_DEFAULT_APPROXIMATED", "A nonpositive saved default tab step uses a 48px compatibility grid; PowerPoint tab behavior for this value is not fully specified");
    if (options.textLayout === "measured" || options.textOutput === "svg") {
      const supported = (!frame.direction || frame.direction === "horizontal") && !frame.paragraphs.some((p) => p.style.direction === "rtl" || p.runs.some((r) => /[\p{Script=Arabic}\p{Script=Hebrew}\u202a-\u202e\u2066-\u2069]/u.test(r.text)));
      const measurer = options.textMeasurer ?? measure_js_1.createCanvasTextMeasurer();
      if ((supported || options.textOutput === "svg") && measurer) {
        const vertical = frame.direction === "vertical" || frame.direction === "vertical270";
        const layoutFrame = vertical ? { ...frame, margins: { left: frame.margins.top, right: frame.margins.bottom, top: frame.margins.right, bottom: frame.margins.left } } : frame;
        const layout = text_layout_js_1.layoutText(layoutFrame, { width: vertical ? height : width, height: vertical ? width : height, measurer, scale: frame.fontScale, lineSpacingScale: frame.lineSpacingScale, autofit: vertical ? "none" : frame.autofit });
        if (!vertical)
          options.onLayout?.(layout);
        if (!supported)
          warn(vertical ? "TEXT_VERTICAL_SVG_APPROXIMATED" : "TEXT_BIDI_SVG_APPROXIMATED", vertical ? "Native SVG vertical glyphs use measured column advances; Office-specific vertical fitting remains approximate" : "Native SVG direction and shaping retain bidirectional text; mixed-script line layout remains approximate");
        if (layout.lineMetricsApproximate)
          warn("TEXT_LINE_METRICS_APPROXIMATED", "Normal baseline advance is unavailable from the text measurer; relative line spacing uses nominal font size rather than font bounding-box height");
        if (layout.overflowX || layout.overflowY)
          warn("TEXT_LAYOUT_OVERFLOW", "Measured text exceeds its frame after the requested fit policy");
        if (options.textOutput === "svg")
          return svgText(layout, colors, frame);
        const lines = layout.lines.map((line) => `<div data-ppt-line="${line.paragraphIndex}" style="position:absolute;inset:0;pointer-events:none">${line.fragments.map((fragment) => {
          const baseline = (fragment.baseline ?? line.baseline) - (fragment.style.fontSize ?? 24) * safe_js_2.finite(fragment.style.baseline) / 100;
          const css = `position:absolute;display:block;left:${safe_js_2.n(fragment.x)}px;top:${safe_js_2.n(baseline - fragment.ascent)}px;font-size:${safe_js_2.n(fragment.style.fontSize ?? 24)}px;font-family:${safe_js_2.cssFont(fragment.style.fontFamily ?? "Arial")};line-height:${safe_js_2.n(fragment.ascent + fragment.descent)}px;height:${safe_js_2.n(fragment.ascent + fragment.descent)}px;white-space:pre;pointer-events:auto`;
          return `<span${fragment.bullet ? ' aria-hidden="true"' : ""} style="${safe_js_2.escapeXml(css)}">${runHtml({ text: fragment.text, style: { ...fragment.style, baseline: 0 } }, colors)}</span>`;
        }).join("")}</div>`).join("");
        const viewportWidth = textViewportWidth(layout);
        return `<foreignObject x="0" y="0" width="${safe_js_2.n(viewportWidth)}" height="${safe_js_2.n(layout.height)}" data-ppt-layout="measured" data-ppt-font-scale="${safe_js_2.n(layout.scale)}"><div xmlns="http://www.w3.org/1999/xhtml" style="position:relative;width:${safe_js_2.n(viewportWidth)}px;height:${safe_js_2.n(layout.height)}px;overflow:hidden;font-family:Arial,sans-serif;color:#000;white-space:pre">${lines}</div></foreignObject>`;
      }
      warn(supported ? options.textOutput === "svg" ? "TEXT_SVG_MEASUREMENT_UNAVAILABLE" : "TEXT_MEASUREMENT_UNAVAILABLE" : "TEXT_DIRECTION_NATIVE_LAYOUT", supported ? "Canvas or a supplied text measurer is unavailable; browser foreign-object text layout is used" : "Vertical or bidirectional text uses the native browser foreign-object layout path");
    }
    if (frame.paragraphs.some((p) => p.style.tabStops?.length))
      warn("TEXT_TABS_NATIVE", "Explicit tab alignment requires measured layout; native layout uses uniform default tab stops");
    if (frame.paragraphs.some((p) => p.style.alignment === "distributed"))
      warn("TEXT_DISTRIBUTED_NATIVE", "Distributed alignment uses browser inter-character justification; measured layout supplies explicit character positions");
    if (frame.autofit && frame.autofit !== "none")
      warn("TEXT_AUTOFIT_NATIVE", "Dynamic text autofit requires measured horizontal layout; the native path retains the source frame bounds");
    if (frame.fontScale != null && frame.fontScale !== 1) {
      const scale = Math.min(1, Math.max(0.05, frame.fontScale));
      frame = { ...frame, paragraphs: frame.paragraphs.map((p) => ({ ...p, runs: p.runs.map((r) => ({ ...r, style: { ...r.style, fontSize: (r.style.fontSize ?? 24) * scale } })) })) };
    }
    const m = frame.margins, align = frame.verticalAlignment === "middle" ? "center" : frame.verticalAlignment === "bottom" ? "flex-end" : "flex-start";
    const style = ["box-sizing:border-box", `width:${safe_js_2.n(width)}px`, `height:${safe_js_2.n(height)}px`, `padding:${safe_js_2.n(m.top)}px ${safe_js_2.n(m.right)}px ${safe_js_2.n(m.bottom)}px ${safe_js_2.n(m.left)}px`, "display:flex", "flex-direction:column", `justify-content:${align}`, "font-family:Arial,sans-serif", "font-size:24px", "font-weight:400", "font-style:normal", "line-height:1.15", "color:#000", "overflow:hidden", `white-space:${frame.wrap ? "pre-wrap" : "pre"}`, frame.wrap ? "overflow-wrap:normal" : "", "word-break:normal", "text-rendering:geometricPrecision"];
    if (frame.direction === "vertical")
      style.push("writing-mode:vertical-rl");
    if (frame.direction === "vertical270")
      style.push("writing-mode:vertical-rl", "transform:rotate(180deg)");
    return `<foreignObject x="0" y="0" width="${safe_js_2.n(width)}" height="${safe_js_2.n(height)}"><div xmlns="http://www.w3.org/1999/xhtml" style="${safe_js_2.escapeXml(style.filter(Boolean).join(";"))}"><div style="flex:none;min-width:0;width:100%">${frame.paragraphs.map((p) => paragraphHtml(p, colors)).join("")}</div></div></foreignObject>`;
  }
  exports_30("renderText", renderText);
  return {
    setters: [
      function(safe_js_2_1) {
        safe_js_2 = safe_js_2_1;
      },
      function(measure_js_1_1) {
        measure_js_1 = measure_js_1_1;
      },
      function(text_layout_js_1_1) {
        text_layout_js_1 = text_layout_js_1_1;
      }
    ],
    execute: function() {
      textClipSequence = 0;
    }
  };
});
System.register("render/fields", [], function(exports_31, context_31) {
  "use strict";
  var lcidLocales, american, chineseClock, formatMaps;
  var __moduleName = context_31 && context_31.id;
  function warning(ctx, code, message) {
    if (!ctx.warnings.some((d) => d.code === code && d.shapeId === ctx.shapeId))
      ctx.warnings.push({ code, severity: "warning", message, slideId: ctx.slide.id, shapeId: ctx.shapeId });
  }
  function localeOf(style, ctx) {
    const language = style.language != null && style.language > 1024 ? style.language : style.alternateLanguage != null && style.alternateLanguage > 1024 ? style.alternateLanguage : void 0;
    const locale = ctx.options.fieldLocale ?? (language == null ? void 0 : lcidLocales[language]);
    if (!locale) {
      warning(ctx, "DATE_LOCALE_FALLBACK", "A datetime field has no supported source language; en-US formatting is used. Set fieldLocale to override it.");
      return "en-US";
    }
    try {
      return Intl.getCanonicalLocales(locale)[0] ?? "en-US";
    } catch {
      warning(ctx, "DATE_LOCALE_INVALID", "The requested date locale is invalid; en-US formatting is used");
      return "en-US";
    }
  }
  function formatter(date, locale, options) {
    return new Intl.DateTimeFormat(locale, options).format(date);
  }
  function patternDate(pattern, date, locale) {
    if (pattern.length > 256)
      return void 0;
    const p = (value, width = 2) => String(value).padStart(width, "0"), year = date.getFullYear(), hour = date.getHours();
    const part = (options, name) => new Intl.DateTimeFormat(locale, options).formatToParts(date).find((p2) => p2.type === name)?.value ?? "";
    const period = () => part({ hour: "numeric", hour12: true }, "dayPeriod");
    const values = { yyyy: () => p(year, 4), yyy: () => p(year, 3), yy: () => p(year % 100), y: () => String(year % 100), MMMM: () => formatter(date, locale, { month: "long" }), MMM: () => formatter(date, locale, { month: "short" }), MM: () => p(date.getMonth() + 1), M: () => String(date.getMonth() + 1), dddd: () => formatter(date, locale, { weekday: "long" }), ddd: () => formatter(date, locale, { weekday: "short" }), dd: () => p(date.getDate()), d: () => String(date.getDate()), HH: () => p(hour), H: () => String(hour), hh: () => p(hour % 12 || 12), h: () => String(hour % 12 || 12), mm: () => p(date.getMinutes()), m: () => String(date.getMinutes()), ss: () => p(date.getSeconds()), s: () => String(date.getSeconds()), AMPM: period, "AM/PM": period, "am/pm": period, tt: period, t: () => period().slice(0, 1), W: () => ["\u65E5", "\u4E00", "\u4E8C", "\u4E09", "\u56DB", "\u4E94", "\u516D"][date.getDay()], ggg: () => new Intl.DateTimeFormat("ja-JP-u-ca-japanese", { era: "long" }).formatToParts(date).find((p2) => p2.type === "era")?.value ?? "", e: () => new Intl.DateTimeFormat("ja-JP-u-ca-japanese", { year: "numeric" }).formatToParts(date).find((p2) => p2.type === "year")?.value ?? "" };
    const tokens = /'(?:[^']|'')*'|"[^"]*"|AM\/PM|am\/pm|AMPM|yyyy|yyy|yy|y|MMMM|MMM|MM|M|dddd|ddd|dd|d|HH|H|hh|h|mm|m|ss|s|tt|t|ggg|e|W|[^A-Za-z]/g;
    let result = "", at = 0;
    for (const match of pattern.matchAll(tokens)) {
      if (match.index !== at)
        return void 0;
      const token = match[0];
      at += token.length;
      result += token[0] === "'" || token[0] === '"' ? token.slice(1, -1).replace(/''/g, "'") : values[token]?.() ?? token;
    }
    return at === pattern.length ? result : void 0;
  }
  function indexedDate(index, date, locale, ctx) {
    const key = locale.toLowerCase(), short = () => formatter(date, locale, { year: "numeric", month: "numeric", day: "numeric" }), long = () => formatter(date, locale, { year: "numeric", month: "long", day: "numeric", weekday: "long" });
    if (index === 0)
      return short();
    if (index === 1)
      return long();
    if (key.startsWith("zh") && key !== "zh-tw") {
      const patterns = { 2: "yyyy\u5E74M\u6708d\u65E5\u661F\u671FW", 3: "yyyy\u5E74M\u6708d\u65E5", 4: "yyyy/M/d", 5: "yy.M.d", 6: "yyyy\u5E74M\u6708d\u65E5\u661F\u671FW", 7: "yyyy\u5E74M\u6708d\u65E5", 8: "yyyy\u5E74M\u6708d\u65E5\u661F\u671FW", 9: "yyyy\u5E74M\u6708", 10: "yyyy\u5E74M\u6708", 11: "h\u65F6m\u5206s\u79D2", 12: "h\u65F6m\u5206", 13: "H\u65F6m\u5206", 14: "h\u65F6m\u5206", 15: "AMPMh\u65F6m\u5206", 16: "AMPMh\u65F6m\u5206" };
      return patterns[index] ? patternDate(patterns[index], date, locale) : void 0;
    }
    if (key === "ja-jp") {
      const patterns = { 2: "ggge\u5E74M\u6708d\u65E5(ddd)", 3: "yyyy\u5E74M\u6708d\u65E5", 4: "yyyy/M/d", 7: "ggge\u5E74M\u6708d\u65E5", 8: "yyyy\u5E74M\u6708d\u65E5(ddd)", 9: "ggge\u5E74M\u6708", 10: "yyyy\u5E74M\u6708", 11: "yy/M/d H\u6642m\u5206", 12: "yy/M/d H\u6642m\u5206s\u79D2", 13: "AMPMh\u6642m\u5206", 14: "AMPMh\u6642m\u5206s\u79D2", 15: "H\u6642m\u5206", 16: "H\u6642m\u5206s\u79D2", 17: "ggge\u5E74M\u6708d\u65E5 dddd" };
      return patterns[index] ? patternDate(patterns[index], date, locale) : void 0;
    }
    if (["zh-tw", "ko-kr", "th-th", "hi-in"].includes(key)) {
      warning(ctx, "DATE_FORMAT_APPROXIMATED", "This datetime locale uses calendar-specific rules that are approximated with the browser locale formatter");
    }
    const pattern = (value) => patternDate(value, date, locale);
    if (index === 2)
      return formatter(date, locale, { year: "numeric", month: "long", day: "numeric" });
    if (index === 3)
      return formatter(date, locale, { year: "2-digit", month: "numeric", day: "numeric" });
    if (index === 4)
      return pattern("yyyy-MM-dd");
    if (index === 5) {
      const first = new Intl.DateTimeFormat(locale, { year: "numeric", month: "numeric", day: "numeric" }).formatToParts(date).find((p) => p.type === "year" || p.type === "month");
      return pattern(first?.type === "year" ? "yy-MMM-d" : "d-MMM-yy");
    }
    if (index === 6) {
      const separator = short().includes("/") ? "." : "/";
      return new Intl.DateTimeFormat(locale, { year: "numeric", month: "numeric", day: "numeric" }).formatToParts(date).filter((p) => ["year", "month", "day"].includes(p.type)).map((p) => p.value).join(separator);
    }
    if (index === 7)
      return formatter(date, locale, { year: "2-digit", month: "short", day: "numeric" });
    if (index === 8)
      return pattern(key === "he-il" ? "d MMMM, yyyy" : "d MMMM yyyy");
    if (index === 9)
      return formatter(date, locale, { year: "2-digit", month: "long" });
    if (index === 10)
      return pattern("MMM-yy");
    if (index === 11 || index === 12)
      return `${short()} ${formatter(date, locale, { hour: "numeric", minute: "2-digit", ...index === 12 ? { second: "2-digit" } : {}, hour12: true })}`;
    if (index === 13 || index === 14)
      return pattern(index === 13 ? "h:mm AMPM" : "h:mm:ss AMPM");
    if (index === 15 || index === 16)
      return pattern(index === 15 ? "HH:mm" : "HH:mm:ss");
    return void 0;
  }
  function dateValue(format, style, ctx) {
    if (!Number.isFinite(ctx.date.getTime())) {
      warning(ctx, "FIELD_DATE_INVALID", "fieldDate is not a valid date; the original field marker is retained");
      return void 0;
    }
    const locale = localeOf(style, ctx);
    let value;
    if (typeof format === "string")
      value = patternDate(format, ctx.date, locale);
    else {
      const index = format === 13 ? 0 : format ?? 0, map = formatMaps[locale.toLowerCase()] ?? american;
      if (!formatMaps[locale.toLowerCase()])
        warning(ctx, "DATE_FORMAT_APPROXIMATED", "This date language has no exact format-ID table in this build; the default mapping is used with the selected locale");
      const mapped = map[index];
      if (typeof mapped === "string")
        value = patternDate(mapped, ctx.date, locale);
      else if (mapped != null)
        value = indexedDate(mapped, ctx.date, locale, ctx);
    }
    if (value == null)
      warning(ctx, "DATE_FORMAT_UNSUPPORTED", "The datetime picture or calendar-specific format is not supported; the original field marker is retained");
    return value;
  }
  function fieldValue(field, style, ctx) {
    if (ctx.slide.suppressHeaderFooter && field.type !== "dateTime")
      return "";
    const hf = ctx.slide.headersFooters;
    switch (field.type) {
      case "slideNumber":
        return String(ctx.slide.displayNumber ?? ctx.slide.index + 1);
      case "header":
        return hf?.header ?? "";
      case "footer":
        return hf?.footer ?? "";
      case "genericDate":
        if (hf?.useUserDate)
          return hf.userDate ?? "";
        if (hf?.useCurrentDate)
          return dateValue(hf.format, style, ctx);
        return "";
      case "dateTime":
        return dateValue(field.format, style, ctx);
    }
  }
  function headerFooterVisible(type, slide) {
    if (type == null || ![7, 8, 9, 10].includes(type))
      return true;
    if (slide.suppressHeaderFooter)
      return false;
    const hf = slide.headersFooters;
    return type === 7 ? !!hf?.showDate : type === 8 ? !!hf?.showSlideNumber : type === 9 ? !!hf?.showFooter : !!hf?.showHeader;
  }
  exports_31("headerFooterVisible", headerFooterVisible);
  function resolveTextFields(frame, ctx, placeholderType) {
    if (!frame.fields?.length) {
      if (placeholderType != null && [7, 8, 9, 10].includes(placeholderType) && frame.paragraphs.length) {
        warning(ctx, "HEADER_FOOTER_FIELD_MISSING", "A header/footer placeholder has no metacharacter record; its text is recovered from the current slide settings");
        const first = frame.paragraphs[0], run = first.runs[0], type = placeholderType === 7 ? "genericDate" : placeholderType === 8 ? "slideNumber" : placeholderType === 9 ? "footer" : "header";
        const text = fieldValue({ position: 0, type }, run?.style ?? {}, ctx);
        if (text != null)
          return { ...frame, paragraphs: [{ ...first, runs: [{ ...run ?? { style: {} }, text }] }] };
      }
      return frame;
    }
    const fields = [...frame.fields].sort((a, b) => a.position - b.position);
    let cursor = 0, nextOffset = 0;
    const paragraphs = frame.paragraphs.map((paragraph) => {
      const runs = paragraph.runs.map((run) => {
        const start = run.sourceStart ?? nextOffset, end = run.sourceEnd ?? start + run.text.length;
        nextOffset = end;
        while (cursor < fields.length && fields[cursor].position < start)
          cursor++;
        let from = 0, changed = false, result = "";
        while (cursor < fields.length && fields[cursor].position < end) {
          const field = fields[cursor++], relative = field.position - start;
          if (relative < from || relative >= run.text.length)
            continue;
          const replacement = fieldValue(field, run.style, ctx);
          if (replacement != null) {
            result += run.text.slice(from, relative) + replacement;
            from = relative + 1;
            changed = true;
          }
        }
        return changed ? { ...run, text: result + run.text.slice(from) } : run;
      });
      nextOffset++;
      return { ...paragraph, runs };
    });
    return { ...frame, paragraphs };
  }
  exports_31("resolveTextFields", resolveTextFields);
  return {
    setters: [],
    execute: function() {
      lcidLocales = { 1033: "en-US", 2057: "en-GB", 3081: "en-AU", 1041: "ja-JP", 1028: "zh-TW", 2052: "zh-CN", 4100: "zh-SG", 5124: "zh-MO", 3076: "zh-HK", 1042: "ko-KR", 1025: "ar-SA", 1037: "he-IL", 1053: "sv-SE", 1054: "th-TH", 1066: "vi-VN", 1081: "hi-IN", 1114: "syr-SY" };
      american = [0, 1, 8, 2, 5, 9, 10, 11, 12, 15, 16, 13, 14];
      chineseClock = ["yyyy\u5E74M\u6708d\u65E5h\u65F6m\u5206", "yyyy\u5E74M\u6708d\u65E5\u661F\u671FWh\u65F6m\u5206s\u79D2", "HH:mm", "HH:mm:ss", "AMPMh\u65F6m\u5206", "AMPMh\u65F6m\u5206s\u79D2"];
      formatMaps = {
        "en-us": american,
        "en-gb": [0, 1, "d MMMM, yyy", 2, 5, 9, 10, 11, 12, 15, 16, 13, 14],
        "en-au": [0, 1, "d MMMM, yyy", 2, 5, 9, 10, 11, 12, 15, 16, 13, 14],
        "zh-cn": [0, 1, 2, 2, 4, 9, 5, ...chineseClock],
        "zh-sg": [0, 1, 3, 2, 4, 9, 5, ...chineseClock],
        "zh-hk": [0, 1, 3, 2, 4, 9, 5, ...chineseClock],
        "zh-mo": [0, 1, 3, 2, 4, 9, 5, ...chineseClock],
        "zh-tw": [0, 1, 3, 7, 12, 9, 10, 4, 11, "HH:mm", "HH:mm:ss", "H:mm AMPM", "H:mm:ss AMPM"],
        "ja-jp": [4, 8, 7, 3, 0, 9, 5, 11, 12, "HH:mm", "HH:mm:ss", 15, 16],
        "ko-kr": [0, 1, 6, 3, 4, 10, 7, 12, 11, "HH:mm", "HH:mm:ss", 13, 14],
        "ar-sa": [0, 1, 2, 3, 4, 5, 8, 7, 8, 1, 10, 11, 5],
        "he-il": [0, 1, 2, 6, 11, 5, 12, 7, 8, 9, 1, 11, 6],
        "sv-se": [0, 1, 3, 2, 7, 9, 10, 11, 12, 15, 16, 13, 14],
        "th-th": [0, 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 13, 14],
        "vi-vn": [0, 1, 2, 3, 5, 6, 10, 11, 12, 13, 14, 15, 16],
        "hi-in": [1, 2, 3, 5, 7, 11, 13, 0, 1, 5, 10, 11, 14],
        "syr-sy": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
      };
    }
  };
});
System.register("render/effects", ["render/geometry", "render/safe"], function(exports_32, context_32) {
  "use strict";
  var geometry_js_2, safe_js_3, unit;
  var __moduleName = context_32 && context_32.id;
  function rgb(value) {
    const c = safe_js_3.color(value, "#000000");
    if (/^#[\da-f]{3}$/i.test(c))
      return [1, 2, 3].map((i) => parseInt(c[i] + c[i], 16));
    if (/^#[\da-f]{6,8}$/i.test(c))
      return [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
    return [0, 0, 0];
  }
  function gradientSampler(stops, resolve) {
    const ordered = stops.map((stop) => ({ position: unit(safe_js_3.finite(stop.position)), rgb: rgb(resolve(stop.color, stop.colorIndex)), opacity: unit(safe_js_3.finite(stop.opacity, 1)) })).sort((a, b) => a.position - b.position);
    return (position) => {
      if (!ordered.length)
        return { color: "#ffffff", opacity: 1 };
      const at = unit(safe_js_3.finite(position));
      let low = 0, high = ordered.length;
      while (low < high) {
        const middle = low + high >>> 1;
        if (ordered[middle].position <= at)
          low = middle + 1;
        else
          high = middle;
      }
      const lo = ordered[Math.max(0, low - 1)], hi = ordered[Math.min(low, ordered.length - 1)];
      const t = hi.position > lo.position ? unit((at - lo.position) / (hi.position - lo.position)) : 0;
      return { color: "#" + lo.rgb.map((v, i) => Math.round(v + (hi.rgb[i] - v) * t).toString(16).padStart(2, "0")).join(""), opacity: lo.opacity + (hi.opacity - lo.opacity) * t };
    };
  }
  function sampleGradient(stops, position, resolve) {
    return gradientSampler(stops, resolve)(position);
  }
  exports_32("sampleGradient", sampleGradient);
  function outline(shape) {
    if (shape?.path)
      return `<path d="${safe_js_3.escapeXml(geometry_js_2.mapPathToBounds(shape.path, shape.pathBounds ?? { x: 0, y: 0, width: shape.bounds.width, height: shape.bounds.height }, 1, 1))}"/>`;
    const geometry = geometry_js_2.presetGeometry(shape?.preset, 1, 1, shape?.source?.properties);
    return `<${geometry.tag} ${geometry.attrs}/>`;
  }
  function renderGradient(paint, ctx, shape) {
    const id = ctx.id, opacity = unit(safe_js_3.finite(paint.opacity, 1));
    const stops = paint.stops?.length ? paint.stops : [{ position: 0, color: paint.color ?? "#ffffff", colorIndex: paint.colorIndex }, { position: 1, color: "#000000" }];
    const gradientType = paint.gradientType ?? "linear";
    const stopMarkup = gradientType === "rectangular" || gradientType === "shape" ? "" : stops.map((s) => `<stop offset="${safe_js_3.n(unit(safe_js_3.finite(s.position)))}" stop-color="${ctx.resolveColor(s.color, s.colorIndex)}" stop-opacity="${safe_js_3.n(unit(safe_js_3.finite(s.opacity, 1)))}"/>`).join("");
    if (gradientType === "rectangular" || gradientType === "shape") {
      const r = paint.gradientRect ?? { left: 0, top: 0, right: 0, bottom: 0 };
      const cx = unit(safe_js_3.finite(paint.gradientCenter?.x, (r.left + r.right) / 2)), cy = unit(safe_js_3.finite(paint.gradientCenter?.y, (r.top + r.bottom) / 2));
      const parts = [], steps = 96, sample = gradientSampler(stops, ctx.resolveColor);
      const geometry = gradientType === "shape" ? outline(shape) : "";
      for (let i = 0; i <= steps; i++) {
        const t = i / steps, s = sample(t);
        if (gradientType === "rectangular") {
          const left = unit(safe_js_3.finite(r.left)) * t, top = unit(safe_js_3.finite(r.top)) * t, right = 1 + (unit(safe_js_3.finite(r.right)) - 1) * t, bottom = 1 + (unit(safe_js_3.finite(r.bottom)) - 1) * t;
          parts.push(`<rect x="${safe_js_3.n(Math.min(left, right))}" y="${safe_js_3.n(Math.min(top, bottom))}" width="${safe_js_3.n(Math.abs(right - left))}" height="${safe_js_3.n(Math.abs(bottom - top))}" fill="${s.color}" fill-opacity="${safe_js_3.n(s.opacity)}"/>`);
        } else {
          const scale = Math.max(1e-6, 1 - t);
          parts.push(`<g transform="translate(${safe_js_3.n(cx * t)} ${safe_js_3.n(cy * t)}) scale(${safe_js_3.n(scale)})" fill="${s.color}" fill-opacity="${safe_js_3.n(s.opacity)}">${geometry}</g>`);
        }
      }
      const opaqueParts = parts.map((p) => p.replace(/ fill-opacity="[^"]*"/g, ""));
      if (stops.some((s) => safe_js_3.finite(s.opacity, 1) !== 1)) {
        const maskId = `${id}-alpha`;
        const mask = parts.map((p) => {
          const alpha = Number(/fill-opacity="([^"]*)"/.exec(p)?.[1] ?? 1), level = Math.round(unit(alpha) * 255).toString(16).padStart(2, "0");
          return p.replace(/fill="#[\da-f]+"/g, `fill="#${level}${level}${level}"`).replace(/ fill-opacity="[^"]*"/g, "");
        });
        ctx.defs.push(`<mask id="${maskId}" maskUnits="objectBoundingBox" maskContentUnits="objectBoundingBox" x="0" y="0" width="1" height="1" style="mask-type:luminance">${mask.join("")}</mask>`);
        ctx.defs.push(`<pattern id="${id}" width="1" height="1" viewBox="0 0 1 1" preserveAspectRatio="none"><g mask="url(#${maskId})">${opaqueParts.join("")}</g></pattern>`);
      } else
        ctx.defs.push(`<pattern id="${id}" width="1" height="1" viewBox="0 0 1 1" preserveAspectRatio="none">${opaqueParts.join("")}</pattern>`);
    } else if (gradientType === "radial") {
      const cx = unit(safe_js_3.finite(paint.gradientCenter?.x, 0.5)), cy = unit(safe_js_3.finite(paint.gradientCenter?.y, 0.5));
      ctx.defs.push(`<radialGradient id="${id}" cx="${safe_js_3.n(cx)}" cy="${safe_js_3.n(cy)}" r="${safe_js_3.n(Math.max(cx, 1 - cx, cy, 1 - cy))}">${stopMarkup}</radialGradient>`);
    } else {
      const angle = safe_js_3.finite(paint.angle) - (paint.rotateWithShape === false ? safe_js_3.finite(shape?.rotation) : 0), rad = angle * Math.PI / 180, h = paint.rotateWithShape === false && shape?.flipH ? -1 : 1, v = paint.rotateWithShape === false && shape?.flipV ? -1 : 1, dx = Math.cos(rad) * h, dy = Math.sin(rad) * v;
      const bounds = shape?.bounds ?? ctx.bounds;
      if (paint.gradientScaled === false && !shape?.wordArt && bounds && bounds.width > 0 && bounds.height > 0) {
        const w = bounds.width, height = bounds.height, extent = (Math.abs(w * dx) + Math.abs(height * dy)) / 2;
        ctx.defs.push(`<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${safe_js_3.n(w / 2 - dx * extent)}" y1="${safe_js_3.n(height / 2 - dy * extent)}" x2="${safe_js_3.n(w / 2 + dx * extent)}" y2="${safe_js_3.n(height / 2 + dy * extent)}">${stopMarkup}</linearGradient>`);
      } else
        ctx.defs.push(`<linearGradient id="${id}" x1="${safe_js_3.n(0.5 - dx * 0.5)}" y1="${safe_js_3.n(0.5 - dy * 0.5)}" x2="${safe_js_3.n(0.5 + dx * 0.5)}" y2="${safe_js_3.n(0.5 + dy * 0.5)}">${stopMarkup}</linearGradient>`);
    }
    return `fill="url(#${id})" fill-opacity="${safe_js_3.n(opacity)}"`;
  }
  exports_32("renderGradient", renderGradient);
  function renderShadow(shape, html, ctx, parent = [1, 0, 0, 1]) {
    const shadow = shape.shadow;
    if (!shadow)
      return html;
    if (shadow.type !== 0 && shadow.type !== 1 && shadow.type !== 5) {
      ctx.warnings?.push({ code: "SHADOW_TRANSFORM_UNSUPPORTED", severity: "warning", message: `Shadow type ${shadow.type} requires a rich/shape/drawing transformation not present in the supported shadow model`, shapeId: shape.id, slideId: ctx.slideId });
      return html;
    }
    const inverse = (x, y) => {
      const d = parent[0] * parent[3] - parent[1] * parent[2];
      return Math.abs(d) > 1e-12 ? [(parent[3] * x - parent[2] * y) / d, (-parent[1] * x + parent[0] * y) / d] : [x, y];
    };
    const [dx, dy] = inverse(safe_js_3.finite(shadow.offsetX), safe_js_3.finite(shadow.offsetY));
    const [sx, sy] = inverse(safe_js_3.finite(shadow.secondOffsetX, shadow.type === 5 ? -shadow.offsetX : 0), safe_js_3.finite(shadow.secondOffsetY, shadow.type === 5 ? -shadow.offsetY : 0));
    const blur = Math.max(0, safe_js_3.finite(shadow.blur)), pad = Math.max(shape.bounds.width, shape.bounds.height, 1) + Math.max(Math.abs(dx) + Math.abs(dy), Math.abs(sx) + Math.abs(sy)) + 3 * blur;
    const parts = [], merges = [];
    const layer = (name, x, y, c) => {
      parts.push(`<feOffset in="SourceAlpha" dx="${safe_js_3.n(x)}" dy="${safe_js_3.n(y)}" result="${name}-offset"/>`);
      if (blur)
        parts.push(`<feGaussianBlur in="${name}-offset" stdDeviation="${safe_js_3.n(blur)}" result="${name}-offset"/>`);
      parts.push(`<feFlood flood-color="${c}" flood-opacity="${safe_js_3.n(unit(safe_js_3.finite(shadow.opacity, 1)))}" result="${name}-color"/><feComposite in="${name}-color" in2="${name}-offset" operator="in" result="${name}"/>`);
      if (shadow.obscured)
        parts.push(`<feComposite in="${name}" in2="SourceAlpha" operator="out" result="${name}"/>`);
      merges.push(`<feMergeNode in="${name}"/>`);
    };
    if (shadow.type === 1 || shadow.type === 5)
      layer("highlight", sx, sy, ctx.resolveColor(shadow.highlightColor, shadow.highlightColorIndex, "#cbcbcb"));
    layer("shadow", dx, dy, ctx.resolveColor(shadow.color, shadow.colorIndex, "#808080"));
    const b = shape.bounds;
    ctx.defs.push(`<filter id="${ctx.id}" filterUnits="userSpaceOnUse" x="${safe_js_3.n(b.x - pad)}" y="${safe_js_3.n(b.y - pad)}" width="${safe_js_3.n(b.width + pad * 2)}" height="${safe_js_3.n(b.height + pad * 2)}" color-interpolation-filters="sRGB">${parts.join("")}<feMerge>${merges.join("")}<feMergeNode in="SourceGraphic"/></feMerge></filter>`);
    return `<g filter="url(#${ctx.id})">${html}</g>`;
  }
  exports_32("renderShadow", renderShadow);
  return {
    setters: [
      function(geometry_js_2_1) {
        geometry_js_2 = geometry_js_2_1;
      },
      function(safe_js_3_1) {
        safe_js_3 = safe_js_3_1;
      }
    ],
    execute: function() {
      unit = (v) => Math.max(0, Math.min(1, v));
    }
  };
});
System.register("render/wordart", ["render/safe", "layout/measure"], function(exports_33, context_33) {
  "use strict";
  var safe_js_4, measure_js_2, clamp, SUPPORTED_WORDART_PRESETS;
  var __moduleName = context_33 && context_33.id;
  function warpPoint(preset, u, v, adjustments = []) {
    const amount = clamp(Math.abs(safe_js_4.finite(adjustments[0], 5400)) / 21600, 0, 0.48), bell = 4 * u * (1 - u), triangle = 1 - Math.abs(2 * u - 1);
    let top = 0, bottom = 1, x = u;
    switch (preset) {
      case 24:
      case 136:
        break;
      case 25:
      case 137:
        top = amount * Math.abs(2 * u - 1);
        bottom = 1 - top;
        break;
      case 26:
        top = amount * Math.max(0, Math.abs(2 * u - 1) - 0.5) * 2;
        bottom = 1 - top;
        break;
      case 138:
        top = 1 - triangle;
        break;
      case 139:
        bottom = triangle;
        break;
      case 140:
        top = amount * triangle;
        bottom = 1 - amount + amount * triangle;
        break;
      case 141:
        top = amount * (1 - triangle);
        bottom = 1 - amount * triangle;
        break;
      case 27:
      case 30:
      case 152:
        top = amount * (1 - bell);
        bottom = 1 - amount * bell;
        break;
      case 153:
        top = amount * bell;
        bottom = 1 - amount + amount * bell;
        break;
      case 154:
      case 172:
        top = amount * (1 - u);
        bottom = 1 - amount * u;
        break;
      case 155:
      case 173:
        top = amount * u;
        bottom = 1 - amount * (1 - u);
        break;
      case 28:
      case 156:
      case 157:
      case 158:
      case 159: {
        const cycles = preset === 158 || preset === 159 ? 2 : 1, phase = safe_js_4.finite(adjustments[1]) / 21600 * Math.PI * 2;
        const wave = Math.sin(u * Math.PI * 2 * cycles + phase) * (preset === 157 || preset === 159 ? -1 : 1);
        top = amount * (1 + wave) / 2;
        bottom = 1 - amount + top;
        break;
      }
      case 160:
        top = amount * (1 - bell);
        bottom = 1 - top;
        break;
      case 161:
        top = amount * bell;
        bottom = 1 - top;
        break;
      case 162:
        bottom = 1 - amount + amount * bell;
        break;
      case 163:
        bottom = 1 - amount * bell;
        break;
      case 164:
        top = amount * (1 - bell);
        break;
      case 165:
        top = amount * bell;
        break;
      case 166: {
        const q = Math.sin(2 * Math.PI * u);
        top = amount * (1 + q) / 2;
        bottom = 1 - top;
        break;
      }
      case 167: {
        const q = Math.cos(4 * Math.PI * u);
        top = amount * (1 + q) / 2;
        bottom = 1 - top;
        break;
      }
      case 168:
        top = amount * u;
        bottom = 1 - top;
        break;
      case 169:
        top = amount * (1 - u);
        bottom = 1 - top;
        break;
      case 170:
        x = amount * (1 - v) + u * (1 - 2 * amount * (1 - v));
        break;
      case 171:
        x = amount * v + u * (1 - 2 * amount * v);
        break;
      case 174:
        top = amount * (1 - bell);
        bottom = 1 - amount * bell;
        break;
      case 175:
        top = amount * bell;
        bottom = 1 - amount + amount * bell;
        break;
      case 29:
      case 31:
      case 142:
      case 143:
      case 144:
      case 145:
      case 146:
      case 147:
      case 148:
      case 149:
      case 150:
      case 151: {
        const full = [29, 31, 142, 143, 146, 147, 150, 151].includes(preset), down = preset === 145 || preset === 149;
        const sweep = full ? 2 * Math.PI : Math.PI;
        const theta = (down ? 0 : Math.PI) + u * sweep, radius = 0.5 - (0.16 + 0.5 * amount) * (preset === 142 ? 1 - v : v);
        const y = 0.5 + Math.sin(theta) * radius;
        return { x: 0.5 + Math.cos(theta) * radius, y: full ? y : down ? (y - 0.5) * 2 : y * 2 };
      }
      default:
        break;
    }
    return { x, y: top + (bottom - top) * v };
  }
  exports_33("warpPoint", warpPoint);
  function triangleMatrix(source, target) {
    const [a, b, c] = source, [p, q, r] = target, ux = b.x - a.x, uy = b.y - a.y, vx = c.x - a.x, vy = c.y - a.y, d = ux * vy - uy * vx;
    if (Math.abs(d) < 1e-12)
      return void 0;
    const aa = ((q.x - p.x) * vy - (r.x - p.x) * uy) / d, cc = ((r.x - p.x) * ux - (q.x - p.x) * vx) / d;
    const bb = ((q.y - p.y) * vy - (r.y - p.y) * uy) / d, dd = ((r.y - p.y) * ux - (q.y - p.y) * vx) / d;
    return [aa, bb, cc, dd, p.x - aa * a.x - cc * a.y, p.y - bb * a.x - dd * a.y];
  }
  exports_33("triangleMatrix", triangleMatrix);
  function renderWordArt(shape, fillAttrs, strokeAttrs, ctx) {
    const art = shape.wordArt;
    if (!art)
      return void 0;
    const w = Math.max(0, safe_js_4.finite(shape.bounds.width)), h = Math.max(0, safe_js_4.finite(shape.bounds.height));
    if (!w || !h || !art.text)
      return "";
    const supported = SUPPORTED_WORDART_PRESETS.has(art.warpPreset), preset = supported ? art.warpPreset : 136;
    if (!supported)
      ctx.warnings?.push({ code: "WORDART_WARP_UNSUPPORTED", severity: "warning", message: `WordArt envelope ${art.warpPreset} is shown without warping`, shapeId: shape.id, slideId: ctx.slideId });
    const textId = `${ctx.id}-glyphs`, lines = art.text.replace(/\r\n/g, "\n").split(/[\r\n]/, 1025);
    if (lines.length > 1024) {
      lines.length = 1024;
      ctx.warnings?.push({ code: "WORDART_RENDER_LIMIT", severity: "warning", message: "WordArt rendering is limited to 1,024 rows; the full source text remains available in the model", shapeId: shape.id, slideId: ctx.slideId });
    }
    const rows = Math.max(1, lines.length), fontSize = 1e3, letterSpacing = (Math.max(0, safe_js_4.finite(art.spacing, 1)) - 1) * fontSize * 0.5, measurer = ctx.textMeasurer ?? measure_js_2.createCanvasTextMeasurer();
    const style = { fontFamily: art.fontFamily, fontSize, bold: art.bold, italic: art.italic, letterSpacing };
    let approximate = false;
    const metrics = lines.map((text) => {
      const measured = measurer?.measure(text, style);
      if (measured && Number.isFinite(measured.width) && measured.width > 0 && measured.ascent + measured.descent > 0)
        return measured;
      approximate = true;
      let width = 0, count = 0;
      for (const c of text) {
        count++;
        width += (c.codePointAt(0) >= 11904 ? 1 : /[MW@]/.test(c) ? 1 : /[mw]/.test(c) ? 0.9 : /[ilI.,'!|]/.test(c) ? 0.28 : /[frjt]/.test(c) ? 0.42 : /\s/.test(c) ? 0.33 : /[A-Z]/.test(c) ? 0.72 : 0.62) * fontSize;
      }
      return { width: Math.max(1, width * 1.2 + Math.max(0, count - 1) * letterSpacing), ascent: fontSize * 0.8, descent: fontSize * 0.2 };
    });
    if (approximate)
      ctx.warnings?.push({ code: "WORDART_METRICS_APPROXIMATED", severity: "warning", message: "Font measurement is unavailable; WordArt source fitting uses conservative character widths", shapeId: shape.id, slideId: ctx.slideId });
    const maxWidth = metrics.reduce((max, m) => Math.max(max, m.width), 1), body = lines.map((text, index) => {
      const metric = metrics[index], length = art.alignment === "justify" ? 1e3 : 1e3 * metric.width / maxWidth, tx = art.alignment === "right" ? 1e3 - length : art.alignment === "center" ? (1e3 - length) / 2 : 0, sx = length / Math.max(1, metric.width), sy = 1e3 / rows / (metric.ascent + metric.descent), anchor = art.alignment === "right" ? "end" : art.alignment === "center" ? "middle" : "start", x = anchor === "end" ? metric.width : anchor === "middle" ? metric.width / 2 : 0;
      return `<g transform="translate(${safe_js_4.n(tx)} ${safe_js_4.n(index * 1e3 / rows)}) scale(${safe_js_4.n(sx)} ${safe_js_4.n(sy)})"><text x="${safe_js_4.n(x)}" y="${safe_js_4.n(metric.ascent)}" text-anchor="${anchor}" font-size="${fontSize}" vector-effect="non-scaling-stroke" letter-spacing="${safe_js_4.n(letterSpacing)}">${safe_js_4.escapeXml(text)}</text></g>`;
    }).join("");
    ctx.defs.push(`<g id="${textId}" transform="scale(.001)" text-rendering="geometricPrecision" font-family="${safe_js_4.escapeXml(safe_js_4.cssFont(art.fontFamily))}"${art.bold ? ' font-weight="700"' : ""}${art.italic ? ' font-style="italic"' : ""} ${fillAttrs} ${strokeAttrs}>${body}</g>`);
    const columns = preset === 136 || preset === 24 ? 1 : 48, parts = [];
    if (columns > 1)
      ctx.warnings?.push({ code: "WORDART_MESH_RASTERIZATION_APPROXIMATED", severity: "warning", message: "WordArt is deformed through clipped affine glyph slices; some SVG rasterizers can show fine seams at slice boundaries", shapeId: shape.id, slideId: ctx.slideId });
    for (let i = 0; i < columns; i++) {
      const x0 = i / columns, x1 = (i + 1) / columns;
      const a = { x: x0, y: 0 }, b = { x: x1, y: 0 }, c = { x: x1, y: 1 }, d = { x: x0, y: 1 };
      for (const [j, source] of [[a, b, c], [a, c, d]].entries()) {
        const target = source.map((p) => {
          const q = warpPoint(preset, p.x, p.y, art.adjustments);
          return art.vertical ? { x: (1 - q.y) * w, y: q.x * h } : { x: q.x * w, y: q.y * h };
        });
        const m = triangleMatrix(source, target);
        if (!m || !m.every(Number.isFinite))
          continue;
        const clipId = `${ctx.id}-clip-${i}-${j}`;
        const center = { x: source.reduce((s, p) => s + p.x, 0) / 3, y: source.reduce((s, p) => s + p.y, 0) / 3 }, epsilon = 25e-4;
        const clip = source.map((p) => ({ x: p.x + Math.sign(p.x - center.x) * epsilon, y: p.y + Math.sign(p.y - center.y) * epsilon }));
        ctx.defs.push(`<clipPath id="${clipId}" clipPathUnits="userSpaceOnUse"><path d="M${clip.map((p) => `${safe_js_4.n(p.x)} ${safe_js_4.n(p.y)}`).join("L")}Z"/></clipPath>`);
        parts.push(`<g transform="matrix(${m.map(safe_js_4.n).join(" ")})"><g clip-path="url(#${clipId})"><use href="#${textId}" xlink:href="#${textId}"/></g></g>`);
      }
    }
    return `<g data-ppt-wordart="${art.warpPreset}" aria-label="${safe_js_4.escapeXml(art.text)}"><g aria-hidden="true">${parts.join("")}</g></g>`;
  }
  exports_33("renderWordArt", renderWordArt);
  return {
    setters: [
      function(safe_js_4_1) {
        safe_js_4 = safe_js_4_1;
      },
      function(measure_js_2_1) {
        measure_js_2 = measure_js_2_1;
      }
    ],
    execute: function() {
      clamp = (n, low = 0, high = 1) => Math.max(low, Math.min(high, n));
      exports_33("SUPPORTED_WORDART_PRESETS", SUPPORTED_WORDART_PRESETS = /* @__PURE__ */ new Set([24, 25, 26, 27, 28, 29, 30, 31, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175]));
    }
  };
});
System.register("render/three-d", ["render/geometry", "render/safe"], function(exports_34, context_34) {
  "use strict";
  var geometry_js_3, safe_js_5, rad, ExtrusionCameraError;
  var __moduleName = context_34 && context_34.id;
  function flattenPath(path, maxPoints = 4096) {
    const tokens = [];
    for (const match of path.matchAll(/[a-df-zA-DF-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g)) {
      if (tokens.length > 1e5)
        throw new RangeError("Path token limit");
      tokens.push(match[0]);
    }
    const contours = [];
    let current, point = { x: 0, y: 0 }, start = point, control, previous = "", command = "", at = 0, count = 0;
    const add = (p) => {
      if (!Number.isFinite(p.x) || !Number.isFinite(p.y) || ++count > maxPoints)
        throw new RangeError("Path point limit");
      if (!current) {
        current = { points: [], closed: false };
        contours.push(current);
      }
      current.points.push(p);
      point = p;
    };
    const read = () => {
      const value = Number(tokens[at++]);
      if (!Number.isFinite(value))
        throw new RangeError("Invalid path coordinate");
      return value;
    };
    const counts = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2, A: 7 };
    while (at < tokens.length) {
      if (/^[a-zA-Z]$/.test(tokens[at]))
        command = tokens[at++];
      const upper = command.toUpperCase(), relative = command !== upper;
      if (upper === "Z") {
        if (current) {
          current.closed = true;
          point = start;
        }
        current = void 0;
        control = void 0;
        previous = upper;
        command = "";
        continue;
      }
      const need = counts[upper];
      if (need == null || at + need > tokens.length)
        throw new RangeError("Invalid SVG path");
      const origin = point, coords = [];
      const xy = () => ({ x: read() + (relative ? origin.x : 0), y: read() + (relative ? origin.y : 0) });
      if (upper === "M") {
        point = xy();
        current = { points: [], closed: false };
        contours.push(current);
        start = point;
        add(point);
        command = relative ? "l" : "L";
      } else if (upper === "L")
        add(xy());
      else if (upper === "H")
        add({ x: read() + (relative ? origin.x : 0), y: origin.y });
      else if (upper === "V")
        add({ x: origin.x, y: read() + (relative ? origin.y : 0) });
      else if (upper === "C" || upper === "S") {
        const c1 = upper === "C" ? xy() : previous === "C" || previous === "S" ? { x: 2 * origin.x - (control?.x ?? origin.x), y: 2 * origin.y - (control?.y ?? origin.y) } : origin, c2 = xy(), end = xy();
        for (let i = 1; i <= 16; i++) {
          const t = i / 16, s = 1 - t;
          coords.push({ x: s * s * s * origin.x + 3 * s * s * t * c1.x + 3 * s * t * t * c2.x + t * t * t * end.x, y: s * s * s * origin.y + 3 * s * s * t * c1.y + 3 * s * t * t * c2.y + t * t * t * end.y });
        }
        coords.forEach(add);
        control = c2;
      } else if (upper === "Q" || upper === "T") {
        const c = upper === "Q" ? xy() : previous === "Q" || previous === "T" ? { x: 2 * origin.x - (control?.x ?? origin.x), y: 2 * origin.y - (control?.y ?? origin.y) } : origin, end = xy();
        for (let i = 1; i <= 16; i++) {
          const t = i / 16, s = 1 - t;
          add({ x: s * s * origin.x + 2 * s * t * c.x + t * t * end.x, y: s * s * origin.y + 2 * s * t * c.y + t * t * end.y });
        }
        control = c;
      } else if (upper === "A") {
        let rx = Math.abs(read()), ry = Math.abs(read());
        const angle = read() * rad, large = read() !== 0, sweep = read() !== 0, end = xy();
        if (!rx || !ry || origin.x === end.x && origin.y === end.y)
          add(end);
        else {
          const cos = Math.cos(angle), sin = Math.sin(angle), dx = (origin.x - end.x) / 2, dy = (origin.y - end.y) / 2, xp = cos * dx + sin * dy, yp = -sin * dx + cos * dy;
          const scale = xp * xp / (rx * rx) + yp * yp / (ry * ry);
          if (scale > 1) {
            rx *= Math.sqrt(scale);
            ry *= Math.sqrt(scale);
          }
          const q = Math.sqrt(Math.max(0, (rx * rx * ry * ry - rx * rx * yp * yp - ry * ry * xp * xp) / (rx * rx * yp * yp + ry * ry * xp * xp))) * (large === sweep ? -1 : 1);
          const cxp = q * rx * yp / ry, cyp = -q * ry * xp / rx, cx = cos * cxp - sin * cyp + (origin.x + end.x) / 2, cy = sin * cxp + cos * cyp + (origin.y + end.y) / 2;
          const a0 = Math.atan2((yp - cyp) / ry, (xp - cxp) / rx), a1 = Math.atan2((-yp - cyp) / ry, (-xp - cxp) / rx);
          let delta = a1 - a0;
          if (sweep && delta < 0)
            delta += Math.PI * 2;
          if (!sweep && delta > 0)
            delta -= Math.PI * 2;
          const steps = Math.max(1, Math.ceil(Math.abs(delta) * 16 / Math.PI));
          for (let i = 1; i <= steps; i++) {
            const a = a0 + delta * i / steps;
            add({ x: cx + cos * rx * Math.cos(a) - sin * ry * Math.sin(a), y: cy + sin * rx * Math.cos(a) + cos * ry * Math.sin(a) });
          }
        }
      }
      if (!["C", "S", "Q", "T"].includes(upper))
        control = void 0;
      previous = upper;
    }
    return contours;
  }
  exports_34("flattenPath", flattenPath);
  function shapePath(shape) {
    const w = shape.bounds.width, h = shape.bounds.height;
    if (shape.path)
      return geometry_js_3.mapPathToBounds(shape.path, shape.pathBounds ?? { x: 0, y: 0, width: w, height: h }, w, h);
    const geometry = geometry_js_3.presetGeometry(shape.preset, w, h, shape.source?.properties);
    if (geometry.tag === "path")
      return /\bd="([^"]*)"/.exec(geometry.attrs)?.[1] ?? "";
    if (geometry.tag === "ellipse")
      return `M${w} ${h / 2} A${w / 2} ${h / 2} 0 1 1 0 ${h / 2} A${w / 2} ${h / 2} 0 1 1 ${w} ${h / 2} Z`;
    const rx = Number(/\brx="([^"]*)"/.exec(geometry.attrs)?.[1] ?? 0);
    return rx ? `M${rx} 0 H${w - rx} A${rx} ${rx} 0 0 1 ${w} ${rx} V${h - rx} A${rx} ${rx} 0 0 1 ${w - rx} ${h} H${rx} A${rx} ${rx} 0 0 1 0 ${h - rx} V${rx} A${rx} ${rx} 0 0 1 ${rx} 0 Z` : `M0 0 H${w} V${h} H0 Z`;
  }
  function extrusionProjector(e, width, height) {
    const yr = safe_js_5.finite(e.rotationY) * rad, xr = safe_js_5.finite(e.rotationX) * rad, cy = Math.cos(yr), sy = Math.sin(yr), cx = Math.cos(xr), sx = Math.sin(xr);
    const skew = e.skewAngle === 0 ? 0 : safe_js_5.finite(e.skewAmount) / 100, kx = Math.cos(safe_js_5.finite(e.skewAngle) * rad) * skew, ky = Math.sin(safe_js_5.finite(e.skewAngle) * rad) * skew;
    const rotate = (point) => {
      const x = point.x - width / 2, y = point.y - height / 2, x1 = x * cy + point.z * sy, z1 = -x * sy + point.z * cy;
      return { x: width / 2 + x1, y: height / 2 + y * cx - z1 * sx, z: y * sx + z1 * cx };
    };
    let camera;
    if (!e.parallel) {
      if (!e.camera || ![e.camera.x, e.camera.y, e.camera.z].every(Number.isFinite) || e.camera.z <= 0)
        throw new ExtrusionCameraError("Perspective camera is missing or has a nonpositive distance");
      camera = { x: width / 2 + safe_js_5.finite(e.origin?.x, 0.5) * width + e.camera.x, y: height / 2 + safe_js_5.finite(e.origin?.y, -0.5) * height + e.camera.y, z: e.camera.z };
    }
    const project = (point) => {
      const p = rotate(point);
      if (!camera)
        return { x: p.x + p.z * kx, y: p.y + p.z * ky, z: p.z };
      const distance = camera.z - p.z;
      if (distance <= Math.max(1e-6, camera.z * 1e-6))
        throw new ExtrusionCameraError("Perspective extrusion crosses the camera plane");
      const scale = camera.z / distance;
      return { x: camera.x + (p.x - camera.x) * scale, y: camera.y + (p.y - camera.y) * scale, z: p.z };
    };
    return { rotate, project, view: (p) => camera ? { x: camera.x - p.x, y: camera.y - p.y, z: camera.z - p.z } : { x: -kx, y: -ky, z: 1 } };
  }
  function projectExtrusionPoint(point, e, width, height) {
    return extrusionProjector(e, width, height).project(point);
  }
  exports_34("projectExtrusionPoint", projectExtrusionPoint);
  function buildExtrusionMesh(shape) {
    const e = shape.extrusion;
    if (!e)
      return void 0;
    const w = safe_js_5.finite(shape.bounds.width), h = safe_js_5.finite(shape.bounds.height), contours = flattenPath(shapePath(shape)), faces = [];
    const projector = extrusionProjector(e, w, h), project = (p2, z) => projector.project({ ...p2, z }), rotate = (p2, z) => projector.rotate({ ...p2, z }), forward = Math.max(0, safe_js_5.finite(e.forward)), back = -Math.max(0, safe_js_5.finite(e.depth));
    for (const contour of contours) {
      if (!contour.closed || contour.points.length < 3)
        continue;
      const points = contour.points, orientation = contours.length === 1 && points.reduce((area, a, i) => {
        const b = points[(i + 1) % points.length];
        return area + a.x * b.y - b.x * a.y;
      }, 0) < 0 ? -1 : 1;
      for (let i = 0; i < points.length; i++) {
        const a = points[i], b = points[(i + 1) % points.length];
        if (a.x === b.x && a.y === b.y)
          continue;
        const p2 = [project(a, back), project(b, back), project(b, forward), project(a, forward)];
        const r0 = rotate(a, back), r1 = rotate(b, back), r3 = rotate(a, forward), ux = r1.x - r0.x, uy = r1.y - r0.y, uz = r1.z - r0.z, vx = r3.x - r0.x, vy = r3.y - r0.y, vz = r3.z - r0.z;
        const nx = (uy * vz - uz * vy) * orientation, ny = (uz * vx - ux * vz) * orientation, nz = (ux * vy - uy * vx) * orientation, length = Math.hypot(nx, ny, nz) || 1, light = Math.max(0, (-0.4 * nx - 0.6 * ny + nz) / (length * Math.sqrt(1.52)));
        const intensity = Math.max(0, Math.min(1, safe_js_5.finite(e.ambient, 0.3) + safe_js_5.finite(e.diffuse, 1) * light));
        const view = projector.view({ x: r0.x + (ux + vx) / 2, y: r0.y + (uy + vy) / 2, z: r0.z + (uz + vz) / 2 });
        faces.push({ points: p2, depth: p2.reduce((sum, q) => sum + q.z, 0) / 4, intensity, visible: contours.length > 1 || nx * view.x + ny * view.y + nz * view.z > 1e-8 });
      }
    }
    faces.sort((a, b) => a.depth - b.depth);
    const dx = w || 1, dy = h || 1, p = project({ x: 0, y: 0 }, forward), x = project({ x: dx, y: 0 }, forward), y = project({ x: 0, y: dy }, forward);
    return { faces, frontMatrix: [(x.x - p.x) / dx, (x.y - p.y) / dx, (y.x - p.x) / dy, (y.y - p.y) / dy, p.x, p.y], contours };
  }
  exports_34("buildExtrusionMesh", buildExtrusionMesh);
  function litColor(value, intensity) {
    const safe = safe_js_5.color(value, "#808080");
    let rgb = safe.slice(1);
    if (rgb.length === 3)
      rgb = rgb.split("").map((v) => v + v).join("");
    if (!/^[\da-f]{6,8}$/i.test(rgb))
      return "#808080";
    return "#" + [0, 2, 4].map((i) => Math.round(parseInt(rgb.slice(i, i + 2), 16) * intensity).toString(16).padStart(2, "0")).join("");
  }
  function renderExtrusion(shape, frontMarkup, ctx) {
    const e = shape.extrusion;
    if (!e || e.depth + e.forward <= 0)
      return frontMarkup;
    const warning = (code, message) => ctx.warnings?.push({ code, severity: "warning", message, shapeId: shape.id, slideId: ctx.slideId });
    if (shape.wordArt) {
      warning("WORDART_EXTRUSION_UNSUPPORTED", "WordArt envelope is rendered, but glyph contour extrusion requires font outline data");
      return frontMarkup;
    }
    let mesh;
    try {
      mesh = buildExtrusionMesh(shape);
    } catch (error) {
      if (error instanceof ExtrusionCameraError)
        warning("EXTRUSION_CAMERA_UNSUPPORTED", error.message + "; the saved foreground is retained");
      else
        warning("EXTRUSION_PATH_LIMIT", "Extrusion contour is invalid or exceeds its 4,096-point rendering limit");
      return frontMarkup;
    }
    if (!mesh || !mesh.faces.length) {
      warning("EXTRUSION_OPEN_CONTOUR", "3D extrusion requires a supported closed shape contour");
      return frontMarkup;
    }
    if (!e.parallel && (e.rotationX !== 0 || e.rotationY !== 0))
      warning("EXTRUSION_PERSPECTIVE_APPROXIMATED", "Rotated perspective side faces use the saved camera; the projective front plane uses a three-corner affine approximation");
    if (e.metallic)
      warning("EXTRUSION_MATERIAL_APPROXIMATED", "Metallic material uses diffuse vector shading; specular highlights are not reproduced");
    if (mesh.contours.length > 1)
      warning("EXTRUSION_COMPLEX_CONTOUR_APPROXIMATED", "Compound extrusion contours use sorted side faces; exact hidden-surface removal is not implemented");
    const c = ctx.resolveColor(e.color, e.colorIndex, shape.fill.color ?? "#808080");
    const sides = mesh.faces.filter((face) => face.visible).map((face) => `<polygon points="${face.points.map((p) => `${safe_js_5.n(p.x)},${safe_js_5.n(p.y)}`).join(" ")}" fill="${litColor(c, face.intensity)}" stroke="${litColor(c, face.intensity)}" stroke-width=".25" stroke-linejoin="round"/>`).join("");
    return `<g data-ppt-extrusion="mesh">${sides}<g transform="matrix(${mesh.frontMatrix.map(safe_js_5.n).join(" ")})">${frontMarkup}</g></g>`;
  }
  exports_34("renderExtrusion", renderExtrusion);
  return {
    setters: [
      function(geometry_js_3_1) {
        geometry_js_3 = geometry_js_3_1;
      },
      function(safe_js_5_1) {
        safe_js_5 = safe_js_5_1;
      }
    ],
    execute: function() {
      rad = Math.PI / 180;
      ExtrusionCameraError = class ExtrusionCameraError extends RangeError {
      };
    }
  };
});
System.register("render/svg", ["core/errors", "render/safe", "render/geometry", "render/text", "render/fields", "render/effects", "render/wordart", "render/three-d"], function(exports_35, context_35) {
  "use strict";
  var errors_js_15, safe_js_6, geometry_js_4, text_js_3, fields_js_1, effects_js_1, wordart_js_1, three_d_js_1, renderSequence, defaultPptCss;
  var __moduleName = context_35 && context_35.id;
  function nextId(ctx) {
    return `${ctx.prefix}-${++ctx.seq}`;
  }
  function sceneColor(value, index, ctx, fallback = "#000000") {
    const rgb = index == null ? void 0 : ctx.slide.colorScheme?.[index];
    return rgb == null ? safe_js_6.color(value, fallback) : `#${[rgb & 255, rgb >>> 8 & 255, rgb >>> 16 & 255].map((v) => v.toString(16).padStart(2, "0")).join("")}`;
  }
  function effectContext(ctx) {
    return { id: nextId(ctx), defs: ctx.defs, resolveColor: (value, index, fallback) => sceneColor(value, index, ctx, fallback), warnings: ctx.warnings, slideId: ctx.slide.id, textMeasurer: ctx.options.textMeasurer, bounds: ctx.slide.size };
  }
  function assetUrl(ctx, id) {
    if (ctx.urls.has(id))
      return ctx.urls.get(id);
    const asset = ctx.assets.get(id);
    let url;
    if (asset && !asset.unsupported) {
      if (ctx.options.assetUrl)
        url = safe_js_6.imageUrl(ctx.options.assetUrl(asset));
      else if (/^image\/(png|jpeg|gif|bmp|webp|svg\+xml)$/.test(asset.mimeType))
        url = `data:${asset.mimeType};base64,${safe_js_6.base64(asset.bytes)}`;
    }
    ctx.urls.set(id, url);
    return url;
  }
  function paint(p, ctx, shape) {
    const opacity = Math.max(0, Math.min(1, safe_js_6.finite(p.opacity, 1)));
    if (p.kind === "none")
      return 'fill="none"';
    if (p.kind === "solid")
      return `fill="${sceneColor(p.color, p.colorIndex, ctx, "#ffffff")}" fill-opacity="${safe_js_6.n(opacity)}"`;
    if (p.kind === "gradient")
      return effects_js_1.renderGradient(p, effectContext(ctx), shape);
    const url = p.assetId ? assetUrl(ctx, p.assetId) : void 0;
    if (url) {
      const id = nextId(ctx), asset = p.assetId ? ctx.assets.get(p.assetId) : void 0, tiled = p.imageStyle === "pattern" || p.imageStyle === "texture";
      const width = tiled ? Math.max(1, safe_js_6.finite(p.tileWidth, asset?.width ?? 8)) : 1, height = tiled ? Math.max(1, safe_js_6.finite(p.tileHeight, asset?.height ?? 8)) : 1;
      let filter = "";
      if (p.imageStyle === "pattern") {
        const foreground = sceneColor(p.color, p.colorIndex, ctx, "#ffffff"), background = sceneColor(p.backColor, p.backColorIndex, ctx, "#ffffff");
        const rgb = (value) => {
          const hex = value.replace(/^#/, "");
          return [0, 1, 2].map((i) => {
            const component = hex.length <= 4 ? hex[i]?.repeat(2) : hex.slice(i * 2, i * 2 + 2);
            return parseInt(component ?? "00", 16) / 255 || 0;
          });
        }, front = rgb(foreground), back = rgb(background), fid = nextId(ctx), alpha = Math.max(0, Math.min(1, safe_js_6.finite(p.backOpacity, 1)));
        const row = (from, to) => `${[0.2126, 0.7152, 0.0722].map((c) => safe_js_6.n(c * (to - from))).join(" ")} 0 ${safe_js_6.n(from)}`;
        ctx.defs.push(`<filter id="${fid}" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="${[...front.map((c, i) => row(c, back[i])), row(opacity, alpha)].join(" ")}"/></filter>`);
        filter = ` filter="url(#${fid})"`;
      }
      ctx.defs.push(`<pattern id="${id}" patternUnits="${tiled ? "userSpaceOnUse" : "objectBoundingBox"}" width="${safe_js_6.n(width)}" height="${safe_js_6.n(height)}"${tiled ? "" : ` viewBox="0 0 1 1" preserveAspectRatio="none"`}><image xlink:href="${safe_js_6.escapeXml(url)}" x="0" y="0" width="${safe_js_6.n(width)}" height="${safe_js_6.n(height)}" preserveAspectRatio="none"${filter}/></pattern>`);
      return `fill="url(#${id})" fill-opacity="${safe_js_6.n(p.imageStyle === "pattern" ? 1 : opacity)}"`;
    }
    return 'fill="none"';
  }
  function marker(ctx, kind, stroke2, start) {
    if (kind === "none" || kind === "0")
      return "";
    const id = nextId(ctx), c = sceneColor(stroke2.color, stroke2.colorIndex, ctx);
    let geometry = '<path d="M0 0L10 5L0 10Z"/>';
    if (kind === "stealth" || kind === "2")
      geometry = '<path d="M0 0L10 5L0 10L3 5Z"/>';
    if (kind === "diamond" || kind === "3")
      geometry = '<path d="M0 5L5 0L10 5L5 10Z"/>';
    if (kind === "oval" || kind === "4")
      geometry = '<ellipse cx="5" cy="5" rx="5" ry="5"/>';
    if (kind === "open" || kind === "5")
      geometry = `<path d="M0 0L10 5L0 10" fill="none" stroke="${c}" stroke-width="1.5"/>`;
    ctx.defs.push(`<marker id="${id}" markerWidth="5" markerHeight="5" refX="9" refY="5" viewBox="0 0 10 10" markerUnits="strokeWidth" orient="auto-start-reverse"><g fill="${c}">${geometry}</g></marker>`);
    return ` marker-${start ? "start" : "end"}="url(#${id})"`;
  }
  function stroke(line, ctx) {
    if (!line || line.width <= 0)
      return 'stroke="none"';
    let attrs = `stroke="${sceneColor(line.color, line.colorIndex, ctx)}" stroke-width="${safe_js_6.n(Math.max(0, safe_js_6.finite(line.width)))}" stroke-opacity="${safe_js_6.n(Math.max(0, Math.min(1, safe_js_6.finite(line.opacity, 1))))}" stroke-linejoin="round"`;
    if (line.cap)
      attrs += ` stroke-linecap="${line.cap}"`;
    if (line.dash?.length)
      attrs += ` stroke-dasharray="${line.dash.map((v) => safe_js_6.n(Math.max(0, v))).join(" ")}"`;
    if (line.startArrow)
      attrs += marker(ctx, line.startArrow, line, true);
    if (line.endArrow)
      attrs += marker(ctx, line.endArrow, line, false);
    return attrs;
  }
  function renderGeometry(shape, ctx, w, h) {
    const physical = { ...shape, bounds: { ...shape.bounds, width: w, height: h } }, fill = paint(shape.fill, ctx, physical), line = stroke(shape.line, ctx);
    if (shape.path) {
      const bounds = shape.pathBounds ?? { x: 0, y: 0, width: shape.bounds.width, height: shape.bounds.height };
      return (shape.pathParts ?? [{ path: shape.path, noFill: false, noLine: false }]).map((part) => `<path d="${safe_js_6.escapeXml(geometry_js_4.mapPathToBounds(part.path, bounds, w, h))}" ${part.noFill ? 'fill="none"' : fill} ${part.noLine ? 'stroke="none"' : line}/>`).join("");
    }
    const geometry = geometry_js_4.presetGeometry(shape.preset, w, h, shape.source?.properties);
    if (!geometry.supported)
      ctx.warnings.push({ code: "PRESET_APPROXIMATED", severity: "warning", message: `Shape preset ${shape.preset} has no exact geometry and is shown with a bounding rectangle`, shapeId: shape.id, slideId: ctx.slide.id });
    else if (shape.preset !== 2 && Object.keys(shape.source?.properties ?? {}).some((key) => Number(key) >= 327 && Number(key) <= 336))
      ctx.warnings.push({ code: "PRESET_ADJUSTMENT_UNSUPPORTED", severity: "warning", message: `Shape preset ${shape.preset} uses default geometry; source adjustment handles are retained but not evaluated`, shapeId: shape.id, slideId: ctx.slide.id });
    return `<${geometry.tag} ${geometry.attrs} ${geometry.open ? 'fill="none"' : fill} ${line}/>`;
  }
  function shapeTransform(shape) {
    const b = shape.bounds, cx = b.width / 2, cy = b.height / 2;
    return `translate(${safe_js_6.transformNumber(b.x)} ${safe_js_6.transformNumber(b.y)})${shape.rotation ? ` rotate(${safe_js_6.transformNumber(shape.rotation)} ${safe_js_6.transformNumber(cx)} ${safe_js_6.transformNumber(cy)})` : ""}${shape.flipH || shape.flipV ? ` translate(${safe_js_6.transformNumber(cx)} ${safe_js_6.transformNumber(cy)}) scale(${shape.flipH ? -1 : 1} ${shape.flipV ? -1 : 1}) translate(${safe_js_6.transformNumber(-cx)} ${safe_js_6.transformNumber(-cy)})` : ""}`;
  }
  function renderImage(shape, ctx) {
    const b = shape.bounds, image = shape.image, url = image ? assetUrl(ctx, image.assetId) : void 0;
    if (!image || !url) {
      ctx.warnings.push({ code: "IMAGE_NOT_RENDERABLE", severity: "warning", message: "Image resource is unavailable or not supported by this renderer", shapeId: shape.id, slideId: ctx.slide.id });
      return ctx.options.showUnsupported === false ? "" : `<rect width="${safe_js_6.n(b.width)}" height="${safe_js_6.n(b.height)}" fill="#f1f5f9" stroke="#94a3b8" stroke-dasharray="4 3"/><text x="6" y="18" font-family="sans-serif" font-size="12" fill="#64748b">Image unavailable</text>`;
    }
    const crop = image.crop ?? { left: 0, top: 0, right: 0, bottom: 0 }, vw = 1 - crop.left - crop.right, vh = 1 - crop.top - crop.bottom;
    if (vw <= 0 || vh <= 0)
      return "";
    const id = nextId(ctx);
    ctx.defs.push(`<clipPath id="${id}"><rect width="${safe_js_6.n(b.width)}" height="${safe_js_6.n(b.height)}"/></clipPath>`);
    let filter = "";
    if (image.brightness != null || image.contrast != null) {
      const fid = nextId(ctx), slope = safe_js_6.finite(image.contrast, 1), intercept = safe_js_6.finite(image.brightness) + (1 - slope) / 2;
      ctx.defs.push(`<filter id="${fid}" color-interpolation-filters="sRGB"><feComponentTransfer>${["R", "G", "B"].map((c) => `<feFunc${c} type="linear" slope="${safe_js_6.n(slope)}" intercept="${safe_js_6.n(intercept)}"/>`).join("")}</feComponentTransfer></filter>`);
      filter = ` filter="url(#${fid})"`;
    }
    return `<g clip-path="url(#${id})"><image xlink:href="${safe_js_6.escapeXml(url)}" x="${safe_js_6.n(-crop.left * b.width / vw)}" y="${safe_js_6.n(-crop.top * b.height / vh)}" width="${safe_js_6.n(b.width / vw)}" height="${safe_js_6.n(b.height / vh)}" preserveAspectRatio="none"${filter}/></g>`;
  }
  function renderMedia(shape, ctx) {
    const media = shape.media;
    if (!media)
      return "";
    const asset = media.assetId ? ctx.assets.get(media.assetId) : void 0;
    let url;
    if (ctx.options.mediaControls === false)
      return media.posterAssetId ? renderImage({ ...shape, image: { assetId: media.posterAssetId } }, ctx) : "";
    if (asset && !asset.unsupported && /^(?:audio|video)\/[a-z0-9.+-]+$/i.test(asset.mimeType)) {
      const supplied = ctx.options.assetUrl?.(asset);
      if (ctx.options.assetUrl) {
        if (supplied && /^(?:blob:|data:(?:audio|video)\/[a-z0-9.+-]+;base64,)/i.test(supplied))
          url = supplied;
      } else
        url = `data:${asset.mimeType};base64,${safe_js_6.base64(asset.bytes)}`;
    }
    if (!url) {
      ctx.warnings.push({ code: "MEDIA_SOURCE_UNAVAILABLE", severity: "warning", message: "Media has no supported embedded asset; external paths are not fetched", shapeId: shape.id, slideId: ctx.slide.id });
      return "";
    }
    const tag = media.kind === "video" ? "video" : "audio", poster = media.posterAssetId ? assetUrl(ctx, media.posterAssetId) : void 0, b = shape.bounds;
    return `<foreignObject x="0" y="0" width="${safe_js_6.n(b.width)}" height="${safe_js_6.n(b.height)}"><div xmlns="http://www.w3.org/1999/xhtml" style="width:100%;height:100%;display:flex;align-items:center;justify-content:center"><${tag} data-ppt-media="${safe_js_6.n(media.mediaId)}" controls="controls" preload="none" playsinline="playsinline"${media.loop ? ' loop="loop"' : ""}${poster && tag === "video" ? ` poster="${safe_js_6.escapeXml(poster)}"` : ""} src="${safe_js_6.escapeXml(url)}" style="width:100%;max-height:100%;object-fit:contain">Embedded media</${tag}></div></foreignObject>`;
  }
  function multiply(a, b) {
    return [a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1], a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3]];
  }
  function shapeLinear(shape) {
    const angle = shape.rotation * Math.PI / 180, cos = Math.cos(angle), sin = Math.sin(angle), hx = shape.flipH ? -1 : 1, vy = shape.flipV ? -1 : 1;
    return [cos * hx, sin * hx, -sin * vy, cos * vy];
  }
  function textAxisScale(shape, parent) {
    const axes = multiply(parent, shapeLinear(shape)), x = Math.hypot(axes[0], axes[1]), y = Math.hypot(axes[2], axes[3]);
    if (!Number.isFinite(x) || x <= 0 || !Number.isFinite(y) || y <= 0 || !Number.isFinite(1 / x) || !Number.isFinite(1 / y))
      return void 0;
    const cross = axes[0] / x * (axes[3] / y) - axes[1] / x * (axes[2] / y);
    return Number.isFinite(cross) && cross !== 0 ? { x, y } : void 0;
  }
  function shadowWrap(shape, html, ctx, parent) {
    return shape.shadow ? effects_js_1.renderShadow(shape, html, effectContext(ctx), parent) : html;
  }
  function renderShape(shape, ctx, depth = 0, parent = [1, 0, 0, 1]) {
    if (shape.hidden || depth > 64 || !fields_js_1.headerFooterVisible(shape.placeholder?.type, ctx.slide))
      return "";
    const b = shape.bounds, w = Math.max(0, safe_js_6.finite(b.width));
    let h = Math.max(0, safe_js_6.finite(b.height));
    const textContent = (resizeShape = true) => {
      if (!shape.text)
        return "";
      const scale = textAxisScale(shape, parent);
      if (!scale || !Number.isFinite(w * scale.x) || !Number.isFinite(h * scale.y)) {
        ctx.warnings.push({ code: "TEXT_TRANSFORM_DEGENERATE", severity: "warning", message: "Text has a singular or non-finite ancestor transform and cannot be laid out in a physical frame", slideId: ctx.slide.id, shapeId: shape.id });
        return "";
      }
      const frame = fields_js_1.resolveTextFields(shape.text, { slide: ctx.slide, options: ctx.options, date: ctx.date, warnings: ctx.warnings, shapeId: shape.id }, shape.placeholder?.type);
      const html = text_js_3.renderText(frame, w * scale.x, h * scale.y, ctx.slide.colorScheme, { ...ctx.options, warnings: ctx.warnings, slideId: ctx.slide.id, shapeId: shape.id, onLayout: (layout) => {
        if (resizeShape && frame.autofit === "resize")
          h = layout.height / scale.y;
      } });
      if (resizeShape && h !== shape.bounds.height)
        shape = { ...shape, bounds: { ...shape.bounds, height: h } };
      return scale.x === 1 && scale.y === 1 ? html : `<g transform="scale(${safe_js_6.transformNumber(1 / scale.x)} ${safe_js_6.transformNumber(1 / scale.y)})">${html}</g>`;
    };
    let text = shape.text && !shape.wordArt ? textContent() : "";
    const animate = (html) => {
      const href = safe_js_6.linkUrl(shape.hyperlink);
      if (href)
        html = `<a href="${safe_js_6.escapeXml(href)}"${href.startsWith("#") ? "" : ' target="_blank" rel="noopener noreferrer"'}>${html}</a>`;
      return ctx.animationTargets.has(shape.id) ? `<g data-ppt-animation="${safe_js_6.n(shape.id)}" data-ppt-parent="${parent.map(safe_js_6.transformNumber).join(" ")}">${html}</g>` : html;
    };
    const label = shape.name ? ` aria-label="${safe_js_6.escapeXml(shape.name)}"` : "";
    if (shape.kind === "group") {
      const gb = shape.groupBounds ?? { x: 0, y: 0, width: w, height: h }, sx = gb.width ? w / gb.width : 1, sy = gb.height ? h / gb.height : 1, linear = multiply(multiply(parent, shapeLinear(shape)), [sx, 0, 0, sy]);
      return animate(shadowWrap(shape, `<g data-ppt-shape="${safe_js_6.n(shape.id)}" transform="${shapeTransform(shape)}"${label}><g transform="scale(${safe_js_6.transformNumber(sx)} ${safe_js_6.transformNumber(sy)}) translate(${safe_js_6.transformNumber(-gb.x)} ${safe_js_6.transformNumber(-gb.y)})">${(shape.children ?? []).map((s) => renderShape(s, ctx, depth + 1, linear)).join("")}</g></g>`, ctx, parent));
    }
    let content = "", wordArtRendered = false;
    if (shape.kind === "unsupported") {
      if (ctx.options.showUnsupported !== false)
        content = `<rect width="${safe_js_6.n(w)}" height="${safe_js_6.n(h)}" fill="#f8fafc" stroke="#94a3b8" stroke-dasharray="4 3"/><text x="6" y="18" font-family="sans-serif" font-size="12" fill="#64748b">Unsupported element</text>`;
    } else if (shape.kind === "image" && shape.preset === 75) {
      content = renderImage(shape, ctx);
    } else {
      const wordArt = shape.wordArt ? wordart_js_1.renderWordArt(shape, paint(shape.fill, ctx, shape), stroke(shape.line, ctx), effectContext(ctx)) : void 0;
      if (wordArt != null) {
        content = wordArt;
        wordArtRendered = true;
      } else {
        const scale = (shape.line || shape.fill.imageStyle === "pattern" || shape.fill.imageStyle === "texture") && !shape.extrusion ? textAxisScale(shape, parent) : void 0;
        if (scale && (scale.x !== 1 || scale.y !== 1) && Number.isFinite(w * scale.x) && Number.isFinite(h * scale.y))
          content = `<g transform="scale(${safe_js_6.transformNumber(1 / scale.x)} ${safe_js_6.transformNumber(1 / scale.y)})">${renderGeometry(shape, ctx, w * scale.x, h * scale.y)}</g>`;
        else
          content = renderGeometry(shape, ctx, w, h);
      }
      if (shape.image)
        content += renderImage(shape, ctx);
    }
    if (shape.wordArt && !wordArtRendered && shape.text)
      text = textContent(false);
    content += text + renderMedia(shape, ctx);
    if (shape.extrusion)
      content = three_d_js_1.renderExtrusion(shape, content, effectContext(ctx));
    return animate(shadowWrap(shape, `<g data-ppt-shape="${safe_js_6.n(shape.id)}" transform="${shapeTransform(shape)}"${label}>${content}</g>`, ctx, parent));
  }
  function composedShapes(doc, slide, options) {
    if (options.includeMaster === false || slide.showMasterShapes === false)
      return slide.shapes;
    const byId = new Map(doc.masters.map((s) => [s.id, s]));
    const covered = /* @__PURE__ */ new Set();
    const visit = (shapes) => {
      for (const s of shapes) {
        if (s.placeholder)
          covered.add(s.placeholder.type);
        if (s.children)
          visit(s.children);
      }
    };
    visit(slide.shapes);
    const filterMaster = (shapes) => shapes.flatMap((s) => s.placeholder && (covered.has(s.placeholder.type) || ![7, 8, 9, 10].includes(s.placeholder.type)) ? [] : [s.children ? { ...s, children: filterMaster(s.children) } : s]);
    const seen = /* @__PURE__ */ new Set();
    const collect = (id) => {
      if (id == null || seen.has(id))
        return [];
      seen.add(id);
      const master = byId.get(id);
      if (!master)
        return [];
      const own = filterMaster(master.shapes);
      visit(master.shapes);
      return [...master.showMasterShapes === false ? [] : collect(master.masterId), ...own];
    };
    const masterShapes = collect(slide.masterId);
    return [...masterShapes, ...slide.shapes];
  }
  function renderSlide(doc, index, options = {}) {
    if (!Number.isInteger(index) || index < 0 || index >= doc.slides.length)
      throw new errors_js_15.PptError("SLIDE_INDEX", `Slide index ${index} is outside the presentation`);
    const slide = doc.slides[index], w = slide.size.width, h = slide.size.height;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0)
      throw new errors_js_15.PptError("SLIDE_SIZE", "Slide size must be finite and positive");
    const ctx = { document: doc, slide, options, date: options.fieldDate ?? /* @__PURE__ */ new Date(), defs: [], prefix: `ppt-${++renderSequence}-${index}`, seq: 0, assets: new Map(doc.assets.map((a) => [a.id, a])), urls: /* @__PURE__ */ new Map(), warnings: [], animationTargets: new Set(slide.timeline?.effects.map((e) => e.targetShapeId) ?? []) };
    const transition = slide.transition;
    if (transition) {
      const direction = transition.direction ?? 0, supported = transition.type === 255 || [0, 6, 23].includes(transition.type) && direction === 0 || [4, 7, 10, 20].includes(transition.type) && Number.isInteger(direction) && direction >= 0 && direction <= 3;
      if (!supported)
        ctx.warnings.push({ code: "TRANSITION_EFFECT_UNSUPPORTED", severity: "warning", message: "This transition variant has no playback implementation and changes slides without the source effect", slideId: slide.id, details: { type: transition.type, direction } });
      if (transition.soundEnabled)
        ctx.warnings.push({ code: "TRANSITION_SOUND_MANUAL", severity: "warning", message: "Transition sound commands are retained but are not played automatically", slideId: slide.id });
    }
    const bg = `<rect width="${safe_js_6.n(w)}" height="${safe_js_6.n(h)}" ${paint(slide.background, ctx)}/>`;
    const shapes = composedShapes(doc, slide, options).map((s) => renderShape(s, ctx)).join("");
    const html = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" class="pptjs-slide${options.className ? " " + safe_js_6.escapeXml(options.className) : ""}" role="img" aria-label="${safe_js_6.escapeXml(slide.name ?? `Slide ${index + 1}`)}" width="${safe_js_6.n(w)}" height="${safe_js_6.n(h)}" viewBox="0 0 ${safe_js_6.n(w)} ${safe_js_6.n(h)}" preserveAspectRatio="xMidYMid meet"><defs>${ctx.defs.join("")}</defs>${bg}${shapes}</svg>`;
    const relatedIds = /* @__PURE__ */ new Set([slide.id]);
    let id = slide.masterId;
    while (id != null && !relatedIds.has(id)) {
      relatedIds.add(id);
      id = doc.masters.find((m) => m.id === id)?.masterId;
    }
    return { html, css: defaultPptCss, warnings: [...doc.diagnostics.filter((d) => d.slideId == null || relatedIds.has(d.slideId)), ...ctx.warnings] };
  }
  exports_35("renderSlide", renderSlide);
  function renderSlideSvg(doc, index, options = {}) {
    return renderSlide(doc, index, options).html;
  }
  exports_35("renderSlideSvg", renderSlideSvg);
  return {
    setters: [
      function(errors_js_15_1) {
        errors_js_15 = errors_js_15_1;
      },
      function(safe_js_6_1) {
        safe_js_6 = safe_js_6_1;
      },
      function(geometry_js_4_1) {
        geometry_js_4 = geometry_js_4_1;
      },
      function(text_js_3_1) {
        text_js_3 = text_js_3_1;
      },
      function(fields_js_1_1) {
        fields_js_1 = fields_js_1_1;
      },
      function(effects_js_1_1) {
        effects_js_1 = effects_js_1_1;
      },
      function(wordart_js_1_1) {
        wordart_js_1 = wordart_js_1_1;
      },
      function(three_d_js_1_1) {
        three_d_js_1 = three_d_js_1_1;
      }
    ],
    execute: function() {
      renderSequence = 0;
      exports_35("defaultPptCss", defaultPptCss = ".pptjs-slide{display:block;max-width:100%;max-height:100%;user-select:text}.pptjs-slide *{box-sizing:border-box}.pptjs-slide a:focus{outline:2px solid #2563eb;outline-offset:2px}");
    }
  };
});
System.register("worker-client", ["core/errors", "ppt/constants"], function(exports_36, context_36) {
  "use strict";
  var errors_js_16, constants_js_6, PptWorkerClient;
  var __moduleName = context_36 && context_36.id;
  function inputLimit(byteLength, options) {
    const maximum = options.limits?.maxFileBytes ?? constants_js_6.DEFAULT_LIMITS.maxFileBytes;
    if (!Number.isSafeInteger(maximum) || maximum <= 0)
      throw new errors_js_16.PptError("INVALID_LIMIT", "Invalid parse limit maxFileBytes");
    if (byteLength > maximum)
      throw new errors_js_16.PptError("LIMIT_FILE", "Presentation exceeds the configured file size limit");
  }
  return {
    setters: [
      function(errors_js_16_1) {
        errors_js_16 = errors_js_16_1;
      },
      function(constants_js_6_1) {
        constants_js_6 = constants_js_6_1;
      }
    ],
    execute: function() {
      PptWorkerClient = class PptWorkerClient2 {
        worker;
        seq = 0;
        pending = /* @__PURE__ */ new Map();
        destroyed = false;
        constructor(worker) {
          this.worker = worker;
          worker.addEventListener("message", this.onMessage);
          worker.addEventListener("error", this.onError);
          worker.addEventListener("messageerror", this.onMessageError);
        }
        static create(url) {
          return new PptWorkerClient2(new Worker(url ?? new URL("./pptjs.worker.js", context_36.meta.url), { type: "module" }));
        }
        onMessage = (event) => {
          const data = event.data;
          if (!data || typeof data.id !== "number")
            return;
          const pending = this.pending.get(data.id);
          if (!pending)
            return;
          if (data.progress) {
            try {
              pending.progress?.(data.progress);
            } catch {
            }
            return;
          }
          this.pending.delete(data.id);
          if (data.ok && data.result)
            pending.resolve(data.result);
          else
            pending.reject(new errors_js_16.PptError(data.error?.code ?? "WORKER_RESPONSE", data.error?.message ?? "Worker returned no presentation", data.error?.offset));
        };
        onError = (event) => {
          const e = event;
          this.fail(new errors_js_16.PptError("WORKER_ERROR", e.message || "The parsing worker failed"));
        };
        onMessageError = () => {
          this.fail(new errors_js_16.PptError("WORKER_MESSAGE", "The worker response could not be decoded"));
        };
        fail(error) {
          for (const p of this.pending.values())
            p.reject(error);
          this.pending.clear();
          this.dispose();
        }
        dispose() {
          if (this.destroyed)
            return;
          this.destroyed = true;
          this.worker.removeEventListener("message", this.onMessage);
          this.worker.removeEventListener("error", this.onError);
          this.worker.removeEventListener("messageerror", this.onMessageError);
          this.worker.terminate();
        }
        /** Safe default: never detaches a caller-owned ArrayBuffer or a typed-array sibling. */
        parse(input, options = {}, onProgress) {
          if (this.destroyed)
            return Promise.reject(new errors_js_16.PptError("WORKER_DESTROYED", "The worker client has been destroyed"));
          let source;
          try {
            if (!(input instanceof ArrayBuffer) && !ArrayBuffer.isView(input))
              throw new errors_js_16.PptError("INVALID_INPUT", "Expected an ArrayBuffer or binary view");
            inputLimit(input.byteLength, options);
            source = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
          } catch (error) {
            return Promise.reject(error);
          }
          return this.parseOwned(source.slice().buffer, options, onProgress);
        }
        /** Ownership-transfer variant: caller explicitly hands over this full buffer. */
        parseOwned(buffer, options = {}, onProgress) {
          if (this.destroyed)
            return Promise.reject(new errors_js_16.PptError("WORKER_DESTROYED", "The worker client has been destroyed"));
          try {
            if (!(buffer instanceof ArrayBuffer))
              throw new errors_js_16.PptError("INVALID_INPUT", "parseOwned expects an ArrayBuffer");
            inputLimit(buffer.byteLength, options);
          } catch (error) {
            return Promise.reject(error);
          }
          const id = ++this.seq;
          return new Promise((resolve, reject) => {
            this.pending.set(id, { resolve, reject, progress: onProgress });
            try {
              this.worker.postMessage({ id, type: "parse", buffer, options }, [buffer]);
            } catch (error) {
              this.pending.delete(id);
              reject(error);
            }
          });
        }
        destroy() {
          if (this.destroyed)
            return;
          for (const p of this.pending.values())
            p.reject(new DOMException("Parsing was cancelled", "AbortError"));
          this.pending.clear();
          this.dispose();
        }
      };
      exports_36("PptWorkerClient", PptWorkerClient);
    }
  };
});
System.register("playback/timeline", [], function(exports_37, context_37) {
  "use strict";
  var bounded, TimelinePlayer;
  var __moduleName = context_37 && context_37.id;
  function compileTimeline(effects) {
    const steps = [];
    let step, previous;
    for (const effect of effects) {
      if (!step || effect.trigger === "click") {
        step = { automatic: effect.trigger !== "click", effects: [], durationMs: 0 };
        steps.push(step);
        previous = void 0;
      }
      const base = effect.trigger === "afterPrevious" ? previous?.endMs ?? 0 : effect.trigger === "withPrevious" ? previous?.startMs ?? 0 : 0;
      const startMs = base + bounded(effect.delayMs), scheduled = { effect, startMs, endMs: startMs + bounded(effect.durationMs) };
      step.effects.push(scheduled);
      step.durationMs = Math.max(step.durationMs, scheduled.endMs);
      previous = scheduled;
    }
    return steps;
  }
  exports_37("compileTimeline", compileTimeline);
  function effectKeyframes(effect, width, height, parent = [1, 0, 0, 1]) {
    const entrance = effect.phase === "entrance", exit = effect.phase === "exit";
    const visible = { opacity: 1, visibility: "visible", transform: "none" }, hidden = { opacity: 0, visibility: "hidden", transform: "none" };
    if (effect.kind === "appear")
      return entrance ? [hidden, visible] : exit ? [visible, hidden] : [visible, visible];
    if (effect.kind === "fade")
      return entrance ? [hidden, visible] : exit ? [visible, hidden] : [{ opacity: 1 }, { opacity: 0.35, offset: 0.5 }, { opacity: 1 }];
    if (effect.kind === "fly") {
      const direction = effect.direction ?? "left", dx = direction === "left" ? -width : direction === "right" ? width : 0, dy = direction === "up" ? -height : direction === "down" ? height : 0;
      let x = dx, y = dy;
      const [a, b, c, d] = parent;
      if (parent.length === 4 && parent.every(Number.isFinite) && Math.abs(a * d - b * c) > 1e-9) {
        const det = a * d - b * c;
        x = (d * dx - c * dy) / det;
        y = (-b * dx + a * dy) / det;
      }
      const clean = (value) => Math.abs(value) < 1e-8 ? 0 : Number(value.toFixed(6));
      const away = { opacity: 0, visibility: "hidden", transform: `translate(${clean(x)}px,${clean(y)}px)` };
      return exit ? [visible, away] : [away, visible];
    }
    const from = Math.max(1e-3, Math.min(16, effect.fromScale ?? (entrance ? 0.01 : 1))), to = Math.max(1e-3, Math.min(16, effect.toScale ?? (exit ? 0.01 : 1)));
    return [{ opacity: entrance ? 0 : 1, visibility: entrance ? "hidden" : "visible", transform: `scale(${from})` }, { opacity: exit ? 0 : 1, visibility: exit ? "hidden" : "visible", transform: `scale(${to})` }];
  }
  exports_37("effectKeyframes", effectKeyframes);
  return {
    setters: [],
    execute: function() {
      bounded = (value, max = 86399e3) => Math.max(0, Math.min(max, Number.isFinite(value) ? value : 0));
      TimelinePlayer = class TimelinePlayer {
        effects;
        options;
        steps;
        stepIndex = 0;
        effectIndex = 0;
        animations = [];
        generation = 0;
        destroyed = false;
        running = false;
        paused = false;
        enabled = true;
        constructor(effects, options) {
          this.effects = effects;
          this.options = options;
          this.steps = compileTimeline(effects);
          this.reset();
        }
        get state() {
          return { enabled: this.enabled, playing: this.running && !this.paused, effectIndex: this.effectIndex, effectCount: this.effects.length };
        }
        notify() {
          this.options.onState?.(this.state);
        }
        setVisibility(final) {
          const initial = /* @__PURE__ */ new Map();
          for (const effect of this.effects)
            if (!initial.has(effect.targetShapeId))
              initial.set(effect.targetShapeId, effect);
          for (const [id, effect] of initial) {
            const target = this.options.resolveTarget(id);
            if (target) {
              target.style.opacity = !final && effect.phase === "entrance" ? "0" : "";
              target.style.visibility = !final && effect.phase === "entrance" ? "hidden" : "";
              target.style.transform = "";
            }
          }
        }
        reset() {
          if (this.destroyed)
            return;
          this.cancelAnimations();
          this.stepIndex = 0;
          this.effectIndex = 0;
          this.running = false;
          this.paused = false;
          this.setVisibility(false);
          this.notify();
        }
        cancelAnimations() {
          this.generation++;
          for (const animation of this.animations) {
            animation.finished.catch(() => {
            });
            animation.cancel();
          }
          this.animations = [];
        }
        play() {
          if (this.destroyed)
            return;
          if (this.paused) {
            this.paused = false;
            for (const animation of this.animations)
              animation.play();
            this.notify();
            return;
          }
          if (!this.running)
            this.advance();
        }
        startAutomatic() {
          if (!this.running && this.steps[this.stepIndex]?.automatic)
            this.advance();
        }
        pause() {
          if (this.destroyed || !this.running)
            return;
          this.paused = true;
          for (const animation of this.animations)
            animation.pause();
          this.notify();
        }
        /** Returns false when every effect has been consumed; the viewer may then change slides. */
        advance() {
          if (this.destroyed)
            return false;
          if (this.running) {
            for (const animation of this.animations) {
              try {
                animation.finish();
              } catch {
              }
            }
            this.paused = false;
            return true;
          }
          const step = this.steps[this.stepIndex++];
          if (!step)
            return false;
          this.running = true;
          this.paused = false;
          const generation = ++this.generation;
          const pending = [];
          for (const scheduled of step.effects) {
            const target = this.options.resolveTarget(scheduled.effect.targetShapeId);
            if (!target)
              continue;
            target.style.transformBox = "fill-box";
            target.style.transformOrigin = "center";
            const parent = (target.getAttribute("data-ppt-parent") ?? "1 0 0 1").split(/\s+/).map(Number);
            const keyframes = effectKeyframes(scheduled.effect, this.options.width, this.options.height, parent);
            const duration = scheduled.effect.kind === "appear" ? 0 : bounded(scheduled.effect.durationMs);
            const final = () => {
              const last = keyframes[keyframes.length - 1];
              target.style.opacity = String(last.opacity ?? "");
              target.style.visibility = String(last.visibility ?? "visible");
              target.style.transform = String(last.transform ?? "");
            };
            if (typeof target.animate === "function") {
              const animation = target.animate(keyframes, { duration, delay: scheduled.startMs, fill: "forwards", easing: "linear" });
              this.animations.push(animation);
              pending.push(animation.finished.then(() => {
                if (this.destroyed || generation !== this.generation)
                  return;
                final();
                animation.cancel();
              }, () => {
              }));
            } else
              final();
          }
          this.notify();
          void Promise.all(pending).then(() => {
            if (this.destroyed || generation !== this.generation)
              return;
            this.animations = [];
            this.running = false;
            this.effectIndex += step.effects.length;
            this.notify();
            if (this.steps[this.stepIndex]?.automatic)
              this.advance();
            else if (this.stepIndex >= this.steps.length)
              this.options.onDone?.();
          });
          return true;
        }
        destroy(showFinal = true) {
          if (this.destroyed)
            return;
          this.destroyed = true;
          this.enabled = false;
          this.cancelAnimations();
          this.running = false;
          if (showFinal) {
            this.setVisibility(true);
            for (const effect of this.effects) {
              const target = this.options.resolveTarget(effect.targetShapeId);
              if (target) {
                target.style.transform = "";
                target.style.transformOrigin = "";
                target.style.transformBox = "";
              }
            }
          }
          this.notify();
        }
      };
      exports_37("TimelinePlayer", TimelinePlayer);
    }
  };
});
System.register("playback/transitions", [], function(exports_38, context_38) {
  "use strict";
  var __moduleName = context_38 && context_38.id;
  function transitionFrames(transition) {
    if (!transition || transition.type === 0)
      return void 0;
    const durationMs = Math.max(0, Math.min(1e4, Number.isFinite(transition.duration) ? transition.duration : 500)), d = transition.direction ?? 0;
    if ((transition.type === 6 || transition.type === 23) && d === 0)
      return { incoming: [{ opacity: 0 }, { opacity: 1 }], durationMs };
    if ([4, 7, 20].includes(transition.type) && Number.isInteger(d) && d >= 0 && d <= 3) {
      const x = d === 0 ? -100 : d === 2 ? 100 : 0, y = d === 1 ? -100 : d === 3 ? 100 : 0;
      const incoming = [{ transform: `translate(${-x}%,${-y}%)` }, { transform: "none" }], outgoing = [{ transform: "none" }, { transform: `translate(${x}%,${y}%)` }];
      return { incoming: transition.type === 7 ? [{ opacity: 1 }, { opacity: 1 }] : incoming, outgoing: transition.type === 4 ? void 0 : outgoing, durationMs };
    }
    if (transition.type === 10 && Number.isInteger(d) && d >= 0 && d <= 3) {
      const clip = ["inset(0 0 0 100%)", "inset(100% 0 0 0)", "inset(0 100% 0 0)", "inset(0 0 100% 0)"][d];
      return { incoming: [{ clipPath: clip }, { clipPath: "inset(0 0 0 0)" }], durationMs };
    }
    return void 0;
  }
  exports_38("transitionFrames", transitionFrames);
  function runTransition(incoming, outgoing, transition, onDone) {
    const frames = transitionFrames(transition), animations = [];
    let settled = false;
    const complete = () => {
      if (settled)
        return;
      settled = true;
      for (const animation of animations) {
        animation.finished.catch(() => {
        });
        animation.cancel();
      }
      onDone();
    };
    const controller = Object.assign(complete, { pause() {
      if (!settled)
        for (const animation of animations)
          animation.pause();
    }, play() {
      if (!settled)
        for (const animation of animations)
          animation.play();
    } });
    if (!frames || typeof incoming.animate !== "function") {
      complete();
      return controller;
    }
    animations.push(incoming.animate(frames.incoming, { duration: frames.durationMs, fill: "both", easing: "linear" }));
    if (outgoing && frames.outgoing && typeof outgoing.animate === "function")
      animations.push(outgoing.animate(frames.outgoing, { duration: frames.durationMs, fill: "both", easing: "linear" }));
    void Promise.all(animations.map((animation) => animation.finished.catch(() => {
    }))).then(complete);
    return controller;
  }
  exports_38("runTransition", runTransition);
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("playback/media", ["core/errors"], function(exports_39, context_39) {
  "use strict";
  var errors_js_17, LocalMediaController;
  var __moduleName = context_39 && context_39.id;
  return {
    setters: [
      function(errors_js_17_1) {
        errors_js_17 = errors_js_17_1;
      }
    ],
    execute: function() {
      LocalMediaController = class LocalMediaController {
        onError;
        media;
        disposed = false;
        listeners = [];
        constructor(root, onError) {
          this.onError = onError;
          this.media = Array.from(root.querySelectorAll("audio[data-ppt-media],video[data-ppt-media]"));
          for (const target of this.media) {
            const listener = () => this.onError?.(new errors_js_17.PptError("MEDIA_DECODE", `The browser could not decode embedded media (${target.error?.code ?? "unknown"})`));
            target.addEventListener("error", listener);
            this.listeners.push({ target, listener });
          }
        }
        async playFromGesture(id, event) {
          if (this.disposed || !event.isTrusted || !["click", "keydown", "pointerup"].includes(event.type))
            return false;
          const target = this.media.find((m) => m.dataset.pptMedia === String(id));
          if (!target)
            return false;
          try {
            await target.play();
            return !this.disposed;
          } catch (error) {
            if (!this.disposed)
              this.onError?.(error instanceof Error ? error : new Error(String(error)));
            return false;
          }
        }
        pause() {
          for (const target of this.media)
            target.pause();
        }
        destroy() {
          if (this.disposed)
            return;
          this.disposed = true;
          for (const { target, listener } of this.listeners)
            target.removeEventListener("error", listener);
          this.listeners = [];
          for (const target of this.media) {
            target.pause();
            target.removeAttribute("src");
            target.load();
          }
        }
      };
      exports_39("LocalMediaController", LocalMediaController);
    }
  };
});
System.register("playback/navigation", [], function(exports_40, context_40) {
  "use strict";
  var __moduleName = context_40 && context_40.id;
  function resolveInternalNavigation(href, current, count, previous) {
    if (!Number.isSafeInteger(count) || count <= 0 || !Number.isSafeInteger(current) || current < 0 || current >= count)
      return void 0;
    const match = /^#pptjs-slide=(0|[1-9]\d*)$/.exec(href);
    if (match) {
      const index = Number(match[1]);
      return Number.isSafeInteger(index) && index < count ? index : void 0;
    }
    if (href === "#pptjs-back")
      return previous != null && Number.isSafeInteger(previous) && previous >= 0 && previous < count ? previous : void 0;
    const targets = { "#pptjs-next": Math.min(count - 1, current + 1), "#pptjs-previous": Math.max(0, current - 1), "#pptjs-first": 0, "#pptjs-last": count - 1 };
    return Object.hasOwn(targets, href) ? targets[href] : void 0;
  }
  exports_40("resolveInternalNavigation", resolveInternalNavigation);
  return {
    setters: [],
    execute: function() {
    }
  };
});
System.register("viewer", ["core/errors", "ppt/parser", "ppt/constants", "render/svg", "worker-client", "layout/measure", "playback/timeline", "playback/transitions", "playback/media", "playback/navigation"], function(exports_41, context_41) {
  "use strict";
  var errors_js_18, parser_js_1, constants_js_7, svg_js_1, worker_client_js_1, measure_js_3, timeline_js_1, transitions_js_1, media_js_1, navigation_js_1, viewerCss, abort;
  var __moduleName = context_41 && context_41.id;
  function createPptViewer(container, options = {}) {
    const owner = container.ownerDocument, root = owner.createElement("div"), stage = owner.createElement("div"), style = owner.createElement("style");
    root.className = "pptjs-viewer";
    root.tabIndex = 0;
    root.setAttribute("role", "region");
    root.setAttribute("aria-label", "PowerPoint presentation");
    stage.className = "pptjs-stage";
    style.textContent = svg_js_1.defaultPptCss + viewerCss;
    root.append(style, stage);
    container.replaceChildren(root);
    let value = null, index = 0, sequence = 0, destroyed = false, worker = null, drawSequence = 0;
    let playbackEnabled = false, presentationRunning = false, timeline = null, media = null, cancelTransition, transitionInProgress = false;
    const history = [];
    let autoTimer, autoRemaining, autoStarted = 0;
    const measurer = options.renderOptions?.textMeasurer ?? measure_js_3.createCanvasTextMeasurer(owner);
    const urls = /* @__PURE__ */ new Map();
    const revoke = () => {
      for (const url of urls.values())
        URL.revokeObjectURL(url);
      urls.clear();
    };
    const empty = (text) => {
      stage.replaceChildren();
      const p = owner.createElement("div");
      p.className = "pptjs-empty";
      p.textContent = text;
      stage.append(p);
    };
    const assertLive = () => {
      if (destroyed)
        throw new errors_js_18.PptError("VIEWER_DESTROYED", "The viewer has been destroyed");
    };
    const playbackState = () => ({ enabled: playbackEnabled, playing: presentationRunning, effectIndex: timeline?.state.effectIndex ?? 0, effectCount: value?.slides[index]?.timeline?.effects.length ?? 0 });
    const notify = () => options.onPlaybackChange?.(playbackState());
    const pauseTimer = () => {
      if (autoTimer !== void 0) {
        clearTimeout(autoTimer);
        autoTimer = void 0;
        autoRemaining = Math.max(0, (autoRemaining ?? 0) - (performance.now() - autoStarted));
      }
    };
    function stopCurrent() {
      drawSequence++;
      pauseTimer();
      autoRemaining = void 0;
      transitionInProgress = false;
      cancelTransition?.();
      cancelTransition = void 0;
      timeline?.destroy(false);
      timeline = null;
      media?.destroy();
      media = null;
    }
    function nextVisible() {
      if (!value)
        return;
      for (let i = index + 1; i < value.slides.length; i++)
        if (!value.slides[i].hidden)
          return i;
      return;
    }
    function armAuto() {
      if (!playbackEnabled || !presentationRunning || autoRemaining == null || autoTimer !== void 0)
        return;
      const current = drawSequence;
      autoStarted = performance.now();
      autoTimer = setTimeout(() => {
        autoTimer = void 0;
        if (destroyed || current !== drawSequence || !presentationRunning)
          return;
        autoRemaining = void 0;
        const next = nextVisible();
        if (next == null) {
          presentationRunning = false;
          notify();
        } else
          goTo(next);
      }, autoRemaining);
    }
    function draw(withTransition = false) {
      if (!value)
        return;
      if (!value.slides.length) {
        empty("\u6B64\u6587\u4EF6\u6CA1\u6709\u53EF\u663E\u793A\u7684\u5E7B\u706F\u7247\u3002");
        return;
      }
      const old = withTransition && playbackEnabled ? stage.firstElementChild : void 0;
      stopCurrent();
      const current = drawSequence, slide = value.slides[index];
      const rendered = svg_js_1.renderSlide(value, index, { textLayout: measurer ? "measured" : "browser", ...options.renderOptions, textMeasurer: measurer, assetUrl: options.renderOptions?.assetUrl ?? ((asset) => {
        let url = urls.get(asset.id);
        if (!url) {
          const bytes = asset.bytes.byteOffset === 0 && asset.bytes.byteLength === asset.bytes.buffer.byteLength && asset.bytes.buffer instanceof ArrayBuffer ? asset.bytes : new Uint8Array(asset.bytes);
          url = URL.createObjectURL(new Blob([bytes], { type: asset.mimeType }));
          urls.set(asset.id, url);
        }
        return url;
      }) });
      stage.innerHTML = rendered.html;
      root.setAttribute("aria-label", `Slide ${index + 1} of ${value.slides.length}`);
      if (typeof stage.querySelectorAll === "function")
        media = new media_js_1.LocalMediaController(stage, (error) => options.onError?.(error));
      if (playbackEnabled) {
        timeline = new timeline_js_1.TimelinePlayer(slide.timeline?.effects ?? [], { resolveTarget: (id) => stage.querySelector(`[data-ppt-animation="${id}"]`), width: slide.size.width, height: slide.size.height, onState: notify });
        autoRemaining = slide.transition?.autoAdvanceAfterMs;
      }
      const begin = () => {
        if (destroyed || current !== drawSequence)
          return;
        if (presentationRunning) {
          timeline?.startAutomatic();
          armAuto();
        }
        notify();
      };
      const incoming = stage.firstElementChild;
      if (old && incoming && playbackEnabled && presentationRunning) {
        const overlay = owner.createElement("div");
        overlay.className = "pptjs-transition-old";
        overlay.setAttribute("aria-hidden", "true");
        overlay.append(old);
        stage.append(overlay);
        if (slide.transition?.type !== 7) {
          overlay.style.zIndex = "0";
          incoming.style.position = "relative";
          incoming.style.zIndex = "1";
        }
        transitionInProgress = true;
        cancelTransition = transitions_js_1.runTransition(incoming, old, slide.transition, () => {
          overlay.remove();
          if (current === drawSequence)
            transitionInProgress = false;
          begin();
        });
      } else
        begin();
      options.onSlideChange?.(index);
    }
    function clear() {
      sequence++;
      worker?.destroy();
      worker = null;
      stopCurrent();
      value = null;
      index = 0;
      history.length = 0;
      presentationRunning = false;
      playbackEnabled = false;
      revoke();
      root.removeAttribute("aria-busy");
      empty("\u9009\u62E9\u4E00\u4E2A\u6F14\u793A\u6587\u7A3F\u5F00\u59CB\u9884\u89C8\u3002");
      notify();
    }
    const goTo = (next, recordHistory = true) => {
      assertLive();
      if (!value || !value.slides.length)
        return;
      if (!Number.isInteger(next) || next < 0 || next >= value.slides.length)
        throw new errors_js_18.PptError("SLIDE_INDEX", `Slide index ${next} is outside the presentation`);
      const changed = next !== index;
      if (changed && recordHistory) {
        history.push(index);
        if (history.length > 1e3)
          history.shift();
      }
      index = next;
      draw(changed);
    };
    function advance() {
      assertLive();
      if (!value)
        return;
      if (playbackEnabled) {
        presentationRunning = true;
        if (transitionInProgress) {
          cancelTransition?.();
          notify();
          return;
        }
        if (timeline?.advance()) {
          armAuto();
          notify();
          return;
        }
        if (value.slides[index]?.transition?.manualAdvance === false) {
          armAuto();
          notify();
          return;
        }
      }
      const next = playbackEnabled ? nextVisible() : index + 1;
      if (next != null && next < value.slides.length)
        goTo(next);
      else {
        presentationRunning = false;
        notify();
      }
    }
    function setPlaybackEnabled(enabled) {
      assertLive();
      if (playbackEnabled === enabled)
        return;
      playbackEnabled = enabled;
      presentationRunning = false;
      draw();
      notify();
    }
    function play() {
      assertLive();
      if (!value)
        return;
      if (!playbackEnabled)
        setPlaybackEnabled(true);
      presentationRunning = true;
      if (transitionInProgress)
        cancelTransition?.play();
      else {
        timeline?.play();
        armAuto();
      }
      notify();
    }
    function pause() {
      assertLive();
      presentationRunning = false;
      pauseTimer();
      cancelTransition?.pause();
      timeline?.pause();
      media?.pause();
      notify();
    }
    const keydown = (event) => {
      if (!value || event.altKey || event.ctrlKey || event.metaKey)
        return;
      const target = event.target;
      if (target.closest('input,textarea,select,button,a,audio,video,[contenteditable="true"]'))
        return;
      if (["ArrowRight", "ArrowDown", "PageDown", " "].includes(event.key)) {
        event.preventDefault();
        advance();
        return;
      }
      let next = index;
      if (["ArrowLeft", "ArrowUp", "PageUp"].includes(event.key))
        next = Math.max(0, index - 1);
      else if (event.key === "Home")
        next = 0;
      else if (event.key === "End")
        next = value.slides.length - 1;
      else if (event.key === "Escape") {
        setPlaybackEnabled(false);
        return;
      } else
        return;
      event.preventDefault();
      if (next !== index)
        goTo(next);
    };
    const click = (event) => {
      if (!value || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey)
        return;
      const target = event.target, anchor = target.closest("a");
      if (anchor) {
        const href = anchor.getAttribute("href") ?? "", destination = navigation_js_1.resolveInternalNavigation(href, index, value.slides.length, history[history.length - 1]);
        if (destination != null) {
          event.preventDefault();
          if (href === "#pptjs-back") {
            history.pop();
            goTo(destination, false);
          } else
            goTo(destination);
          return;
        }
        if (href.startsWith("#pptjs-"))
          event.preventDefault();
        if (href === "#pptjs-end") {
          setPlaybackEnabled(false);
          return;
        }
        const mediaMatch = /^#pptjs-media=(\d+)$/.exec(href);
        if (mediaMatch)
          void media?.playFromGesture(Number(mediaMatch[1]), event);
        return;
      }
      if (playbackEnabled && !target.closest('audio,video,button,input,textarea,select,[contenteditable="true"]'))
        advance();
    };
    const fontsChanged = () => {
      measurer?.clear?.();
      if (value && !destroyed && !playbackEnabled)
        draw();
    };
    owner.fonts?.addEventListener("loadingdone", fontsChanged);
    root.addEventListener("keydown", keydown);
    root.addEventListener("click", click);
    empty("\u9009\u62E9\u4E00\u4E2A\u6F14\u793A\u6587\u7A3F\u5F00\u59CB\u9884\u89C8\u3002");
    return {
      async load(input) {
        assertLive();
        clear();
        const current = sequence;
        root.setAttribute("aria-busy", "true");
        empty("\u6B63\u5728\u8BFB\u53D6\u6F14\u793A\u6587\u7A3F\u2026");
        const currentOnly = () => {
          if (destroyed || sequence !== current)
            throw abort();
        };
        const progress = (p) => {
          if (!destroyed && current === sequence)
            options.onProgress?.(p);
        };
        try {
          const blob = typeof input.arrayBuffer === "function" && !ArrayBuffer.isView(input) && !(input instanceof ArrayBuffer);
          const maxFileBytes = options.parseOptions?.limits?.maxFileBytes ?? constants_js_7.DEFAULT_LIMITS.maxFileBytes;
          if (!Number.isSafeInteger(maxFileBytes) || maxFileBytes <= 0)
            throw new errors_js_18.PptError("INVALID_LIMIT", "Invalid parse limit maxFileBytes");
          const byteLength = blob ? input.size : input.byteLength;
          if (!Number.isSafeInteger(byteLength) || byteLength < 0)
            throw new errors_js_18.PptError("INVALID_INPUT", "Expected a Blob, ArrayBuffer or binary view with a valid byte length");
          if (byteLength > maxFileBytes)
            throw new errors_js_18.PptError("LIMIT_FILE", `Presentation file exceeds the configured ${maxFileBytes}-byte limit`);
          const buffer = blob ? await input.arrayBuffer() : input;
          currentOnly();
          let parsed;
          if (options.worker !== false && typeof Worker !== "undefined") {
            worker = worker_client_js_1.PptWorkerClient.create(options.workerUrl);
            parsed = blob ? await worker.parseOwned(buffer, options.parseOptions, progress) : await worker.parse(buffer, options.parseOptions, progress);
          } else {
            progress({ phase: "parse", elapsedMs: 0 });
            await new Promise((resolve) => setTimeout(resolve, 0));
            currentOnly();
            const start = performance.now();
            parsed = parser_js_1.parsePpt(buffer, options.parseOptions);
            progress({ phase: "complete", elapsedMs: performance.now() - start, slideCount: parsed.slides.length });
          }
          currentOnly();
          worker?.destroy();
          worker = null;
          value = parsed;
          index = 0;
          root.removeAttribute("aria-busy");
          draw();
          return parsed;
        } catch (error) {
          if (destroyed || sequence !== current)
            throw abort();
          worker?.destroy();
          worker = null;
          root.removeAttribute("aria-busy");
          const e = error instanceof Error ? error : new Error(String(error));
          empty(e.message);
          options.onError?.(e);
          throw e;
        }
      },
      goTo,
      play,
      pause,
      advance,
      setPlaybackEnabled,
      next() {
        if (value && index + 1 < value.slides.length)
          goTo(index + 1);
      },
      previous() {
        if (value && index > 0)
          goTo(index - 1);
      },
      clear() {
        assertLive();
        clear();
      },
      destroy() {
        if (destroyed)
          return;
        clear();
        destroyed = true;
        root.removeEventListener("keydown", keydown);
        root.removeEventListener("click", click);
        owner.fonts?.removeEventListener("loadingdone", fontsChanged);
        root.remove();
      },
      get value() {
        return value;
      },
      get slideIndex() {
        return index;
      },
      get playbackState() {
        return playbackState();
      }
    };
  }
  exports_41("createPptViewer", createPptViewer);
  return {
    setters: [
      function(errors_js_18_1) {
        errors_js_18 = errors_js_18_1;
      },
      function(parser_js_1_1) {
        parser_js_1 = parser_js_1_1;
      },
      function(constants_js_7_1) {
        constants_js_7 = constants_js_7_1;
      },
      function(svg_js_1_1) {
        svg_js_1 = svg_js_1_1;
      },
      function(worker_client_js_1_1) {
        worker_client_js_1 = worker_client_js_1_1;
      },
      function(measure_js_3_1) {
        measure_js_3 = measure_js_3_1;
      },
      function(timeline_js_1_1) {
        timeline_js_1 = timeline_js_1_1;
      },
      function(transitions_js_1_1) {
        transitions_js_1 = transitions_js_1_1;
      },
      function(media_js_1_1) {
        media_js_1 = media_js_1_1;
      },
      function(navigation_js_1_1) {
        navigation_js_1 = navigation_js_1_1;
      }
    ],
    execute: function() {
      viewerCss = `.pptjs-viewer{position:relative;display:grid;place-items:center;width:100%;height:100%;min-height:240px;overflow:hidden;outline:none}.pptjs-viewer:focus-visible{outline:2px solid #2563eb;outline-offset:-2px}.pptjs-stage{position:relative;display:flex;align-items:center;justify-content:center;width:100%;height:100%;min-width:0;min-height:0;overflow:hidden}.pptjs-stage>.pptjs-slide,.pptjs-transition-old>.pptjs-slide{width:100%;height:100%;max-width:100%;max-height:100%}.pptjs-transition-old{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none}.pptjs-empty{font:14px/1.6 system-ui,sans-serif;color:#64748b;padding:24px;text-align:center}`;
      abort = () => new DOMException("The presentation load was cancelled", "AbortError");
    }
  };
});
System.register("runtime", ["ppt/parser", "worker-client", "viewer", "render/svg", "layout/measure", "core/errors"], function(exports_42, context_42) {
  "use strict";
  var parser_js_2, worker_client_js_2, viewer_js_1, svg_js_2, measure_js_4, errors_js_19, license, watermark, closedError, documentSequence;
  var __moduleName = context_42 && context_42.id;
  function getPptPackageManifest() {
    return Object.freeze({ kind: "flyfish-ppt-typescript-v1", product: "Flyfish PPT Viewer", format: "PowerPoint 97-2003 (.ppt)", packageName: "@file-viewer/ppt", packageVersion: parser_js_2.VERSION, renderer: "typescript-svg-canvas", license: "Apache-2.0", watermarkRequired: false, wasmRequired: false, workerFile: "worker.mjs", sourceRepositoryPrivate: true });
  }
  exports_42("getPptPackageManifest", getPptPackageManifest);
  function positive(value, fallback) {
    const n = value ?? fallback;
    if (!Number.isFinite(n) || n <= 0)
      throw new errors_js_19.PptError("RENDER_SCALE", "Render scale and pixel ratio must be finite and positive");
    return n;
  }
  function dimensions(model, index, options, ratio) {
    const slide = model.slides[index];
    if (!Number.isInteger(index) || !slide)
      throw new errors_js_19.PptError("SLIDE_INDEX", `Slide index ${index} is outside the presentation`);
    const scale = positive(options.scale, 1), pixelRatio = positive(options.pixelRatio, ratio);
    const width = Math.max(1, Math.ceil(slide.size.width * scale * pixelRatio)), height = Math.max(1, Math.ceil(slide.size.height * scale * pixelRatio));
    if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width > 32768 || height > 32768 || width * height > 64 * 1024 * 1024)
      throw new errors_js_19.PptError("RENDER_LIMIT", "Requested slide bitmap exceeds the 64-megapixel render limit");
    return { slideIndex: index, width, height, logicalWidth: slide.size.width, logicalHeight: slide.size.height, scale, pixelRatio, source: "svg" };
  }
  function makeDocument(model, mode, removed) {
    const attached = /* @__PURE__ */ new Map();
    let closed = false, sequence = 0, svgRenders = 0, cancellations = 0;
    const stats = () => ({ enabled: false, available: false, disabledReason: "The TypeScript renderer does not use persistent raster caching", entries: 0, bytes: 0, maxBytes: 0, maxEntries: 0, maxEntryBytes: 0, hits: 0, misses: 0, writes: 0, nativeRenders: 0, svgRenders, cancellations, attachedCanvases: attached.size, activeCanvases: [...attached.keys()].filter((c) => c.width > 1 && c.height > 1).length, wasmMemoryBytes: 0 });
    const doc = {
      mode,
      documentId: `ppt-ts-${++documentSequence}`,
      slideCount: model.slides.length,
      width: model.size.width,
      height: model.size.height,
      model,
      get closed() {
        return closed;
      },
      async renderSlide(index, canvas, options = {}) {
        if (closed)
          throw closedError();
        const owner = canvas.ownerDocument ?? (typeof document === "undefined" ? void 0 : document);
        const result = dimensions(model, index, options, owner?.defaultView?.devicePixelRatio ?? 1), current = ++sequence;
        attached.set(canvas, { index, sequence: current });
        const stale = () => closed || attached.get(canvas)?.sequence !== current;
        const cancelled = () => {
          cancellations++;
          return { ...result, cancelled: true };
        };
        try {
          await owner?.fonts?.ready;
          if (stale())
            return cancelled();
          const output = svg_js_2.renderSlide(model, index, { textLayout: "measured", textOutput: "svg", textMeasurer: measure_js_4.createCanvasTextMeasurer(owner), mediaControls: false });
          const blob = new Blob([output.html], { type: "image/svg+xml" });
          let image, url;
          try {
            if (owner) {
              image = owner.createElement("img");
              url = URL.createObjectURL(blob);
              const loaded = new Promise((resolve, reject) => {
                const img = image;
                img.onload = () => resolve();
                img.onerror = () => reject(new errors_js_19.PptError("SVG_DECODE", "The browser could not decode the rendered slide"));
              });
              image.src = url;
              await loaded;
            } else if (typeof createImageBitmap === "function")
              image = await createImageBitmap(blob);
            else
              throw new errors_js_19.PptError("CANVAS_UNAVAILABLE", "Canvas snapshots require a browser image decoder");
            if (stale())
              return cancelled();
            canvas.width = result.width;
            canvas.height = result.height;
            const context = canvas.getContext("2d");
            if (!context)
              throw new errors_js_19.PptError("CANVAS_UNAVAILABLE", "A two-dimensional Canvas context is unavailable");
            context.clearRect(0, 0, result.width, result.height);
            context.drawImage(image, 0, 0, result.width, result.height);
            svgRenders++;
            if ("style" in canvas) {
              canvas.style.width = `${result.logicalWidth * result.scale}px`;
              canvas.style.height = `${result.logicalHeight * result.scale}px`;
              canvas.dataset.renderState = "rendered";
            }
            return result;
          } finally {
            if (url)
              URL.revokeObjectURL(url);
            if (image && "close" in image)
              image.close();
          }
        } catch (error) {
          if (stale())
            return cancelled();
          if ("dataset" in canvas)
            canvas.dataset.renderState = "error";
          throw error;
        }
      },
      async releaseSlide(index) {
        let released = false;
        for (const [canvas, state] of attached)
          if (state.index === index) {
            attached.delete(canvas);
            canvas.width = 1;
            canvas.height = 1;
            if ("dataset" in canvas)
              canvas.dataset.renderState = "released";
            released = true;
          }
        return released;
      },
      async cacheStats() {
        return stats();
      },
      async close() {
        if (closed)
          return;
        closed = true;
        for (const canvas of attached.keys()) {
          canvas.width = 1;
          canvas.height = 1;
          if ("dataset" in canvas)
            canvas.dataset.renderState = "closed";
        }
        attached.clear();
        model.assets = [];
        model.slides = [];
        model.masters = [];
        model.fonts = [];
        model.extras = void 0;
        removed();
      }
    };
    return doc;
  }
  async function loadPptViewer(options = {}) {
    const mode = options.worker !== false && typeof Worker !== "undefined" ? "worker" : "direct";
    const documents = /* @__PURE__ */ new Set(), workers = /* @__PURE__ */ new Set(), mounts = /* @__PURE__ */ new Set();
    let closed = false;
    const runtime = {
      mode,
      license,
      watermark,
      async open(input) {
        if (closed)
          throw closedError();
        let model;
        if (mode === "worker") {
          const worker = worker_client_js_2.PptWorkerClient.create(options.workerUrl);
          workers.add(worker);
          try {
            const buffer = input instanceof ArrayBuffer ? input : input.buffer instanceof ArrayBuffer && input.byteOffset === 0 && input.byteLength === input.buffer.byteLength ? input.buffer : void 0;
            model = options.transferInputOwnership && buffer ? await worker.parseOwned(buffer, options.parseOptions) : await worker.parse(input, options.parseOptions);
          } finally {
            workers.delete(worker);
            worker.destroy();
          }
        } else {
          await Promise.resolve();
          if (closed)
            throw closedError();
          model = parser_js_2.parsePpt(input, options.parseOptions);
        }
        if (closed)
          throw closedError();
        const document2 = makeDocument(model, mode, () => documents.delete(document2));
        documents.add(document2);
        return document2;
      },
      async mount(target, input, mountOptions = {}) {
        const element = typeof target === "string" ? globalThis.document?.querySelector(target) : target;
        if (!element)
          throw new errors_js_19.PptError("MOUNT_TARGET", "The presentation mount target does not exist");
        const scale = positive(mountOptions.scale, 1);
        positive(mountOptions.pixelRatio, 1);
        const doc = await runtime.open(input), owner = element.ownerDocument, root = owner.createElement("div"), canvases = [], timers = /* @__PURE__ */ new Map();
        const IO = owner.defaultView?.IntersectionObserver, virtualized = mountOptions.virtualize !== false && !!IO;
        let observer, mountClosed = false;
        root.className = mountOptions.className ?? "pptjs-pages";
        Object.assign(root.style, { display: "flex", flexDirection: "column", alignItems: "center", gap: "16px", padding: "20px", background: "#e5e7eb" });
        for (let index = 0; index < doc.slideCount; index++) {
          const size = doc.model.slides[index].size, page = owner.createElement("div"), canvas = owner.createElement("canvas");
          Object.assign(page.style, { position: "relative", width: `${size.width * scale}px`, height: `${size.height * scale}px`, flex: "none", background: "white" });
          canvas.width = 1;
          canvas.height = 1;
          canvas.dataset.renderState = "pending";
          canvas.dataset.slideIndex = String(index);
          canvas.setAttribute("role", "img");
          canvas.setAttribute("aria-label", `Slide ${index + 1}`);
          Object.assign(canvas.style, { display: "block", width: "100%", height: "100%" });
          page.append(canvas);
          root.append(page);
          canvases.push(canvas);
        }
        const clearTimer = (index) => {
          const timer = timers.get(index);
          if (timer !== void 0)
            clearTimeout(timer);
          timers.delete(index);
        };
        const mounted = {
          document: doc,
          root,
          canvases,
          virtualized,
          async renderSlide(index) {
            if (mountClosed)
              throw closedError();
            const canvas = canvases[index];
            if (!canvas)
              throw new errors_js_19.PptError("SLIDE_INDEX", "Slide is outside the presentation");
            clearTimer(index);
            canvas.dataset.renderState = "rendering";
            return doc.renderSlide(index, canvas, mountOptions);
          },
          cacheStats: () => doc.cacheStats(),
          async close() {
            if (mountClosed)
              return;
            mountClosed = true;
            observer?.disconnect();
            for (const timer of timers.values())
              clearTimeout(timer);
            timers.clear();
            await doc.close();
            root.remove();
            mounts.delete(mounted);
          }
        };
        mounts.add(mounted);
        try {
          if (mountOptions.replace !== false)
            element.replaceChildren(root);
          else
            element.append(root);
          if (virtualized) {
            observer = new IO((entries) => {
              for (const entry of entries) {
                const index = Number(entry.target.dataset.slideIndex);
                if (entry.isIntersecting) {
                  clearTimer(index);
                  if (canvases[index]?.dataset.renderState !== "rendered" && canvases[index]?.dataset.renderState !== "rendering")
                    void mounted.renderSlide(index).catch(() => {
                    });
                } else {
                  clearTimer(index);
                  timers.set(index, setTimeout(() => {
                    timers.delete(index);
                    if (!mountClosed)
                      void doc.releaseSlide(index);
                  }, Math.max(0, mountOptions.releaseDelayMs ?? 1200)));
                }
              }
            }, { root: mountOptions.scrollRoot ?? null, rootMargin: mountOptions.rootMargin ?? "150% 0px" });
            for (const canvas of canvases)
              observer.observe(canvas);
            if (canvases.length)
              await mounted.renderSlide(0);
          } else
            for (let index = 0; index < canvases.length; index++)
              await mounted.renderSlide(index);
          return mounted;
        } catch (error) {
          await mounted.close();
          throw error;
        }
      },
      async cacheStats() {
        const all = await Promise.all([...documents].map((d) => d.cacheStats()));
        const empty = { enabled: false, available: false, disabledReason: "The TypeScript renderer does not use persistent raster caching", entries: 0, bytes: 0, maxBytes: 0, maxEntries: 0, maxEntryBytes: 0, hits: 0, misses: 0, writes: 0, nativeRenders: 0, svgRenders: 0, cancellations: 0, attachedCanvases: 0, activeCanvases: 0, wasmMemoryBytes: 0 };
        return all.reduce((sum, s) => ({ ...sum, svgRenders: sum.svgRenders + s.svgRenders, cancellations: sum.cancellations + s.cancellations, attachedCanvases: sum.attachedCanvases + s.attachedCanvases, activeCanvases: sum.activeCanvases + s.activeCanvases }), empty);
      },
      async close() {
        if (closed)
          return;
        closed = true;
        for (const worker of workers)
          worker.destroy();
        workers.clear();
        await Promise.all([...mounts].map((m) => m.close()));
        await Promise.all([...documents].map((d) => d.close()));
      }
    };
    return runtime;
  }
  exports_42("loadPptViewer", loadPptViewer);
  function createPptViewer(containerOrOptions, options) {
    return containerOrOptions && "ownerDocument" in containerOrOptions && "replaceChildren" in containerOrOptions ? viewer_js_1.createPptViewer(containerOrOptions, options) : loadPptViewer(containerOrOptions);
  }
  exports_42("createPptViewer", createPptViewer);
  return {
    setters: [
      function(parser_js_2_1) {
        parser_js_2 = parser_js_2_1;
      },
      function(worker_client_js_2_1) {
        worker_client_js_2 = worker_client_js_2_1;
      },
      function(viewer_js_1_1) {
        viewer_js_1 = viewer_js_1_1;
      },
      function(svg_js_2_1) {
        svg_js_2 = svg_js_2_1;
      },
      function(measure_js_4_1) {
        measure_js_4 = measure_js_4_1;
      },
      function(errors_js_19_1) {
        errors_js_19 = errors_js_19_1;
      }
    ],
    execute: function() {
      license = Object.freeze({ id: "FV-PPT-TYPESCRIPT-APACHE-2.0", edition: "public", holder: "Individuals and Organizations", policy: "Apache-2.0", commercialUse: true, apacheLicenseApplies: true, redistributionAllowed: true, standaloneRedistributionAllowed: true });
      watermark = Object.freeze({ required: false, text: "" });
      closedError = () => new errors_js_19.PptError("DOCUMENT_CLOSED", "The presentation has been closed");
      documentSequence = 0;
    }
  };
});
System.register("index", ["ppt/parser", "render/svg", "runtime", "viewer", "worker-client", "core/errors", "layout/measure", "layout/text-layout"], function(exports_43, context_43) {
  "use strict";
  var __moduleName = context_43 && context_43.id;
  return {
    setters: [
      function(parser_js_3_1) {
        exports_43({
          "parsePpt": parser_js_3_1["parsePpt"],
          "VERSION": parser_js_3_1["VERSION"]
        });
      },
      function(svg_js_3_1) {
        exports_43({
          "renderSlide": svg_js_3_1["renderSlide"],
          "renderSlideSvg": svg_js_3_1["renderSlideSvg"],
          "defaultPptCss": svg_js_3_1["defaultPptCss"]
        });
      },
      function(runtime_js_1_1) {
        exports_43({
          "createPptViewer": runtime_js_1_1["createPptViewer"],
          "loadPptViewer": runtime_js_1_1["loadPptViewer"],
          "getPptPackageManifest": runtime_js_1_1["getPptPackageManifest"]
        });
      },
      function(viewer_js_2_1) {
        exports_43({
          "createSlideViewer": viewer_js_2_1["createPptViewer"]
        });
      },
      function(worker_client_js_3_1) {
        exports_43({
          "PptWorkerClient": worker_client_js_3_1["PptWorkerClient"]
        });
      },
      function(errors_js_20_1) {
        exports_43({
          "PptError": errors_js_20_1["PptError"]
        });
      },
      function(measure_js_5_1) {
        exports_43({
          "createCanvasTextMeasurer": measure_js_5_1["createCanvasTextMeasurer"]
        });
      },
      function(text_layout_js_2_1) {
        exports_43({
          "layoutText": text_layout_js_2_1["layoutText"]
        });
      }
    ],
    execute: function() {
    }
  };
});
System.register("worker", ["ppt/parser"], function(exports_44, context_44) {
  "use strict";
  var parser_js_4, scope;
  var __moduleName = context_44 && context_44.id;
  return {
    setters: [
      function(parser_js_4_1) {
        parser_js_4 = parser_js_4_1;
      }
    ],
    execute: function() {
      scope = globalThis;
      scope.addEventListener("message", (event) => {
        const request = event.data;
        if (!request || request.type !== "parse" || typeof request.id !== "number")
          return;
        const start = performance.now();
        try {
          scope.postMessage({ id: request.id, progress: { phase: "parse", elapsedMs: 0 } });
          const result = parser_js_4.parsePpt(request.buffer, request.options);
          const buffers = /* @__PURE__ */ new Set();
          for (const asset of result.assets) {
            if (!(asset.bytes.buffer instanceof ArrayBuffer) || asset.bytes.byteOffset !== 0 || asset.bytes.byteLength !== asset.bytes.buffer.byteLength)
              asset.bytes = new Uint8Array(asset.bytes);
            buffers.add(asset.bytes.buffer);
          }
          scope.postMessage({ id: request.id, progress: { phase: "complete", elapsedMs: performance.now() - start, slideCount: result.slides.length } });
          scope.postMessage({ id: request.id, ok: true, result }, [...buffers]);
        } catch (error) {
          const e = error;
          scope.postMessage({ id: request.id, ok: false, error: { code: e.code ?? "PARSE_FAILED", message: e.message ?? String(error), offset: e.offset } });
        }
      });
    }
  };
});
System.importSync("worker");
