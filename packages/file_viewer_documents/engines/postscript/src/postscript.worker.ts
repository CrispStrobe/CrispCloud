// SPDX-License-Identifier: Apache-2.0
// Modified by CrispCloud on 2026-11-13 from File Viewer d264009.
// See ../UPSTREAM.md for retained grants and the exact modification record.
/// <reference lib="webworker" />
import initStet, {
  set_max_vm,
  create_interpreter,
  page_count,
  page_dimensions,
  ps_stream_active,
  reference_dpi,
  render,
  render_viewport,
  step_ps_page,
  type Interpreter,
} from './postscriptRuntime/stet_wasm.js'
import { resolvePostscriptSafetyLimits, type PostscriptSafetyLimits } from './postscriptLimits.js'
import type {
  PostscriptOpenResult,
  PostscriptPageInfo,
  PostscriptRenderedPage,
  PostscriptWorkerRequest,
  PostscriptWorkerResponse,
} from './postscriptProtocol.js'

const scope = self as unknown as DedicatedWorkerGlobalScope
const nativeFetch = globalThis.fetch.bind(globalThis)
const pinnedWasmSha256 = 'b8d72531ec41ca497d67a79589a1dbb44748a4fefd088aa122007fbb28e06b20'
const denyExternal = () => { throw new Error('External PostScript resources are disabled.') }
Object.defineProperty(globalThis, 'fetch', {value: async () => denyExternal(), writable: false, configurable: false})
for (const name of ['XMLHttpRequest', 'WebSocket', 'EventSource', 'importScripts']) {
  Object.defineProperty(globalThis, name, {value: denyExternal, writable: false, configurable: false})
}

async function loadPinnedWasm(value: string): Promise<Uint8Array<ArrayBuffer>> {
  const url = new URL(value, scope.location.href)
  if (!/^https?:$/.test(url.protocol) || url.origin !== scope.location.origin || url.username || url.password || url.hash) {
    throw new Error('PostScript WASM must use the local viewer origin.')
  }
  const response = await nativeFetch(url, {redirect: 'error', credentials: 'omit', mode: 'same-origin'})
  if (!response.ok || !response.body) throw new Error('The bundled PostScript engine is unavailable.')
  const maximum = 16 * 1024 * 1024
  if (Number(response.headers.get('content-length')) > maximum) {
    await response.body.cancel()
    throw new Error('PostScript engine exceeds its asset byte limit.')
  }
  const reader = response.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  let complete = false
  try {
    while (true) {
      const {done, value: chunk} = await reader.read()
      if (done) break
      total += chunk.byteLength
      if (total > maximum) throw new Error('PostScript engine exceeds its asset byte limit.')
      chunks.push(chunk)
    }
    const bytes = new Uint8Array(total)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
    const hash = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('')
    if (hash !== pinnedWasmSha256) throw new Error('PostScript engine does not match the reviewed native artifact.')
    complete = true
    return bytes
  } finally {
    if (!complete) await reader.cancel().catch(() => undefined)
    reader.releaseLock()
  }
}

class PostscriptWorkerError extends Error {
  constructor(
    readonly code: string,
    message: string
  ) {
    super(message)
    this.name = 'PostscriptWorkerError'
  }
}

interface OpenDocument {
  interpreter: Interpreter
  limits: PostscriptSafetyLimits
  pages: PostscriptPageInfo[]
}

let initializedWasmUrl: string | undefined
let documentSession: OpenDocument | undefined

const closeDocument = () => {
  documentSession?.interpreter.free()
  documentSession = undefined
}

const hasPostscriptHeader = (buffer: ArrayBuffer) => {
  if (buffer.byteLength < 4) return false
  const bytes = new Uint8Array(buffer, 0, Math.min(buffer.byteLength, 32))
  const ps = bytes[0] === 0x25 && bytes[1] === 0x21 && bytes[2] === 0x50 && bytes[3] === 0x53
  const dosEps = bytes[0] === 0xc5 && bytes[1] === 0xd0 && bytes[2] === 0xd3 && bytes[3] === 0xc6
  return ps || dosEps
}

