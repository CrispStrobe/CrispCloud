// SPDX-License-Identifier: Apache-2.0
import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stageSelected, toolingImport, fixture, npmPath, sha256} from './support.mjs';
import {nativeXslt} from './native-xslt.mjs';

let stage, safety, limitMemory, documentRef;
before(async () => {
  stage = await stageSelected('xml');
  safety = await stage.load('xmlSafety');
  ({limitXmlWasmMemory: limitMemory} = await stage.load('xmlWasmMemory'));
  const {DOMParser} = await toolingImport('@xmldom/xmldom');
  // Guard unit tests use a genuine XML DOM parser under Node, not a browser.
  documentRef = {defaultView: {DOMParser}};
});
after(async () => stage?.close());

test('selected XML build has no unrelated renderer or copyleft runtime', () => {
  for (const name of Object.keys(stage.metafile.inputs)) {
    assert.doesNotMatch(name, /(?:renderers\/(?:cad|geometry-engine)|node_modules\/(?:mermaid|elkjs|heic2any|libarchive\.js))/);
  }
});

test('pinned Playwright CommonJS entry exposes its genuine Chromium launcher', async () => {
  const imported = await toolingImport('playwright');
  const {chromium} = imported.default || imported;
  // Resolve the real package without attempting an unavailable local browser.
  assert.equal(typeof chromium.launch, 'function');
  assert.equal(chromium.name(), 'chromium');
});

test('allows self-contained schema and stylesheets, including XML/text output', async () => {
  safety.parseSafeXml((await fixture('xml','valid.xml')).toString(), documentRef, 'xml');
  safety.parseSafeXml((await fixture('xml','order.xsd')).toString(), documentRef, 'xsd');
  const stylesheet = (await fixture('xml','table.xsl')).toString();
  for (const method of ['html','xml','text']) {
    safety.parseSafeXml(stylesheet.replace('method="html"', `method="${method}"`), documentRef, 'xslt');
  }
});

test('rejects entities, schema dependencies, XInclude and escaped document()', () => {
  for (const [kind, source] of [
    ['xml','<!DOCTYPE a [<!ENTITY s SYSTEM "file:///secret">]><a>&s;</a>'],
    ['xml','<a xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="/secret"/></a>'],
    ['xsd','<x:schema xmlns:x="http://www.w3.org/2001/XMLSchema"><x:include schemaLocation="/other.xsd"/></x:schema>'],
    ['xsd','<x:schema xmlns:x="http://www.w3.org/2001/XMLSchema"><x:import namespace="urn:other" schemaLocation="https://external.invalid/a"/></x:schema>'],
    ['xslt','<x:stylesheet version="1.0" xmlns:x="http://www.w3.org/1999/XSL/Transform"><x:include href="/other.xsl"/></x:stylesheet>'],
    ['xslt','<x:stylesheet version="1.0" xmlns:x="http://www.w3.org/1999/XSL/Transform"><x:template match="/"><x:value-of select="docum&#101;nt(\'/secret\')"/></x:template></x:stylesheet>'],
    ['xslt','<x:stylesheet version="1.0" xmlns:x="http://www.w3.org/1999/XSL/Transform" xmlns:e="http://exslt.org/common" extension-element-prefixes="e"><x:template match="/"><e:document href="/written"/></x:template></x:stylesheet>'],
  ]) assert.throws(() => safety.parseSafeXml(source, documentRef, kind), {code: 'unsafe-resource'});
});

test('runtime URL policy rejects other origins, schemes, credentials and fragments', () => {
  assert.equal(safety.sameOriginXmlUrl('./engine.wasm','https://viewer.test/runtime/a.js','https://viewer.test'),'https://viewer.test/runtime/engine.wasm');
  for (const value of ['https://outside.test/engine.wasm','file:///tmp/a','data:application/wasm,','blob:https://viewer.test/x','https://user:pass@viewer.test/a','/a#fragment']) {
    assert.throws(() => safety.sameOriginXmlUrl(value,'https://viewer.test/runtime/a.js','https://viewer.test'),{code:'unsafe-resource'});
  }
});

