// Host-owned security boundary. Do not weaken this to enable scripted EPUBs.
export const BOOK_CSP = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline' blob:; img-src blob: data:; font-src blob: data:; media-src blob: data:; frame-src 'none'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
export const HOST_CSP = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline' blob:; img-src blob: data:; font-src blob: data:; media-src blob: data:; frame-src blob:; connect-src 'self' blob: data:; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

export const isLocalResource = value => /^blob:|^data:(?:image\/|font\/|audio\/|video\/|application\/(?:font|x-font|vnd\.ms-fontobject|octet-stream))|^#/i.test(value?.trim() ?? '')

export function sanitizeCss(css) {
    // CSP remains authoritative, including CSS escapes and malformed syntax.
    // Match the complete import before inspecting its URL. A negative lookahead
    // after an optional quote can backtrack and discard even a local stylesheet.
    // Foliate has already materialized packaged stylesheets as blob URLs.
    return String(css).replace(/@import\b((?:[^;"']|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')*);/gi, (_, body) => {
        const match = /^\s*(?:url\(\s*(?:"([^"]*)"|'([^']*)'|([^\s)]+))\s*\)|"([^"]*)"|'([^']*)')([\s\S]*)$/i.exec(body)
        const url = match?.slice(1, 6).find(value => value !== undefined)?.trim()
        if (!url?.startsWith('blob:') || /[\\"'\r\n]/.test(url)) return ''
        return `@import url("${url}")${match[6]};`
    })
        .replace(/url\(\s*(['"]?)(.*?)\1\s*\)/gi,
            (_, q, url) => isLocalResource(url) ? `url("${url.replaceAll('"', '%22')}")` : 'url("data:,")')
}

export function parseDocument(text, type = 'application/xhtml+xml') {
    type = type.split(';')[0].trim()
    if (!['text/html', 'application/xhtml+xml', 'image/svg+xml', 'application/xml', 'text/xml'].includes(type)) type = 'text/html'
    let doc = new DOMParser().parseFromString(text, type)
    if (doc.querySelector('parsererror') || !doc.documentElement) {
        doc = new DOMParser().parseFromString(text, 'text/html')
    }
    return doc
}

export function serializeDocument(doc) {
    // HTML parsing treats xmlns as an ordinary attribute, while XMLSerializer
    // also emits the element's real namespace. Bind those declarations to the
    // XMLNS namespace first so MOBI's HTML does not become invalid duplicate-
    // xmlns XHTML. Keep prefixed declarations and SVG namespaces intact.
    const xmlns = 'http://www.w3.org/2000/xmlns/'
    for (const el of doc.querySelectorAll('*')) for (const attr of [...el.attributes]) {
        if (attr.namespaceURI !== xmlns && (attr.name === 'xmlns' || attr.name.startsWith('xmlns:'))) {
            const {name, value} = attr
            el.removeAttributeNode(attr)
            el.setAttributeNS(xmlns, name, value)
        }
    }
    return new XMLSerializer().serializeToString(doc)
}

export function sanitizeDocument(doc, {csp = true} = {}) {
    for (const node of doc.querySelectorAll('script, iframe, frame, frameset, object, embed, base, foreignObject, animate, animateMotion, animateTransform, set, input, button, textarea, select')) node.remove()
    for (const form of doc.querySelectorAll('form')) form.replaceWith(...form.childNodes)
    for (const meta of doc.querySelectorAll('meta[http-equiv]')) meta.remove()
    for (const link of doc.querySelectorAll('link')) {
        if (link.getAttribute('rel')?.toLowerCase() !== 'stylesheet') link.remove()
    }
    for (const el of doc.querySelectorAll('*')) {
        for (const attr of [...el.attributes]) {
            const name = attr.localName.toLowerCase()
            const value = attr.value.trim()
            if (name.startsWith('on') || ['srcdoc', 'autofocus', 'contenteditable', 'formaction', 'action', 'ping', 'target', 'download'].includes(name)) {
                el.removeAttributeNode(attr)
            } else if (name === 'style') {
                el.setAttribute('style', sanitizeCss(value))
            } else if (['src', 'poster', 'data', 'background', 'srcset'].includes(name)) {
                // srcset is removed; src remains. Parsing all srcset variants is
                // deliberately not delegated to a permissive URL regex.
                if (name === 'srcset' || !isLocalResource(value)) el.removeAttributeNode(attr)
            } else if (name === 'href') {
                const isAnchor = el.localName.toLowerCase() === 'a'
                if (isAnchor ? /^(?:javascript|vbscript|data|file):/i.test(value) : !isLocalResource(value)) el.removeAttributeNode(attr)
            }
        }
    }
    for (const style of doc.querySelectorAll('style')) style.textContent = sanitizeCss(style.textContent)
    for (const node of [...doc.childNodes]) if (node.nodeType === 7) node.remove()
    if (csp && doc.documentElement.localName.toLowerCase() === 'html') {
        let head = doc.querySelector('head')
        if (!head) {
            head = doc.createElementNS('http://www.w3.org/1999/xhtml', 'head')
            doc.documentElement.prepend(head)
        }
        const policy = doc.createElementNS('http://www.w3.org/1999/xhtml', 'meta')
        policy.setAttribute('http-equiv', 'Content-Security-Policy')
        policy.setAttribute('content', BOOK_CSP)
        head.prepend(policy)
    }
    return doc
}

export function safeResourceTransform(book) {
    book.transformTarget?.addEventListener('load', event => {
        if (event.detail.isScript) event.detail.allow = false
    })
    book.transformTarget?.addEventListener('data', event => {
        const {data, type} = event.detail
        if (!/html|svg|css/i.test(type ?? '')) return
        event.detail.data = Promise.resolve(data).then(async value => {
            const text = value instanceof Blob ? await value.text() : String(value)
            if (/css/i.test(type)) return sanitizeCss(text)
            return serializeDocument(sanitizeDocument(parseDocument(text, type)))
        })
    })
}

/// Guard every format, including MOBI6 and CBZ which lack transformTarget.
export function secureSections(book) {
    const safeUrls = new Map()
    for (const [index, section] of book.sections.entries()) {
        const originalLoad = section.load.bind(section)
        const originalUnload = section.unload?.bind(section)
        section.load = async () => {
            if (safeUrls.has(index)) return safeUrls.get(index)
            const url = await originalLoad()
            if (!String(url).startsWith('blob:')) throw new Error('Book sections must be local blobs')
            const response = await fetch(url)
            const doc = sanitizeDocument(parseDocument(await response.text(), response.headers.get('content-type') || 'text/html'))
            const safe = URL.createObjectURL(new Blob([serializeDocument(doc)], {type:'application/xhtml+xml'}))
            safeUrls.set(index, safe)
            return safe
        }
        // Search and CFI generation must see the exact sanitized structure
        // rendered on screen, including when removed script elements shifted
        // sibling indices in a source chapter.
        section.createDocument = async () => {
            const response = await fetch(await section.load())
            return parseDocument(await response.text(), 'application/xhtml+xml')
        }
        section.unload = () => {
            if (safeUrls.has(index)) URL.revokeObjectURL(safeUrls.get(index))
            safeUrls.delete(index)
            originalUnload?.()
        }
    }
    return () => {
        for (const url of safeUrls.values()) URL.revokeObjectURL(url)
        safeUrls.clear()
    }
}
