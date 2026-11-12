import { parseDocument, sanitizeDocument, sanitizeCss } from './security.js'
import { imageDimensions } from './image_dimensions.js'

const MAX_OUTPUT = 256 * 1024 * 1024
const MAX_RESOURCES = 12000
const textValue = value => typeof value === 'string' ? value : value && typeof value === 'object'
    ? textValue(value.name ?? value[Object.keys(value)[0]]) : ''
export const metadataOf = (book, filename) => ({
    title: textValue(book.metadata?.title) || filename,
    authors: [book.metadata?.author ?? []].flat().map(textValue).filter(Boolean),
    language: textValue(book.metadata?.language) || null,
    identifier: textValue(book.metadata?.identifier) || null,
    publisher: textValue(book.metadata?.publisher) || null,
    description: textValue(book.metadata?.description) || null,
})
const bytesToBase64 = bytes => {
    let str = ''
    for (let offset = 0; offset < bytes.length; offset += 32768) str += String.fromCharCode(...bytes.subarray(offset, offset + 32768))
    return btoa(str)
}
const extension = type => ({'text/css':'css', 'image/svg+xml':'svg', 'image/png':'png', 'image/jpeg':'jpg',
    'image/gif':'gif', 'image/webp':'webp', 'font/woff':'woff', 'font/woff2':'woff2', 'font/ttf':'ttf', 'font/otf':'otf',
    'audio/mpeg':'mp3', 'audio/mp4':'m4a', 'video/mp4':'mp4'}[type] || 'bin')
const inferType = (bytes, declared, hint) => {
    declared = (declared ?? '').split(';')[0].trim()
    if (declared && declared !== 'application/octet-stream') return declared
    const start = new TextDecoder().decode(bytes.subarray(0, 400)).trim()
    if (bytes[0] === 0x89 && bytes[1] === 0x50) return 'image/png'
    if (bytes[0] === 0xff && bytes[1] === 0xd8) return 'image/jpeg'
    if (start.startsWith('GIF8')) return 'image/gif'
    if (start.startsWith('RIFF') && start.slice(8, 12) === 'WEBP') return 'image/webp'
    if (start.startsWith('wOFF')) return 'font/woff'
    if (start.startsWith('wOF2')) return 'font/woff2'
    if (start.startsWith('OTTO')) return 'font/otf'
    if (bytes[0] === 0 && bytes[1] === 1 && bytes[2] === 0 && bytes[3] === 0) return 'font/ttf'
    if (/<svg[\s>]/i.test(start)) return 'image/svg+xml'
    return hint || 'application/octet-stream'
}

