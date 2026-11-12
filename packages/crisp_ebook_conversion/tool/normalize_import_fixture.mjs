import assert from 'node:assert/strict'
import {createHash} from 'node:crypto'
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs'
import {createRequire} from 'node:module'
import {basename,join,resolve} from 'node:path'
import {pathToFileURL} from 'node:url'

const [repoArg,outputArg,...sourceArgs] = process.argv.slice(2)
assert(repoArg && outputArg && sourceArgs.length,'usage: normalize_import_fixture.mjs REPO OUTPUT SOURCE...')
const repo = resolve(repoArg)
const output = resolve(outputArg)
mkdirSync(output,{recursive:true})
const reader = join(repo,'packages/crisp_ebook_reader')
const require = createRequire(join(reader,'package.json'))
const {JSDOM} = require('jsdom')
const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>')
// Like parser_smoke, jsdom has no layout engine; fixture labels are plain text.
Object.defineProperty(dom.window.HTMLElement.prototype,'innerText',{
    get() { return this.textContent }, set(value) { this.textContent = value },
})
for (const name of ['document','HTMLElement','customElements','DOMParser','XMLSerializer','Node','NodeFilter','Range','EventTarget','Event','CustomEvent','ProcessingInstruction']) globalThis[name] = dom.window[name]
globalThis.CSS = {escape:value => String(value).replace(/[^a-z0-9_-]/gi,char => `\\${char}`)}
const {makeBook} = await import(pathToFileURL(join(reader,'assets/foliate/view.js')))
const {safeResourceTransform,secureSections} = await import(pathToFileURL(join(reader,'assets/security.js')))
const {exportPublication} = await import(pathToFileURL(join(reader,'assets/normalize.js')))
const digest = data => createHash('sha256').update(data).digest('hex')
const entries = items => items.flatMap(item => [item,...entries(item.children ?? [])])
const results = []
try {
    for (const sourceArg of sourceArgs) {
        const source = resolve(sourceArg)
        const bytes = readFileSync(source)
        const before = digest(bytes)
        const filename = basename(source)
        const book = await makeBook(new File([bytes],filename))
        safeResourceTransform(book)
        const cleanup = secureSections(book)
        try {
            const payload = await exportPublication(book,{filename,sourceFormat:filename.split('.').pop()})
            const rewritten = filename.startsWith('updated.')
            assert.equal(payload.metadata.title,rewritten ? 'Updated café $(touch should-not-exist); literal' : 'Crisp Conversion Fixture')
            assert.deepEqual(payload.metadata.authors,rewritten ? ['First Author','Second Author'] : ['Test Author'])
            assert(payload.readingOrder.length >= 2)
            assert(payload.resources.some(item => item.mediaType === 'image/png'))
            const parent = entries(payload.toc).find(item => item.label === 'First Chapter')
            assert(parent && entries(parent.children).some(item => item.label === 'The Answer'),'Nested TOC hierarchy')
            const prose = payload.resources.filter(item => /xhtml/.test(item.mediaType)).map(item => Buffer.from(item.data,'base64').toString()).join('\n')
            for (const phrase of ['First Chapter','Second Chapter','silver heron','café','Ωμέγα','日本語','forty-two']) assert(prose.includes(phrase),`Missing ${phrase}`)
            assert(/href="\d+\.xhtml#/.test(prose),'Cross-chapter link')
            const json = join(output,`${filename}.publication.json`)
            writeFileSync(json,JSON.stringify(payload,null,2)+'\n')
            assert.equal(digest(readFileSync(source)),before,'Source bytes preserved by normalization')
            const result = {source,sourceSha256:before,publication:json,chapters:payload.readingOrder.length,resources:payload.resources.length,warnings:payload.warnings}
            results.push(result)
            console.log(JSON.stringify(result))
        } finally {cleanup();book.destroy?.()}
    }
    writeFileSync(join(output,'source-baselines.json'),JSON.stringify(results,null,2)+'\n')
} finally {dom.window.close()}
