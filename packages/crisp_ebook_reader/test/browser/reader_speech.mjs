import assert from 'node:assert/strict'
import {speechChunks, createReaderSpeech} from '../../assets/reader_speech.js'

export async function checkReaderSpeech() {
    const parse = body => new DOMParser().parseFromString(`<html lang="en"><body>${body}</body></html>`, 'text/html')
    const doc = parse(`<p>Before <em>café Ωμέγα 日本語 😀</em> after this sentence.</p>
        <p hidden>Hidden words.</p><p style="display:none">Invisible words.</p>
        <p aria-hidden="true">Decorative words.</p><script>Never speech.</script>
        <p>${'More Unicode 😀 words. '.repeat(50)}</p>`)
    const chunks = [...speechChunks(doc, {maxChars:40})]
    assert(chunks.length > 5)
    for (const chunk of chunks) {
        assert(chunk.text.length <= 40)
        assert.equal(chunk.range().toString(), chunk.text)
        assert.equal(chunk.range(3, 4).toString(), chunk.text.slice(3, 7))
        assert(!/[\uD800-\uDBFF]$/.test(chunk.text))
        assert(!/^[\uDC00-\uDFFF]/.test(chunk.text))
    }
    const spoken = chunks.map(chunk => chunk.text).join(' ')
    assert.match(spoken, /café Ωμέγα 日本語 😀/)
    assert.doesNotMatch(spoken, /Hidden|Invisible|Decorative|Never/)
    const start = doc.createRange()
    const text = doc.querySelector('em').firstChild
    start.setStart(text, 5); start.setEnd(text, 6)
    assert.equal([...speechChunks(doc, {startRange:start})][0].text.slice(0, 5), 'Ωμέγα')
    const elementAnchor = doc.createRange()
    elementAnchor.setStartAfter(doc.querySelector('p'))
    elementAnchor.collapse(true)
    assert([...speechChunks(doc, {startRange:elementAnchor})][0].text.startsWith('More Unicode'))

    const local = {voiceURI:'local-en', name:'Local English', lang:'en-US', localService:true, default:true}
    const remote = {voiceURI:'remote', name:'Remote voice', lang:'en-US', localService:false}
    class Synthesis extends EventTarget {
        voices = [local, remote]
        submitted = []
        cancellations = 0
        getVoices() { return this.voices }
        speak(utterance) { this.submitted.push(utterance); utterance.onstart?.() }
        cancel() { ++this.cancellations }
    }
    class Utterance { constructor(text) { this.text = text } }
    const synthesis = new Synthesis()
    const visibility = new EventTarget()
    visibility.hidden = false
    const first = parse('<p>one two three four five</p><p>next paragraph</p>')
    const second = parse('<p>new chapter</p>')
    let current = {doc:first, index:0}, pending = false, releaseNavigation = null
    const spokenRanges = [], states = []
    const speech = createReaderSpeech({
        synthesis, Utterance, visibilityDocument:visibility,
        getCurrentContent:() => current,
        nextSection:index => index === 0 ? 1 : null,
        isNavigationPending:() => pending,
        navigateToSection:async (index, isCurrent) => {
            await new Promise(resolve => releaseNavigation = resolve)
            if (!isCurrent()) return false
            current = {doc:second, index}
            return true
        },
        reveal:(content, range) => spokenRanges.push(range.toString()),
        onState:state => states.push(state),
    })
    assert.deepEqual(speech.state().voices.map(voice => voice.uri), ['local-en'])
    assert.equal(speech.state().status, 'stopped')
    assert.throws(() => speech.start({voiceUri:'remote'}), /local voice is unavailable/)
    speech.start({rate:100})
    const firstUtterance = synthesis.submitted.at(-1)
    assert.equal(firstUtterance.voice, local)
    assert.equal(firstUtterance.rate, 2)
    assert.equal(speech.state().status, 'speaking')
    firstUtterance.onboundary({charIndex:4, charLength:3})
    assert.equal(spokenRanges.at(-1), 'two')
    const staleEnd = firstUtterance.onend
    speech.pause()
    assert.equal(speech.state().status, 'paused')
    staleEnd()
    assert.equal(synthesis.submitted.length, 1, 'A canceled utterance cannot advance text')
    speech.resume()
    const resumed = synthesis.submitted.at(-1)
    assert.equal(resumed.text, 'two three four five', 'Pause resumes at the last reported word')
    resumed.onboundary({charIndex:4, charLength:5})
    assert.equal(spokenRanges.at(-1), 'three', 'Boundary indices include the resumed utterance offset')
    speech.pause(); speech.resume()
    assert.equal(synthesis.submitted.at(-1).text, 'three four five')
    synthesis.submitted.at(-1).onend()
    assert.equal(synthesis.submitted.at(-1).text, 'next paragraph')
    synthesis.submitted.at(-1).onend()
    await Promise.resolve(); await Promise.resolve()
    assert(releaseNavigation)
    const submitted = synthesis.submitted.length
    speech.pause()
    assert.throws(() => speech.resume(), /navigation to finish/)
    releaseNavigation()
    await new Promise(resolve => setTimeout(resolve, 0))
    assert.equal(synthesis.submitted.length, submitted, 'Pause invalidates a delayed chapter transition')
    assert.equal(current.index, 0, 'The queued stale navigation must check its cancellation token')
    current = {doc:second, index:1}
    speech.resume()
    assert.equal(synthesis.submitted.at(-1).text, 'new chapter', 'Resume rebinds to the visible document')
    visibility.hidden = true
    visibility.dispatchEvent(new Event('visibilitychange'))
    assert.equal(speech.state().status, 'paused')
    assert.throws(() => speech.resume(), /visible/)
    visibility.hidden = false
    pending = true
    assert.throws(() => speech.start(), /navigation to finish/)
    pending = false
    speech.resume()
    const denied = synthesis.submitted.at(-1)
    denied.onerror({error:'not-allowed'})
    assert.equal(speech.state().requiresGesture, true)
    speech.resume()
    assert.equal(speech.state().requiresGesture, false)
    speech.configure({rate:0.1})
    assert.equal(speech.state().status, 'paused', 'Voice changes do not autoplay')
    assert.equal(speech.state().rate, 0.5)
    speech.resume()
    const completion = synthesis.submitted.at(-1).onend
    speech.dispose()
    const stateCount = states.length, utteranceCount = synthesis.submitted.length
    completion()
    synthesis.dispatchEvent(new Event('voiceschanged'))
    visibility.hidden = true
    visibility.dispatchEvent(new Event('visibilitychange'))
    assert.equal(states.length, stateCount, 'Disposed speech has no callbacks/listeners')
    assert.equal(synthesis.submitted.length, utteranceCount)
    assert(states.every((state, index) => state.revision === index + 1))

    const emptyPage = createReaderSpeech({synthesis:new Synthesis(), Utterance,
        getCurrentContent:() => ({doc:parse('<img alt="cover" src="cover.png">'), index:0}),
        nextSection:() => { throw new Error('An image-only page must not navigate automatically') },
        navigateToSection:() => {}, visibilityDocument:null})
    assert.equal(emptyPage.start().status, 'stopped')
    assert.match(emptyPage.state().reason, /no readable text/)
    emptyPage.dispose()

    const unavailable = new Synthesis()
    unavailable.voices = [remote]
    const noLocalVoice = createReaderSpeech({synthesis:unavailable, Utterance,
        getCurrentContent:() => current, nextSection:() => null,
        navigateToSection:() => {}, visibilityDocument:null})
    assert.equal(noLocalVoice.state().status, 'unavailable')
    assert.throws(() => noLocalVoice.start(), /locally installed/)
    assert.equal(unavailable.submitted.length, 0)
    unavailable.voices.push(local)
    unavailable.dispatchEvent(new Event('voiceschanged'))
    assert.equal(noLocalVoice.state().status, 'stopped', 'Asynchronously installed local voices become available')
    noLocalVoice.start()
    unavailable.voices = [remote]
    unavailable.dispatchEvent(new Event('voiceschanged'))
    assert.equal(noLocalVoice.state().status, 'unavailable')
    assert.equal(unavailable.cancellations, 1, 'A disappearing local voice stops speech')
    noLocalVoice.dispose()
    console.log('PASS local-only foreground speech, bounded Unicode DOM ranges, exact resume offsets, activation, navigation cancellation, visibility and disposal')
}