test('asset fetch bounds streamed bytes and cancels an oversized response', async () => {
  const previous = globalThis.fetch;
  let cancelled = false;
  globalThis.fetch = async (_url, options) => {
    assert.equal(options.redirect,'error');
    assert.equal(options.mode,'same-origin');
    return new Response(new ReadableStream({
      start(controller) {controller.enqueue(new Uint8Array(3));controller.enqueue(new Uint8Array(3));},
      cancel() {cancelled=true;},
    }));
  };
  try {
    await assert.rejects(safety.fetchXmlBytes('https://viewer.test/asset',5,new AbortController().signal),{code:'limit-exceeded'});
    assert.equal(cancelled,true);
  } finally {globalThis.fetch=previous;}
});

test('already aborted resource reads do not start a request', async () => {
  const controller = new AbortController();controller.abort();
  const previous=globalThis.fetch;let called=false;globalThis.fetch=async()=>{called=true;throw new Error('unexpected');};
  try {await assert.rejects(safety.fetchXmlBytes('https://viewer.test/a',100,controller.signal),{code:'cancelled'});assert.equal(called,false);}
  finally{globalThis.fetch=previous;}
});

test('real xmllint WASM accepts valid XML and rejects invalid schema values', async () => {
  const imported = await toolingImport('xmllint-wasm');
  const {validateXML} = imported.default || imported;
  const xml=(await fixture('xml','valid.xml')).toString();
  const schema=(await fixture('xml','order.xsd')).toString();
  const options={schema, initialMemoryPages:256, maxMemoryPages:1024,modifyArguments:args=>['--nonet',...args]};
  assert.equal((await validateXML({...options,xml})).valid,true);
  const invalid=await validateXML({...options,xml:xml.replace('<quantity>3</quantity>','<quantity>0</quantity>')});
  assert.equal(invalid.valid,false);assert.match(invalid.rawOutput,/quantity|positiveInteger/);
  assert.equal(sha256(await readFile(`${npmPath('xmllint-wasm')}/xmllint.wasm`)),sha256(await readFile(`${stage.runtime}/xmllint.wasm`)));
});

test('real libxslt computes HTML and its compiled memory cannot exceed 64 MiB', async () => {
  const result=await nativeXslt((await fixture('xml','valid.xml')).toString(),(await fixture('xml','table.xsl')).toString(),limitMemory);
  assert.match(result.output,/<td>Tea &amp; biscuits<\/td>/);
  assert.match(result.output,/<td>6<\/td>/);
  assert.equal(result.mime,'text/html');assert.equal(result.memoryGuardUsed,true);
  assert.throws(()=>result.memory.grow(1024),RangeError);
});

test('real libxslt returns XML and text serializations without executing markup', async () => {
  const xml=(await fixture('xml','valid.xml')).toString();
  for (const method of ['xml','text']) {
    const style=`<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:output method="${method}"/><x:template match="/"><result><x:value-of select="order/item/quantity * 2"/></result></x:template></x:stylesheet>`;
    const result=await nativeXslt(xml,style,limitMemory);
    assert.match(result.output,method==='text'?/^6$/ : /<result>6<\/result>/);
    assert.equal(result.mime,method==='text'?'text/plain':'application/xml');
  }
});

test('WASM guard rejects malformed, imported-only and excessive memory declarations', () => {
  for(const bytes of [new Uint8Array(),new Uint8Array([0,97,115,109,1,0,0,0]),new Uint8Array([0,97,115,109,1,0,0,0,5,5,1,1,128,16,128])])assert.throws(()=>limitMemory(bytes));
  assert.throws(()=>limitMemory(new Uint8Array([0,97,115,109,1,0,0,0]),1025));
});
