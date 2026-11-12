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

function fullName(record) {
    const start = record.readUInt32BE(84), length = record.readUInt32BE(88)
    assert.ok(start + length <= record.length)
    return record.subarray(start, start + length)
}

function decodeMetadata(header, bytes) {
    const encoding = header.readUInt32BE(28)
    assert.ok([1252, 65001].includes(encoding))
    // Use the platform decoder, independently of Kindling's encoder.
    return new TextDecoder(encoding === 1252 ? 'windows-1252' : 'utf-8',
        {fatal: true}).decode(bytes)
}

function u32(value) {
    const bytes = Buffer.alloc(4)
    bytes.writeUInt32BE(value)
    return bytes
}

// Fixture surgery only. Metadata is rebuilt inside the original header's
// padding; record offsets and all nonmetadata records remain unchanged.
function withHeader(input, index, {encoding, fields, hasExth = true} = {}) {
    const original = records(input)[index]
    const headerLength = 16 + original.readUInt32BE(20)
    let block = Buffer.alloc(0)
    if (hasExth) {
        const entries = []
        let count = 0
        for (const [type, values] of fields ?? exth(original)) {
            for (const value of values) {
                entries.push(u32(type), u32(value.length + 8), value)
                count++
            }
        }
        const data = Buffer.concat(entries)
        const length = (data.length + 12 + 3) & ~3
        block = Buffer.concat([Buffer.from('EXTH'), u32(length), u32(count),
            data, Buffer.alloc(length - data.length - 12)])
    }
    const name = fullName(original), nameOffset = headerLength + block.length
    assert.ok(nameOffset + name.length <= original.length)
    const header = Buffer.alloc(original.length)
    original.copy(header, 0, 0, headerLength)
    block.copy(header, headerLength)
    name.copy(header, nameOffset)
    header.writeUInt32BE(nameOffset, 84)
    header.writeUInt32BE(name.length, 88)
    const flags = original.readUInt32BE(128)
    header.writeUInt32BE((hasExth ? flags | 0x40 : flags & ~0x40) >>> 0, 128)
    if (encoding !== undefined) header.writeUInt32BE(encoding, 28)
    const output = Buffer.from(input)
    header.copy(output, output.readUInt32BE(78 + index * 8))
    return output
}

// Match the established smoke fixture's standalone KF7 surgery, retaining all
// of its text/resource records and marking EXTH121 as having no KF8 section.
function legacyOnly(input) {
    const parts = records(input), headers = sections(parts)
    assert.equal(headers.length, 2)
    const boundary = headers[1]
    const fields = exth(parts[0])
    fields.set(121, [u32(0xffffffff)])
    const first = records(withHeader(input, 0, {fields}))[0]
    const kept = [first, ...parts.slice(1, boundary - 1)]
    const header = Buffer.from(input.subarray(0, 78))
    header.writeUInt16BE(kept.length, 76)
    const table = []
    let offset = 78 + kept.length * 8 + 2
    for (let index = 0; index < kept.length; index++) {
        table.push(u32(offset), input.subarray(82 + index * 8, 86 + index * 8))
        offset += kept[index].length
    }
    return Buffer.concat([header, ...table, Buffer.alloc(2), ...kept])
}

async function nativeOperation(input, patch, format, operation = 'metadata') {
    const folder = await mkdtemp(path.join(tmpdir(), 'crisp-metadata-parity-'))
    try {
        const name = operation === 'metadata' ? 'input.mobi' : 'input.epub'
        await writeFile(path.join(folder, name), input)
        const result = spawnSync(binary, [], {cwd: folder, encoding: 'utf8',
            input: JSON.stringify({work_dir: folder, operation,
                format, metadata: patch, cover: false, limits})})
        assert.equal(result.status, 0, result.stderr || String(result.error))
        const line = result.stdout.trim().split('\n').filter(value => value.startsWith('{')).at(-1)
        const info = JSON.parse(line)
        assert.deepEqual(await readFile(path.join(folder, name)), input)
        const bytes = await readFile(path.join(folder, `output.${format}`)).catch(error => {
            assert.equal(error.code, 'ENOENT')
            return null
        })
        return {info, bytes}
    } finally { await rm(folder, {recursive: true, force: true}) }
}

