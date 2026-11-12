// Shared by the browser worker and the independent Node verification harness.
// A fresh worker owns one engine and all Wasm memory; no user file is written.
const MAX_INPUT = 64 * 1024 * 1024
const MAX_JSON = 131072
const MAX_OUTPUT = 128 * 1024 * 1024
const encoder = new TextEncoder()
const decoder = new TextDecoder('utf-8', {fatal: true})

export async function instantiateMetadataEngine(bytes) {
    const module = await WebAssembly.compile(bytes)
    if (WebAssembly.Module.imports(module).length !== 0)
        throw new Error('The metadata engine must be self-contained')
    const {exports: api} = await WebAssembly.instantiate(module)
    if (api.crisp_metadata_abi?.() !== 1 || !(api.memory instanceof WebAssembly.Memory))
        throw new Error('Unreviewed metadata engine ABI')
    const names = ['alloc', 'free', 'rewrite', 'reply_json', 'reply_json_length',
        'reply_data', 'reply_data_length', 'reply_free']
    for (const name of names) if (typeof api[`crisp_metadata_${name}`] !== 'function')
        throw new Error('Incomplete metadata engine ABI')

    function rewrite(input, request) {
        if (!(input instanceof Uint8Array) || !input.length || input.length > MAX_INPUT)
            return {ok: false, code: 'limitExceeded', message: 'Ebook size exceeds the browser metadata limit.'}
        if (typeof request !== 'string' || request.length > MAX_JSON)
            return {ok: false, code: 'limitExceeded', message: 'Metadata is too large.'}
        const json = encoder.encode(request)
        if (json.length > MAX_JSON)
            return {ok: false, code: 'limitExceeded', message: 'Metadata is too large.'}
        let inputPointer = 0, requestPointer = 0, reply = 0
        try {
            inputPointer = api.crisp_metadata_alloc(input.length)
            requestPointer = api.crisp_metadata_alloc(json.length)
            if (!inputPointer || !requestPointer) throw new Error('Metadata allocation failed')
            new Uint8Array(api.memory.buffer, inputPointer, input.length).set(input)
            new Uint8Array(api.memory.buffer, requestPointer, json.length).set(json)
            reply = api.crisp_metadata_rewrite(inputPointer, input.length, requestPointer, json.length)
            if (!reply) throw new Error('Missing metadata result')
            const responseLength = api.crisp_metadata_reply_json_length(reply)
            if (responseLength > 1024 * 1024) throw new Error('Metadata response is too large')
            const result = JSON.parse(decoder.decode(new Uint8Array(api.memory.buffer,
                api.crisp_metadata_reply_json(reply), responseLength)))
            if (result.ok) {
                const length = api.crisp_metadata_reply_data_length(reply)
                if (!length || length > MAX_OUTPUT) throw new Error('Invalid metadata output size')
                result.bytes = new Uint8Array(api.memory.buffer,
                    api.crisp_metadata_reply_data(reply), length).slice()
            }
            return result
        } finally {
            if (reply) api.crisp_metadata_reply_free(reply)
            if (requestPointer) api.crisp_metadata_free(requestPointer, json.length)
            if (inputPointer) api.crisp_metadata_free(inputPointer, input.length)
        }
    }
    return {abi: 1, version: '0.46.2', rewrite}
}
