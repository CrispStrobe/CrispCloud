// Host-controlled reading options. No publication CSS or script is accepted
// through this API; every interpolated value is bounded or allowlisted here.
const number = (value, fallback, min, max) =>
    typeof value === 'number' && Number.isFinite(value)
        ? Math.max(min, Math.min(max, value)) : fallback

export function normalizeAppearance(options = {}) {
    options = options && typeof options === 'object' ? options : {}
    return {
        fontSize:number(options.fontSize, 18, 10, 48),
        lineHeight:number(options.lineHeight, 1.6, 1, 2.5),
        theme:['light','sepia','dark'].includes(options.theme) ? options.theme : 'light',
        flow:options.flow === 'scrolled' ? 'scrolled' : 'paginated',
        fontFamily:['serif','sans-serif','monospace'].includes(options.fontFamily)
            ? options.fontFamily : 'serif',
        maxColumnCount:Math.trunc(number(options.maxColumnCount, 2, 1, 3)),
        pageMargin:number(options.pageMargin, 24, 0, 96),
        pageWidth:number(options.pageWidth, 780, 320, 1600),
        usePublisherStyles:typeof options.usePublisherStyles === 'boolean'
            ? options.usePublisherStyles : true,
    }
}

export function appearanceStyle(options) {
    const value = normalizeAppearance(options)
    const palettes = {
        light:['#ffffff','#243248','#245f9f'],
        sepia:['#f5eddb','#493c2c','#785024'],
        dark:['#19222e','#dce4ec','#96c9ff'],
    }
    const [background, foreground, link] = palettes[value.theme]
    // Foliate inserts the first sheet before publication styles, and the
    // second after them. This preserves book nodes, inline styling and CFIs.
    const defaults = `body { font-family: ${value.fontFamily}; font-size: 1rem; }
        p, li, blockquote, dd { line-height: ${value.lineHeight}; }`
    const theme = `html { font-size: ${value.fontSize}px !important;
            color-scheme: ${value.theme === 'dark' ? 'dark' : 'light'}; }
        html, body { background: ${background} !important; color: ${foreground} !important; }
        a { color: ${link} !important; }
        img, svg { max-width: 100%; } pre { white-space: pre-wrap; }`
    const typography = value.usePublisherStyles ? '' : `
        body, p, li, blockquote, dd, dt, div, span, h1, h2, h3, h4, h5, h6 {
            font-family: ${value.fontFamily} !important;
        }
        body, p, li, blockquote, dd, dt { font-size: 1rem !important; }
        p, li, blockquote, dd { line-height: ${value.lineHeight} !important; }
        pre, pre *, code, code *, kbd, kbd *, samp, samp * { font-family: monospace !important; }`
    return {background, styles:[defaults, theme + typography], attributes:{
        flow:value.flow,
        'max-column-count':String(value.maxColumnCount),
        'max-inline-size':`${value.pageWidth}px`,
        margin:`${value.pageMargin}px`,
    }}
}

export function readingCapabilities(view) {
    const fractions = view?.getSectionFractions?.() ?? []
    const supportsTextAppearance = !view?.isFixedLayout &&
        typeof view?.renderer?.setStyles === 'function'
    const supportsLayout = !view?.isFixedLayout &&
        typeof view?.renderer?.setAttribute === 'function'
    return {
        supportsProgressSeeking:Array.isArray(fractions) && fractions.length > 1 &&
            fractions.every(value => Number.isFinite(value)) &&
            fractions.at(-1) > fractions[0],
        supportsNavigationHistory:typeof view?.history?.back === 'function' &&
            typeof view?.history?.forward === 'function',
        supportsTextAppearance,
        supportsLayout,
        supportsPublisherStyles:supportsTextAppearance,
    }
}

export function progressFraction(value) {
    if (typeof value !== 'number' || !Number.isFinite(value))
        throw new Error('Progress must be a finite number')
    return Math.max(0, Math.min(1, value))
}

export const navigationHistory = view => ({
    canGoBack:view?.history?.canGoBack === true,
    canGoForward:view?.history?.canGoForward === true,
})

export async function navigateHistory(view, direction) {
    if (!readingCapabilities(view).supportsNavigationHistory ||
        typeof view?.renderer?.goTo !== 'function')
        throw new Error('Navigation history is unavailable for this publication')
    if (!['back','forward'].includes(direction)) throw new Error('Unknown history direction')
    // History's public methods return void, but synchronously dispatch popstate
    // to View, which calls renderer.goTo(). Capture that public promise only
    // during dispatch, restoring the method immediately. No private history
    // state is inspected or replaced, and failures reach the host command.
    const renderer = view.renderer
    const original = renderer.goTo
    const pending = []
    renderer.goTo = function(...args) {
        let result
        try { result = Promise.resolve(original.apply(this, args)) }
        catch (error) { result = Promise.reject(error) }
        pending.push(result)
        return result
    }
    try { view.history[direction]() }
    finally { renderer.goTo = original }
    await Promise.all(pending)
    return navigationHistory(view)
}

export function createNavigationQueue() {
    let pending = Promise.resolve()
    return task => {
        const result = pending.then(task)
        // A rejected command must not poison the next navigation request.
        pending = result.catch(() => {})
        return result
    }
}

export function guardRendererLifecycle(view) {
    const renderer = view?.renderer
    if (view?.isFixedLayout || typeof renderer?.render !== 'function' ||
        typeof renderer?.getContents !== 'function') return
    const original = renderer.render
    renderer.render = function(...args) {
        // Foliate publishes its new iframe before the document's load event.
        // A ResizeObserver or changed layout attribute can run in that gap,
        // or after detachment. Do not style an absent documentElement/body.
        const contents = renderer.getContents()
        if (renderer.isConnected === false || !contents.length ||
            !contents.every(({doc}) => doc?.documentElement && doc?.body)) return
        return original.apply(this, args)
    }
}
