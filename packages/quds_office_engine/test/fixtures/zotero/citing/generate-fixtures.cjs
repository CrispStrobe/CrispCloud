'use strict';

// Generates verification data with the exact processor shipped by Zotero.
// Third-party source files are test inputs and are not vendored into Quds.
// Usage: node generate-fixtures.cjs /path/to/pinned-sources /path/to/output
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');

const [sourceDir, outputDir] = process.argv.slice(2);
if (!sourceDir || !outputDir) {
  throw new Error('Pass the pinned source directory and output directory.');
}

const zotero = '992853536935dce3249a4ecf61d0d129883f85c4';
const styles = 'd16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3';
const locales = '14940e56f7c783e4173cafbd92e0f5856f2caa14';
const definitions = [
  ['citeproc.js', 'zotero/zotero', zotero, 'chrome/content/zotero/xpcom/citeproc.js', '821ba30cb1b10677744f166b56f12fbd54394df3', 'CPAL-1.0 OR AGPL-3.0-or-later'],
  ['httpIntegrationClient.js', 'zotero/zotero', zotero, 'chrome/content/zotero/xpcom/httpIntegrationClient.js', '611911bbfce0a7656eab8e4a322588863976aa34', 'AGPL-3.0-or-later'],
  ['chicago-notes-bibliography-subsequent-ibid.csl', 'citation-style-language/styles', styles, 'chicago-notes-bibliography-subsequent-ibid.csl', '566c3ef53459703b91a2c9c85137c8b81ff89396', 'CC-BY-SA-3.0'],
  ['elsevier-vancouver.csl', 'citation-style-language/styles', styles, 'elsevier-vancouver.csl', 'c0b242a13fcf2803ab03fdd99b9b0c984329f10e', 'CC-BY-SA-3.0'],
  ['apa.csl', 'citation-style-language/styles', styles, 'apa.csl', 'd663d1e1b728c5fbc70dea233e1c0d09121e8909', 'CC-BY-SA-3.0'],
  ['locales-de-DE.xml', 'citation-style-language/locales', locales, 'locales-de-DE.xml', '87ec7f698f0137f69f08ce2005cff8baef2d7933', 'CC-BY-SA-3.0'],
  ['locales-en-US.xml', 'citation-style-language/locales', locales, 'locales-en-US.xml', '0d74676be4376660f43f2fdb4bf7cade9cf15fe6', 'CC-BY-SA-3.0'],
];
const content = {};
const sources = definitions.map(([name, repo, commit, sourcePath, gitBlobSha, license]) => {
  const bytes = fs.readFileSync(path.join(sourceDir, name));
  const actualBlob = crypto.createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  assert.equal(actualBlob, gitBlobSha, `Pinned source mismatch: ${name}`);
  content[name] = bytes.toString('utf8');
  return {
    name, repository: repo, commit, path: sourcePath, gitBlobSha,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    url: `https://raw.githubusercontent.com/${repo}/${commit}/${sourcePath}`,
    license,
  };
});

