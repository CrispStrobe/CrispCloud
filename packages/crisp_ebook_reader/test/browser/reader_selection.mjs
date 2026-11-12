import assert from 'node:assert/strict'
import {createReaderSelection} from '../../assets/reader_selection.js'

const clock = () => {
    let next = 0
    const intervals = new Map(), timeouts = new Map()
    return {
        intervals, timeouts,
        setInterval(callback, delay) {
            assert.equal(delay, 200)
            intervals.set(++next, callback)
            return next
        },
        clearInterval(id) { intervals.delete(id) },
        setTimeout(callback, delay) {
            assert.equal(delay, 150)
            timeouts.set(++next, callback)
            return next
        },
        clearTimeout(id) { timeouts.delete(id) },
        poll() { for (const callback of [...intervals.values()]) callback() },
        events() {
            const callbacks = [...timeouts.values()]
            timeouts.clear()
            for (const callback of callbacks) callback()
        },
    }
}

const publicationDocument = (text = 'A library stays local.') => {
    const doc = document.implementation.createHTMLDocument('Selection fixture')
    const paragraph = doc.createElement('p')
    paragraph.textContent = text
    doc.body.append(paragraph)
    const range = doc.createRange()
    range.selectNodeContents(paragraph)
    const state = {reads:0, strings:0, range, fail:false, selection:null}
    state.selection = {
        rangeCount:1, isCollapsed:false,
        getRangeAt:() => state.range,
        toString:() => { ++state.strings; return state.range.toString() },
    }
    doc.getSelection = () => {
        ++state.reads
        if (state.fail) throw new Error('Detached document')
        return state.selection
    }
    return {doc, state, paragraph}
}

