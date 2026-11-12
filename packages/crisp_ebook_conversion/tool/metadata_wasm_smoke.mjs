// Independent record checks and native/Wasm parity. Run tool/smoke.py first.
import assert from 'node:assert/strict'
import {readFile, writeFile, mkdtemp, rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {spawnSync} from 'node:child_process'
import {createHash} from 'node:crypto'
import {instantiateMetadataEngine} from '../assets/metadata_runtime.js'

const root = fileURLToPath(new URL('../', import.meta.url))
const binary = process.argv[2] || path.join(root, 'native/target/release',
    process.platform === 'win32' ? 'crisp-kindling.exe' : 'crisp-kindling')
const wasm = await readFile(path.join(root, 'assets/kindling_metadata.wasm'))
const module = await WebAssembly.compile(wasm)
assert.deepEqual(WebAssembly.Module.imports(module), [], 'No network/filesystem/thread imports')
const engine = await instantiateMetadataEngine(wasm)
const limits = {input_bytes: 67108864, output_bytes: 134217728,
    expanded_bytes: 201326592, entry_bytes: 33554432, entries: 10000, image_pixels: 50000000}
const request = (metadata = {}, format = 'azw3', extra = {}) => JSON.stringify({
    format, metadata, input_limit: limits.input_bytes, output_limit: limits.output_bytes, ...extra})
const hash = data => createHash('sha256').update(data).digest('hex')

function records(bytes) {
    bytes = Buffer.from(bytes)
    assert.equal(bytes.subarray(60, 68).toString(), 'BOOKMOBI')
    const count = bytes.readUInt16BE(76)
    assert.ok(count > 0 && 78 + count * 8 <= bytes.length)
    const offsets = Array.from({length: count}, (_, i) => bytes.readUInt32BE(78 + i * 8))
    assert.ok(offsets.every((value, i) => value >= 78 + count * 8 &&
        value <= bytes.length && (i === 0 || value >= offsets[i - 1])))
    return offsets.map((start, i) => bytes.subarray(start, offsets[i + 1] ?? bytes.length))
}

function exth(record) {
    assert.equal(record.subarray(16, 20).toString(), 'MOBI')
    const start = 16 + record.readUInt32BE(20)
    if (!(record.readUInt32BE(128) & 0x40)) return new Map()
    assert.equal(record.subarray(start, start + 4).toString(), 'EXTH')
    const count = record.readUInt32BE(start + 8)
    const end = start + record.readUInt32BE(start + 4)
    assert.ok(end <= record.length)
    const result = new Map()
    let cursor = start + 12
    for (let i = 0; i < count; i++) {
        const type = record.readUInt32BE(cursor), size = record.readUInt32BE(cursor + 4)
        assert.ok(size >= 8 && cursor + size <= end)
        const values = result.get(type) || []
        values.push(record.subarray(cursor + 8, cursor + size))
        result.set(type, values)
        cursor += size
    }
    return result
}

function sections(book) {
    const result = [0]
    const boundary = exth(book[0]).get(121)?.[0]
    if (boundary && boundary.length === 4) {
        const value = boundary.readUInt32BE(0)
        if (value !== 0xffffffff) {
            assert.equal(book[value - 1].toString(), 'BOUNDARY')
            assert.equal(book[value].subarray(16, 20).toString(), 'MOBI')
            result.push(value)
        }
    }
    return result
}

function unchangedResources(before, after) {
    const original = records(before), edited = records(after)
    assert.equal(edited.length, original.length)
    const headers = sections(original)
    assert.deepEqual(sections(edited), headers)
    for (let i = 0; i < original.length; i++) if (!headers.includes(i))
        assert.deepEqual(edited[i], original[i], `Nonmetadata record ${i} was changed`)
}

async function nativeRewrite(input, patch, format) {
    const folder = await mkdtemp(path.join(tmpdir(), 'crisp-metadata-parity-'))
    try {
        await writeFile(path.join(folder, 'input.mobi'), input)
        const result = spawnSync(binary, [], {cwd: folder, encoding: 'utf8',
            input: JSON.stringify({work_dir: folder, operation: 'metadata',
                format, metadata: patch, cover: false, limits})})
        assert.equal(result.status, 0, result.stderr || String(result.error))
        const line = result.stdout.trim().split('\n').filter(value => value.startsWith('{')).at(-1)
        const info = JSON.parse(line)
        assert.equal(info.ok, true, JSON.stringify(info))
        assert.deepEqual(await readFile(path.join(folder, 'input.mobi')), input)
        return {info, bytes: await readFile(path.join(folder, `output.${format}`))}
    } finally { await rm(folder, {recursive: true, force: true}) }
}

const patch = {title: 'Über Café 世界', authors: ['Alice', 'Béla'],
    publisher: 'Éditions 世界', description: 'A preserved description & notes.',
    language: 'de', isbn: '9781234567897', asin: 'B012345678',
    publication_date: '2026-11-12', subjects: ['One', '世界'],
    identifier: 'urn:uuid:12345678-1234-1234-1234-123456789abc'}
const clear = {publisher: '', description: '', isbn: '', asin: '',
    publication_date: '', subjects: []}
let count = 0
for (const filename of ['book.azw3', 'book.mobi', 'legacy.mobi']) {
    const format = filename.endsWith('.azw3') ? 'azw3' : 'mobi'
    const input = await readFile(path.join(root, 'test/fixtures/generated', filename))
    const baseline = hash(input)
    const noop = engine.rewrite(input, request({}, format))
    assert.equal(noop.ok, true, JSON.stringify(noop))
    assert.equal(noop.noOp, true)
    assert.deepEqual(Buffer.from(noop.bytes), input)
    const result = engine.rewrite(input, request(patch, format))
    assert.equal(result.ok, true, JSON.stringify(result))
    unchangedResources(input, result.bytes)
    const native = await nativeRewrite(input, patch, format)
    assert.deepEqual(Buffer.from(result.bytes), native.bytes, `${filename} native/Wasm bytes differ`)
    assert.deepEqual(result.changes, native.info.changes)
    const again = engine.rewrite(result.bytes, request(patch, format))
    assert.equal(again.noOp, true)
    assert.deepEqual(again.bytes, result.bytes)
    const edited = records(result.bytes)
    for (const index of sections(edited)) {
        const fields = exth(edited[index])
        for (const [type, expected] of [[503, [patch.title]], [100, patch.authors],
            [101, [patch.publisher]], [103, [patch.description]], [104, [patch.isbn]],
            [105, patch.subjects], [106, [patch.publication_date]], [504, [patch.asin]],
            [524, [patch.language]]]) {
            assert.deepEqual(fields.get(type)?.map(value => value.toString()), expected,
                `${filename} section ${index} field ${type}`)
        }
    }
    const cleared = engine.rewrite(result.bytes, request(clear, format))
    assert.equal(cleared.ok, true)
    unchangedResources(result.bytes, cleared.bytes)
    const nativeClear = await nativeRewrite(Buffer.from(result.bytes), clear, format)
    assert.deepEqual(Buffer.from(cleared.bytes), nativeClear.bytes)
    for (const index of sections(records(cleared.bytes))) {
        const fields = exth(records(cleared.bytes)[index])
        for (const type of [101, 103, 104, 105, 106, 504]) assert.equal(fields.has(type), false)
    }
    const protectedInput = Buffer.from(input)
    const first = protectedInput.readUInt32BE(78)
    protectedInput.writeUInt16BE(2, first + 12)
    assert.equal(engine.rewrite(protectedInput, request({}, format)).code, 'drmProtected')
    for (const index of sections(records(input)).slice(1)) {
        const protectedSecond = Buffer.from(input)
        const offset = protectedSecond.readUInt32BE(78 + index * 8)
        protectedSecond.writeUInt16BE(2, offset + 12)
        assert.equal(engine.rewrite(protectedSecond, request({}, format)).code, 'drmProtected')
    }
    const malformed = Buffer.from(input)
    malformed.writeUInt32BE(input.length + 10, 86)
    assert.equal(engine.rewrite(malformed, request({}, format)).code, 'conversionFailed')
    assert.equal(engine.rewrite(input, request({}, format, {input_limit: 10})).code, 'limitExceeded')
    assert.equal(engine.rewrite(input, request(patch, format, {output_limit: 10})).code, 'limitExceeded')
    assert.equal(hash(input), baseline)
    count++
    console.log(`PASS ${filename}: all fields, native parity, idempotence, clear, source/record preservation, DRM and budgets`)
}
assert.equal(engine.rewrite(new Uint8Array([1, 2, 3]), request()).code, 'conversionFailed')
assert.equal(engine.rewrite(new Uint8Array([1]), request({title: 'x'.repeat(131073)})).code, 'limitExceeded')
console.log(`PASS metadata Wasm (${wasm.length} bytes, no host imports), ${count} real Kindle fixtures`)
