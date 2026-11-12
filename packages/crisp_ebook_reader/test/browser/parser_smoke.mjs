// DOM/parser integration coverage, usable where a browser cannot be launched.
// This is not a substitute for the separate actual-browser rendering suite.
import assert from 'node:assert/strict'
import {readFileSync,mkdtempSync,rmSync} from 'node:fs'
import {dirname,join,resolve} from 'node:path'
import {fileURLToPath} from 'node:url'
import {createRequire} from 'node:module'
import {spawnSync} from 'node:child_process'
const require = createRequire(import.meta.url)
const {JSDOM} = require('jsdom')
if (process.env.CRISP_TEST_RAW_INFLATE_FALLBACK === '1') globalThis.DecompressionStream = undefined
const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>')
// jsdom has no layout engine and omits innerText. These fixtures contain plain
// TOC labels, so textContent is sufficient for parser-level MOBI6 assertions.
Object.defineProperty(dom.window.HTMLElement.prototype,'innerText',{
    get() { return this.textContent }, set(value) { this.textContent = value },
})
for (const name of ['document','HTMLElement','customElements','DOMParser','XMLSerializer','Node','NodeFilter','Range','EventTarget','Event','CustomEvent','ProcessingInstruction']) globalThis[name] = dom.window[name]
globalThis.CSS = {escape:value => String(value).replace(/[^a-z0-9_-]/gi, char => `\\${char}`)}
const {makeBook} = await import('../../assets/foliate/view.js')
const {safeResourceTransform,secureSections,sanitizeDocument,parseDocument,sanitizeCss} = await import('../../assets/security.js')
const {exportPublication} = await import('../../assets/normalize.js')
const here = dirname(fileURLToPath(import.meta.url))
const temporary = mkdtempSync(join(here,'.tmp-'))
const generated = spawnSync('python3',[join(here,'make_fixtures.py'),temporary],{encoding:'utf8'})
assert.equal(generated.status,0,generated.stderr)
const open = async path => {
    const book = await makeBook(new File([readFileSync(path)],path.split('/').pop()))
    safeResourceTransform(book)
    return {book,cleanup:secureSections(book)}
}
try {
    const safe = sanitizeDocument(parseDocument('<html><body><script>alert(1)</script><p onclick="evil()">Hello</p><img src="https://invalid.test/pixel"/><iframe srcdoc="x"/></body></html>','text/html'))
    assert.equal(safe.querySelectorAll('script,iframe,[onclick],img[src]').length,0)
    assert(safe.querySelector('meta[http-equiv="Content-Security-Policy"]').getAttribute('content').includes("script-src 'none'"))
    for (const source of ["@import 'blob:https://reader.test/style';", '@import url("blob:https://reader.test/style") screen;']) {
        assert(sanitizeCss(source).includes('blob:https://reader.test/style'),'Packaged CSS imports must survive sanitation')
    }
    for (const source of ['@import "https://tracker.test/a.css";', '@import url(https://tracker.test/a.css);', '@import "data:text/css;base64,eA==";']) {
        assert.equal(sanitizeCss(source),'','Remote and unmaterialized CSS imports must be omitted')
    }
    for (const ext of ['epub','fb2','cbz']) {
        const path = join(temporary,`fixture.${ext}`)
        const {book,cleanup} = await open(path)
        try {
            const payload = await exportPublication(book,{filename:`fixture.${ext}`,sourceFormat:ext})
            assert.equal(payload.readingOrder.length,2)
            assert(payload.resources.some(resource => resource.mediaType === 'image/png'))
            for (const resource of payload.resources.filter(item => /xhtml|css/.test(item.mediaType))) {
                const text = Buffer.from(resource.data,'base64').toString()
                assert(!text.includes('blob:'), resource.href)
                assert(!/<script|onerror=|<iframe/i.test(text),resource.href)
            }
            if (ext === 'epub') {
                assert.equal(payload.metadata.title,'Crisp reader fixture')
                assert.equal(payload.toc[0].children.length,1)
                const styles = payload.resources.filter(item => item.mediaType === 'text/css')
                assert.equal(styles.length,3,'Every nested imported stylesheet is retained')
                const css = styles.map(item => Buffer.from(item.data,'base64').toString()).join('\n')
                assert.equal((css.match(/@import url\("asset-/g) ?? []).length,2,'Stylesheets keep relative imported resource links')
                assert(css.includes('#1f5947'))
                assert(css.includes('letter-spacing:0.1px'))
                const first = payload.resources.find(item => item.href === 'chapters/0001.xhtml')
                assert(Buffer.from(first.data,'base64').toString().includes('0002.xhtml#finish'))
            }
            if (ext === 'cbz') {
                assert.equal(payload.layout,'pre-paginated')
                for (const page of payload.resources.filter(item => /xhtml/.test(item.mediaType)))
                    assert(Buffer.from(page.data,'base64').toString().includes('name="viewport"'))
            }
            console.log(`PASS ${ext}: ${payload.readingOrder.length} chapters, ${payload.resources.length} resources; ${payload.warnings.length} warnings`)
        } finally {cleanup(); book.destroy?.()}
    }
    await assert.rejects(open(join(temporary,'encrypted.epub')),/DRM-protected/)
    for (const path of process.argv.slice(2)) {
        const {book,cleanup} = await open(resolve(path))
        try {
            const payload = await exportPublication(book,{filename:path.split('/').pop(),sourceFormat:path.split('.').pop()})
            assert(payload.readingOrder.length > 0)
            assert(payload.resources.some(item => item.mediaType === 'application/xhtml+xml'))
            for (const resource of payload.resources.filter(item => /xhtml|css/.test(item.mediaType))) {
                assert(!Buffer.from(resource.data,'base64').toString().includes('blob:'),resource.href)
            }
            if (path.includes('crisp_ebook_conversion/test/fixtures/generated/')) {
                assert.equal(payload.metadata.title,'Crisp Conversion Fixture')
                assert.deepEqual(payload.metadata.authors,['Test Author'])
                const prose = payload.resources.filter(item => /xhtml/.test(item.mediaType))
                    .map(item => Buffer.from(item.data,'base64').toString()).join('\n')
                for (const phrase of ['First Chapter','Second Chapter','silver heron','café','Ωμέγα','日本語','forty-two'])
                    assert(prose.includes(phrase),`Kindling ${path} missing ${phrase}`)
                assert(payload.resources.some(item => item.mediaType === 'image/png'))
                const labels = items => items.flatMap(item => [item.label,...labels(item.children)])
                assert(labels(payload.toc).includes('The Answer'),`Kindling nested TOC anchor: ${JSON.stringify(payload.toc)}`)
                assert(/href="\d+\.xhtml#/.test(prose),'Kindling cross-chapter link')
            }
            console.log(`PASS ${path}: ${payload.readingOrder.length} chapters, ${payload.resources.length} resources; ${payload.warnings.length} warnings`)
        } finally {cleanup(); book.destroy?.()}
    }
    // Verify upstream renderer patches keep the browser sandbox independent of
    // DOM sanitation. Actual execution probes live in reader_smoke.mjs.
    for (const name of ['paginator.js','fixed-layout.js']) {
        const source = readFileSync(resolve(here,'../../assets/foliate',name),'utf8')
        assert(source.includes("setAttribute('sandbox', 'allow-same-origin')"))
        assert(!source.includes("setAttribute('sandbox', 'allow-same-origin allow-scripts')"))
    }
    console.log('PASS DOM sanitation, offline normalized EPUB/FB2/CBZ resource graph, nested TOC, cross-chapter links, Unicode, script-disabled frame configuration and encrypted EPUB rejection')
} finally {rmSync(temporary,{recursive:true,force:true}); dom.window.close()}
