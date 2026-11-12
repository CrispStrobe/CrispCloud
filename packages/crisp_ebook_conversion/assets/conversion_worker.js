import {instantiateConversionEngine} from './conversion_runtime.js'

let loading
const engine = () => loading ??= (async () => {
    const response = await fetch(new URL('./kindling_conversion.wasm', import.meta.url))
    if (!response.ok) throw new Error('The bundled Kindle converter could not be loaded.')
    return instantiateConversionEngine(await response.arrayBuffer())
})()
let busy = false

self.onmessage = async ({data}) => {
    if (!data || !['probe', 'convert'].includes(data.kind)) return
    if (busy) {
        self.postMessage({kind: 'result', json: JSON.stringify({ok: false,
            code: 'busy', message: 'A conversion operation is still running.'})})
        return
    }
    busy = true
    try {
        const runtime = await engine()
        if (data.kind === 'probe') {
            self.postMessage({kind: 'ready', json: JSON.stringify({abi: runtime.abi, version: runtime.version})})
        } else {
            const result = await runtime.convert(new Uint8Array(data.bytes), data.request)
            const bytes = result.bytes?.buffer
            delete result.bytes
            self.postMessage({kind: 'result', json: JSON.stringify(result), bytes}, bytes ? [bytes] : [])
        }
    } catch (error) {
        self.postMessage({kind: 'result', json: JSON.stringify({ok: false,
            code: data.kind === 'probe' ? 'unavailable' : 'conversionFailed',
            message: error instanceof Error ? error.message : 'Kindle conversion failed.'})})
    } finally {
        busy = false
    }
}
