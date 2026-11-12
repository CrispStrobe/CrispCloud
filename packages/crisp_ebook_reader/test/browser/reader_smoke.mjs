import assert from 'node:assert/strict'
import {createServer} from 'node:http'
import {readFileSync, existsSync, mkdtempSync, rmSync} from 'node:fs'
import {dirname, join, resolve, extname} from 'node:path'
import {tmpdir} from 'node:os'
import {fileURLToPath} from 'node:url'
import {spawnSync} from 'node:child_process'
import {createRequire} from 'node:module'
const require = createRequire(import.meta.url)
const {chromium} = require('playwright')
const here = dirname(fileURLToPath(import.meta.url))
const assets = resolve(here, '../../assets')
// Chromium creates a Unix-domain socket below TMPDIR. A repository-relative
// directory exceeds the socket path limit in GitHub's nested checkout path.
const temporary = mkdtempSync(join(tmpdir(), 'ce-'))
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
    // Exercise the production compatibility import in a real document before
    // any EPUB is parsed, as on WebKit versions without standard grouping.
    await page.addInitScript(() => { delete Object.groupBy; delete Map.groupBy })
    const unexpectedRequests = []
    const errors = []
    let currentCommand = 'startup'
    page.on('request', request => {
        if (/^https?:/.test(request.url()) && !request.url().startsWith(`http://127.0.0.1:${server.address().port}/`)) unexpectedRequests.push(request.url())
    })
    page.on('pageerror', error => {
        const diagnostic = `${currentCommand}: ${error.stack || error.message}`
        errors.push(diagnostic)
        console.error(diagnostic)
    })
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html#browser-test`)
    await page.waitForFunction(() => !!window.crispEbookHost)
    assert.deepEqual(await page.evaluate(() => [typeof Object.groupBy, typeof Map.groupBy]),
        ['function', 'function'], 'The host installs missing grouping APIs before book loading')
    await page.evaluate(() => {
        window.__messages = []
        window.addEventListener('crisp-ebook-message', event => window.__messages.push(event.detail))
    })
    let counter = 0
    const command = async (method, args = {}) => {
        currentCommand = method === 'open' ? `open ${args.filename}` : method
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
    assert.equal(info.supportsProgressSeeking, true)
    assert.equal(info.supportsNavigationHistory, true)
    assert.equal(info.supportsTextAppearance, true)
    assert.equal(info.supportsLayout, true)
    assert.equal(info.supportsPublisherStyles, true)
    const lastEvent = event => page.evaluate(name =>
        window.__messages.filter(message => message.event === name).at(-1)?.data, event)
    const waitForSection = index => page.waitForFunction(section =>
        window.__messages.filter(message => message.event === 'location').at(-1)?.data.sectionIndex === section, index)
    const initialLocation = await lastEvent('location')
    await command('next')
    await page.waitForFunction(cfi =>
        window.__messages.filter(message => message.event === 'location').at(-1)?.data.cfi !== cfi, initialLocation.cfi)
    const historyOrigin = await lastEvent('location')
    assert.equal((await lastEvent('history')).canGoBack, false, 'Page turns must not add Back entries')
    const tocEntries = items => items.flatMap(item => [item, ...tocEntries(item.children)])
    const secondChapter = tocEntries(info.toc).find(item => item.label === 'Second shelf')
    assert(secondChapter?.href)
    await command('goTo', {target:secondChapter.href})
    await waitForSection(1)
    assert.equal((await lastEvent('history')).canGoBack, true)
    const back = await command('historyBack')
    assert.deepEqual(back, {canGoBack:false, canGoForward:true})
    await waitForSection(0)
    assert(Math.abs((await lastEvent('location')).fraction - historyOrigin.fraction) < 0.03,
        'Back must restore the last reading position, not the chapter start')
    const forward = await command('historyForward')
    assert.deepEqual(forward, {canGoBack:true, canGoForward:false})
    await waitForSection(1)
    await command('historyBack')
    await waitForSection(0)
    await command('goToFraction', {fraction:1})
    await waitForSection(1)
    assert.equal((await lastEvent('history')).canGoForward, false, 'A new jump discards the forward branch')
    await assert.rejects(command('goToFraction', {fraction:'0.5'}), /finite/)
    await command('goToFraction', {fraction:0})
    await waitForSection(0)
    await command('goTo', {target:secondChapter.href})
    await waitForSection(1)
    const headingCfi = () => page.evaluate(() => {
        const view = document.querySelector('foliate-view')
        const {doc, index} = view.renderer.getContents()[0]
        const range = doc.createRange()
        range.selectNodeContents(doc.querySelector('h1'))
        return view.getCFI(index, range)
    })
    const anchorBeforeStyle = await headingCfi()
    const publisher = await command('appearance', {fontFamily:'monospace', usePublisherStyles:true,
        maxColumnCount:1, pageMargin:40, pageWidth:900})
    assert.equal(publisher.pageMargin, 40)
    const renderedOptions = () => page.evaluate(() => {
        const renderer = document.querySelector('foliate-view').renderer
        const doc = renderer.getContents()[0].doc
        return {columns:renderer.getAttribute('max-column-count'),
            margin:renderer.getAttribute('margin'), width:renderer.getAttribute('max-inline-size'),
            fontFamily:doc.defaultView.getComputedStyle(doc.body).fontFamily}
    })
    assert.deepEqual(await renderedOptions(), {columns:'1', margin:'40px', width:'900px', fontFamily:'serif'})
    await command('appearance', {usePublisherStyles:false})
    assert.equal((await renderedOptions()).fontFamily, 'monospace')
    assert.equal(await headingCfi(), anchorBeforeStyle, 'Appearance must preserve publication CFI nodes')
    await command('appearance', {usePublisherStyles:true})
    assert.equal((await renderedOptions()).fontFamily, 'serif')
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
    assert.equal(cbz.supportsProgressSeeking,true)
    assert.equal(cbz.supportsNavigationHistory,true)
    assert.equal(cbz.supportsTextAppearance,false)
    assert.equal(cbz.supportsLayout,false)
    assert.equal(cbz.supportsPublisherStyles,false)
    assert.deepEqual(await lastEvent('history'), {canGoBack:false,canGoForward:false})
    await command('goToFraction',{fraction:1})
    await waitForSection(1)
    await command('appearance',{flow:'scrolled',maxColumnCount:3,pageMargin:80})
    assert.equal(await page.evaluate(() =>
        document.querySelector('foliate-view').renderer.getAttribute('flow')),null,
        'Fixed-layout pages must not advertise or apply text pagination')
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
    console.log('PASS EPUB/FB2/CBZ render, TOC, search, progress/history, publisher styles, CFI-preserving appearance, fixed-layout capabilities, highlights, offline normalization, link/image/CSS preservation, script isolation and DRM rejection')
} finally {
    await browser?.close()
    await new Promise(resolve => server.close(resolve))
    rmSync(temporary,{recursive:true,force:true})
}
