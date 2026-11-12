import assert from 'node:assert/strict'
import {normalizeAppearance, appearanceStyle, readingCapabilities, progressFraction,
    navigationHistory, navigateHistory, createNavigationQueue,
    guardRendererLifecycle} from '../../assets/reader_controls.js'
import {SectionProgress} from '../../assets/foliate/progress.js'

// Run with the parser suite's DOM and the actual pinned Foliate View class.
// Layout/rendering assertions remain in the separate real-browser suite.
export async function checkReadingControls(View) {
    const options = {fontSize:22, lineHeight:1.9, theme:'sepia', flow:'scrolled',
        fontFamily:'sans-serif', maxColumnCount:3, pageMargin:42, pageWidth:940,
        usePublisherStyles:false}
    assert.deepEqual(normalizeAppearance(JSON.parse(JSON.stringify(options))), options)
    assert.deepEqual(normalizeAppearance({fontSize:Infinity, lineHeight:99,
        fontFamily:'serif; background:url(https://invalid.example)', theme:'url(bad)',
        flow:'bad', maxColumnCount:1000, pageMargin:-20, pageWidth:NaN,
        usePublisherStyles:'false'}), {
        fontSize:18, lineHeight:2.5, theme:'light', flow:'paginated', fontFamily:'serif',
        maxColumnCount:3, pageMargin:0, pageWidth:780, usePublisherStyles:true,
    })
    const overridden = appearanceStyle(options)
    assert.deepEqual(overridden.attributes, {flow:'scrolled', 'max-column-count':'3',
        'max-inline-size':'940px', margin:'42px'})
    assert.match(overridden.styles[1], /font-family: sans-serif !important/)
    const publisher = appearanceStyle({...options, usePublisherStyles:true})
    assert.match(publisher.styles[0], /font-family: sans-serif/)
    assert.doesNotMatch(publisher.styles[1], /font-family:/)
    assert(!appearanceStyle({fontFamily:'url(https://invalid.example)'}).styles.join('').includes('url('))
    assert.equal(progressFraction(-1), 0)
    assert.equal(progressFraction(2), 1)
    assert.equal(progressFraction(0.375), 0.375)
    for (const invalid of [NaN, Infinity, -Infinity, '0.5', null])
        assert.throws(() => progressFraction(invalid), /finite/)

    const progress = new SectionProgress([
        {size:100}, {size:100, linear:'no'}, {size:300},
    ], 1500, 1600)
    const [section, anchor] = progress.getSection(0.625)
    assert.equal(section, 2)
    assert(Math.abs(anchor - 0.5) < 1e-12)
    assert.deepEqual(progress.getSection(0), [0, 0])
    assert.deepEqual(progress.getSection(1), [2, 1])

    const view = new View()
    const destinations = []
    view.resolveNavigation = state => ({state})
    view.renderer = {goTo:destination => destinations.push(destination.state),
        setStyles() {}, setAttribute() {}}
    view.getSectionFractions = () => progress.sectionFractions
    assert(readingCapabilities(view).supportsProgressSeeking)
    assert(readingCapabilities(view).supportsTextAppearance)
    view.isFixedLayout = true
    assert(readingCapabilities(view).supportsProgressSeeking)
    assert(!readingCapabilities(view).supportsTextAppearance)
    assert(!readingCapabilities(view).supportsLayout)
    assert(!readingCapabilities(view).supportsPublisherStyles)
    view.getSectionFractions = () => [0, NaN]
    assert(!readingCapabilities(view).supportsProgressSeeking)

    const updates = []
    view.history.addEventListener('index-change', () => updates.push(navigationHistory(view)))
    view.history.pushState('epubcfi(/6/2!/4/2)')
    // Normal page movement replaces the current position, not a new Back step.
    view.history.replaceState('epubcfi(/6/2!/4/10)')
    assert.equal(navigationHistory(view).canGoBack, false)
    view.history.pushState('epubcfi(/6/4!/4/2)')
    assert.equal(navigationHistory(view).canGoBack, true)
    assert.deepEqual(await navigateHistory(view, 'back'), {canGoBack:false, canGoForward:true})
    assert.equal(destinations.at(-1), 'epubcfi(/6/2!/4/10)')
    assert.deepEqual(await navigateHistory(view, 'forward'), {canGoBack:true, canGoForward:false})
    assert.equal(destinations.at(-1), 'epubcfi(/6/4!/4/2)')
    await navigateHistory(view, 'back')
    view.history.pushState({fraction:0.7})
    assert.equal(navigationHistory(view).canGoForward, false)
    const count = destinations.length
    await navigateHistory(view, 'forward')
    assert.equal(destinations.length, count)
    assert(updates.some(state => state.canGoForward))
    view.history.clear()
    assert.deepEqual(navigationHistory(view), {canGoBack:false, canGoForward:false})
    await assert.rejects(navigateHistory({}, 'back'), /unavailable/)
    await assert.rejects(navigateHistory(view, 'up'), /Unknown/)
    view.history.pushState('first')
    view.history.pushState('second')
    let finishRender
    const render = () => new Promise(resolve => finishRender = resolve)
    view.renderer.goTo = render
    let completed = false
    const historyMove = navigateHistory(view, 'back').then(() => completed = true)
    assert.equal(view.renderer.goTo, render, 'Temporary navigation capture must be restored immediately')
    await Promise.resolve()
    assert.equal(completed, false, 'History completion must await the actual renderer')
    finishRender()
    await historyMove
    assert.equal(completed, true)

    const enqueue = createNavigationQueue()
    const order = []
    let release
    const first = enqueue(async () => {
        order.push('first start')
        await new Promise(resolve => release = resolve)
        order.push('first finish')
    })
    const second = enqueue(() => { order.push('second'); throw new Error('bad target') })
    const rejected = assert.rejects(second, /bad target/)
    const third = enqueue(() => order.push('third'))
    await Promise.resolve()
    assert.deepEqual(order, ['first start'])
    release()
    await Promise.all([first, rejected, third])
    assert.deepEqual(order, ['first start', 'first finish', 'second', 'third'])

    let contents = []
    let rendered = 0
    const renderer = {
        isConnected:true,
        getContents:() => contents,
        render() {
            // This is the exact failing operation reported by Chromium CI.
            const {style} = contents[0].doc.body
            assert(style)
            ++rendered
        },
    }
    contents = [{doc:{documentElement:document.documentElement, body:null}}]
    assert.throws(() => renderer.render(), /style/)
    guardRendererLifecycle({renderer, isFixedLayout:false})
    renderer.render()
    assert.equal(rendered, 0, 'An incomplete iframe must not be sent to Foliate render()')
    contents = [{doc:document}]
    renderer.render()
    assert.equal(rendered, 1, 'Ready documents still render normally')
    renderer.isConnected = false
    renderer.render()
    assert.equal(rendered, 1, 'A detached renderer must not reflow its removed iframe')
    view.remove()
    console.log('PASS bounded appearance, publisher-style cascade, progress mapping, capabilities, actual Foliate navigation history, async navigation queue and iframe lifecycle guard')
}
