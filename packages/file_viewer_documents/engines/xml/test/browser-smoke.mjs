// SPDX-License-Identifier: Apache-2.0
// Real-browser acceptance. Run on an enabled CI runner, not through a DOM shim.
import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {stageSelected, startBrowser, fixture} from './support.mjs';

let stage, browser, source, schema, stylesheet;
before(async () => {
  stage = await stageSelected('xml');
  browser = await startBrowser(stage);
  source = await fixture('xml', 'valid.xml');
  schema = (await fixture('xml', 'order.xsd')).toString();
  stylesheet = (await fixture('xml', 'table.xsl')).toString();
}, {timeout: 60000});
after(async () => {
  await browser?.close();
  await stage?.close();
  assert.deepEqual(browser?.failures || [], [], 'uncaught browser errors');
});

const bytes = value => Buffer.from(value, 'utf8');
const status = () => browser.page.locator('.xml-status');
async function waitForStatus(pattern) {
  await browser.page.waitForFunction(({source, flags}) => {
    const text = document.querySelector('.xml-status')?.textContent || '';
    return new RegExp(source, flags).test(text);
  }, {source: pattern.source, flags: pattern.flags}, {timeout: 20000});
  return status().textContent();
}
async function runXslt(value) {
  await browser.page.getByRole('textbox', {name: 'XSLT stylesheet', exact: true}).fill(value);
  await browser.page.getByRole('button', {name: 'Transform with XSLT', exact: true}).click();
}

test('real browser module worker validates both valid and invalid XML against XSD', {timeout: 60000}, async () => {
  await browser.open(source, 'order.xml');
  await browser.page.getByRole('textbox', {name: 'XML Schema', exact: true}).fill(schema);
  await browser.page.getByRole('button', {name: 'Validate with XSD', exact: true}).click();
  assert.match(await waitForStatus(/^Valid:/), /conforms/);
  await browser.open(bytes(source.toString().replace('<quantity>3</quantity>', '<quantity>0</quantity>')), 'invalid.xml');
  await browser.page.getByRole('textbox', {name: 'XML Schema', exact: true}).fill(schema);
  await browser.page.getByRole('button', {name: 'Validate with XSD', exact: true}).click();
  assert.match(await waitForStatus(/^Invalid XML:/), /quantity|positiveInteger/);
  assert.ok(browser.requests.includes('/runtime/xmllint.wasm'));
});

test('local UTF-16 schema upload decodes and reaches the real validation engine', {timeout: 30000}, async () => {
  await browser.open(source, 'order.xml');
  const utf16 = schema.replace(/<\?xml[^?]*\?>/, '<?xml version="1.0" encoding="UTF-16"?>');
  await browser.page.getByLabel('Choose XML Schema', {exact: true}).setInputFiles({
    name: 'order.xsd', mimeType: 'application/xml', buffer: Buffer.from(`\ufeff${utf16}`, 'utf16le'),
  });
  await browser.page.waitForFunction(() => document.querySelector('textarea[aria-label="XML Schema"]').value.includes('schema'));
  await browser.page.getByRole('button', {name: 'Validate with XSD', exact: true}).click();
  assert.match(await waitForStatus(/^Valid:/), /conforms/);
});

test('real browser XSLT computes HTML plus exact XML and text serializations', {timeout: 60000}, async () => {
  await browser.open(source, 'order.xml');
  await runXslt(stylesheet);
  await waitForStatus(/^Transformation complete/);
  assert.match(await browser.page.locator('[data-xml-output]').textContent(), /<td>6<\/td>/);
  assert.equal(await browser.page.locator('[data-xml-output]').getAttribute('data-xml-output'), 'text/html');
  assert.equal(await browser.page.frameLocator('iframe').locator('td').first().textContent(), 'Tea & biscuits');
  for (const method of ['xml', 'text']) {
    const value = `<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:output method="${method}"/><x:template match="/"><result><x:value-of select="order/item/quantity * 2"/></result></x:template></x:stylesheet>`;
    await runXslt(value);
    await waitForStatus(/^Transformation complete/);
    const output = await browser.page.locator('[data-xml-output]').textContent();
    assert.match(output, method === 'text' ? /^6$/ : /<result>6<\/result>/);
    assert.equal(await browser.page.locator('iframe').count(), 0);
  }
});

test('DTD, dependency and XPath external-resource requests are rejected before workers run', {timeout: 30000}, async () => {
  await assert.rejects(browser.open(bytes('<!DOCTYPE a [<!ENTITY e SYSTEM "/tripwire">]><a>&e;</a>'), 'unsafe.xml'), /DTD|entity|DOCTYPE|external/i);
  await browser.open(source, 'order.xml');
  const before = await browser.page.evaluate(() => workerStats.created);
  const schemaWithImport = '<x:schema xmlns:x="http://www.w3.org/2001/XMLSchema"><x:include schemaLocation="/tripwire"/></x:schema>';
  await browser.page.getByRole('textbox', {name: 'XML Schema', exact: true}).fill(schemaWithImport);
  await browser.page.getByRole('button', {name: 'Validate with XSD', exact: true}).click();
  await waitForStatus(/disabled|forbidden|external|self-contained/i);
  for (const value of [
    '<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:include href="/tripwire"/></x:stylesheet>',
    '<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:template match="/"><x:value-of select="docum&#101;nt(\'/tripwire\')"/></x:template></x:stylesheet>',
  ]) {
    await runXslt(value);
    await waitForStatus(/disabled|forbidden|external|self-contained/i);
  }
  assert.equal(await browser.page.evaluate(() => workerStats.created), before);
  assert.equal(browser.requests.some(path => path.startsWith('/tripwire')), false);
});

