// SPDX-License-Identifier: Apache-2.0
// Native browser workers, the reviewed Stet WASM, and real Canvas 2D pixels.
import test, {before, after} from 'node:test';
import assert from 'node:assert/strict';
import {stageSelected, startBrowser, fixture} from '../../xml/test/support.mjs';

let stage, browser;
before(async () => {
  stage = await stageSelected('postscript');
  browser = await startBrowser(stage);
}, {timeout: 60000});
after(async () => {
  await browser?.close();
  await stage?.close();
  assert.deepEqual(browser?.failures || [], [], 'uncaught browser errors');
});
const bytes = text => Buffer.from(text, 'utf8');
const design = extra => ({design: {postscriptRenderDpi: 72, ...extra}});
const center = () => browser.page.locator('.postscript-page-shell canvas').evaluate(canvas => {
  const {width, height} = canvas;
  return {width, height, rgba: [...canvas.getContext('2d').getImageData(Math.floor(width / 2), Math.floor(height / 2), 1, 1).data]};
});

test('real browser PS renders exactly two allowed pages and page selection changes pixels', {timeout: 60000}, async () => {
  await browser.open(await fixture('postscript', 'multipage.ps'), 'multipage.ps', design({postscriptMaxPages: 2}));
  assert.equal(await browser.page.locator('.postscript-viewer').getAttribute('data-page-count'), '2');
  assert.match(await browser.page.locator('.postscript-title').textContent(), /0\.8\.7/);
  assert.deepEqual(await center(), {width: 144, height: 144, rgba: [255, 0, 0, 255]});
  await browser.page.locator('[data-postscript-action="next"]').click();
  await browser.page.waitForFunction(() => document.querySelector('.postscript-status')?.textContent.includes('2/2'));
  assert.deepEqual((await center()).rgba, [0, 0, 255, 255]);
  assert.equal(await browser.page.locator('[data-page-index="1"]').getAttribute('aria-current'), 'page');
  await browser.page.locator('[data-page-index="0"]').click();
  await browser.page.waitForFunction(() => document.querySelector('.postscript-status')?.textContent.includes('1/2'));
  assert.deepEqual((await center()).rgba, [255, 0, 0, 255]);
});

test('real browser EPS contains rasterized vector shape and embedded-font text', {timeout: 30000}, async () => {
  await browser.open(await fixture('postscript', 'shape.eps'), 'shape.eps', design());
  const counts = await browser.page.locator('.postscript-page-shell canvas').evaluate(canvas => {
    const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
    let green = 0, black = 0, white = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      const [r, g, b, a] = pixels.slice(i, i + 4);
      if (a !== 255) continue;
      if (r < 30 && g > 100 && b < 30) green++;
      if (r < 30 && g < 30 && b < 30) black++;
      if (r > 240 && g > 240 && b > 240) white++;
    }
    return {green, black, white};
  });
  assert.ok(counts.green > 5000, JSON.stringify(counts));
  assert.ok(counts.black > 30, JSON.stringify(counts));
  assert.ok(counts.white > 1000, JSON.stringify(counts));
  assert.ok(browser.requests.includes('/runtime/stet_wasm_bg.wasm'));
});

test('malformed, oversized and over-page-limit files return failures without partial previews', {timeout: 30000}, async () => {
  await assert.rejects(browser.open(bytes('not PostScript'), 'bad.ps'), /PostScript|signature/i);
  await assert.rejects(browser.open(await fixture('postscript', 'shape.eps'), 'large.eps', design({maxFileBytes: 1})), /input limit/);
  await assert.rejects(browser.open(await fixture('postscript', 'multipage.ps'), 'two.ps', design({postscriptMaxPages: 1})), /page.*limit|exceeds.*page/i);
  await assert.rejects(browser.open(bytes('%!PS\n<< /PageSize [1000000 1000000] >> setpagedevice\nshowpage\n'), 'huge.ps'), /dimension|raster|page/i);
  assert.equal(await browser.page.locator('.postscript-viewer').count(), 0);
  const stats = await browser.page.evaluate(() => workerStats);
  assert.equal(stats.created, stats.terminated);
});

test('a nonterminating PostScript input cannot exceed its browser worker deadline', {timeout: 10000}, async () => {
  const started = performance.now();
  await assert.rejects(browser.open(bytes('%!PS\n{} loop\n'), 'loop.ps', design({workerTimeoutMs: 1000})), /exceeded 1000ms/);
  assert.ok(performance.now() - started < 8000);
  const stats = await browser.page.evaluate(() => workerStats);
  assert.equal(stats.created, stats.terminated);
});

test('host abort terminates a live browser worker and leaves no canvas', {timeout: 20000}, async () => {
  const started = browser.page.waitForEvent('worker', {timeout: 10000});
  const rejected = assert.rejects(browser.open(bytes('%!PS\n{} loop\n'), 'cancel.ps', design()), /abort|cancel/i);
  await started;
  await browser.page.evaluate(() => previewController.abort());
  await rejected;
  const stats = await browser.page.evaluate(() => workerStats);
  assert.equal(stats.created, stats.terminated);
  assert.equal(await browser.page.locator('canvas').count(), 0);
});

test('unmount zeros retained canvases and destroys its native worker', {timeout: 30000}, async () => {
  await browser.open(await fixture('postscript', 'shape.eps'), 'shape.eps', design());
  const state = await browser.page.evaluate(() => {
    const canvases = [...document.querySelectorAll('canvas')];
    previewController.abort();previewInstance.destroy();
    return {sizes: canvases.map(canvas => [canvas.width, canvas.height]), workers: workerStats,
      children: document.querySelector('#document').childElementCount};
  });
  assert.equal(state.children, 0);
  for (const size of state.sizes) assert.deepEqual(size, [0, 0]);
  assert.equal(state.workers.created, state.workers.terminated);
  // All network I/O belongs to the selected local runtime and host document.
  assert.equal(browser.requests.some(path => path !== '/' && !path.startsWith('/runtime/')), false);
});