const CSL = vm.runInNewContext(content['citeproc.js'] + '\nCSL;', {console}, {timeout: 10000});
assert.equal(CSL.PROCESSOR_VERSION, '1.4.61');
const copy = value => JSON.parse(JSON.stringify(value));
const items = {
  A: {id: 'A', type: 'book', title: 'Forschung in Jerusalem', author: [{family: 'Müller', given: 'Anna'}], issued: {'date-parts': [[2024]]}, publisher: 'Beispiel Verlag', 'publisher-place': 'Berlin'},
  B: {id: 'B', type: 'book', title: 'Quellen und Methoden', author: [{family: 'Schmidt', given: 'Omar'}], issued: {'date-parts': [[2022]]}, publisher: 'Muster Verlag', 'publisher-place': 'Hamburg'},
  C: {id: 'C', type: 'book', title: 'Neue Perspektiven', author: [{family: 'Ali', given: 'Layla'}], issued: {'date-parts': [[2025]]}, publisher: 'Beispiel Verlag', 'publisher-place': 'Berlin'},
  D: {id: 'D', type: 'book', title: 'Weitere Forschung', author: [{family: 'Müller', given: 'Anna'}], issued: {'date-parts': [[2024]]}, publisher: 'Beispiel Verlag', 'publisher-place': 'Berlin'},
};
const cite = (citationID, noteIndex, itemSpecs) => ({
  citationID,
  properties: {noteIndex},
  citationItems: itemSpecs.map(spec => {
    const [id, locator] = Array.isArray(spec) ? spec : [spec];
    return {id, ...(locator === undefined ? {} : {label: 'page', locator: String(locator)}), itemData: copy(items[id])};
  }),
});
const render = (id, styleFile, locale, citations) => {
  const engine = new CSL.Engine({
    retrieveItem: itemId => copy(items[itemId]),
    retrieveLocale: lang => {
      if (['de', 'de-DE'].includes(lang)) return content['locales-de-DE.xml'];
      if (['en', 'en-US', 'us'].includes(lang)) return content['locales-en-US.xml'];
      return false;
    },
  }, content[styleFile], locale, true);
  engine.opt.development_extensions.throw_on_empty = true;
  const input = copy(citations);
  const rendered = copy(engine.rebuildProcessorState(citations, 'html')).map(([citationId, noteIndex, html]) => ({citationId, noteIndex, html}));
  const bib = engine.makeBibliography();
  assert.ok(bib && bib[0].bibliography_errors.length === 0);
  return {
    id, styleFile, styleId: /<id>([^<]+)<\/id>/.exec(content[styleFile])[1], locale,
    items: copy(items), citations: input, rendered,
    bibliography: {parameters: copy(bib[0]), html: bib[0].bibstart + bib[1].join('') + bib[0].bibend},
  };
};
const scenarios = [
  render('german-ibid', 'chicago-notes-bibliography-subsequent-ibid.csl', 'de-DE', [
    cite('g1', 1, [['A', 12]]), cite('g2', 2, [['A', 12]]), cite('g3', 3, [['A', 34]]),
    cite('g4', 4, [['B', 8]]), cite('g5', 5, [['A', 35]]), cite('g6', 6, ['A']),
    cite('g7', 7, [['A', 38]]), cite('g8', 8, [['A', 39], ['B', 9]]), cite('g9', 9, [['B', 10]]),
  ]),
  render('numeric-original', 'elsevier-vancouver.csl', 'en-US', [cite('n1', 0, ['A']), cite('n2', 0, ['B']), cite('n3', 0, ['A'])]),
  render('numeric-prepend', 'elsevier-vancouver.csl', 'en-US', [cite('n0', 0, ['C']), cite('n1', 0, ['A']), cite('n2', 0, ['B']), cite('n3', 0, ['A'])]),
  render('author-year-single', 'apa.csl', 'en-US', [cite('a1', 0, ['A'])]),
  render('author-year-disambiguation', 'apa.csl', 'en-US', [cite('a1', 0, ['A']), cite('a2', 0, ['D'])]),
];
assert.equal(scenarios[0].rendered[1].html, 'Ebd.');
assert.equal(scenarios[0].rendered[2].html, 'Ebd., 34.');
assert.ok(!scenarios[0].rendered[4].html.includes('Ebd.'));
assert.ok(!scenarios[0].rendered[5].html.includes('Ebd.'));
assert.ok(!scenarios[0].rendered[8].html.includes('Ebd.'));
assert.deepEqual(scenarios[1].rendered.map(r => r.html), ['[1]', '[2]', '[1]']);
assert.deepEqual(scenarios[2].rendered.map(r => r.html), ['[1]', '[2]', '[3]', '[2]']);
assert.ok(!scenarios[3].rendered[0].html.includes('2024a'));
assert.ok(scenarios[4].rendered[0].html.includes('2024a'));
assert.ok(scenarios[4].rendered[1].html.includes('2024b'));

