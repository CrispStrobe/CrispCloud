import assert from 'node:assert/strict'
import {createReaderSelection} from '../../assets/reader_selection.js'

export function checkReaderSelection() {
    let nextId = 0
    const scheduled = new Map(), reports = []
    const schedule = callback => { const id = ++nextId; scheduled.set(id, callback); return id }
    const cancel = id => scheduled.delete(id)
    const tick = () => {
        const [id, callback] = scheduled.entries().next().value
        scheduled.delete(id)
        callback()
    }
    const start = {}, end = {}
    const range = {startContainer:start, startOffset:0, endContainer:end, endOffset:5}
    const selection = {rangeCount:1, isCollapsed:false,
        getRangeAt:() => range, toString:() => 'Library'}
    // There is deliberately no event listener API: the observed WebKit frame
    // has a real selection but never dispatches its selectionchange callback.
    const doc = {getSelection:() => selection}
    let contents = [{doc, index:2}]
    const view = {renderer:{getContents:() => contents},
        getCFI:(index, actual) => {
            assert.equal(actual, range, 'Use the native range, not a reconstructed text match')
            return `epubcfi(${index}:${actual.startOffset}-${actual.endOffset})`
        }}
    const observer = createReaderSelection(view, {onSelection:value => reports.push(value), schedule, cancel})
    tick()
    assert.deepEqual(reports, [{text:'Library', cfi:'epubcfi(2:0-5)', sectionIndex:2}])
    tick()
    assert.equal(reports.length, 1, 'A stable range must not repeatedly notify the app')
    range.endOffset = 6
    tick()
    assert.equal(reports.at(-1).cfi, 'epubcfi(2:0-6)', 'Dragging updates the actual range')
    selection.isCollapsed = true
    tick()
    selection.isCollapsed = false
    tick()
    assert.equal(reports.length, 3, 'Reselecting the same text is a fresh selection')
    selection.toString = () => 'x'.repeat(25000)
    range.endOffset = 7
    tick()
    assert.equal(reports.at(-1).text.length, 20000, 'Preserve the bridge selection-text bound')
    contents = []
    tick()
    range.endOffset = 8
    tick()
    assert.equal(reports.length, 4, 'Detached publication documents are not observed')
    contents = [{doc, index:3}]
    tick()
    assert.equal(reports.at(-1).sectionIndex, 3)
    const lateCallback = scheduled.values().next().value
    observer.dispose()
    observer.dispose()
    assert.equal(scheduled.size, 0, 'Closing the reader removes the parent timer')
    lateCallback()
    assert.equal(reports.length, 5, 'A callback already queued at close cannot report a stale selection')
    assert.equal(scheduled.size, 0)
    console.log('PASS real-range selection without child events, drag updates, bounds, deduplication, document replacement and disposal')
}

checkReaderSelection()
