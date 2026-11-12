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
const {safeResourceTransform,secureSections,sanitizeDocument,parseDocument,serializeDocument,sanitizeCss} = await import('../../assets/security.js')
const {exportPublication} = await import('../../assets/normalize.js')
const {imageDimensions} = await import('../../assets/image_dimensions.js')
const strictXhtml = (text, name = 'XHTML') => {
    const doc = new DOMParser().parseFromString(text,'application/xhtml+xml')
    const error = doc.querySelector('parsererror')
    assert.equal(error,null,`${name}: ${error?.textContent}`)
    return doc
}
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
    const htmlNamespaces = parseDocument('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Namespace fixture</title></head><body epub:type="chapter"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><title>Accessible SVG title</title><rect width="10" height="10"/></svg></body></html>','text/html')
    const namespaced = strictXhtml(serializeDocument(htmlNamespaces),'HTML namespace serialization')
    assert.equal(namespaced.documentElement.namespaceURI,'http://www.w3.org/1999/xhtml')
    assert.equal(namespaced.querySelector('body').getAttributeNS('http://www.idpf.org/2007/ops','type'),'chapter')
    assert.equal(namespaced.querySelector('svg').namespaceURI,'http://www.w3.org/2000/svg')
    assert.equal(namespaced.querySelector('svg title').textContent,'Accessible SVG title')
    // A truncated JPEG marker run must not abort normalization of the whole
    // book. Keep the resource and let the platform display its broken image.
    assert.equal(await imageDimensions(Uint8Array.from([0xff,0xd8,...Array(14).fill(0xff)]),'image/jpeg'),null)
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
                if (resource.mediaType === 'application/xhtml+xml') strictXhtml(text,resource.href)
            }
            if (ext === 'epub') {
                assert.equal(payload.metadata.title,'Crisp reader fixture')
                assert.equal(payload.toc[0].label,'Part One')
                assert.equal(payload.toc[0].href,'','A non-link TOC heading remains a group')
                assert.equal(payload.toc[0].children.length,1)
                assert.equal(payload.toc[0].children[0].children[0].label,'Second shelf')
                assert.deepEqual(payload.readingOrder.map(chapter => chapter.title),['The blue library','Second shelf'])
                assert(!payload.warnings.some(warning => warning.includes('navigation')))
                const styles = payload.resources.filter(item => item.mediaType === 'text/css')
                assert.equal(styles.length,3,'Every nested imported stylesheet is retained')
                const css = styles.map(item => Buffer.from(item.data,'base64').toString()).join('\n')
                assert.equal((css.match(/@import url\("asset-/g) ?? []).length,2,'Stylesheets keep relative imported resource links')
                assert(css.includes('#1f5947'))
                assert(css.includes('letter-spacing:0.1px'))
                assert(/url\("asset-[^"]+\.svg#clip"\)/.test(css),'SVG paint-server fragments survive normalization')
                const symbols = payload.resources.filter(item => item.mediaType === 'image/svg+xml')
                assert.equal(symbols.length,1,'Fragments share the same packaged SVG resource')
                assert(/href="asset-[^"]+\.png"/.test(Buffer.from(symbols[0].data,'base64').toString()),'SVG 2 images keep their packaged href')
                const first = payload.resources.find(item => item.href === 'chapters/0001.xhtml')
                const chapter = Buffer.from(first.data,'base64').toString()
                assert(chapter.includes('0002.xhtml#finish'))
                assert(/href="\.\.\/resources\/asset-[^"]+\.svg#mark"/.test(chapter),'SVG symbol target survives normalization')
                assert(/<image[^>]+href="\.\.\/resources\/asset-[^"]+\.png"/.test(chapter),'Inline SVG 2 images are retained')
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
                const text = Buffer.from(resource.data,'base64').toString()
                assert(!text.includes('blob:'),resource.href)
                if (resource.mediaType === 'application/xhtml+xml') {
                    const doc = strictXhtml(text,resource.href)
                    if (/\.(mobi|azw|azw3)$/i.test(path)) {
                        assert.equal(doc.querySelector('guide, [aid], [filepos], [recindex], [mediarecindex]'),null,'Kindle addressing fields are consumed after link rewriting')
                        assert(doc.querySelector('head > title'),'Converted Kindle chapters need a document title')
                        assert.equal(doc.querySelector('body > title, body > link, body > meta, link:not([href])'),null,'Legacy head metadata must not leak into prose')
                    }
                }
            }
            if (path.includes('crisp_ebook_conversion/test/fixtures/generated/')) {
                const rewritten = path.split('/').pop().startsWith('updated.')
                assert.equal(payload.metadata.title, rewritten
                    ? 'Updated café $(touch should-not-exist); literal' : 'Crisp Conversion Fixture')
                assert.deepEqual(payload.metadata.authors, rewritten
                    ? ['First Author','Second Author'] : ['Test Author'])
                const prose = payload.resources.filter(item => /xhtml/.test(item.mediaType))
                    .map(item => Buffer.from(item.data,'base64').toString()).join('\n')
                for (const phrase of ['First Chapter','Second Chapter','silver heron','café','Ωμέγα','日本語','forty-two'])
                    assert(prose.includes(phrase),`Kindling ${path} missing ${phrase}`)
                assert(payload.resources.some(item => item.mediaType === 'image/png'))
                const labels = items => items.flatMap(item => [item.label,...labels(item.children)])
                assert(labels(payload.toc).includes('The Answer'),`Kindling nested TOC anchor: ${JSON.stringify(payload.toc)}`)
                const entries = items => items.flatMap(item => [item,...entries(item.children)])
                const parent = entries(payload.toc).find(item => item.label === 'First Chapter')
                assert(parent && labels(parent.children).includes('The Answer'),`Kindling TOC hierarchy: ${JSON.stringify(payload.toc)}`)
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