test('HTML output is inert and cannot load or navigate to external resources', {timeout: 30000}, async () => {
  await browser.open(source, 'order.xml');
  await runXslt('<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:output method="html"/><x:template match="/"><html><body><script>parent.xmlScriptRan = true</script><a href="/tripwire">Link</a><img src="/tripwire" onerror="parent.xmlScriptRan = true"/><p>Safe result</p></body></html></x:template></x:stylesheet>');
  await waitForStatus(/^Transformation complete/);
  assert.equal(await browser.page.locator('iframe').getAttribute('sandbox'), '');
  const frame = browser.page.frameLocator('iframe');
  await frame.getByText('Safe result', {exact: true}).waitFor();
  assert.equal(await frame.locator('script').count(), 0);
  assert.equal(await frame.locator('a').getAttribute('href'), null);
  assert.equal(await frame.locator('img').getAttribute('onerror'), null);
  await frame.locator('a').click();
  assert.equal(await browser.page.evaluate(() => globalThis.xmlScriptRan), undefined);
  assert.equal(browser.requests.some(path => path.startsWith('/tripwire')), false);
});

test('input, stylesheet and transformed output bounds are enforced in the browser', {timeout: 30000}, async () => {
  await assert.rejects(browser.open(source, 'large.xml', {xml: {limits: {maxXmlBytes: 1}}}), /byte limit/);
  await browser.open(source, 'order.xml', {xml: {limits: {maxResourceBytes: 128}}});
  await browser.page.getByLabel('Choose XSLT stylesheet', {exact: true}).setInputFiles({
    name: 'large.xsl', mimeType: 'application/xml', buffer: Buffer.alloc(129, 32),
  });
  assert.match(await waitForStatus(/byte limit/), /Schema or stylesheet/);
  await browser.open(source, 'order.xml', {xml: {limits: {maxOutputBytes: 64}}});
  await runXslt(`<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:output method="text"/><x:template match="/">${'x'.repeat(256)}</x:template></x:stylesheet>`);
  assert.match(await waitForStatus(/output exceeds its byte limit/i), /limit/);
  assert.equal(await browser.page.locator('[data-xml-output]').count(), 0);
});

test('cancel stops a genuine worker and leaves the XML tools reusable', {timeout: 30000}, async () => {
  const manyItems = bytes(`<root>${'<item>content</item>'.repeat(30000)}</root>`);
  await browser.open(manyItems, 'many.xml');
  const style = '<x:stylesheet xmlns:x="http://www.w3.org/1999/XSL/Transform" version="1.0"><x:output method="text"/><x:template match="/"><x:for-each select="root/item"><x:value-of select="count(preceding-sibling::item)"/></x:for-each></x:template></x:stylesheet>';
  const started = browser.page.waitForEvent('worker', {timeout: 10000});
  await runXslt(style);
  await started;
  await browser.page.getByRole('button', {name: 'Cancel', exact: true}).click();
  await waitForStatus(/^Processing cancelled/);
  const counters = await browser.page.evaluate(() => workerStats);
  assert.equal(counters.created, counters.terminated);
  assert.equal(await browser.page.getByRole('button', {name: 'Transform with XSLT', exact: true}).isEnabled(), true);
});

test('the processing deadline also bounds an unfinished local runtime load', {timeout: 10000}, async () => {
  await browser.open(source, 'order.xml', {xml: {timeoutMs: 100}});
  const held = [];
  const routePattern = '**/runtime/xslt-wasm.js';
  await browser.page.route(routePattern, route => {held.push(route);});
  try {
    await runXslt(stylesheet);
    assert.match(await waitForStatus(/time limit/), /stopped/);
    assert.ok(held.length > 0, 'the genuine local runtime request started');
  } finally {
    for (const route of held) await route.abort().catch(() => {});
    await browser.page.unroute(routePattern);
  }
});

test('unmount clears source/output and releases every native worker and object URL', async () => {
  await browser.page.evaluate(() => {previewController.abort();previewInstance?.destroy();});
  const state = await browser.page.evaluate(() => ({
    workers: workerStats, urls: objectUrlStats, children: document.querySelector('#document').childElementCount,
  }));
  assert.equal(state.children, 0);
  assert.equal(state.workers.created, state.workers.terminated);
  for (const url of state.urls.created) assert.ok(state.urls.revoked.includes(url), `unreleased blob URL ${url}`);
});