export async function checkReaderSelection() {
    const timers = clock(), messages = [], conversions = []
    let current = [], live = true, failCFI = false
    const view = new EventTarget()
    view.renderer = {getContents:() => current}
    view.getCFI = (index, range) => {
        if (failCFI) throw new Error('Range disappeared during reflow')
        conversions.push({index, range})
        return `epubcfi(/6/${(index + 1) * 2}!/4/2:${range.startOffset})`
    }
    const observer = createReaderSelection(view, value => messages.push(value),
        {timers, isCurrent:() => live})
    const load = (doc, index) => view.dispatchEvent(new CustomEvent('load', {detail:{doc, index}}))
    const first = publicationDocument()
    load(first.doc, 0)
    current = [{doc:first.doc}]
    // No publication event is fired. This reproduces the actual WebKit gate:
    // native selection exists, while child-document JS listeners never run.
    timers.poll()
    assert.deepEqual(messages, [{text:'A library stays local.',
        cfi:'epubcfi(/6/2!/4/2:0)', sectionIndex:0}])
    timers.poll()
    first.doc.dispatchEvent(new Event('selectionchange'))
    timers.events()
    assert.equal(messages.length, 1, 'Polling and normal events must not duplicate a selection')
    assert.equal(first.state.strings, 1, 'Unchanged range endpoints must avoid text extraction')
    assert.equal(conversions.length, 1, 'Unchanged range endpoints must avoid CFI work')

    first.state.selection.isCollapsed = true
    timers.poll()
    first.state.selection.isCollapsed = false
    timers.poll()
    assert.equal(messages.length, 2, 'The same selection can be made again after collapse')
    first.state.selection.rangeCount = 0
    timers.poll()
    first.state.selection.rangeCount = 1
    timers.poll()
    assert.equal(messages.length, 3)
    first.state.range.setStart(first.paragraph.firstChild, 2)
    first.doc.dispatchEvent(new Event('selectionchange'))
    timers.events()
    assert.equal(messages.at(-1).text, 'library stays local.')
    assert.equal(messages.length, 4, 'Changed endpoints must produce a new selection')

    first.state.fail = true
    assert.doesNotThrow(() => timers.poll())
    first.state.fail = false
    first.state.range.setStart(first.paragraph.firstChild, 3)
    failCFI = true
    timers.poll()
    assert.equal(messages.length, 4)
    failCFI = false
    timers.poll()
    assert.equal(messages.length, 5, 'A transient CFI failure must not mark the range as delivered')

    // Fixed-layout contents intentionally omit index. Only renderer load
    // events may identify a document; no guessed index or stale document.
    const fixed = publicationDocument('The right page.'), unknown = publicationDocument('Unknown page.')
    load(fixed.doc, 7)
    current = [{doc:unknown.doc}, {doc:fixed.doc}]
    timers.poll()
    assert.equal(messages.length, 6)
    assert.equal(messages.at(-1).sectionIndex, 7)
    assert.equal(messages.at(-1).cfi, 'epubcfi(/6/16!/4/2:0)')
    const oldReads = first.state.reads
    first.doc.dispatchEvent(new Event('selectionchange'))
    timers.events()
    assert.equal(first.state.reads, oldReads, 'An unloaded chapter must not be sampled again')
    assert.equal(messages.length, 6)

    const large = publicationDocument('x'.repeat(100000))
    // A single large Text node must be read with bounded substringData, not
    // materialized in JS through data/textContent or Selection.toString().
    Object.defineProperty(large.paragraph.firstChild, 'data', {get() { throw new Error('Unbounded text read') }})
    large.state.selection.toString = () => { throw new Error('Unbounded selection read') }
    load(large.doc, 8)
    current = [{doc:large.doc}]
    timers.poll()
    assert.equal(messages.length, 7)
    assert.equal(messages.at(-1).text, 'x'.repeat(20000))
    timers.poll()
    assert.equal(messages.length, 7)

    const fragmented = publicationDocument('')
    for (let i = 0; i < 5000; ++i) {
        const span = fragmented.doc.createElement('span')
        span.textContent = 'a'
        fragmented.paragraph.append(span)
    }
    fragmented.state.range.selectNodeContents(fragmented.paragraph)
    fragmented.state.selection.toString = () => { throw new Error('Unbounded fragmented selection') }
    load(fragmented.doc, 9)
    current = [{doc:fragmented.doc}]
    timers.poll()
    assert.equal(messages.length, 8)
    assert(messages.at(-1).text.length > 0 && messages.at(-1).text.length < 4096,
        'Node traversal must stop within its work budget')

    const multiple = publicationDocument('Only the first range.')
    multiple.state.selection.rangeCount = 2
    multiple.state.selection.toString = () => { throw new Error('Unbounded later selection range') }
    load(multiple.doc, 10)
    current = [{doc:multiple.doc}]
    timers.poll()
    assert.equal(messages.length, 9)
    assert.equal(messages.at(-1).text, 'Only the first range.',
        'A multi-range quote must stay within the first range described by its CFI')
    assert.equal(messages.at(-1).sectionIndex, 10)

    const beforeStale = messages.length
    live = false
    const reads = multiple.state.reads
    multiple.doc.dispatchEvent(new Event('selectionchange'))
    timers.poll()
    timers.events()
    assert.equal(multiple.state.reads, reads)
    assert.equal(messages.length, beforeStale, 'A replaced view must not report late selections')
    live = true
    multiple.doc.dispatchEvent(new Event('selectionchange'))
    assert.equal(timers.timeouts.size, 1)
    const latePoll = [...timers.intervals.values()][0]
    observer.dispose()
    observer.dispose()
    view.renderer.getContents = () => { throw new Error('Closed renderer was touched') }
    assert.equal(timers.intervals.size, 0)
    assert.equal(timers.timeouts.size, 0)
    assert.doesNotThrow(latePoll)
    first.doc.dispatchEvent(new Event('selectionchange'))
    multiple.doc.dispatchEvent(new Event('selectionchange'))
    assert.equal(timers.timeouts.size, 0, 'Retained old documents must not restart a disposed timer')
    assert.equal(messages.length, beforeStale)

    console.log('PASS parent selection without child callbacks, event/poll dedup, exact section mapping, bounded text/node work, reflow recovery and disposal/replacement')
}
