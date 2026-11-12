// Foreground read-aloud over the reader's already sanitized DOM. Only voices
// explicitly marked local by the platform may receive publication text.
const BLOCKS = 'address,article,aside,blockquote,dd,div,dl,dt,figcaption,figure,footer,h1,h2,h3,h4,h5,h6,header,li,main,nav,ol,p,pre,section,table,td,th,tr,ul'
const EXCLUDED = 'script,style,noscript,template,svg,math,audio,video,rt,rp,[hidden],[aria-hidden="true"]'
const boundedRate = value => Number.isFinite(value) ? Math.min(2, Math.max(0.5, value)) : 1
const utf16Boundary = (text, end) => end > 0 && end < text.length &&
    /[\uD800-\uDBFF]/.test(text[end - 1]) && /[\uDC00-\uDFFF]/.test(text[end]) ? end - 1 : end

// Keep exact DOM offsets. No text nodes are inserted, wrapped or normalized,
// so saved CFIs, selections and annotations remain valid during speech.
export function* speechChunks(doc, {startRange, maxChars = 240} = {}) {
    if (!doc?.body) return
    maxChars = Math.min(1000, Math.max(40, Math.trunc(maxChars) || 240))
    let anchor
    if (startRange?.startContainer?.ownerDocument === doc) {
        anchor = startRange.cloneRange()
        anchor.collapse(true)
    }
    const visible = new WeakMap()
    const isVisible = element => {
        if (!element) return true
        if (visible.has(element)) return visible.get(element)
        let result = !element.matches(EXCLUDED)
        if (result) {
            const style = doc.defaultView?.getComputedStyle(element) ?? element.style
            result = style?.display !== 'none' && style?.visibility !== 'hidden' &&
                style?.visibility !== 'collapse' && isVisible(element.parentElement)
        }
        visible.set(element, result)
        return result
    }
    const walker = doc.createTreeWalker(doc.body, 4)
    let text = '', pieces = [], block = null
    const finish = () => {
        const left = text.length - text.trimStart().length
        const right = text.trimEnd().length
        if (right <= left) { text = ''; pieces = []; return null }
        const source = pieces, value = text.slice(left, right)
        const point = (position, end) => {
            const candidates = end ? [...source].reverse() : source
            const piece = candidates.find(item => position >= item.from && position <= item.to)
            return [piece.node, piece.start + position - piece.from]
        }
        text = ''; pieces = []
        return {text:value, range(offset = 0, length = value.length - offset) {
            offset = Math.min(value.length, Math.max(0, offset))
            const end = Math.min(value.length, Math.max(offset, offset + length))
            const range = doc.createRange()
            range.setStart(...point(left + offset, false))
            range.setEnd(...point(left + end, true))
            return range
        }}
    }
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!isVisible(node.parentElement)) continue
        let start = 0
        if (anchor) {
            if (anchor.comparePoint(node, node.length) < 0) continue
            if (node === anchor.startContainer) start = anchor.startOffset
            else if (anchor.comparePoint(node, 0) < 0) continue
            anchor = null
        }
        const nextBlock = node.parentElement?.closest(BLOCKS) ?? doc.body
        if (block && block !== nextBlock) {
            const chunk = finish()
            if (chunk) yield chunk
        }
        block = nextBlock
        while (start < node.length) {
            const room = maxChars - text.length
            let end = utf16Boundary(node.data, Math.min(node.length, start + room))
            if (end === start) {
                const chunk = finish()
                if (chunk) yield chunk
                // A surrogate pair must remain together, even in the final
                // one-character slot of the previous chunk.
                continue
            }
            if (end < node.length && end - start > 40) {
                const portion = node.data.slice(start, end)
                const sentence = [...portion.matchAll(/[.!?。！？](?:\s|$)/gu)].at(-1)
                const whitespace = portion.lastIndexOf(' ')
                const boundary = sentence ? sentence.index + sentence[0].length
                    : whitespace > portion.length / 2 ? whitespace + 1 : 0
                if (boundary) end = start + boundary
            }
            pieces.push({node, start, from:text.length, to:text.length + end - start})
            text += node.data.slice(start, end)
            start = end
            if (start < node.length || text.length >= maxChars) {
                const chunk = finish()
                if (chunk) yield chunk
            }
        }
    }
    const chunk = finish()
    if (chunk) yield chunk
}