async function nativeRewrite(input, patch, format) {
    const result = await nativeOperation(input, patch, format)
    assert.equal(result.info.ok, true, JSON.stringify(result.info))
    assert.ok(result.bytes)
    return result
}

let edgeCases = 0, encodingRejections = 0
async function checkedEdgeCase(input, patch, format, inspect) {
    const baseline = Buffer.from(input)
    const result = engine.rewrite(input, request(patch, format))
    assert.equal(result.ok, true, JSON.stringify(result))
    assert.equal(result.noOp, false)
    unchangedResources(input, result.bytes)
    const native = await nativeRewrite(input, patch, format)
    assert.deepEqual(Buffer.from(result.bytes), native.bytes, 'Native/Wasm edge-case output differs')
    assert.deepEqual(result.changes, native.info.changes)
    inspect(records(result.bytes))
    const repeated = engine.rewrite(result.bytes, request(patch, format))
    assert.equal(repeated.ok, true, JSON.stringify(repeated))
    assert.equal(repeated.noOp, true)
    assert.deepEqual(repeated.bytes, result.bytes)
    const nativeRepeated = await nativeRewrite(Buffer.from(result.bytes), patch, format)
    assert.equal(nativeRepeated.info.noOp, true)
    assert.deepEqual(nativeRepeated.bytes, Buffer.from(result.bytes))
    assert.deepEqual(input, baseline)
    edgeCases++
    return result
}

async function rejectedEncoding(input, patch, diagnostic) {
    const baseline = Buffer.from(input)
    const result = engine.rewrite(input, request(patch, 'mobi'))
    assert.equal(result.ok, false)
    assert.equal(result.code, 'conversionFailed')
    assert.ok(result.message.includes(diagnostic), result.message)
    assert.equal(result.bytes, undefined)
    const native = await nativeOperation(input, patch, 'mobi')
    assert.equal(native.info.ok, false)
    assert.equal(native.info.code, result.code)
    assert.ok(native.info.message.includes(diagnostic), native.info.message)
    assert.equal(native.bytes, null, 'Rejected encoding must not publish output')
    assert.deepEqual(input, baseline)
    encodingRejections++
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

    const headerIndexes = sections(records(input))
    // For dual files keep the primary EXTH121 so the missing KF8 EXTH remains
    // discoverable; standalone AZW3/MOBI fixtures exercise the primary header.
    const missingIndex = headerIndexes.at(-1)
    const withoutExth = withHeader(input, missingIndex, {hasExth: false})
    assert.equal(exth(records(withoutExth)[missingIndex]).size, 0)
    const newMetadata = {authors: ['New author'], publisher: 'New publisher',
        description: 'Metadata added to a section without EXTH.'}
    await checkedEdgeCase(withoutExth, newMetadata, format, headers => {
        for (const index of headerIndexes) {
            assert.equal(headers[index].readUInt32BE(128) & 0x40, 0x40)
            const fields = exth(headers[index])
            for (const [type, values] of [[100, newMetadata.authors],
                [101, [newMetadata.publisher]], [103, [newMetadata.description]]])
                assert.deepEqual(fields.get(type)?.map(value => decodeMetadata(headers[index], value)), values)
            assert.deepEqual(fullName(headers[index]), fullName(records(withoutExth)[index]))
        }
    })

    for (const emptyRecord of [false, true]) {
        let missingTitle = Buffer.from(input)
        for (const index of headerIndexes) {
            const fields = exth(records(missingTitle)[index])
            assert.ok(fields.has(542), 'Fixture retains a title hash to clear')
            if (emptyRecord) fields.set(503, [Buffer.alloc(0)])
            else fields.delete(503)
            missingTitle = withHeader(missingTitle, index, {fields})
            assert.ok(fullName(records(missingTitle)[index]).length > 0)
        }
        await checkedEdgeCase(missingTitle, {title: ''}, format, headers => {
            for (const index of headerIndexes) {
                assert.equal(exth(headers[index]).has(503), false)
                assert.equal(exth(headers[index]).has(542), false)
                assert.equal(headers[index].readUInt32BE(88), 0)
                assert.equal(fullName(headers[index]).length, 0)
            }
        })
    }
    count++
    console.log(`PASS ${filename}: all fields, native parity, idempotence, clear, no-EXTH, missing/empty title, source/record preservation, DRM and budgets`)
}

