// WebKit blocks parent-installed listeners in script-disabled publication
// documents (https://bugs.webkit.org/show_bug.cgi?id=218086). Observe the real
// selection from the trusted parent as well; never enable publication scripts.
const selectionText = (selection, range) => {
    const limit = 20000
    const root = range.commonAncestorContainer
    let budget = 4096, text = ''
    // The CFI describes range zero. A multi-range Selection.toString() could
    // include arbitrarily large, unscanned later ranges (notably in Firefox).
    const rendered = () => selection.rangeCount === 1
        ? selection.toString().slice(0, limit) : text
    const after = node => {
        while (node && node !== root) {
            if (--budget <= 0) return null
            if (node.nextSibling) return node.nextSibling
            node = node.parentNode
        }
        return null
    }
    const isText = node => node.nodeType === 3 || node.nodeType === 4
    let node = range.startContainer
    if (!isText(node)) node = node.childNodes[range.startOffset] ?? after(node)
    while (node && budget-- > 0) {
        if (range.comparePoint(node, 0) > 0)
            return rendered()
        if (isText(node)) {
            const start = node === range.startContainer ? range.startOffset : 0
            const end = node === range.endContainer ? range.endOffset : node.length
            const length = Math.min(end - start, limit - text.length)
            text += node.substringData(start, length)
            if (length < end - start || text.length >= limit) return text
            if (node === range.endContainer)
                return rendered()
        }
        node = node.firstChild ?? after(node)
    }
    // Preserve rendered whitespace for ordinary short selections. A large or
    // unusually fragmented selection uses only the bounded DOM-text prefix;
    // never materialize the complete chapter just to truncate its quote.
    return budget > 0 ? rendered() : text
}

export function createReaderSelection(view, onSelection, {
    isCurrent = () => true, timers = globalThis,
} = {}) {
    let indices = new WeakMap(), selections = new WeakMap()
    let disposed = false, eventTimer = null
    const active = () => !disposed && isCurrent()
    const contents = () => view?.renderer?.getContents?.() ?? []
    const sample = () => {
        if (!active()) return
        let current
        try { current = contents().slice(0, 8) }
        catch { return } // A renderer can be between documents during reflow.
        for (const {doc} of current) {
            if (!active()) return
            const index = doc && indices.get(doc)
            if (!Number.isSafeInteger(index) || index < 0) continue
            try {
                const selection = doc.getSelection()
                if (!selection?.rangeCount || selection.isCollapsed) {
                    selections.delete(doc)
                    continue
                }
                const range = selection.getRangeAt(0)
                const previous = selections.get(doc)
                if (previous && previous.start === range.startContainer &&
                    previous.startOffset === range.startOffset &&
                    previous.end === range.endContainer &&
                    previous.endOffset === range.endOffset) continue
                const text = selectionText(selection, range)
                const cfi = view.getCFI(index, range)
                if (!active()) return
                if (typeof cfi !== 'string' || !cfi.startsWith('epubcfi(')) continue
                selections.set(doc, {start:range.startContainer,
                    startOffset:range.startOffset, end:range.endContainer,
                    endOffset:range.endOffset})
                onSelection({text, cfi, sectionIndex:index})
            } catch { /* Ignore a document detached while its range was read. */ }
        }
    }
    const changed = () => {
        if (!active()) return
        timers.clearTimeout(eventTimer)
        eventTimer = timers.setTimeout(() => { eventTimer = null; sample() }, 150)
    }
    const loaded = ({detail}) => {
        if (!active()) return
        const {doc, index} = detail ?? {}
        if (!doc || !Number.isSafeInteger(index) || index < 0) return
        // Fixed-layout getContents() omits its section index. The trusted
        // renderer load event provides the exact document-to-section mapping.
        indices.set(doc, index)
        selections.delete(doc)
        doc.addEventListener('selectionchange', changed)
    }
    view.addEventListener('load', loaded)
    const pollTimer = timers.setInterval(sample, 200)
    return {dispose() {
        if (disposed) return
        disposed = true
        timers.clearInterval(pollTimer)
        timers.clearTimeout(eventTimer)
        view.removeEventListener('load', loaded)
        try {
            for (const {doc} of contents().slice(0, 8))
                doc?.removeEventListener('selectionchange', changed)
        } catch { /* The renderer may already have been detached. */ }
        indices = new WeakMap()
        selections = new WeakMap()
        view = null
        isCurrent = null
    }}
}
