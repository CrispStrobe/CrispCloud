import assert from 'node:assert/strict'
import {secureSections} from '../../assets/security.js'

const deferred = () => {
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    return {promise, resolve, reject}
}

export async function checkSectionResourceLifecycle() {
    const created = new Set()
    const originalCreate = URL.createObjectURL
    const originalRevoke = URL.revokeObjectURL
    URL.createObjectURL = blob => {
        const url = originalCreate(blob)
        created.add(url)
        return url
    }
    URL.revokeObjectURL = url => { created.delete(url); originalRevoke(url) }
    const cleanups = []
    const fixture = () => {
        const requests = []
        let originalUrl = null, unloads = 0
        const section = {
            load:async () => {
                const request = deferred()
                requests.push(request)
                await request.promise
                originalUrl = URL.createObjectURL(new Blob([
                    '<!doctype html><html><body><script>bad()</script><p>Reading text</p></body></html>',
                ], {type:'text/html'}))
                return originalUrl
            },
            unload:() => {
                ++unloads
                if (originalUrl) URL.revokeObjectURL(originalUrl)
                originalUrl = null
            },
        }
        const cleanup = secureSections({sections:[section]})
        cleanups.push(cleanup)
        return {section, requests, cleanup, unloads:() => unloads}
    }
    try {
        const shared = fixture()
        const first = shared.section.load()
        const second = shared.section.load()
        const document = shared.section.createDocument()
        assert.equal(shared.requests.length, 1, 'Renderer and search must share an in-flight section load')
        shared.requests[0].resolve()
        const [one, two, doc] = await Promise.all([first, second, document])
        assert.equal(one, two)
        assert.equal(doc.querySelector('script'), null)
        assert.equal(doc.querySelector('p').textContent, 'Reading text')
        assert.equal(created.size, 2, 'Exactly one upstream and one sanitized blob should remain')
        // A document request has captured its blob before unload. Revocation
        // must not make an already-started search fail with a missing blob URL.
        const captured = shared.section.createDocument()
        shared.section.unload()
        assert.equal((await captured).querySelector('p').textContent, 'Reading text')
        assert.equal(created.size, 0)
        assert.equal(shared.unloads(), 1)
        shared.cleanup()
        shared.cleanup()
        await assert.rejects(shared.section.load(), /canceled/)
        await assert.rejects(shared.section.createDocument(), /canceled/)

        const replaced = fixture()
        const obsolete = replaced.section.load()
        const obsoleteRejected = assert.rejects(obsolete, /canceled/)
        replaced.section.unload()
        const replacement = replaced.section.load()
        const replacementDocument = replaced.section.createDocument()
        assert.equal(replaced.requests.length, 1, 'The replacement must wait for stale upstream cleanup')
        replaced.requests[0].resolve()
        await obsoleteRejected
        // Wait for the replacement to pass the old in-flight completion.
        for (let i = 0; i < 10 && replaced.requests.length < 2; ++i) await Promise.resolve()
        assert.equal(replaced.requests.length, 2)
        assert.equal(replaced.unloads(), 1)
        assert.equal(created.size, 0, 'A canceled completion must release its upstream blob')
        replaced.requests[1].resolve()
        const fresh = await replacement
        assert.equal((await replacementDocument).querySelector('p').textContent, 'Reading text')
        assert.equal((await fetch(fresh)).ok, true, 'Stale cleanup must not revoke the new section')
        assert.equal(created.size, 2)
        replaced.cleanup()
        assert.equal(created.size, 0)

        const closed = fixture()
        const pending = closed.section.load()
        const pendingRejected = assert.rejects(pending, /canceled/)
        closed.cleanup()
        await assert.rejects(closed.section.load(), /canceled/)
        closed.requests[0].resolve()
        await pendingRejected
        assert.equal(closed.unloads(), 1)
        assert.equal(created.size, 0, 'Closing during load must not publish a late blob')

        const retry = fixture()
        const failure = retry.section.load()
        const failed = assert.rejects(failure, /read failed/)
        retry.requests[0].reject(new Error('read failed'))
        await failed
        const recovered = retry.section.load()
        assert.equal(retry.requests.length, 2, 'A failed load must not poison the cache')
        retry.requests[1].resolve()
        assert.equal((await fetch(await recovered)).ok, true)
        retry.cleanup()
        assert.equal(created.size, 0)
        console.log('PASS concurrent section loads, search snapshots, unload/reload ordering, failure retry and terminal resource disposal')
    } finally {
        for (const cleanup of cleanups) cleanup()
        for (const url of created) originalRevoke(url)
        URL.createObjectURL = originalCreate
        URL.revokeObjectURL = originalRevoke
    }
}
