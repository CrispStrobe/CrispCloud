// WebKit can suppress parent-installed listeners in a script-disabled book
// frame (https://bugs.webkit.org/show_bug.cgi?id=218086). Observe the actual
// native selection from the trusted parent instead. Publication scripts stay
// disabled, and every locator still comes from the selected DOM Range.
export function createReaderSelection(view, {
    onSelection,
    schedule = setTimeout,
    cancel = clearTimeout,
    delay = 150,
} = {}) {
    let disposed = false, timer = null, previous = new Map()
    const scan = () => {
        timer = null
        if (disposed) return
        const current = new Map()
        // Paginators normally expose one document and fixed layouts at most a
        // spread. Bound the work even if a future renderer exposes more.
        for (const {doc, index} of (view.renderer?.getContents?.() ?? []).slice(0, 8)) {
            try {
                const selection = doc.getSelection()
                if (!selection?.rangeCount || selection.isCollapsed) continue
                const range = selection.getRangeAt(0)
                const value = {index, start:range.startContainer, from:range.startOffset,
                    end:range.endContainer, to:range.endOffset}
                current.set(doc, value)
                const old = previous.get(doc)
                if (old && Object.keys(value).every(key => value[key] === old[key])) continue
                onSelection({text:selection.toString().slice(0, 20000),
                    cfi:view.getCFI(index, range), sectionIndex:index})
            } catch {
                // A navigation may detach a document between enumeration and
                // reading its range. Never retain or report that stale range.
                current.delete(doc)
            }
        }
        previous = current
        if (!disposed) timer = schedule(scan, delay)
    }
    timer = schedule(scan, delay)
    return {
        dispose() {
            if (disposed) return
            disposed = true
            cancel(timer)
            timer = null
            previous.clear()
        },
    }
}