async function protocolContract() {
  // Run the actual Zotero wrapper to obtain argument shapes. Replacing only
  // sendCommand isolates its IPC boundary; no Zotero desktop services are used.
  const sandbox = {Zotero: {}, console};
  vm.runInNewContext(content['httpIntegrationClient.js'], sandbox, {timeout: 10000});
  const api = sandbox.Zotero.HTTPIntegrationClient;
  const transcript = [];
  let nextResult;
  api.sendCommand = async (command, args = []) => {
    transcript.push({command, arguments: copy(args), result: copy(nextResult ?? null)});
    return nextResult;
  };
  const application = new api.Application();
  nextResult = {documentID: 'fixture-document', outputFormat: 'html', supportedNotes: ['footnotes', 'endnotes'], supportsImportExport: false, supportsTextInsertion: false, supportsCitationMerging: false, processorName: 'Quds Office'};
  const document = await application.getActiveDocument();
  nextResult = '<data><prefs><pref name="fieldType" value="Http"/></prefs></data>';
  await document.getDocumentData();
  nextResult = true;
  await document.canInsertField('Http');
  nextResult = {id: 'f1', code: 'ITEM CSL_CITATION {"citationID":"sample"}', text: '(Müller, 2024)', noteIndex: 0};
  const field = await document.cursorInField('Http');
  nextResult = [{id: field._id, code: field._code, text: field._text, noteIndex: field._noteIndex}];
  const fields = await document.getFields('Http');
  assert.equal(fields[0]._id, 'f1');
  const countBeforeCachedReads = transcript.length;
  assert.equal(await field.getCode(), field._code);
  assert.equal(await field.getText(), field._text);
  assert.equal(await field.getNoteIndex(), 0);
  assert.equal(transcript.length, countBeforeCachedReads);
  nextResult = {id: 'f2', code: '', text: '', noteIndex: 2};
  const inserted = await document.insertField('Http', 1);
  nextResult = null;
  await inserted.setCode('ITEM CSL_CITATION {"citationID":"new"}');
  // The real wrapper uses DOMParser only to cache plain text. This small DOM
  // stand-in handles the plain input below; it is not an HTML rendering test.
  sandbox.DOMParser = class { parseFromString(text) { return {documentElement: {textContent: text}}; } };
  await inserted.setText('Ebd., 34.', true);
  await document.convert([field, inserted], 'Http', [1, 1]);
  await document.setBibliographyStyle(-720, 720, 240, 0, [720], 1);
  nextResult = 2;
  await document.displayAlert('Apply changes?', 2, 3);
  nextResult = null;
  await field.select();
  await inserted.removeCode();
  await inserted.delete();
  await document.setDocumentData('<data/>');
  await document.activate();
  api.inProgress = true;
  await document.complete();
  assert.equal(api.inProgress, false);
  assert.deepEqual(transcript.find(t => t.command === 'Document.convert').arguments, ['fixture-document', ['f1', 'f2'], 'Http', [1, 1]]);
  assert.deepEqual(transcript.at(-1), {command: 'Document.complete', arguments: ['fixture-document'], result: null});
  return {source: sources.find(s => s.name === 'httpIntegrationClient.js'), cachedReadsIssueNoCommands: true, completeClearsInProgress: true, transcript};
}

(async () => {
  fs.mkdirSync(outputDir, {recursive: true});
  fs.writeFileSync(path.join(outputDir, 'processor-output.json'), JSON.stringify({schemaVersion: 1, processorVersion: CSL.PROCESSOR_VERSION, sources, scenarios}, null, 2) + '\n');
  const contract = await protocolContract();
  fs.writeFileSync(path.join(outputDir, 'protocol-contract.json'), JSON.stringify(contract, null, 2) + '\n');
  console.log(JSON.stringify({processorVersion: CSL.PROCESSOR_VERSION, sources: sources.length, scenarios: scenarios.length, formattedCitations: scenarios.reduce((sum, s) => sum + s.rendered.length, 0), protocolCommands: contract.transcript.length, result: 'passed'}));
})().catch(error => { console.error(error); process.exitCode = 1; });
