// The pinned EPUB parser uses the standard grouping methods, which older
// WebKit runtimes lack. Keep this small host-owned fallback outside the vendor
// tree and leave native implementations intact. No publication code runs here.
// Algorithm: https://tc39.es/ecma262/multipage/abstract-operations.html#sec-groupby
const checkArguments = (items, callback) => {
    if (items === null || items === undefined)
        throw new TypeError('Grouping requires an iterable')
    if (typeof callback !== 'function')
        throw new TypeError('Grouping requires a callback function')
}

const objectGroupBy = {
    groupBy(items, callback) {
        checkArguments(items, callback)
        const groups = Object.create(null)
        let index = 0
        for (const value of items) {
            if (index >= Number.MAX_SAFE_INTEGER)
                throw new TypeError('Grouping exceeds the iteration limit')
            // A computed key performs the language's exact ToPropertyKey
            // conversion, including objects whose primitive value is a Symbol.
            const key = Reflect.ownKeys({[callback(value, index++)]: null})[0]
            if (Object.prototype.hasOwnProperty.call(groups, key))
                groups[key].push(value)
            else groups[key] = [value]
        }
        return groups
    },
}.groupBy

const mapGroupBy = {
    groupBy(items, callback) {
        checkArguments(items, callback)
        const groups = new Map()
        let index = 0
        for (const value of items) {
            if (index >= Number.MAX_SAFE_INTEGER)
                throw new TypeError('Grouping exceeds the iteration limit')
            const key = callback(value, index++)
            // Map preserves object/Symbol keys and provides SameValueZero
            // equality for NaN and signed zero without string coercion.
            if (groups.has(key)) groups.get(key).push(value)
            else groups.set(key, [value])
        }
        return groups
    },
}.groupBy

export function installReaderCompatibility() {
    for (const [owner, value] of [[Object, objectGroupBy], [Map, mapGroupBy]]) {
        if (typeof owner.groupBy === 'function') continue
        Object.defineProperty(owner, 'groupBy', {
            value, writable:true, configurable:true, enumerable:false,
        })
    }
}

installReaderCompatibility()
