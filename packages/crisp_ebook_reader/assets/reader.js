import './reader_compat.js'
import {makeBook} from './foliate/view.js'
import {Overlayer} from './foliate/overlayer.js'
import {safeResourceTransform, secureSections} from './security.js'
import {exportPublication, metadataOf} from './normalize.js'
import {normalizeAppearance, appearanceStyle, readingCapabilities, progressFraction,
    navigationHistory, navigateHistory, createNavigationQueue,
    guardRendererLifecycle, readerKeyDirection} from './reader_controls.js'
import {createReaderSearch} from './reader_search.js'
import {createReaderSelection} from './reader_selection.js'

const session = decodeURIComponent(location.hash.slice(1))
const status = document.getElementById('status')
let book = null, view = null, filename = '', sourceFormat = '', cleanupSections = null
let opened = false, appearance = normalizeAppearance(), searchSession = null
let selectionObserver = null
const highlights = new Map()
const enqueueNavigation = createNavigationQueue()
const navigationMethods = new Set(['open','next','previous','goTo','goToFraction',
    'historyBack','historyForward','appearance','hostKey'])
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
    appearance = normalizeAppearance({...appearance, ...options})
    const {background, styles, attributes} = appearanceStyle(appearance)
    document.body.style.background = background
    const capabilities = readingCapabilities(view)
    if (capabilities.supportsLayout) {
        for (const [name, value] of Object.entries(attributes))
            if (view.renderer.getAttribute(name) !== value)
                view.renderer.setAttribute(name, value)
    }
    if (capabilities.supportsTextAppearance) view.renderer.setStyles(styles)
    // Column limits and margins do not always resize the outer host. Render
    // explicitly so the paginator restores its current range after reflow.
    if (capabilities.supportsLayout) view.renderer.render?.()
    return appearance
}
async function open(args) {
    opened = true
    searchSession?.dispose()
    searchSession = null
    selectionObserver?.dispose()
    selectionObserver = null
    const previousView = view
    view = null
    if (previousView) { previousView.close(); previousView.remove() }
    cleanupSections?.()
    book?.destroy?.()
    book = null
    appearance = normalizeAppearance(args.appearance)
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
    const currentView = view
    searchSession = createReaderSearch(currentView)
    selectionObserver = createReaderSelection(currentView,
        data => send({event:'selection', data}), {isCurrent:() => view === currentView})
    currentView.history.addEventListener('index-change', () => {
        if (view === currentView)
            send({event:'history', data:navigationHistory(currentView)})
    })
    view.addEventListener('external-link', event => {
        event.preventDefault()
        if (view !== currentView) return
        const href = String(event.detail.href_ ?? '')
        if (/^(https?:|mailto:)/i.test(href)) send({event:'externalLink', data:href})
    })
    view.addEventListener('load', ({detail:{doc}}) => {
        if (view !== currentView) return
        doc.addEventListener('keydown', event => {
            const direction = readerKeyDirection(event)
            if (direction) {
                event.preventDefault()
                enqueueNavigation(() => view === currentView ? currentView[direction]() : null)
                    .catch(() => {})
            }
        })
    })
    view.addEventListener('relocate', ({detail}) => {
        if (view === currentView) send({event:'location', data:{
            cfi:detail.cfi, fraction:Number.isFinite(detail.fraction) ? progressFraction(detail.fraction) : 0,
            chapterTitle:detail.tocItem?.label ?? '', sectionIndex:detail.section?.current ?? 0}})
    })
    view.addEventListener('draw-annotation', ({detail:{draw,annotation}}) => draw(Overlayer.highlight, {color:annotation.color}))
    view.addEventListener('create-overlay', () => {
        requestAnimationFrame(() => {
            if (view !== currentView) return
            for (const annotation of highlights.values()) currentView.addAnnotation(annotation).catch(() => {})
        })
    })
    await view.open(book)
    guardRendererLifecycle(view)
    applyAppearance(args.appearance ?? {})
    await view.init({lastLocation:args.initialLocation || undefined, showTextStart:false})
    status.hidden = true
    const info = {...metadataOf(book, filename), toc:tocOf(book.toc), sectionCount:book.sections.length,
        sourceFormat, fixedLayout:view.isFixedLayout, warnings:[], ...readingCapabilities(view)}
    send({event:'history', data:navigationHistory(view)})
    send({event:'ready', data:info})
    return info
}
async function search({query,limit = 200}) {
    requireBook()
    return searchSession.search({query, limit})
}
const methods = {
    open,
    next:async () => { requireBook(); await view.next() },
    previous:async () => { requireBook(); await view.prev() },
    // Native texture hosts cannot rely on WebKit invoking listeners installed
    // in a script-disabled book. This uses the same authenticated command
    // envelope and navigation queue; the host suppresses duplicate GDK keys.
    hostKey:async args => {
        const direction = readerKeyDirection(args)
        if (!direction || !book || !view?.renderer) return false
        await view[direction]()
        return true
    },
    goTo:async ({target}) => { requireBook(); await view.goTo(target) },
    goToFraction:async ({fraction}) => {
        requireBook()
        if (!readingCapabilities(view).supportsProgressSeeking)
            throw new Error('Progress seeking is unavailable for this publication')
        await view.goToFraction(progressFraction(fraction))
    },
    historyBack:async () => { requireBook(); return navigateHistory(view, 'back') },
    historyForward:async () => { requireBook(); return navigateHistory(view, 'forward') },
    appearance:async args => applyAppearance(args),
    search,
    clearSearch:async () => { requireBook(); searchSession.clear() },
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
        const data = await (navigationMethods.has(method)
            ? enqueueNavigation(() => methods[method](args)) : methods[method](args))
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
window.addEventListener('pagehide', () => {
    searchSession?.dispose()
    selectionObserver?.dispose()
    cleanupSections?.()
    book?.destroy?.()
    view = null
})
// Native JS channels may be installed after the module has evaluated.
ready()
const readyTimer = setInterval(() => { if (opened) clearInterval(readyTimer); else ready() }, 400)
