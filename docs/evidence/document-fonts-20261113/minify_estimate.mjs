// Estimate esbuild transform savings in memory only; this is not a production rebuild.
import {readFile, readdir} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {gzipSync, brotliCompressSync, constants} from 'node:zlib';
const repo = resolve(process.argv[2]);
const esbuild = await import(pathToFileURL(join(repo, 'packages/file_viewer_documents/tooling/node_modules/esbuild/lib/main.js')).href);
const root = join(repo, 'packages/file_viewer_documents/assets/runtime');
const copied = new Set(['libwpd.mjs', 'chm_wasm.js', 'xmllint-browser.mjs', 'xslt-wasm.js']);
const rows = [];
for (const file of (await readdir(root)).sort()) {
  if (!/\.m?js$/.test(file) || copied.has(file)) continue;
  const data = await readFile(join(root, file));
  const result = await esbuild.transform(data.toString('utf8'), {loader: 'js', minify: true, target: 'es2022', legalComments: 'inline'});
  const minified = Buffer.from(result.code);
  rows.push({file, bytes: data.length, minified_bytes: minified.length, gzip9_bytes: gzipSync(data, {level:9}).length, minified_gzip9_bytes: gzipSync(minified, {level:9}).length});
}
const totals = Object.fromEntries(['bytes', 'minified_bytes', 'gzip9_bytes', 'minified_gzip9_bytes'].map(key=>[key, rows.reduce((sum,r)=>sum+r[key],0)]));
const selectedCompression = [];
for (const file of ['stet_wasm_bg.wasm', 'libwpd.wasm', 'chm_wasm_bg.wasm', 'sheet.worker.js', 'pptjs.worker.js', 'xmllint.wasm', 'xslt-wasm.js']) {
  const data=await readFile(join(root,file));
  selectedCompression.push({file, bytes: data.length, gzip9_bytes: gzipSync(data,{level:9}).length, brotli9_bytes: brotliCompressSync(data,{params:{[constants.BROTLI_PARAM_QUALITY]:9}}).length});
}
console.log(JSON.stringify({schema:1, versions:{node:process.version,zlib:process.versions.zlib,brotli:process.versions.brotli,esbuild:esbuild.version}, method:'Transform each existing esbuild-produced JS file in memory, preserve legal comments inline; exclude unchanged copied vendor runtimes. No rebundle, tests or production edits; savings are an estimate. Node compression may differ from Python zlib; compare before/after within this file.',files:rows.length,totals,rows,selected_compression:selectedCompression},null,2));
