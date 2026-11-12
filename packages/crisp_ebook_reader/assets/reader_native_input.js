// GTK still performs focus, selection, clipboard and link activation. WebKit
// may suppress the parent's click callback inside a script-disabled book
// frame. Give those links a host-local token that native navigation policy
// intercepts before any load; resolve the original publication href here.
export function createNativeReaderInput(view, book, prefix, onLink) {
    let next = 0, disposed = false
    const links = new Map()
    const activeDocuments = () => new Set(
        (view.renderer?.getContents?.() ?? []).map(item => item.doc))
    const prune = () => {
        const active = activeDocuments()
        for (const [token, value] of links)
            if (!active.has(value.doc) || !value.anchor.isConnected) links.delete(token)
    }
    const activate = token => {
        if (disposed || typeof token !== 'string' || !/^[0-9]+$/.test(token)) return false
        prune()
        const value = links.get(token)
        if (!value || value.anchor.ownerDocument !== value.doc ||
            value.anchor.getAttribute('href') !== prefix + token) return false
        onLink({href:value.href, originalHref:value.originalHref})
        return true
    }
    return {
        decorate(doc, index) {
            if (disposed) return
            // Only the rendered copy is changed. Book bytes, node structure,
            // CFIs and the normalized-export source remain untouched.
            for (const anchor of Array.from(doc.querySelectorAll('a[href]')).slice(0, 20000)) {
                const originalHref = anchor.getAttribute('href')
                try {
                    const href = book.sections[index]?.resolveHref?.(originalHref) ?? originalHref
                    const token = String(++next)
                    links.set(token, {doc, anchor, href, originalHref})
                    anchor.setAttribute('href', prefix + token)
                } catch {
                    // Invalid publication links retain the native host's
                    // normal fail-closed navigation policy.
                }
            }
        },
        activate,
        // If a future WebKit starts delivering child events, the ordinary
        // Foliate handler prevents native navigation and reaches this same
        // registry once, rather than treating the local token as an external URL.
        followUrl(url) {
            if (typeof url !== 'string' || !url.startsWith(prefix)) return false
            activate(url.slice(prefix.length))
            return true
        },
        prune,
        dispose() { disposed = true; links.clear() },
    }
}
