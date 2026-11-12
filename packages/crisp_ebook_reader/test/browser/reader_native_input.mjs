import assert from 'node:assert/strict'
import {createNativeReaderInput} from '../../assets/reader_native_input.js'

export function checkNativeReaderInput() {
    const prefix = 'blob:http://127.0.0.1:8181/session/__link__/'
    const hrefs = ['one.xhtml#start', '#finish', 'https://example.com/info']
    const anchors = hrefs.map(href => ({href, isConnected:true,
        getAttribute() { return this.href }, setAttribute(_, value) { this.href = value }}))
    const doc = {querySelectorAll:() => anchors}
    anchors.forEach(anchor => { anchor.ownerDocument = doc })
    let contents = [{doc, index:1}]
    const view = {renderer:{getContents:() => contents}}
    const calls = []
    const book = {sections:[{}, {resolveHref:href => /^https?:/.test(href) ? href : `OPS/${href}`} ]}
    const input = createNativeReaderInput(view, book, prefix, value => calls.push(value))
    input.decorate(doc, 1)
    assert.deepEqual(anchors.map(a => a.href), [1, 2, 3].map(id => prefix + id))
    assert(input.activate('1'))
    assert.deepEqual(calls, [{href:'OPS/one.xhtml#start', originalHref:'one.xhtml#start'}])
    assert(input.followUrl(prefix + '2'))
    assert.equal(calls.at(-1).originalHref, '#finish')
    assert(input.activate('3'))
    assert.equal(calls.at(-1).href, 'https://example.com/info')
    assert.equal(input.followUrl('https://example.com/'), false)
    assert.equal(input.activate('1/../../outside'), false)
    assert.equal(input.activate('1?target=2'), false)
    assert.equal(input.activate('999'), false)
    anchors[0].href = prefix + '2'
    assert.equal(input.activate('1'), false, 'A modified anchor cannot reuse its old registration')
    anchors[1].isConnected = false
    assert.equal(input.activate('2'), false, 'Detached anchors cannot initiate a navigation')
    contents = []
    assert.equal(input.activate('3'), false, 'A former chapter cannot navigate the current book')
    contents = [{doc, index:1}]
    assert.equal(input.activate('3'), false, 'Pruning removes stale route registrations')
    input.dispose()
    input.dispose()
    assert.equal(input.activate('3'), false)
    assert.equal(calls.length, 3)
    console.log('PASS native link registration, original-href resolution, bounds, stale-document rejection and disposal')
}

checkNativeReaderInput()
