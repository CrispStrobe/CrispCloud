import assert from 'node:assert/strict'

export async function checkReaderCompatibility() {
    const originalObject = Object.getOwnPropertyDescriptor(Object, 'groupBy')
    const originalMap = Object.getOwnPropertyDescriptor(Map, 'groupBy')
    try {
        const {installReaderCompatibility} = await import('../../assets/reader_compat.js')
        if (typeof originalObject?.value === 'function')
            assert.equal(Object.groupBy, originalObject.value, 'The first import preserves native Object.groupBy')
        if (typeof originalMap?.value === 'function')
            assert.equal(Map.groupBy, originalMap.value, 'The first import preserves native Map.groupBy')
        const retainedObject = Object.groupBy, retainedMap = Map.groupBy
        installReaderCompatibility()
        assert.equal(Object.groupBy, retainedObject, 'Existing Object implementation is retained')
        assert.equal(Map.groupBy, retainedMap, 'Existing Map implementation is retained')
        delete Object.groupBy
        delete Map.groupBy
        installReaderCompatibility()
        for (const owner of [Object, Map]) {
            const descriptor = Object.getOwnPropertyDescriptor(owner, 'groupBy')
            assert.equal(descriptor.enumerable, false)
            assert.equal(descriptor.configurable, true)
            assert.equal(descriptor.writable, true)
            assert.equal(owner.groupBy.length, 2)
            assert.equal(owner.groupBy.name, 'groupBy')
            assert.throws(() => new owner.groupBy([], value => value), TypeError)
        }

        const symbol = Symbol('publication')
        const keys = ['__proto__', 'constructor', 'toString', 'x', '2', '1', symbol, '__proto__']
        const grouped = Object.groupBy(keys, value => value)
        assert.equal(Object.getPrototypeOf(grouped), null)
        assert.deepEqual(Reflect.ownKeys(grouped), ['1', '2', '__proto__', 'constructor', 'toString', 'x', symbol])
        assert.deepEqual(grouped.__proto__, ['__proto__', '__proto__'])
        assert.deepEqual(grouped.constructor, ['constructor'])
        assert.deepEqual(grouped[symbol], [symbol])
        assert.equal(Object.getPrototypeOf({}), Object.prototype)
        let coercionHint
        const symbolObject = {[Symbol.toPrimitive](hint) { coercionHint = hint; return symbol }}
        assert.deepEqual(Object.groupBy([7], () => symbolObject)[symbol], [7])
        assert.equal(coercionHint, 'string')

        const first = {}, second = {}
        const values = [first, NaN, second, NaN, -0, 0, symbol, first]
        const mapped = Map.groupBy(values, value => value)
        assert.deepEqual([...mapped.keys()], [first, NaN, second, 0, symbol])
        assert.deepEqual(mapped.get(first), [first, first])
        assert.deepEqual(mapped.get(NaN), [NaN, NaN])
        assert.deepEqual(mapped.get(0), [-0, 0])
        assert.equal(Object.is([...mapped.keys()][3], -0), false)
        const uncoercible = {[Symbol.toPrimitive]() { throw new Error('Map must not coerce keys') }}
        assert.deepEqual(Map.groupBy([9], () => uncoercible).get(uncoercible), [9])

        for (const groupBy of [Object.groupBy, Map.groupBy]) {
            const calls = []
            groupBy('a😀b', function(value, index) {
                calls.push([value, index, this])
                return index % 2
            })
            assert.deepEqual(calls, [['a', 0, undefined], ['😀', 1, undefined], ['b', 2, undefined]])
            assert.throws(() => groupBy(null, () => 1), TypeError)
            assert.throws(() => groupBy(undefined, () => 1), TypeError)
            assert.throws(() => groupBy({}, () => 1), TypeError)
            assert.throws(() => groupBy({[Symbol.iterator]:1}, () => 1), TypeError)
            let iteratorRequested = false
            const lazy = {[Symbol.iterator]() { iteratorRequested = true; return [][Symbol.iterator]() }}
            assert.throws(() => groupBy(lazy, null), TypeError)
            assert.equal(iteratorRequested, false, 'Validate the callback before requesting an iterator')
            const failure = new Error('callback failure')
            let closed = false
            function* source() {
                try { yield 1; yield 2 }
                finally { closed = true }
            }
            assert.throws(() => groupBy(source(), () => { throw failure }), error => error === failure)
            assert.equal(closed, true, 'Callback failure closes an active iterator')
            const broken = {[Symbol.iterator]() { return {next() { throw failure }} }}
            assert.throws(() => groupBy(broken, value => value), error => error === failure)
        }
        let keyIteratorClosed = false
        function* keySource() {
            try { yield 1 }
            finally { keyIteratorClosed = true }
        }
        assert.throws(() => Object.groupBy(keySource(), () => uncoercible), /must not coerce/)
        assert.equal(keyIteratorClosed, true, 'Property-key conversion failure also closes the iterator')

        const retained = Object.groupBy
        delete Map.groupBy
        installReaderCompatibility()
        assert.equal(Object.groupBy, retained, 'A missing Map implementation does not replace Object.groupBy')
        assert.equal(typeof Map.groupBy, 'function')
        console.log('PASS missing grouping APIs: native preservation, prototype safety, key order, symbols, callback indices and iterator errors')
    } finally {
        if (originalObject) Object.defineProperty(Object, 'groupBy', originalObject)
        else delete Object.groupBy
        if (originalMap) Object.defineProperty(Map, 'groupBy', originalMap)
        else delete Map.groupBy
    }
}