// The regular fixtures contain UTF-8 Greek/Japanese body text. Create a real
// ASCII-body export before declaring Windows-1252; do not simply mislabel that
// existing Unicode body. Python's stdlib only rewrites text fixture members.
const asciiEpub = spawnSync(process.platform === 'win32' ? 'python' : 'python3', ['-c', `
import io, sys, zipfile
output = io.BytesIO()
with zipfile.ZipFile(sys.argv[1]) as source, zipfile.ZipFile(output, 'w') as target:
    for item in source.infolist():
        data = source.read(item.filename)
        if item.filename.endswith(('.xhtml', '.html', '.opf', '.ncx', '.css')):
            data = data.decode('utf-8').encode('ascii', errors='replace')
        target.writestr(item, data)
sys.stdout.buffer.write(output.getvalue())
`, path.join(root, 'test/fixtures/book.epub')])
assert.equal(asciiEpub.status, 0, String(asciiEpub.stderr))
const asciiExport = await nativeOperation(asciiEpub.stdout, {}, 'mobi', 'export')
assert.equal(asciiExport.info.ok, true, JSON.stringify(asciiExport.info))
assert.ok(asciiExport.bytes)
const cpPatch = {title: 'Café € —', authors: ['Béla', '€ditor'],
    publisher: 'Éditions', description: '“Quotes” — €', subjects: ['café', '€']}
const title1252 = Buffer.from([0x43, 0x61, 0x66, 0xe9, 0x20, 0x80, 0x20, 0x97])
for (const [name, candidate] of [['legacy', legacyOnly(asciiExport.bytes)],
    ['mixed-codepage dual', asciiExport.bytes]]) {
    const input = withHeader(candidate, 0, {encoding: 1252})
    await checkedEdgeCase(input, cpPatch, 'mobi', headers => {
        for (const index of sections(headers)) {
            const header = headers[index]
            assert.equal(header.readUInt32BE(28), index === 0 ? 1252 : 65001)
            const fields = exth(header)
            for (const [type, values] of [[503, [cpPatch.title]], [100, cpPatch.authors],
                [101, [cpPatch.publisher]], [103, [cpPatch.description]], [105, cpPatch.subjects]])
                assert.deepEqual(fields.get(type)?.map(value => decodeMetadata(header, value)), values)
            const title = index === 0 ? title1252 : Buffer.from(cpPatch.title, 'utf8')
            assert.deepEqual(fields.get(503), [title])
            assert.deepEqual(fullName(header), title)
            assert.deepEqual(fields.get(542), [createHash('md5').update(title).digest().subarray(0, 4)])
        }
    })
    for (const patch of [{title: '世界'}, {authors: ['Author 😀']},
        {description: 'Must not replace U+0080 with Euro: \u0080'}]) {
        await rejectedEncoding(input, patch,
            'metadata cannot be represented losslessly in MOBI text encoding 1252')
    }
    await rejectedEncoding(withHeader(input, 0, {encoding: 932}), {title: 'New ASCII title'},
        'unsupported MOBI text encoding 932')
    const noop = engine.rewrite(input, request({}, 'mobi'))
    assert.equal(noop.ok, true, JSON.stringify(noop))
    assert.equal(noop.noOp, true)
    assert.deepEqual(Buffer.from(noop.bytes), input)
    console.log(`PASS ${name}: Windows-1252 bytes/decoder/MD5, UTF-8 KF8 preservation, native/Wasm parity, rejection without output`)
}
assert.equal(engine.rewrite(new Uint8Array([1, 2, 3]), request()).code, 'conversionFailed')
assert.equal(engine.rewrite(new Uint8Array([1]), request({title: 'x'.repeat(131073)})).code, 'limitExceeded')
console.log(`PASS metadata Wasm (${wasm.length} bytes, no host imports), ${count} real Kindle fixtures, ${edgeCases} native/Wasm edge cases, ${encodingRejections} explicit encoding rejections`)
