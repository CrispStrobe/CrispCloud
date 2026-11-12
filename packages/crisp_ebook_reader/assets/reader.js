import {makeBook} from './foliate/view.js'
import {Overlayer} from './foliate/overlayer.js'
import {safeResourceTransform, secureSections} from './security.js'
import {exportPublication, metadataOf} from './normalize.js'

const session = decodeURIComponent(location.hash.slice(1))
const status = document.getElementById('status')
let book = null, view = null, filename = '', sourceFormat = '', cleanupSections = null
let opened = false, appearance = {}, searchGeneration = 0
const highlights = new Map()
const expectedParent = location.origin
const serialize = value => JSON.stringify({...value, session, channel:'crisp-ebook-v1'})
const send = value => {
    const message = serialize(value)
    if (globalThis.flutter_inappwebview?.callHandler) {
        globalThis.flutter_inappwebview.callHandler('CrispEbookMessage', message).catch(() => {})
    } else if (typeof globalThis.CrispEbookMessage === 'function') {
        globalThis.CrispEbookMessage(JSON.parse(message))
    } else if (globalThis.CrispEbookMessage?.postMessage) {
        globalThis.CrispEbookMessage.postMessage(message)
    } else if (parent !== window) parent.postMessage(message, expectedParent)
    // Used by the local deterministic browser suite, never by a publication.
    window.dispatchEvent(new CustomEvent('crisp-ebook-message', {detail:JSON.parse(message)}))
}
const ready = () => send({event:'hostReady'})
const fail = error => {
    const message = error instanceof Error ? error.message : String(error)
    status.textContent = message
    status.hidden = false
    send({event:'error', data:message})
}
const tocOf = items => (items ?? []).map(item => ({label:String(item.label ?? ''), href:String(item.href ?? ''), children:tocOf(item.subitems)}))
const requireBook = () => { if (!book || !view) throw new Error('No book is open') }
const base64ToBytes = data => {
    if (typeof data !== 'string' || data.length > 180 * 1024 * 1024) throw new Error('Book exceeds the 128 MiB input limit')
    const binary = atob(data)
    if (binary.length > 128 * 1024 * 1024) throw new Error('Book exceeds the 128 MiB input limit')
    return Uint8Array.from(binary, character => character.charCodeAt(0))
}
function applyAppearance(options) {
    appearance = {...appearance, ...options}
    const fontSize = Math.min(48, Math.max(10, Number(appearance.fontSize) || 18))
    const lineHeight = Math.min(2.5, Math.max(1, Number(appearance.lineHeight) || 1.6))
    const colors = {light:['#ffffff','#243248','#245f9f'], sepia:['#f5eddb','#493c2c','#785024'], dark:['#19222e','#dce4ec','#96c9ff']}
    const [background, foreground, link] = colors[appearance.theme] ?? colors.light
    const fontFamily = ['serif','sans-serif','monospace'].includes(appearance.fontFamily) ? appearance.fontFamily : 'serif'
    document.body.style.background = background
    view?.renderer?.setAttribute('flow', appearance.flow === 'scrolled' ? 'scrolled' : 'paginated')
    view?.renderer?.setAttribute('max-column-count', '2')
    view?.renderer?.setAttribute('max-inline-size', '780px')
    view?.renderer?.setAttribute('margin', '24px')
    view?.renderer?.setStyles?.(`html, body { background: ${background}; color: ${foreground}; }
        html { font-size: ${fontSize}px !important; } body { font-family: ${fontFamily}; }
        p, li, blockquote, dd { line-height: ${lineHeight}; } a { color: ${link}; }
        img, svg { max-width: 100%; } pre { white-space: pre-wrap; }`)
}
async function open(args) {
    opened = true
    if (view) { view.close(); view.remove() }
    cleanupSections?.()
    book?.destroy?.()
    book = null
    highlights.clear()
    filename = String(args.filename || 'book.epub').slice(0, 512)
    const suffix = filename.toLowerCase().split('.').pop()
    if (!['epub','mobi','azw','azw3','fb2','fbz','cbz'].includes(suffix)) throw new Error('Unsupported ebook format. KFX and DRM-protected books are not supported.')
    sourceFormat = suffix === 'azw' ? 'mobi' : suffix === 'fbz' ? 'fb2' : suffix
    status.textContent = 'Opening book…'; status.hidden = false
    const bytes = base64ToBytes(args.data)
    if (new TextDecoder().decode(bytes.subarray(0, 5)) === '%PDF-') throw new Error('Open PDF files in the PDF viewer instead.')
    book = await makeBook(new File([bytes], filename.toLowerCase()))
    if (!book.sections?.length) throw new Error('This publication contains no readable sections')
    if (book.sections.length > 10000) throw new Error('This book exceeds the 10,000 chapter limit')
    safeResourceTransform(book)
    cleanupSections = secureSections(book)
    view = document.createElement('foliate-view')
    document.getElementById('reader').append(view)
    view.addEventListener('external-link', event => {
        event.preventDefault()
        const href = String(event.detail.href_ ?? '')
        if (/^(https?:|mailto:)/i.test(href)) send({event:'externalLink', data:href})
    })
    view.addEventListener('load', ({detail:{doc,index}}) => {
        let selectionTimer
        doc.addEventListener('selectionchange', () => {
            clearTimeout(selectionTimer)
            selectionTimer = setTimeout(() => {
                const selection = doc.getSelection()
                if (!selection?.rangeCount || selection.isCollapsed) return
                send({event:'selection', data:{text:selection.toString().slice(0, 20000),
                    cfi:view.getCFI(index, selection.getRangeAt(0)), sectionIndex:index}})
            }, 150)
        })
        doc.addEventListener('keydown', event => {
            if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return
            if (event.key === 'ArrowRight') { event.preventDefault(); view.goRight() }
            if (event.key === 'ArrowLeft') { event.preventDefault(); view.goLeft() }
        })
    })
    view.addEventListener('relocate', ({detail}) => send({event:'location', data:{
        cfi:detail.cfi, fraction:Number.isFinite(detail.fraction) ? detail.fraction : 0,
        chapterTitle:detail.tocItem?.label ?? '', sectionIndex:detail.section?.current ?? 0}}))
    view.addEventListener('draw-annotation', ({detail:{draw,annotation}}) => draw(Overlayer.highlight, {color:annotation.color}))
    view.addEventListener('create-overlay', () => {
        requestAnimationFrame(() => { for (const annotation of highlights.values()) view.addAnnotation(annotation).catch(() => {}) })
    })
    await view.open(book)
    applyAppearance(args.appearance ?? {})
    await view.init({lastLocation:args.initialLocation || undefined, showTextStart:false})
    status.hidden = true
    const info = {...metadataOf(book, filename), toc:tocOf(book.toc), sectionCount:book.sections.length,
        sourceFormat, fixedLayout:view.isFixedLayout, warnings:[]}
    send({event:'ready', data:info})
    return info
}
async function search({query,limit = 200}) {
    requireBook()
    const generation = ++searchGeneration
    query = String(query ?? '').trim().slice(0, 1000)
    if (!query) { view.clearSearch(); return [] }
    const hits = []
    for await (const result of view.search({query, matchCase:false, matchDiacritics:false, matchWholeWords:false})) {
        if (generation !== searchGeneration) break
        for (const match of result.subitems ?? []) {
            const excerpt = typeof match.excerpt === 'string' ? match.excerpt
                : [match.excerpt?.pre, match.excerpt?.match, match.excerpt?.post].filter(Boolean).join('')
            hits.push({cfi:match.cfi, excerpt, sectionIndex:result.index})
            if (hits.length >= Math.min(1000, Math.max(1, limit))) return hits
        }
    }
    return hits
}
const methods = {
    open,
    next:async () => { requireBook(); await view.next() },
    previous:async () => { requireBook(); await view.prev() },
    goTo:async ({target}) => { requireBook(); await view.goTo(target) },
    goToFraction:async ({fraction}) => { requireBook(); await view.goToFraction(Math.max(0, Math.min(1, Number(fraction) || 0))) },
    appearance:async args => applyAppearance(args),
    search,
    clearSearch:async () => { requireBook(); ++searchGeneration; view.clearSearch() },
    addHighlight:async ({id,cfi,color,note}) => {
        requireBook()
        if (typeof id !== 'string' || typeof cfi !== 'string' || !cfi.startsWith('epubcfi(')) throw new Error('Invalid annotation')
        const annotation = {id, value:cfi, color:/^#[0-9a-f]{6}$/i.test(color ?? '') ? color : '#f9d66b', note:String(note ?? '').slice(0,10000)}
        highlights.set(id, annotation)
        await view.addAnnotation(annotation)
    },
    removeHighlight:async ({id}) => {
        requireBook()
        const annotation = highlights.get(id)
        if (annotation) await view.deleteAnnotation(annotation)
        highlights.delete(id)
    },
    exportPublication:async () => { requireBook(); return exportPublication(book, {filename,sourceFormat}) },
}
async function receive(message) {
    if (!message || message.session !== session || message.channel !== 'crisp-ebook-v1' || typeof message.id !== 'number') return
    const {id, method, args = {}} = message
    try {
        if (!Object.hasOwn(methods, method)) throw new Error('Unknown ebook command')
        const data = await methods[method](args)
        send({id, result:data ?? null})
    } catch (error) {
        const description = error instanceof Error ? error.message : String(error)
        send({id, error:description})
        if (method === 'open') fail(error)
    }
}
Object.defineProperty(window, 'crispEbookHost', {value:Object.freeze({receive,ready}), writable:false, configurable:false})
window.addEventListener('message', event => {
    if (event.source !== parent || event.origin !== expectedParent) return
    try { receive(typeof event.data === 'string' ? JSON.parse(event.data) : event.data) } catch { /* ignore unrelated frames */ }
})
window.addEventListener('unhandledrejection', event => {
    if (!opened) fail(event.reason)
})
window.addEventListener('pagehide', () => { cleanupSections?.(); book?.destroy?.() })
// Native JS channels may be installed after the module has evaluated.
ready()
const readyTimer = setInterval(() => { if (opened) clearInterval(readyTimer); else ready() }, 400)
