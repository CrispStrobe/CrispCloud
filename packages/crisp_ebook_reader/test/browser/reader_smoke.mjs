import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {readFileSync, existsSync, mkdtempSync, rmSync} from 'node:fs'
import {dirname, join, resolve, extname} from 'node:path'
import {fileURLToPath} from 'node:url'
import {spawnSync} from 'node:child_process'
import {createRequire} from 'node:module'
const require = createRequire(import.meta.url)
const {chromium} = require('playwright')
const here = dirname(fileURLToPath(import.meta.url))
const assets = resolve(here, '../../assets')
const temporary = mkdtempSync(join(here, '.tmp-'))
process.env.TMPDIR = temporary
const generated = spawnSync('python3', [join(here,'make_fixtures.py'),temporary], {encoding:'utf8'})
assert.equal(generated.status, 0, generated.stderr)
let browser
const server = createServer((request,response) => {
    const pathname = new URL(request.url, 'http://localhost').pathname
    if (pathname === '/sandbox-probe.js') {
        response.setHeader('Content-Type','application/javascript')
        response.end('parent.__sandboxEscape = true; parent.localStorage.setItem("crisp-sandbox-escape", "true");')
        return
    }
    const path = resolve(assets, '.' + pathname)
    if (!path.startsWith(assets + '/') || !existsSync(path)) { response.writeHead(404); response.end(); return }
    response.setHeader('Content-Type', {'.html':'text/html','.js':'application/javascript','.css':'text/css'}[extname(path)] ?? 'application/octet-stream')
    response.end(readFileSync(path))
})
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve))
try {
    browser = await chromium.launch({headless:true, executablePath:process.env.CHROMIUM_PATH || '/usr/bin/chromium'})
    const page = await browser.newPage({viewport:{width:1100,height:760}})
    const unexpectedRequests = []
    const errors = []
    page.on('request', request => {
        if (/^https?:/.test(request.url()) && !request.url().startsWith(`http://127.0.0.1:${server.address().port}/`)) unexpectedRequests.push(request.url())
    })
    page.on('pageerror', error => errors.push(error.message))
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html#browser-test`)
    await page.waitForFunction(() => !!window.crispEbookHost)
    await page.evaluate(() => {
        window.__messages = []
        window.addEventListener('crisp-ebook-message', event => window.__messages.push(event.detail))
    })
    let counter = 0
    const command = async (method, args = {}) => {
        const id = ++counter
        await page.evaluate(message => window.crispEbookHost.receive(message), {id,method,args,session:'browser-test',channel:'crisp-ebook-v1'})
        await page.waitForFunction(id => window.__messages.some(message => message.id === id), id, {timeout:90000})
        const message = await page.evaluate(id => window.__messages.find(message => message.id === id), id)
        if (message.error) throw new Error(message.error)
        return message.result
    }
    const open = path => command('open', {filename:path.split('/').pop(),data:readFileSync(path).toString('base64')})
    const info = await open(join(temporary,'fixture.epub'))
    assert.equal(info.title, 'Crisp reader fixture')
    assert.equal(info.sectionCount, 2)
    assert.equal(info.toc[0].children.length, 1)
    const frames = page.frames().filter(frame => frame.url().startsWith('blob:'))
    assert(frames.length > 0,'Publication must render in a dedicated frame')
    for (const frame of frames) {
        const element = await frame.frameElement()
        const sandbox = (await element.getAttribute('sandbox')).split(/\s+/)
        assert(sandbox.includes('allow-same-origin'))
        assert(!sandbox.includes('allow-scripts'),'Publication scripts must stay sandbox-disabled')
    }
    // Bypass sanitation entirely in an isolated test frame. A same-origin
    // external script is permitted by the host CSP, so the frame sandbox must
    // independently prevent storage access even with attacker-controlled HTML.
    await page.evaluate(() => {
        const probe = document.createElement('iframe')
        probe.setAttribute('sandbox','allow-same-origin')
        probe.src = URL.createObjectURL(new Blob([
            `<html><body><script src="${location.origin}/sandbox-probe.js"><\/script><svg onload="parent.__sandboxEscape = true"></svg></body></html>`
        ],{type:'text/html'}))
        probe.hidden = true
        document.body.append(probe)
        window.__sandboxProbe = probe
    })
    await page.waitForTimeout(200)
    assert.equal(await page.evaluate(() => window.__sandboxEscape),undefined)
    assert.equal(await page.evaluate(() => localStorage.getItem('crisp-sandbox-escape')),null)
    await page.evaluate(() => { URL.revokeObjectURL(window.__sandboxProbe.src); window.__sandboxProbe.remove() })
    const hits = await command('search',{query:'library',limit:10})
    assert(hits.length > 0)
    assert(hits[0].cfi.startsWith('epubcfi('))
    await command('goTo',{target:info.toc[0].children[0].href})
    await command('appearance',{theme:'dark',fontSize:22,flow:'scrolled'})
    await command('addHighlight',{id:'fixture',cfi:hits[0].cfi,color:'#f9d66b'})
    await command('removeHighlight',{id:'fixture'})
    const publication = await command('exportPublication')
    assert.equal(publication.schemaVersion,1)
    assert.equal(publication.readingOrder.length,2)
    assert(publication.resources.some(resource => resource.mediaType === 'image/png'))
    assert.equal(publication.resources.filter(resource => resource.mediaType === 'text/css').length,3,'Nested imported stylesheets are retained')
    for (const resource of publication.resources.filter(resource => resource.mediaType === 'application/xhtml+xml')) {
        const text = Buffer.from(resource.data,'base64').toString()
        assert(!text.includes('blob:'))
        assert(!/<script|onerror=|<iframe/i.test(text))
    }
    assert.equal(await page.evaluate(() => window.__bookScriptRan),undefined)
    assert.deepEqual(unexpectedRequests,[])
    const one = publication.resources.find(resource => resource.href === 'chapters/0001.xhtml')
    assert(Buffer.from(one.data,'base64').toString().includes('0002.xhtml#finish'))
    const fb2 = await open(join(temporary,'fixture.fb2'))
    assert.equal(fb2.title,'FB2 local fixture')
    const fb2Export = await command('exportPublication')
    assert.equal(fb2Export.readingOrder.length,2)
    assert(fb2Export.resources.some(resource => resource.mediaType === 'image/png'))
    assert(fb2Export.resources.filter(resource => /xhtml|css/.test(resource.mediaType)).every(resource => !Buffer.from(resource.data,'base64').toString().includes('blob:')))
    const cbz = await open(join(temporary,'fixture.cbz'))
    assert.equal(cbz.fixedLayout,true)
    const cbzExport = await command('exportPublication')
    assert.equal(cbzExport.readingOrder.length,2)
    assert.equal(cbzExport.layout,'pre-paginated')
    await assert.rejects(open(join(temporary,'encrypted.epub')),/DRM-protected/)
    for (const file of process.argv.slice(2)) {
        const info = await open(resolve(file))
        const payload = await command('exportPublication')
        assert(info.sectionCount > 0)
        assert(payload.resources.length > 0)
        assert(payload.resources.filter(resource => /xhtml|css/.test(resource.mediaType)).every(resource => !Buffer.from(resource.data,'base64').toString().includes('blob:')))
        console.log(`PASS ${file}: ${info.sectionCount} chapters, ${payload.resources.length} resources, ${payload.warnings.length} warnings`)
    }
    assert.deepEqual(errors,[], errors.join('\n'))
    console.log('PASS EPUB/FB2/CBZ render, TOC, search, navigation, themes, highlights, offline normalization, link/image/CSS preservation, script isolation and DRM rejection')
} finally {
    await browser?.close()
    await new Promise(resolve => server.close(resolve))
    rmSync(temporary,{recursive:true,force:true})
}
