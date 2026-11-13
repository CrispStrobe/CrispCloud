import { readFileSync } from 'node:fs';
import { parseMsDoc } from './upstream/msdoc/parser.js';
import { renderMsDoc } from './upstream/render/html.js';

const started = performance.now();
try {
  const parsed = parseMsDoc(readFileSync(process.argv[2]));
  const paragraphs = [];
  let tables = 0, rows = 0, cells = 0;
  function walk(blocks) {
    for (const block of blocks) {
      if (block.type === 'paragraph') paragraphs.push(block);
      if (block.type !== 'table') continue;
      tables++;
      for (const row of block.rows) {
        rows++;
        for (const cell of row.cells) {
          cells++;
          walk(cell.blocks ?? cell.paragraphs ?? []);
        }
      }
    }
  }
  walk(parsed.blocks);
  const storyParagraphs = {};
  for (const p of paragraphs) {
    const kind = p.storyKind ?? 'main';
    storyParagraphs[kind] = (storyParagraphs[kind] ?? 0) + 1;
  }
  console.log(JSON.stringify({
    ok: true, elapsedMs: performance.now() - started, meta: parsed.meta,
    warnings: parsed.warnings, paragraphs: paragraphs.length, tables, rows, cells,
    storyParagraphs, assets: parsed.assets.map(a => ({type:a.type,mimeType:a.mimeType})),
    html: Object.fromEntries(['all','final','original'].map(reviewMode =>
      [reviewMode, renderMsDoc(parsed,{reviewMode}).html])),
  }));
} catch (error) {
  console.log(JSON.stringify({ok:false,elapsedMs:performance.now()-started,error:String(error)}));
}
