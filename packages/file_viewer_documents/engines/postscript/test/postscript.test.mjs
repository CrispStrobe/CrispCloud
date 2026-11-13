// SPDX-License-Identifier: Apache-2.0
import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {Worker as NodeWorker} from 'node:worker_threads';
import {stageSelected, fixture} from '../../xml/test/support.mjs';

let stage, createSession, limits;
const previousWorker = globalThis.Worker;
const bridges = [];
let corruptAsset = false;
class WorkerTransport extends EventTarget {
  constructor() {
    super();
    this.requests = [];
    this.terminated = false;
    this.native = new NodeWorker(new URL('./worker-transport.mjs', import.meta.url), {
      workerData: {runtime: stage.runtime, corruptAsset},
    });
    bridges.push(this);
    this.native.on('message', data => {
      if (data.transportRequest) {this.requests.push(data.transportRequest);return;}
      this.dispatchEvent(new MessageEvent('message', {data}));
    });
    this.native.on('error', error => {
      const event = new Event('error');Object.defineProperty(event, 'message', {value: error.message});this.dispatchEvent(event);
    });
  }
  postMessage(value, transfers) {this.native.postMessage(value, transfers);}
  terminate() {if (!this.terminated) {this.terminated=true;this.stopping=this.native.terminate();}}
}
before(async () => {
  stage=await stageSelected('postscript');
  ({createPostscriptRenderSession:createSession}=await stage.load('postscriptWorkerClient'));
  ({resolvePostscriptSafetyLimits:limits}=await stage.load('postscriptLimits'));
  globalThis.Worker=WorkerTransport;
});
after(async () => {
  globalThis.Worker=previousWorker;
  for(const bridge of bridges)bridge.terminate();
  await Promise.all(bridges.map(bridge=>bridge.stopping));
  await stage?.close();
});
const bytes = value => typeof value==='string' ? new TextEncoder().encode(value).buffer : value.buffer.slice(value.byteOffset,value.byteOffset+value.byteLength);
const session = overrides => createSession({
  workerUrl:'http://127.0.0.1/runtime/postscript.worker.js',
  wasmUrl:'http://127.0.0.1/runtime/stet_wasm_bg.wasm',
  limits:overrides,
});

test('selected build excludes unrelated design, CAD and copyleft engines', () => {
  for(const name of Object.keys(stage.metafile.inputs)) {
    assert.doesNotMatch(name,/(?:renderers\/(?:cad|geometry-engine)|node_modules\/(?:mermaid|elkjs|heic2any|libarchive\.js)|src\/(?:illustrator|indesign|introspect|psd)\.)/);
  }
});

test('hard execution limits cannot be raised through worker options', () => {
  const resolved=limits({maxPages:100000,maxFileBytes:1e10,maxVmBytes:1e10,maxCanvasDimension:50000,maxRenderedPixels:1e10,workerTimeoutMs:1e10,maxSourceDimension:1e10});
  assert.equal(resolved.maxPages,200);assert.equal(resolved.maxFileBytes,32*1024*1024);
  assert.equal(resolved.maxVmBytes,128*1024*1024);assert.equal(resolved.maxCanvasDimension,8192);
  assert.equal(resolved.maxRenderedPixels,16*1024*1024);assert.equal(resolved.workerTimeoutMs,30000);
  assert.equal(resolved.maxSourceDimension,100000);
});

test('real PS worker accepts exactly two pages and returns red/blue RGBA pixels', async () => {
  const worker=session({maxPages:2});
  try {
    const source=bytes(await fixture('postscript','multipage.ps'));const length=source.byteLength;
    const opened=await worker.open(source,'multipage.ps');
    assert.equal(source.byteLength,length);
    assert.equal(opened.engineVersion,'0.8.7');assert.equal(opened.pages.length,2);
    assert.deepEqual(opened.fontSubstitutes,['URW Base35 (OFL-1.1)']);
    for (const [index,color] of [[0,[255,0,0,255]],[1,[0,0,255,255]]]) {
      const page=await worker.renderPage(index,72);
      assert.equal(page.width,144);assert.equal(page.height,144);
      assert.equal(page.rgba.byteLength,144*144*4);
      assert.deepEqual([...page.rgba.subarray((72*144+72)*4,(72*144+72)*4+4)],color);
    }
    assert.deepEqual(bridges.at(-1).requests,['http://127.0.0.1/runtime/stet_wasm_bg.wasm']);
  } finally {worker.destroy();}
});

