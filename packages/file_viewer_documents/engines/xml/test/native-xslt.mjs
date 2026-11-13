// SPDX-License-Identifier: Apache-2.0
// Genuine pinned libxslt WASM under Node. This verifies engine bytes/ABI only;
// it is deliberately not a claim of browser Worker, DOM or CSP acceptance.
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {npmPath} from './support.mjs';

export async function nativeXslt(xml, stylesheet, limitMemory) {
  const source = await readFile(`${npmPath('xslt-polyfill')}/dist/xslt-wasm.js`, 'utf8');
  let memoryGuardUsed = false;
  const wasmApi = Object.create(WebAssembly);
  wasmApi.Module = class extends WebAssembly.Module {
    constructor(bytes) { super(limitMemory(bytes)); memoryGuardUsed = true; }
  };
  const deny = () => { throw new Error('Unexpected network request in the local engine fixture.'); };
  const context = vm.createContext({
    console, TextEncoder, TextDecoder, WebAssembly: wasmApi, atob, btoa,
    setTimeout, clearTimeout, URL, fetch: deny, XMLHttpRequest: deny,
  });
  vm.runInContext(`${source};globalThis.factory=createXSLTTransformModule;`, context, {timeout: 1000});
  const engine = await context.factory({print: () => {}, printErr: () => {}});
  const pointers = [];
  const allocate = text => {
    const bytes = typeof text === 'string' ? new TextEncoder().encode(text) : text;
    const pointer = engine._malloc(bytes.length + 1);
    if (!pointer) throw new Error('Native XSLT fixture allocation failed.');
    pointers.push(pointer);
    const heap = new Uint8Array(engine.wasmMemory.buffer);
    heap.set(bytes, pointer); heap[pointer + bytes.length] = 0;
    return [pointer, bytes.length];
  };
  try {
    const [input, inputLength] = allocate(xml);
    const [style, styleLength] = allocate(stylesheet);
    const [url] = allocate('stylesheet.xsl');
    const [mime] = allocate(new Uint8Array(32));
    const transform = engine.cwrap('transform', 'number', Array(7).fill('number'), {async: true});
    const result = await transform(input, inputLength, style, styleLength, 0, url, mime);
    if (!result) throw new Error('Native XSLT transformation failed.');
    pointers.push(result);
    const heap = new Uint8Array(engine.wasmMemory.buffer);
    let end = result;
    while (end < heap.length && heap[end] !== 0) end++;
    return {
      output: new TextDecoder().decode(heap.subarray(result, end)),
      mime: new TextDecoder().decode(heap.subarray(mime, mime + 32)).split('\0')[0],
      memory: engine.wasmMemory, memoryGuardUsed,
    };
  } finally { for (const pointer of pointers) engine._free(pointer); }
}
