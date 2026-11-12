// Independent format-reader verification, not a browser rendering test.
import assert from 'node:assert/strict'
import {readFileSync, writeFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import {dirname, join, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'
const here = dirname(fileURLToPath(import.meta.url))
const require = createRequire(resolve(here, '../../crisp_ebook_reader/package.json'))
const {JSDOM} = require('jsdom')
const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>')
for (const name of ['document', 'HTMLElement', 'customElements', 'DOMParser',
    'XMLSerializer', 'Node', 'NodeFilter', 'Range', 'EventTarget', 'Event',
    'CustomEvent', 'ProcessingInstruction']) globalThis[name] = dom.window[name]
const {installReaderCompatibility} = await import('../../crisp_ebook_reader/assets/reader_compat.js')
installReaderCompatibility()
const {makeBook} = await import('../../crisp_ebook_reader/assets/foliate/view.js')
const {exportPublication} = await import('../../crisp_ebook_reader/assets/normalize.js')
const {safeResourceTransform, secureSections} = await import('../../crisp_ebook_reader/assets/security.js')
const directory = resolve(process.argv[2] ?? join(here, '../build/fictionbook'))
const expected = JSON.parse(readFileSync(join(directory, 'expected.json'), 'utf8'))
const roundtrip = process.argv[3] === '--roundtrip'
for (const filename of roundtrip ? ['roundtrip.fb2'] : ['fixture.fb2', 'fixture.fbz']) {
    const extension = filename.split('.').pop()
    const file = new File([readFileSync(join(directory, filename))], filename)
    const book = await makeBook(file)
    safeResourceTransform(book)
    const cleanup = secureSections(book)
    try {
        assert.equal(book.metadata.title, expected.title)
        assert.deepEqual(book.metadata.author, expected.authors)
        assert.equal(book.metadata.language, expected.language)
        assert.equal(book.sections.length, 3, 'Two chapters plus a separate notes body')
        const documents = await Promise.all(book.sections.map(section => section.createDocument()))
        const text = documents.map(document => document.documentElement.textContent).join('\n')
        const corrected = roundtrip ? 'Edited after FictionBook import — 東京.' : 'A corrected destination — 東京.'
        for (const phrase of ['bold & exact', 'italic', 'Footnote body', corrected,
            'Inside a nested section.', 'Text after the nested section', '3. Third item', '4. Fourth item']) {
            assert(text.includes(phrase), `Missing readable content: ${phrase}`)
        }
        assert(documents[0].querySelectorAll('strong, em, sup, sub, code').length >= 8)
        assert.equal(documents[0].querySelector('td').getAttribute('colspan'), '2')
        for (const document of documents) {
            for (const anchor of document.querySelectorAll('a[href]')) {
                const href = anchor.getAttribute('href')
                if (!href.startsWith('#')) continue
                const resolved = book.resolveHref(href)
                assert(Number.isInteger(resolved.index), `Unresolved internal link: ${href}`)
                assert(resolved.anchor(documents[resolved.index]), `Unresolved target: ${href}`)
            }
        }
        const cover = await book.getCover()
        assert.equal(Buffer.from(await cover.arrayBuffer()).toString('base64'), expected.image)
        const payload = await exportPublication(book, {filename, sourceFormat: extension})
        assert.equal(payload.readingOrder.length, 3)
        assert(payload.resources.some(resource => resource.mediaType === 'image/png' && resource.data === expected.image))
        assert(payload.resources.filter(resource => resource.mediaType === 'application/xhtml+xml')
            .some(resource => Buffer.from(resource.data, 'base64').toString().includes(corrected)))
        if (!roundtrip && extension === 'fb2') {
            writeFileSync(join(directory, 'imported.json'), JSON.stringify(payload))
        }
    } finally {
        cleanup()
        book.destroy?.()
    }
}
console.log('Foliate independently opened FB2 and FBZ, resolved links and notes, retained formatting/images, and imported both into editable publications.')
