// Foliate's iterator updates its shared search overlays before yielding each
// result. Serialize that mutable work, but cancel the public command promptly
// and prevent a suspended, canceled iterator from drawing stale results.
export function createReaderSearch(view) {
    let current = null, executing = null, disposed = false
    let pending = Promise.resolve()
    const addAnnotation = view.addAnnotation
    view.addAnnotation = function(annotation, remove, ...args) {
        const searchResult = annotation?.value?.startsWith('foliate-search:')
        if (!remove && searchResult && (disposed || !executing ||
            executing !== current || executing.canceled)) return Promise.resolve()
        return addAnnotation.call(this, annotation, remove, ...args)
    }
    const clear = () => {
        if (current) {
            current.canceled = true
            current.cancel()
            current = null
        }
        if (!disposed) view.clearSearch()
    }
    const search = ({query, limit = 200} = {}) => {
        if (disposed) return Promise.reject(new Error('Ebook search was closed'))
        clear()
        query = String(query ?? '').trim().slice(0, 1000)
        if (!query) return Promise.resolve([])
        limit = Number.isFinite(limit) ? Math.max(1, Math.min(1000, Math.trunc(limit))) : 200
        let cancel
        const canceled = new Promise(resolve => { cancel = () => resolve([]) })
        const token = {cancel, canceled:false}
        current = token
        const work = pending.then(async () => {
            if (disposed || token.canceled) return []
            executing = token
            const hits = []
            try {
                for await (const result of view.search({query, matchCase:false,
                    matchDiacritics:false, matchWholeWords:false})) {
                    if (disposed || token.canceled) return []
                    for (const match of result.subitems ?? []) {
                        const excerpt = typeof match.excerpt === 'string' ? match.excerpt
                            : [match.excerpt?.pre, match.excerpt?.match, match.excerpt?.post]
                                .filter(Boolean).join('')
                        const sectionIndex = Number.isInteger(result.index) ? result.index
                            : view.resolveNavigation(match.cfi)?.index ?? 0
                        hits.push({cfi:match.cfi, excerpt, sectionIndex})
                        if (hits.length >= limit) return hits
                    }
                }
                return hits
            } catch (error) {
                if (disposed || token.canceled) return []
                view.clearSearch()
                throw error
            } finally {
                // The old iterator can still populate its private result map,
                // even though our adapter suppressed drawing. Remove those
                // entries before the next queued query starts.
                if (!disposed && token.canceled) view.clearSearch()
            }
        })
        // Observe detached work after prompt cancellation, including failures
        // from a document read that completes after its view has been closed.
        pending = work.catch(() => {})
        return Promise.race([work, canceled])
    }
    return {search, clear, dispose:() => {
        if (disposed) return
        clear()
        disposed = true
    }}
}
