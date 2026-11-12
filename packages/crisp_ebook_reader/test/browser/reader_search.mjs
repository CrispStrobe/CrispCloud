import assert from 'node:assert/strict'
import {createReaderSearch} from '../../assets/reader_search.js'

const deferred = () => {
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    return {promise, resolve, reject}
}
const flushUntil = async condition => {
    for (let i = 0; i < 30 && !condition(); ++i) await Promise.resolve()
    assert(condition(), 'Queued search did not reach its expected state')
}

export async function checkReaderSearch() {
    const starts = [], stored = new Set(), drawn = new Set()
    const gates = new Map()
    let closed = false, callsAfterClose = 0
    const view = {
        addAnnotation:async (annotation, remove) => {
            if (closed) ++callsAfterClose
            if (remove) drawn.delete(annotation.value)
            else drawn.add(annotation.value)
        },
        clearSearch() {
            if (closed) ++callsAfterClose
            for (const value of stored) this.addAnnotation({value}, true)
            stored.clear()
        },
        resolveNavigation:() => ({index:2}),
        async *search({query}) {
            this.clearSearch()
            starts.push(query)
            const gate = deferred()
            gates.set(query, gate)
            await gate.promise
            // Reproduce the upstream ordering: shared results and annotation
            // drawing are updated before the host sees the next yielded hit.
            const value = `foliate-search:${query}`
            stored.add(value)
            this.addAnnotation({value})
            if (closed) throw new Error('Document finished after view closure')
            yield {subitems:[{cfi:query, excerpt:{pre:'before ',match:query,post:' after'}}]}
        },
    }
    const session = createReaderSearch(view)
    const first = session.search({query:'old'})
    await flushUntil(() => gates.has('old'))
    session.clear()
    assert.deepEqual(await first, [], 'Clearing must complete the canceled command before the blocked read finishes')
    assert.deepEqual([...drawn], [])
    await view.addAnnotation({value:'epubcfi(user-note)'})
    assert(drawn.has('epubcfi(user-note)'), 'Canceling search must not suppress user highlights')

    const skipped = session.search({query:'skipped'})
    const fresh = session.search({query:'fresh'})
    assert.deepEqual(await skipped, [], 'A superseded queued request must cancel promptly')
    assert.deepEqual(starts, ['old'], 'Only one upstream iterator may mutate the shared result map')
    gates.get('old').resolve()
    await flushUntil(() => gates.has('fresh'))
    assert.deepEqual(starts, ['old', 'fresh'])
    assert(!drawn.has('foliate-search:old'), 'A canceled iterator must not draw when its read resumes')
    gates.get('fresh').resolve()
    assert.deepEqual(await fresh, [{cfi:'fresh', excerpt:'before fresh after', sectionIndex:2}])
    assert(drawn.has('foliate-search:fresh'))
    assert(drawn.has('epubcfi(user-note)'))
    await view.addAnnotation({value:'foliate-search:fresh'})
    assert(drawn.has('foliate-search:fresh'), 'Completed current results must still redraw on chapter navigation')
    session.clear()
    assert(!drawn.has('foliate-search:fresh'), 'Clear must continue to remove search annotations')

    const failed = session.search({query:'failure'})
    const failure = assert.rejects(failed, /read failed/)
    await flushUntil(() => gates.has('failure'))
    gates.get('failure').reject(new Error('read failed'))
    await failure
    const afterFailure = session.search({query:'recovered'})
    await flushUntil(() => gates.has('recovered'))
    gates.get('recovered').resolve()
    assert.equal((await afterFailure)[0].cfi, 'recovered')

    const closing = session.search({query:'closing'})
    await flushUntil(() => gates.has('closing'))
    session.dispose()
    session.dispose()
    assert.deepEqual(await closing, [], 'Disposal must not wait for an uncooperative document read')
    closed = true
    gates.get('closing').resolve()
    await flushUntil(() => stored.has('foliate-search:closing'))
    for (let i = 0; i < 10; ++i) await Promise.resolve()
    assert.equal(callsAfterClose, 0, 'Late iterator completion must not draw or clear a disposed view')
    await assert.rejects(session.search({query:'too late'}), /closed/)
    session.clear()
    assert.equal(callsAfterClose, 0)
    assert(!drawn.has('foliate-search:closing'))
    console.log('PASS prompt search cancellation, serialized iterators, stale-overlay suppression, section locations, failure recovery and disposal during a suspended read')
}
