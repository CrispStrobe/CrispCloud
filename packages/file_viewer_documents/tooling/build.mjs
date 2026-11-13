import {chmod, cp, mkdir, readFile, readdir, rm, stat, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {dirname, join, resolve, relative, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import * as esbuild from 'esbuild';
import {pptFontPatches, patchPptFontSource} from './ppt-font-patches.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const pin = 'd264009ca6efb3daed79a39d1ae63133e0f25558';
const repo = 'https://github.com/flyfish-dev/file-viewer.git';
const source = process.env.FILE_VIEWER_UPSTREAM_DIR ? resolve(process.env.FILE_VIEWER_UPSTREAM_DIR) : join(here, '.source');
const stage = join(here, '.stage', 'file-viewer');
const output = join(root, 'assets', 'runtime');
const licenses = join(root, 'assets', 'licenses');
const sourceNotices = join(root, 'notices');
const correspondingSource = join(root, 'corresponding-source', 'wordperfect');
const require = createRequire(import.meta.url);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

if (!existsSync(join(source, '.git'))) {
  if (process.env.FILE_VIEWER_UPSTREAM_DIR) throw new Error('Expected a pinned upstream git checkout.');
  execFileSync('git', ['clone', '--filter=blob:none', '--no-checkout', repo, source], {stdio:'inherit'});
  execFileSync('git', ['-C',source,'checkout','--detach',pin], {stdio:'inherit'});
}
if (execFileSync('git',['-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim() !== pin) throw new Error('Upstream commit differs from the reviewed pin.');
execFileSync('git',['-C',source,'diff','--exit-code',pin,'--','packages','apps/viewer-demo/public/vendor/ppt','LICENSE'],{stdio:'inherit'});
// These host grants are maintained independently of the generated engine
// notices. Preserve their exact bytes while replacing the generated payload.
const hostNotices = new Map(await Promise.all(
  ['crisperbooks-host-MIT.txt', 'file-viewer-Apache-2.0.txt']
    .map(async name => [name, await readFile(join(licenses, name))])));
await rm(join(here,'.stage'), {recursive:true,force:true});
await rm(output, {recursive:true,force:true});
await rm(licenses, {recursive:true,force:true});
await rm(sourceNotices, {recursive:true,force:true});
await mkdir(stage,{recursive:true}); await mkdir(output,{recursive:true}); await mkdir(licenses,{recursive:true});
await mkdir(sourceNotices,{recursive:true});
for (const [name, bytes] of hostNotices) await writeFile(join(licenses, name), bytes);
const renderers = {wordperfect:'wordperfect',chm:'chm',spreadsheet:'spreadsheet',ppt:'presentation-ppt',postscript:'design',xml:'text'};
const sourceRecords = [];
async function files(directory) {
  const found=[];
  for (const entry of await readdir(directory,{withFileTypes:true})) {
    const path=join(directory,entry.name);
    if(entry.isDirectory()) found.push(...await files(path)); else if(entry.isFile()) found.push(path);
  }
  return found.sort();
}
for (const path of ['packages/core/src', ...Object.values(renderers).map(name=>`packages/renderers/${name}/src`), 'apps/viewer-demo/public/vendor/ppt/dist']) {
  await cp(join(source,path),join(stage,path),{recursive:true});
  for (const file of await files(join(source,path))) sourceRecords.push({path:relative(source,file),sha256:hash(await readFile(file))});
}
for (const [engine,name] of Object.entries(renderers)) {
  const overlay=join(root,'engines',engine,'src');
  if (!existsSync(join(overlay,'entry.ts'))) throw new Error(`Missing selected ${engine} entry.`);
  await cp(overlay,join(stage,'packages/renderers',name,'src'),{recursive:true});
}
await cp(join(root,'engines/host'),join(stage,'crisp-host'),{recursive:true});
for (const patch of pptFontPatches) {
  const path = join(stage, 'apps/viewer-demo/public/vendor/ppt/dist', patch.path);
  await writeFile(path, patchPptFontSource(await readFile(path, 'utf8'), patch));
}
const aliases = Object.fromEntries(Object.entries(renderers).map(([engine,name])=>[`@crisp/${engine}`,join(stage,'packages/renderers',name,'src/entry.ts')]));
for (const part of ['index','assets','browser','headless','export','print-mask']) aliases[part==='index'?'@file-viewer/core':`@file-viewer/core/${part}`]=join(stage,'packages/core/src',`${part}.ts`);
aliases['@file-viewer/ppt']=join(stage,'apps/viewer-demo/public/vendor/ppt/dist/index.js');
const entryPoints = {
  host:join(stage,'crisp-host/index.ts'),
  'wordperfect.worker':join(stage,'packages/renderers/wordperfect/src/wordperfect.worker.ts'),
  'chm.worker':join(stage,'packages/renderers/chm/src/chm.worker.ts'),
  'postscript.worker':join(stage,'packages/renderers/design/src/postscript.worker.ts'),
  'sheet.worker':join(stage,'packages/renderers/spreadsheet/src/spreadsheet/worker/sheetjs/sheet.worker.ts'),
  'pptjs.worker':join(stage,'apps/viewer-demo/public/vendor/ppt/dist/pptjs.worker.js'),
};
// Only this allowlist is bundled. No preset, CAD, OCCT, Mermaid or demo assets.
const built=await esbuild.build({absWorkingDir:stage,entryPoints,outdir:output,bundle:true,format:'esm',splitting:true,target:['es2022'],platform:'browser',alias:aliases,metafile:true,legalComments:'linked',sourcemap:false,minify:true,logLevel:'warning'});
for (const input of Object.keys(built.metafile.inputs)) {
  if (/(?:renderers\/(?:cad|geometry-engine)|node_modules\/(?:mermaid|elkjs|heic2any|libarchive\.js)|vendor\/drawio)/.test(input)) throw new Error(`Disallowed dependency in selected runtime: ${input}`);
}
const copies = {
  'libwpd.mjs':'packages/renderers/wordperfect/vendor/libwpd.mjs',
  'libwpd.wasm':'packages/renderers/wordperfect/vendor/libwpd.wasm',
  'chm_wasm.js':'packages/renderers/chm/src/wasm/chm_wasm.js',
  'chm_wasm_bg.wasm':'packages/renderers/chm/src/wasm/chm_wasm_bg.wasm',
  'stet_wasm_bg.wasm':'packages/renderers/design/runtime/postscript/stet_wasm_bg.wasm',
};
for (const [out,path] of Object.entries(copies)) await cp(join(source,path),join(output,out));
// Keep the actual checksum-pinned MPL source archives and original build/shim
// materials alongside our source distribution, independently of upstream hosting.
await mkdir(join(correspondingSource,'vendor'),{recursive:true});
await mkdir(join(correspondingSource,'scripts'),{recursive:true});
await cp(join(source,'packages/renderers/wordperfect/vendor/libwpd-src'),join(correspondingSource,'vendor/libwpd-src'),{recursive:true});
await cp(join(source,'packages/renderers/wordperfect/scripts/build-libwpd-wasm.mjs'),join(correspondingSource,'scripts/build-libwpd-wasm.mjs'));
const correspondingSourceRecords=[];
for(const file of await files(correspondingSource)) {
  const bytes=await readFile(file);
  await chmod(file,0o644);
  correspondingSourceRecords.push({path:relative(root,file),bytes:bytes.length,sha256:hash(bytes)});
}
const npmRoot=name=>dirname(require.resolve(`${name}/package.json`));
for (const [out,name,path] of [['xmllint-browser.mjs','xmllint-wasm','xmllint-browser.mjs'],['xmllint.wasm','xmllint-wasm','xmllint.wasm'],['xslt-wasm.js','xslt-polyfill','dist/xslt-wasm.js']]) await cp(join(npmRoot(name),path),join(output,out));

const noticeRecords=[];
const noticeByHash = new Map();
const noticeNames = new Map();
async function notice(path, prefix) {
  const bytes=await readFile(path); const out=`${prefix}-${basename(path)}`;
  // A duplicate grant is still attributed to every original source, but its
  // complete text is stored once and included once in the shipped aggregate.
  // Original bytes remain outside Flutter's asset tree for source review.
  const sha256 = hash(bytes);
  if (!Buffer.from(bytes.toString('utf8'), 'utf8').equals(bytes)) throw new Error(`Notice is not lossless UTF-8: ${path}`);
  if (noticeNames.has(out) && noticeNames.get(out) !== sha256) throw new Error(`Conflicting notice filename: ${out}`);
  noticeNames.set(out, sha256);
  const origin={name:out,source:path.startsWith(source)?relative(source,path):path.startsWith(here)?relative(here,path):relative(root,path)};
  const previous = noticeByHash.get(sha256);
  if (previous) {
    previous.sources.push(origin);
  } else {
    await writeFile(join(sourceNotices,out),bytes);
    const record={file:out,bytes:bytes.length,sha256,sources:[origin]};
    noticeByHash.set(sha256,record);
    noticeRecords.push(record);
  }
}
await notice(join(source,'LICENSE'),'file-viewer');
for(const engine of Object.keys(renderers)) {
  const path=join(root,'engines',engine,'UPSTREAM.md');
  if(!existsSync(path)) throw new Error(`Missing selected ${engine} modification/source record.`);
  await notice(path,`crispcloud-${engine}`);
  for(const directory of ['licenses','provenance']) {
    const extra=join(root,'engines',engine,directory);
    if(!existsSync(extra))continue;
    for(const file of await files(extra)) {
      if(/LICENSE|COPYING|NOTICE|Copyright|\.txt$/i.test(basename(file))) {
        await notice(file,`crispcloud-${engine}-${directory}`);
      }
    }
  }
}
for (const name of ['wordperfect','chm','spreadsheet','presentation-ppt']) {
  const dir=join(source,'packages/renderers',name);
  for (const file of await files(dir)) {
    const rel=relative(dir,file);
    if (!/\.(?:md|txt|json)$|(?:^|\/)LICENSE$/.test(rel)) continue;
    if (!/(?:LICENSE|NOTICE|PROVENANCE|THIRD_PARTY)/i.test(rel)) continue;
    if (/(?:test|fixtures|node_modules|dist)\//.test(rel)) continue;
    await notice(file,`${name}-${dirname(rel).replaceAll('/','_').replace('.','root')}`);
  }
}
for (const file of await files(join(source,'packages/renderers/design/LICENSES'))) {
  if (/Stet|^CC0-1.0.txt$/.test(basename(file))) await notice(file,'postscript');
}
for (const file of await files(join(source,'packages/renderers/text/licenses/xml-profiles'))) await notice(file,'xml');
for (const name of ['LICENSE','NOTICE.md','package.json']) await notice(join(source,'apps/viewer-demo/public/vendor/ppt',name),'ppt-runtime');
const npmPackages=new Map();
for(const input of Object.keys(built.metafile.inputs)) {
  const match=input.match(/node_modules\/((?:@[^/]+\/)?[^/]+)/);
  if(match) npmPackages.set(match[1],join(here,'node_modules',match[1]));
}
for(const name of ['xmllint-wasm','xslt-polyfill'])npmPackages.set(name,npmRoot(name));
// Some selected npm distributions already bundle their dependencies (notably
// Floating UI in e-virt-table). A bundler metafile cannot identify those grants.
// Retain the exact installed production closure as well as direct bundle inputs.
for(const [name,path] of npmPackages) {
  const meta=JSON.parse(await readFile(join(path,'package.json'),'utf8'));
  for(const dependency of Object.keys(meta.dependencies || {})) {
    if(npmPackages.has(dependency))continue;
    let directory=path, dependencyPath;
    while(true) {
      const candidate=join(directory,'node_modules',dependency);
      if(existsSync(join(candidate,'package.json'))) {dependencyPath=candidate;break;}
      const parent=dirname(directory); if(parent===directory)break; directory=parent;
    }
    if(!dependencyPath)throw new Error(`Missing installed production dependency ${dependency} of ${name}`);
    npmPackages.set(dependency,dependencyPath);
  }
}
const npmRecords=[];
for(const [name,path] of npmPackages) {
  const meta=JSON.parse(await readFile(join(path,'package.json'),'utf8'));
  const grants=(await readdir(path)).filter(name=>/^(?:LICENSE|COPYING|NOTICE)/i.test(name));
  // This exact published package carries its complete MIT grant in the README.
  if(name==='isarray' && meta.version==='1.0.0' && grants.length===0) grants.push('README.md');
  if(grants.length===0 && !['xmllint-wasm','xslt-polyfill'].includes(name)) throw new Error(`Missing original license in ${name}`);
  for(const grant of grants) {
    const file=join(path,grant); if((await stat(file)).isFile()) await notice(file,`npm-${name.replaceAll('/','_')}`);
  }
  npmRecords.push({name,version:meta.version,declaredLicense:meta.license,selectedLicense:name==='dompurify'?'Apache-2.0':name==='jszip'?'MIT':meta.license});
}
const assetRecords=[];
for(const file of await files(output)) {
  if(basename(file)==='manifest.json')continue;
  await chmod(file,0o644);
  const bytes=await readFile(file);assetRecords.push({path:relative(output,file),bytes:bytes.length,sha256:hash(bytes)});
}
const overlays=[];
for(const file of await files(join(root,'engines'))) {
  if(!file.includes('/src/') && !file.includes('/host/'))continue;
  overlays.push({path:relative(root,file),sha256:hash(await readFile(file))});
}
for (const path of ['tooling/build.mjs', 'tooling/ppt-font-patches.mjs']) {
  overlays.push({path, sha256: hash(await readFile(join(root, path)))});
}
const noticeText=['CrispCloud selected File Viewer document engines',`Upstream: ${repo} @ ${pin}`,'WordPerfect selects MPL-2.0 for libwpd and librevenge. Matching source and build provenance are retained below.','Only the listed selected paths are included; the full upstream preset is not distributed.'];
noticeText.push('Matching WordPerfect library source archives, MIT shim and build materials are included in the CrispCloud source distribution under packages/file_viewer_documents/corresponding-source/wordperfect. The unchanged originals are also available at https://github.com/flyfish-dev/file-viewer/tree/'+pin+'/packages/renderers/wordperfect/vendor/libwpd-src . Their exact hashes appear in RUNTIME_MANIFEST.json.');
noticeText.push('Identical complete notice texts are included once below, with every original source listed. Byte-identical source copies and the source-to-copy mapping are retained under packages/file_viewer_documents/notices and RUNTIME_MANIFEST.json; these source copies are not additional application assets.');
for(const record of noticeRecords) {
  const origins = record.sources.map(origin=>`Source: ${origin.name} (${origin.source})`).join('\n');
  noticeText.push(`\n===== ${record.file} =====\n${origins}\n${await readFile(join(sourceNotices,record.file),'utf8')}`);
}
await writeFile(join(licenses,'THIRD_PARTY.txt'),noticeText.join('\n')+'\n');
const distributionNotices=[];
for(const file of await files(licenses)) {
  await chmod(file,0o644);
  const bytes=await readFile(file);
  distributionNotices.push({path:relative(root,file),bytes:bytes.length,sha256:hash(bytes)});
}
const manifest={schema:2,upstream:{repository:repo,commit:pin,version:'3.3.3'},engines:Object.keys(renderers),assets:assetRecords,dependencies:npmRecords.sort((a,b)=>a.name.localeCompare(b.name)),notices:noticeRecords,distributionNotices,sourceInputs:sourceRecords,overlays,correspondingSource:correspondingSourceRecords};
await writeFile(join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
await writeFile(join(root,'RUNTIME_MANIFEST.json'),JSON.stringify({...manifest,assets:assetRecords},null,2)+'\n');
console.log(JSON.stringify({engines:manifest.engines,assets:assetRecords.length,bytes:assetRecords.reduce((sum,x)=>sum+x.bytes,0),npmPackages:npmRecords.length,uniqueNotices:noticeRecords.length,noticeSources:noticeRecords.reduce((sum,record)=>sum+record.sources.length,0),noticeBytes:distributionNotices.reduce((sum,record)=>sum+record.bytes,0)}));