const validatePage = (
  interpreter: Interpreter,
  index: number,
  limits: PostscriptSafetyLimits
): PostscriptPageInfo => {
  const dimensions = page_dimensions(interpreter, index) as ArrayLike<number> | null
  if (!dimensions || dimensions.length < 3) {
    throw new PostscriptWorkerError('POSTSCRIPT_PAGE_INVALID', `PostScript page ${index + 1} has no dimensions.`)
  }
  const width = Number(dimensions[0])
  const height = Number(dimensions[1])
  const pageDpi = Number(dimensions[2])
  if (![width, height, pageDpi].every(Number.isFinite) || width <= 0 || height <= 0 || pageDpi <= 0) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_PAGE_INVALID',
      `PostScript page ${index + 1} reports invalid dimensions.`
    )
  }
  if (width > limits.maxSourceDimension || height > limits.maxSourceDimension) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_PAGE_DIMENSION_LIMIT',
      `PostScript page ${index + 1} exceeds the ${limits.maxSourceDimension}-unit source-dimension limit.`
    )
  }
  const minScale = limits.minDpi / pageDpi
  const minWidth = Math.max(1, Math.round(width * minScale))
  const minHeight = Math.max(1, Math.round(height * minScale))
  if (
    minWidth > limits.maxCanvasDimension ||
    minHeight > limits.maxCanvasDimension ||
    minWidth * minHeight > limits.maxRenderedPixels
  ) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_PAGE_RASTER_LIMIT',
      `PostScript page ${index + 1} cannot fit the configured raster limits even at ${limits.minDpi} DPI.`
    )
  }
  return { index, width, height, referenceDpi: pageDpi }
}

const openDocument = async (
  buffer: ArrayBuffer,
  filename: string,
  wasmUrl: string,
  limitOverrides: PostscriptSafetyLimits
): Promise<PostscriptOpenResult> => {
  closeDocument()
  const limits = resolvePostscriptSafetyLimits(limitOverrides)
  if (buffer.byteLength > limits.maxFileBytes) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_FILE_LIMIT',
      `PostScript source exceeds the ${limits.maxFileBytes}-byte safety limit.`
    )
  }
  if (!hasPostscriptHeader(buffer)) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_SIGNATURE_INVALID',
      'The source is not an Adobe PostScript document or DOS EPS container.'
    )
  }
  if (initializedWasmUrl && initializedWasmUrl !== wasmUrl) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_WASM_URL_CHANGED',
      'A PostScript Worker cannot switch WebAssembly binaries after initialization.'
    )
  }
  if (!initializedWasmUrl) {
    await initStet({ module_or_path: await loadPinnedWasm(wasmUrl) })
    initializedWasmUrl = wasmUrl
  }
  const interpreter = create_interpreter()
  set_max_vm(interpreter, limits.maxVmBytes)
  try {
    const referenceDpi = 72
    render(interpreter, new Uint8Array(buffer), referenceDpi, filename)
    while (ps_stream_active(interpreter)) {
      // Stet remains stream-active after the last showpage until a final
      // step consumes EOF. Check the count after stepping so a document at
      // the exact page limit is accepted; at most one extra native page can
      // complete before rejection, still within the interpreter VM ceiling.
      step_ps_page(interpreter)
      const knownPages = page_count(interpreter)
      if (knownPages > limits.maxPages) {
        throw new PostscriptWorkerError(
          'POSTSCRIPT_PAGE_LIMIT',
          `PostScript execution reached the ${limits.maxPages}-page safety limit before the program ended.`
        )
      }
      await new Promise<void>(resolve => setTimeout(resolve, 0))
    }
    const count = page_count(interpreter)
    if (count < 1) {
      throw new PostscriptWorkerError('POSTSCRIPT_EMPTY', 'The PostScript program did not produce a page.')
    }
    if (count > limits.maxPages) {
      throw new PostscriptWorkerError(
        'POSTSCRIPT_PAGE_LIMIT',
        `PostScript output exceeds the ${limits.maxPages}-page safety limit.`
      )
    }
    const pages = Array.from({ length: count }, (_, index) => validatePage(interpreter, index, limits))
    documentSession = { interpreter, limits, pages }
    return {
      engine: 'stet-wasm',
      engineVersion: '0.8.7',
      renderBackend: 'cpu-tiny-skia',
      colorProfile: 'CGATS001Compat-v2-micro (CC0)',
      fontSubstitutes: ['URW Base35 (OFL-1.1)'],
      pages,
    }
  } catch (error) {
    interpreter.free()
    throw error
  }
}

