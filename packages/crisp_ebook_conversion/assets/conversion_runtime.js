// The same reviewed native request processor runs in a fresh WASI instance.
// Its only directory is a private, memory-only /job; no host filesystem,
// network, OPFS, environment variables or process execution is available.
import WASI from './wasi_shim/wasi.js'
import {File, OpenFile, ConsoleStdout, PreopenDirectory} from './wasi_shim/fs_mem.js'

const encoder = new TextEncoder()
const decoder = new TextDecoder('utf-8', {fatal: true})
const MAX_JSON = 131072
const LIMITS = Object.freeze({input_bytes: 64 * 1024 * 1024,
    output_bytes: 128 * 1024 * 1024, expanded_bytes: 192 * 1024 * 1024,
    entry_bytes: 32 * 1024 * 1024, entries: 10000, image_pixels: 50000000})
const failure = (code, message) => ({ok: false, code, message})

export async function instantiateConversionEngine(bytes) {
    const module = await WebAssembly.compile(bytes)
    const imports = WebAssembly.Module.imports(module)
    if (imports.some(item => item.module !== 'wasi_snapshot_preview1' ||
        item.kind !== 'function' || item.name.startsWith('sock_')))
        throw new Error('Unexpected conversion engine imports')
    const exports = WebAssembly.Module.exports(module)
    if (!exports.some(item => item.name === '_start' && item.kind === 'function') ||
        !exports.some(item => item.name === 'memory' && item.kind === 'memory'))
        throw new Error('Incomplete conversion engine ABI')

    async function convert(input, requestJson) {
        if (!(input instanceof Uint8Array) || !input.length || input.length > LIMITS.input_bytes)
            return failure('limitExceeded', 'Ebook size exceeds the browser conversion limit.')
        if (typeof requestJson !== 'string' || encoder.encode(requestJson).length > MAX_JSON)
            return failure('limitExceeded', 'Conversion request is too large.')
        let request
        try { request = JSON.parse(requestJson) } catch {
            return failure('invalidInput', 'Invalid conversion request.')
        }
        if (!request || !['export', 'metadata'].includes(request.operation) ||
            !['azw3', 'mobi'].includes(request.format))
            return failure('unsupportedFormat', 'Unsupported Kindle conversion operation.')
        if (!request.limits || Object.entries(LIMITS).some(([name, max]) =>
            !Number.isSafeInteger(request.limits[name]) || request.limits[name] <= 0 ||
            request.limits[name] > max) || input.length > request.limits.input_bytes)
            return failure('limitExceeded', 'Unsupported browser conversion limits.')
        if (request.cover)
            return failure('unsupportedOperation', 'Browser cover replacement is unavailable.')
        request = {...request, work_dir: '/job', cover: false}
        const encodedRequest = encoder.encode(JSON.stringify(request))
        if (encodedRequest.length > MAX_JSON)
            return failure('limitExceeded', 'Conversion request is too large.')
        const files = new Map([
            [request.operation === 'export' ? 'input.epub' : 'input.mobi',
                new File(input, {readonly: true})],
        ])
        const directory = new PreopenDirectory('/job', files)
        let output = ''
        let outputLength = 0
        const stdout = new ConsoleStdout(data => {
            outputLength += data.length
            if (outputLength > 1024 * 1024) throw new Error('Conversion response is too large')
            output += new TextDecoder().decode(data)
        })
        const wasi = new WASI(['crisp-kindling'], [], [
            new OpenFile(new File(encodedRequest, {readonly: true})),
            stdout, new ConsoleStdout(() => {}), directory,
        ], {debug: false})
        // Bound memory allocated by the JS filesystem before each write or
        // resize. The Rust validator separately limits archive entries and
        // expanded bytes; Wasm linear memory has its own 512 MiB link limit.
        const maximumFiles = input.length + request.limits.expanded_bytes +
            request.limits.output_bytes
        const fileSizes = new Map()
        let totalFiles = 0
        function reserve(fd, requested) {
            const file = wasi.fds[fd]?.file
            if (!file) return
            if (!Number.isSafeInteger(requested) || requested < 0 ||
                requested > Math.max(request.limits.entry_bytes, request.limits.output_bytes))
                throw Object.assign(new Error('Conversion file exceeds the byte limit.'), {code: 'limitExceeded'})
            const previous = fileSizes.get(file) ?? file.data.length
            const next = Math.max(requested, file.data.length)
            if (!fileSizes.has(file)) totalFiles += previous
            if (totalFiles + next - previous > maximumFiles)
                throw Object.assign(new Error('Conversion files exceed the memory limit.'), {code: 'limitExceeded'})
            totalFiles += next - previous
            fileSizes.set(file, next)
        }
        const write = wasi.wasiImport.fd_write
        wasi.wasiImport.fd_write = (fd, iovs, count, written) => {
            const memory = new DataView(wasi.inst.exports.memory.buffer)
            let size = 0
            for (let i = 0; i < count; i++) size += memory.getUint32(iovs + 8 * i + 4, true)
            reserve(fd, Number(wasi.fds[fd]?.file_pos ?? 0n) + size)
            return write(fd, iovs, count, written)
        }
        const pwrite = wasi.wasiImport.fd_pwrite
        wasi.wasiImport.fd_pwrite = (fd, iovs, count, offset, written) => {
            const memory = new DataView(wasi.inst.exports.memory.buffer)
            let size = 0
            for (let i = 0; i < count; i++) size += memory.getUint32(iovs + 8 * i + 4, true)
            reserve(fd, Number(offset) + size)
            return pwrite(fd, iovs, count, offset, written)
        }
        for (const name of ['fd_allocate', 'fd_filestat_set_size']) {
            const original = wasi.wasiImport[name]
            wasi.wasiImport[name] = (fd, offset, length) => {
                reserve(fd, Number(offset) + Number(length ?? 0n))
                return original(fd, offset, length)
            }
        }
        try {
            const instance = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi.wasiImport})
            if (wasi.start(instance) !== 0) throw new Error('The conversion engine could not complete the operation.')
            const response = JSON.parse(output)
            if (response.ok) {
                const bytes = directory.dir.contents.get(`output.${request.format}`)?.data
                if (!(bytes instanceof Uint8Array) || bytes.length < 78 ||
                    bytes.length > request.limits.output_bytes ||
                    decoder.decode(bytes.subarray(60, 68)) !== 'BOOKMOBI')
                    throw new Error('Invalid Kindle conversion output.')
                response.bytes = bytes.slice()
            }
            return response
        } catch (error) {
            return failure(error?.code === 'limitExceeded' ? 'limitExceeded' : 'conversionFailed',
                error instanceof Error ? error.message : 'The browser converter could not process this ebook.')
        }
    }
    return {abi: 2, version: '0.46.2', convert}
}