test('real EPS raster contains the authored shape and embedded-font text', async () => {
  const worker=session();
  try {
    const opened=await worker.open(bytes(await fixture('postscript','shape.eps')),'shape.eps');
    assert.equal(opened.pages.length,1);
    const page=await worker.renderPage(0,72);let green=0,black=0,white=0;
    for(let i=0;i<page.rgba.length;i+=4){const[r,g,b,a]=page.rgba.subarray(i,i+4);if(a!==255)continue;if(r<30&&g>100&&b<30)green++;if(r<30&&g<30&&b<30)black++;if(r>240&&g>240&&b>240)white++;}
    assert.ok(green>5000,`green pixels=${green}`);assert.ok(black>30,`font pixels=${black}`);assert.ok(white>1000,`white pixels=${white}`);
  } finally {worker.destroy();}
});

test('first page beyond a lower cap rejects rather than returning a prefix', async () => {
  const worker=session({maxPages:1});
  try {await assert.rejects(worker.open(bytes(await fixture('postscript','multipage.ps')),'two.ps'),{code:'POSTSCRIPT_PAGE_LIMIT'});}
  finally{worker.destroy();}
});

test('bad PostScript signatures reject before requesting the native asset', async () => {
  const worker=session();const bridge=bridges.at(-1);
  try {await assert.rejects(worker.open(bytes('not a PostScript file'),'wrong.ps'),{code:'POSTSCRIPT_SIGNATURE_INVALID'});assert.deepEqual(bridge.requests,[]);}
  finally{worker.destroy();}
});

test('an altered native asset fails exact provenance before WASM execution', async () => {
  corruptAsset=true;const worker=session();corruptAsset=false;
  try {await assert.rejects(worker.open(bytes(await fixture('postscript','shape.eps')),'shape.eps'),/reviewed native artifact/);}
  finally{worker.destroy();}
});

test('hostile source dimensions reject before allocating a huge raster', async () => {
  const worker=session();
  try {await assert.rejects(worker.open(bytes('%!PS\n<< /PageSize [1000000 1000000] >> setpagedevice\nshowpage\n'),'huge.ps'),/dimension|raster|page/i);}
  finally{worker.destroy();}
});

test('unbounded genuine PS execution is terminated by the production deadline', async () => {
  const worker=session({workerTimeoutMs:1000});const started=performance.now();
  try {await assert.rejects(worker.open(bytes('%!PS\n{} loop\n'),'loop.ps'),/exceeded 1000ms/);assert.ok(performance.now()-started<5000);assert.equal(bridges.at(-1).terminated,true);}
  finally{worker.destroy();}
});

test('explicit cancellation terminates the genuine interpreter worker', async () => {
  const worker=session();const controller=new AbortController();
  const pending=worker.open(bytes('%!PS\n{} loop\n'),'loop.ps',controller.signal);
  const timer=setTimeout(()=>controller.abort(),200);
  try {await assert.rejects(pending,{name:'AbortError'});assert.equal(bridges.at(-1).terminated,true);}
  finally{clearTimeout(timer);worker.destroy();}
});

test('source, page index and DPI bounds reject through the real client', async () => {
  const worker=session({maxFileBytes:1024});
  try {
    await assert.rejects(worker.open(new ArrayBuffer(1025),'large.ps'),/safety limit/);
    await worker.open(bytes(await fixture('postscript','shape.eps')),'shape.eps');
    await assert.rejects(worker.renderPage(3,72),RangeError);
    await assert.rejects(worker.renderPage(0,10000),RangeError);
  } finally{worker.destroy();}
});