const renderPage = (pageIndex: number, dpi: number): PostscriptRenderedPage => {
  if (!documentSession) {
    throw new PostscriptWorkerError('POSTSCRIPT_NOT_OPEN', 'The PostScript Worker has no open document.')
  }
  const { interpreter, limits, pages } = documentSession
  if (!Number.isSafeInteger(pageIndex) || pageIndex < 0 || pageIndex >= pages.length) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_PAGE_RANGE',
      `PostScript page index ${pageIndex} is outside 0..${pages.length - 1}.`
    )
  }
  if (!Number.isFinite(dpi) || dpi < limits.minDpi || dpi > limits.maxDpi) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_DPI_LIMIT',
      `PostScript render DPI must be between ${limits.minDpi} and ${limits.maxDpi}.`
    )
  }
  const source = pages[pageIndex]
  const scale = dpi / source.referenceDpi
  const width = Math.max(1, Math.round(source.width * scale))
  const height = Math.max(1, Math.round(source.height * scale))
  if (width > limits.maxCanvasDimension || height > limits.maxCanvasDimension) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_CANVAS_DIMENSION_LIMIT',
      `PostScript raster ${width}×${height} exceeds the ${limits.maxCanvasDimension}-pixel canvas dimension limit.`
    )
  }
  if (width * height > limits.maxRenderedPixels) {
    throw new PostscriptWorkerError(
      'POSTSCRIPT_PIXEL_LIMIT',
      `PostScript raster ${width}×${height} exceeds the ${limits.maxRenderedPixels}-pixel limit.`
    )
  }
  const page = render_viewport(
    interpreter,
    pageIndex,
    0,
    0,
    source.width,
    source.height,
    width,
    height
  )
  try {
    if (page.width !== width || page.height !== height) {
      throw new PostscriptWorkerError('POSTSCRIPT_PAGE_INVALID', 'The PostScript engine returned unexpected raster dimensions.')
    }
    const bytes = page.rgba
    if (bytes.byteLength !== width * height * 4) {
      throw new PostscriptWorkerError('POSTSCRIPT_PAGE_INVALID', 'The PostScript engine returned an invalid pixel buffer.')
    }
    const rgba = new Uint8ClampedArray(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    return { pageIndex, dpi, width: page.width, height: page.height, rgba }
  } finally {
    page.free()
  }
}

const errorCode = (error: unknown) => {
  if (error instanceof PostscriptWorkerError) return error.code
  if (
    error instanceof Error &&
    'code' in error &&
    typeof (error as Error & { code?: unknown }).code === 'string'
  ) {
    return (error as Error & { code: string }).code
  }
  return 'POSTSCRIPT_ENGINE_FAILURE'
}

const processRequest = async (request: PostscriptWorkerRequest) => {
  try {
    if (request.type === 'open') {
      const result = await openDocument(request.buffer, request.filename, request.wasmUrl, request.limits)
      const response: PostscriptWorkerResponse = { id: request.id, ok: true, type: 'open', result }
      scope.postMessage(response)
      return
    }
    if (request.type === 'destroy') {
      closeDocument()
      const response: PostscriptWorkerResponse = { id: request.id, ok: true, type: 'destroy' }
      scope.postMessage(response)
      return
    }
    const result = renderPage(request.pageIndex, request.dpi)
    const response: PostscriptWorkerResponse = { id: request.id, ok: true, type: 'renderPage', result }
    scope.postMessage(response, [result.rgba.buffer as ArrayBuffer])
  } catch (error) {
    const code = errorCode(error)
    if (request.type === 'open') closeDocument()
    const response: PostscriptWorkerResponse = {
      id: request.id,
      ok: false,
      error: {
        name: error instanceof Error ? error.name : 'Error',
        code,
        message: error instanceof Error ? error.message : String(error),
        fatal: request.type === 'open' || code === 'POSTSCRIPT_ENGINE_FAILURE',
      },
    }
    scope.postMessage(response)
  }
}

let operationQueue = Promise.resolve()
scope.addEventListener('message', (event: MessageEvent<PostscriptWorkerRequest>) => {
  operationQueue = operationQueue.catch(() => undefined).then(() => processRequest(event.data))
})
