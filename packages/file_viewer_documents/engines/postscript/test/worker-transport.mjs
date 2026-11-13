// SPDX-License-Identifier: Apache-2.0
// Test-only Node worker-thread transport for the unchanged production worker.
// The file-backed Response replaces local HTTP asset delivery; WASM execution,
// worker code, request protocol and client deadlines remain genuine.
import {parentPort, workerData} from 'node:worker_threads';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {join} from 'node:path';

globalThis.self = globalThis;
globalThis.location = new URL('http://127.0.0.1/runtime/postscript.worker.js');
globalThis.addEventListener = (kind, listener) => {
  if (kind === 'message') parentPort.on('message', data => listener({data}));
};
globalThis.postMessage = (data, transfers) => parentPort.postMessage(data, transfers);
globalThis.fetch = async (input, options) => {
  const url = String(input);
  parentPort.postMessage({transportRequest: url});
  if (url !== 'http://127.0.0.1/runtime/stet_wasm_bg.wasm' ||
      options?.redirect !== 'error' || options?.credentials !== 'omit' || options?.mode !== 'same-origin') {
    throw new Error('Unexpected asset request in the Node transport fixture.');
  }
  const bytes = await readFile(join(workerData.runtime, 'stet_wasm_bg.wasm'));
  if (workerData.corruptAsset) bytes[0] ^= 1;
  return new Response(bytes, {headers: {'content-type': 'application/wasm', 'content-length': String(bytes.length)}});
};
await import(pathToFileURL(join(workerData.runtime, 'postscript.worker.js')).href);