/// Convert the parsed publication to one consistent, self-contained archive
/// model. Original archives are edited by the core package instead of here.
export async function exportPublication(book, {filename, sourceFormat}) {
    const resources = []
    const warnings = new Set(sourceFormat === 'epub' ? ['This export is a normalized copy. Use archive-preserving EPUB editing to retain all original features.'] : [])
    const urlPaths = new Map()
    const dimensions = new Map()
    let outputBytes = 0
    const add = (href, mediaType, bytes) => {
        outputBytes += bytes.length
        if (outputBytes > MAX_OUTPUT || resources.length >= MAX_RESOURCES) throw new Error('Converted publication exceeds the 256 MiB / 12,000 resource limit')
        resources.push({href, mediaType, encoding:'base64', data:bytesToBase64(bytes)})
    }
    const chapterPaths = book.sections.map((_, i) => `chapters/${String(i + 1).padStart(4, '0')}.xhtml`)
    const docs = []
    for (const section of book.sections) {
        const url = await section.load()
        if (!String(url).startsWith('blob:')) throw new Error('Nonlocal publication section rejected')
        const response = await fetch(url)
        docs.push(sanitizeDocument(parseDocument(await response.text(), response.headers.get('content-type') || 'text/html'), {csp:false}))
    }
    let anchorCounter = 0
    const resolveLink = async (href, sectionIndex = null) => {
        if (!href) return null
        if (/^(https?:|mailto:|tel:)/i.test(href)) return href
        try {
            const section = sectionIndex == null ? null : book.sections[sectionIndex]
            const resolved = await book.resolveHref?.(section?.resolveHref?.(href) ?? href)
            if (!resolved || !docs[resolved.index]) return null
            const doc = docs[resolved.index]
            const anchor = resolved.anchor?.(doc)
            let el = anchor?.nodeType === 1 ? anchor : anchor?.startContainer
            if (el?.nodeType !== 1) el = el?.parentElement
            let id = ''
            if (el && !['html', 'body'].includes(el.localName)) {
                if (!el.id) {
                    do { id = `crisp-anchor-${++anchorCounter}` } while (doc.getElementById(id))
                    el.id = id
                } else id = el.id
            }
            return chapterPaths[resolved.index] + (id ? `#${encodeURIComponent(id)}` : '')
        } catch { return null }
    }
    const mapToc = async items => {
        const result = []
        for (const item of items ?? []) {
            const href = await resolveLink(String(item.href ?? ''))
            if (href) result.push({label:textValue(item.label), href, children:await mapToc(item.subitems)})
            else warnings.add('Some navigation entries could not be converted.')
        }
        return result
    }
    const toc = await mapToc(book.toc)
    // Establish anchor IDs before serializing any target chapter.
    for (const [i, doc] of docs.entries()) for (const anchor of doc.querySelectorAll('a[href]')) {
        const raw = anchor.getAttribute('href')
        const target = await resolveLink(raw, i)
        if (target) anchor.setAttribute('href', target.startsWith('chapters/') ? target.slice('chapters/'.length) : target)
        else {
            anchor.removeAttribute('href')
            if (raw) warnings.add('Some internal links could not be converted.')
        }
    }
    const rewriteCss = async css => {
        let out = sanitizeCss(css)
        const matches = [...out.matchAll(/url\(\s*['"]?((?:blob:|data:)[^'"\s)]*)['"]?\s*\)/gi)]
        for (const match of matches) {
            const path = await materialize(match[1])
            out = out.replaceAll(match[0], path ? `url("${path.split('/').pop()}")` : 'url("data:,")')
        }
        const imports = [...out.matchAll(/@import\s+['"](blob:[^'"]+)['"]/gi)]
        for (const match of imports) {
            const path = await materialize(match[1], 'text/css')
            out = out.replaceAll(match[0], path ? `@import "${path.split('/').pop()}"` : '')
        }
        return out
    }
    const materialize = async (url, hint) => {
        if (!/^(blob:|data:)/i.test(url)) return null
        if (urlPaths.has(url)) return urlPaths.get(url)
        const response = await fetch(url)
        let bytes = new Uint8Array(await response.arrayBuffer())
        const mediaType = inferType(bytes, response.headers.get('content-type'), hint)
        if (/javascript|text\/html|application\/xhtml/i.test(mediaType)) {
            warnings.add('Executable or embedded document resources were omitted from the converted copy.')
            return null
        }
        const href = `resources/asset-${String(urlPaths.size + 1).padStart(5, '0')}.${extension(mediaType)}`
        // Register before recursion to support cyclic CSS imports safely.
        urlPaths.set(url, href)
        if (mediaType === 'text/css') bytes = new TextEncoder().encode(await rewriteCss(new TextDecoder().decode(bytes)))
        if (mediaType === 'image/svg+xml') {
            const doc = sanitizeDocument(parseDocument(new TextDecoder().decode(bytes), mediaType), {csp:false})
            await rewriteDocumentResources(doc, 'resources/')
            bytes = new TextEncoder().encode(new XMLSerializer().serializeToString(doc))
        }
        if (mediaType.startsWith('image/')) {
            const size = await imageDimensions(bytes, mediaType)
            if (size) dimensions.set(href, size)
        }
        if (mediaType === 'application/octet-stream') warnings.add('A resource has an unknown media type; review the converted book before saving.')
        add(href, mediaType, bytes)
        return href
    }
    const rewriteDocumentResources = async (doc, folder) => {
        for (const el of doc.querySelectorAll('*')) for (const attr of [...el.attributes]) {
            const name = attr.localName.toLowerCase()
            if (!['src', 'poster', 'href', 'background'].includes(name) || (el.localName === 'a' && name === 'href')) continue
            const raw = attr.value
            if (raw.startsWith('#')) continue
            const target = await materialize(raw, el.localName === 'link' ? 'text/css' : undefined)
            if (target) attr.value = folder === 'resources/' ? target.slice('resources/'.length) : `../${target}`
            else if (raw) { el.removeAttributeNode(attr); warnings.add('Remote or unresolved resources were omitted from the offline converted copy.') }
        }
        // Inline styles live beside chapters; adjust resource-relative CSS paths.
        for (const style of doc.querySelectorAll('style')) {
            let css = await rewriteCss(style.textContent)
            if (folder !== 'resources/') css = css.replaceAll('url("asset-', 'url("../resources/asset-').replaceAll('@import "asset-', '@import "../resources/asset-')
            style.textContent = css
        }
        for (const el of doc.querySelectorAll('[style]')) {
            let css = await rewriteCss(el.getAttribute('style'))
            if (folder !== 'resources/') css = css.replaceAll('url("asset-', 'url("../resources/asset-')
            el.setAttribute('style', css)
        }
    }
    let coverHref = null
    try {
        const cover = await book.getCover?.()
        if (cover instanceof Blob) {
            const url = URL.createObjectURL(cover)
            try { coverHref = await materialize(url) } finally { URL.revokeObjectURL(url) }
        }
    } catch { warnings.add('The cover could not be converted.') }
    for (const [i, doc] of docs.entries()) {
        await rewriteDocumentResources(doc, 'chapters/')
        if (book.rendition?.layout === 'pre-paginated' && !doc.querySelector('meta[name="viewport"]')) {
            const image = doc.querySelector('img[src]')
            const size = dimensions.get(image?.getAttribute('src')?.replace(/^\.\.\//, ''))
            const head = doc.querySelector('head')
            if (size && head) {
                const meta = doc.createElementNS('http://www.w3.org/1999/xhtml', 'meta')
                meta.setAttribute('name', 'viewport')
                meta.setAttribute('content', `width=${size.width}, height=${size.height}`)
                head.append(meta)
                if (!image.hasAttribute('width')) image.setAttribute('width', size.width)
                if (!image.hasAttribute('height')) image.setAttribute('height', size.height)
            } else warnings.add('A fixed-layout page has no viewport; review its size in the converted book.')
        }
        add(chapterPaths[i], 'application/xhtml+xml', new TextEncoder().encode(new XMLSerializer().serializeToString(doc)))
    }
    const readingOrder = chapterPaths.map((href, index) => ({href,
        title: toc.find(item => item.href.split('#')[0] === href)?.label || `Chapter ${index + 1}`,
        linear: book.sections[index].linear !== 'no'}))
    return {schemaVersion:1, sourceFormat, metadata:metadataOf(book, filename),
        direction:book.dir === 'rtl' ? 'rtl' : 'ltr', layout:book.rendition?.layout === 'pre-paginated' ? 'pre-paginated' : 'reflowable',
        readingOrder, toc, resources, coverHref, warnings:[...warnings]}
}