export function createReaderSpeech({
    getCurrentContent, nextSection, navigateToSection, isNavigationPending = () => false,
    reveal = () => {}, clearHighlight = () => {}, onState = () => {},
    synthesis = globalThis.speechSynthesis, Utterance = globalThis.SpeechSynthesisUtterance,
    visibilityDocument = globalThis.document,
}) {
    let disposed = false, generation = 0, revision = 0, status = 'stopped'
    let reason = '', voiceUri = '', rate = 1, requiresGesture = false
    let iterator = null, chunk = null, content = null, offset = 0, chunkIndex = 0
    let utterance = null, startTimer = null, transition = null
    const localVoices = () => {
        try { return (synthesis?.getVoices?.() ?? []).filter(voice => voice.localService === true) }
        catch { return [] }
    }
    const state = () => ({status, reason, voiceUri, rate, requiresGesture, revision,
        sectionIndex:content?.index ?? -1, chunkIndex,
        voices:localVoices().map(voice => ({uri:voice.voiceURI, name:voice.name,
            language:voice.lang, isDefault:voice.default === true}))})
    const emit = () => { if (!disposed) { ++revision; onState(state()) } return state() }
    const resetUtterance = () => {
        ++generation
        clearTimeout(startTimer); startTimer = null
        const owned = utterance
        utterance = null
        if (owned) {
            owned.onstart = owned.onend = owned.onerror = owned.onboundary = null
            synthesis?.cancel?.()
        }
        clearHighlight()
    }
    const chooseVoice = requested => {
        const voices = localVoices()
        const requestedVoice = requested ? voices.find(voice => voice.voiceURI === requested) : null
        if (requested && !requestedVoice) throw new Error('The selected local voice is unavailable.')
        const language = content?.doc?.documentElement?.lang?.toLowerCase()
        const voice = requestedVoice ?? voices.find(voice => voice.voiceURI === voiceUri) ??
            voices.find(voice => language && voice.lang.toLowerCase() === language) ??
            voices.find(voice => language && voice.lang.toLowerCase().split('-')[0] === language.split('-')[0]) ??
            voices.find(voice => voice.default) ?? voices[0]
        voiceUri = voice?.voiceURI ?? ''
        return voice
    }
    const refresh = () => {
        if (disposed) return state()
        if (!synthesis || typeof Utterance !== 'function' || !localVoices().length) {
            resetUtterance()
            status = 'unavailable'
            reason = 'No locally installed speech voice is available in this reader. Install a local voice or use a supported browser.'
            requiresGesture = false
        } else if (status === 'unavailable') { status = 'stopped'; reason = '' }
        chooseVoice()
        return emit()
    }
    const prime = (fromVisible = true) => {
        content = getCurrentContent()
        if (!content?.doc?.body) throw new Error('The current chapter is not ready for read-aloud.')
        iterator = speechChunks(content.doc, {startRange:fromVisible ? content.range : null})
        chunk = iterator.next().value ?? null
        offset = 0; chunkIndex = 0
    }
    const fail = error => {
        resetUtterance()
        status = 'paused'
        reason = error instanceof Error ? error.message : String(error)
        return emit()
    }
    const speak = () => {
        if (disposed || status === 'paused') return state()
        const voice = chooseVoice()
        if (!voice) return refresh()
        if (!chunk) { advance(); return state() }
        const token = generation
        const baseOffset = offset
        const current = new Utterance(chunk.text.slice(baseOffset))
        utterance = current
        current.voice = voice; current.lang = voice.lang; current.rate = rate
        status = 'starting'; reason = ''; requiresGesture = false
        const active = () => !disposed && token === generation && utterance === current
        current.onstart = () => {
            if (!active()) return
            clearTimeout(startTimer); startTimer = null
            status = 'speaking'; emit()
        }
        current.onboundary = event => {
            if (!active() || !Number.isInteger(event.charIndex) || event.charIndex < 0) return
            offset = Math.min(chunk.text.length - 1, baseOffset + event.charIndex)
            try { reveal(content, chunk.range(offset, event.charLength > 0 ? event.charLength : 1), false) }
            catch { /* Highlighting must not interrupt a local voice. */ }
        }
        current.onend = () => {
            if (!active()) return
            clearTimeout(startTimer); startTimer = null; utterance = null
            chunk = iterator.next().value ?? null
            offset = 0; ++chunkIndex
            if (chunk) speak()
            else advance()
        }
        current.onerror = event => {
            if (!active()) return
            resetUtterance()
            status = 'paused'
            requiresGesture = event.error === 'not-allowed'
            reason = requiresGesture
                ? 'Press Continue reading inside the book to enable the local voice.'
                : `The local speech voice stopped (${String(event.error || 'speech error')}).`
            emit()
        }
        // Reveal synchronously and submit speech in the initiating task. An
        // awaited reflow before speak() can consume the browser's user gesture.
        try { reveal(content, chunk.range(baseOffset), true) }
        catch { /* A missing overlay does not disable speech. */ }
        emit()
        if (!active()) return state()
        startTimer = setTimeout(() => {
            if (!active() || status !== 'starting') return
            resetUtterance(); status = 'paused'; requiresGesture = true
            reason = 'The voice did not start. Press Continue reading inside the book.'
            emit()
        }, 8000)
        try { synthesis.speak(current) }
        catch (error) { fail(error) }
        return state()
    }
    const advance = () => {
        if (disposed || status === 'paused' || transition) return
        const target = nextSection(content?.index ?? -1)
        if (target == null) {
            resetUtterance(); status = 'stopped'; reason = 'End of book.'; emit(); return
        }
        const token = generation
        status = 'starting'; reason = 'Opening the next chapter…'; emit()
        const current = Promise.resolve().then(() => navigateToSection(target,
            () => !disposed && generation === token && status !== 'paused'))
        transition = current
        current.then(moved => {
            if (transition === current) transition = null
            if (disposed || generation !== token || status === 'paused' || moved === false) return
            prime(false)
            speak()
        }).catch(error => {
            if (transition === current) transition = null
            if (!disposed && generation === token) fail(error)
        })
    }
    const canBegin = () => {
        if (disposed) throw new Error('Read-aloud has been disposed.')
        if (visibilityDocument?.hidden) throw new Error('Read-aloud is available while this reader is visible.')
        if (transition || isNavigationPending()) throw new Error('Wait for the chapter navigation to finish before starting read-aloud.')
        if (!synthesis || typeof Utterance !== 'function' || !localVoices().length) {
            refresh(); throw new Error(reason)
        }
    }
    const start = (options = {}) => {
        canBegin()
        // Validate before disturbing an already active voice. Invalid options
        // must not leave the UI claiming that a canceled utterance is speaking.
        if (options.voiceUri && !localVoices().some(voice => voice.voiceURI === options.voiceUri))
            throw new Error('The selected local voice is unavailable.')
        const current = getCurrentContent()
        if (!current?.doc?.body) throw new Error('The current chapter is not ready for read-aloud.')
        resetUtterance(); prime()
        if (!chunk) {
            status = 'stopped'; requiresGesture = false
            reason = 'This page has no readable text. Open a chapter with text to start read-aloud.'
            return emit()
        }
        chooseVoice(options.voiceUri)
        rate = boundedRate(options.rate ?? rate)
        status = 'starting'; reason = ''; requiresGesture = false
        return speak()
    }
    const pause = () => {
        if (disposed || !['speaking','starting'].includes(status)) return state()
        // Reissuing the current word on resume works on platforms whose native
        // pause/resume is unreliable, without losing our exact text offsets.
        resetUtterance(); status = 'paused'; reason = ''; requiresGesture = false
        return emit()
    }
    const resume = () => {
        canBegin()
        if (status !== 'paused') return start()
        resetUtterance()
        const current = getCurrentContent()
        if (!chunk || current?.doc !== content?.doc || current?.index !== content?.index) prime()
        status = 'starting'; reason = ''; requiresGesture = false
        return speak()
    }
    const stop = () => {
        if (disposed) return state()
        resetUtterance(); status = localVoices().length && typeof Utterance === 'function' ? 'stopped' : 'unavailable'
        iterator = chunk = content = null; offset = chunkIndex = 0
        requiresGesture = false
        reason = status === 'unavailable' ? 'No locally installed speech voice is available in this reader.' : ''
        return emit()
    }
    const configure = (options = {}) => {
        if (disposed) return state()
        // Changing voice/rate pauses rather than unexpectedly restarting audio.
        if (['speaking','starting'].includes(status)) pause()
        chooseVoice(options.voiceUri)
        rate = boundedRate(options.rate ?? rate)
        return emit()
    }
    const onVoices = () => {
        if (utterance && !localVoices().some(voice => voice.voiceURI === voiceUri)) pause()
        refresh()
    }
    const onVisibility = () => { if (visibilityDocument?.hidden) pause() }
    synthesis?.addEventListener?.('voiceschanged', onVoices)
    visibilityDocument?.addEventListener?.('visibilitychange', onVisibility)
    refresh()
    return {state, refresh, start, pause, resume, stop, configure,
        dispose() {
            if (disposed) return
            resetUtterance(); disposed = true
            synthesis?.removeEventListener?.('voiceschanged', onVoices)
            visibilityDocument?.removeEventListener?.('visibilitychange', onVisibility)
            iterator = chunk = content = null
        },
    }
}
