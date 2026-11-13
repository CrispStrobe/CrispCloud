// SPDX-License-Identifier: Apache-2.0
// Modified by CrispCloud on 2026-11-13 from File Viewer d264009.
// See ../UPSTREAM.md for retained grants and the exact modification record.
import type { FileViewerXmlDiagnosticCode, FileViewerXmlOptions } from '@file-viewer/core'

export class XmlProfileError extends Error {
  constructor(public readonly code: FileViewerXmlDiagnosticCode, message: string) {
    super(message)
    this.name = 'XmlProfileError'
  }
}

const MiB = 1024 * 1024
export const xmlHardLimits = Object.freeze({
  maxXmlBytes: 4 * MiB,
  maxResourceBytes: 2 * MiB,
  maxOutputBytes: 8 * MiB,
  maxProfiles: 32,
  maxTotalResourceBytes: 16 * MiB
})

export function resolveXmlLimits(options: FileViewerXmlOptions) {
  const limits: Record<keyof typeof xmlHardLimits, number> = { ...xmlHardLimits }
  for (const key of Object.keys(limits) as (keyof typeof limits)[]) {
    const value = options.limits?.[key]
    if (value !== undefined) {
      if (!Number.isSafeInteger(value) || value < 1) {
        throw new XmlProfileError('invalid-manifest', `Invalid XML limit: ${key}`)
      }
      limits[key] = Math.min(value, limits[key])
    }
  }
  return limits
}

export function checkXmlAbort(signal: AbortSignal) {
  if (signal.aborted) {
    throw signal.reason instanceof XmlProfileError
      ? signal.reason
      : new XmlProfileError('cancelled', 'XML profile processing was cancelled.')
  }
}

export function sameOriginXmlUrl(value: string, base: string, origin: string): string {
  let url: URL
  try { url = new URL(value, base) } catch {
    throw new XmlProfileError('resource-error', 'Invalid XML resource URL.')
  }
  if (!/^https?:$/.test(url.protocol) || url.origin !== origin || url.username || url.password || url.hash) {
    throw new XmlProfileError('unsafe-resource', 'XML resources must use same-origin HTTP(S) URLs without credentials or fragments.')
  }
  return url.href
}

export async function fetchXmlBytes(url: string, maxBytes: number, signal: AbortSignal): Promise<Uint8Array> {
  checkXmlAbort(signal)
  const response = await fetch(url, {
    signal, redirect: 'error', credentials: 'same-origin', mode: 'same-origin', referrerPolicy: 'no-referrer'
  })
  if (!response.ok) {
    await response.body?.cancel()
    throw new XmlProfileError('resource-error', `XML resource returned HTTP ${response.status}.`)
  }
  const length = Number(response.headers.get('content-length'))
  if (length > maxBytes) {
    await response.body?.cancel()
    throw new XmlProfileError('limit-exceeded', 'XML resource exceeds its byte limit.')
  }
  if (!response.body) return new Uint8Array()
  const reader = response.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0
  let completed = false
  try {
    while (true) {
      checkXmlAbort(signal)
      const { done, value } = await reader.read()
      if (done) break
      total += value.byteLength
      if (total > maxBytes) throw new XmlProfileError('limit-exceeded', 'XML resource exceeds its byte limit.')
      chunks.push(value)
    }
    checkXmlAbort(signal)
    completed = true
    const bytes = new Uint8Array(total)
    let offset = 0
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
    return bytes
  } finally {
    if (!completed) await reader.cancel().catch(() => undefined)
    reader.releaseLock()
  }
}

const XSD = 'http://www.w3.org/2001/XMLSchema'
const XSL = 'http://www.w3.org/1999/XSL/Transform'

export function parseSafeXml(source: string, documentRef: Document, kind: 'xml' | 'xsd' | 'xslt'): XMLDocument {
  // Reject declarations before invoking any XML parser, including entity expansion.
  if (/<!\s*(?:DOCTYPE|ENTITY)\b/i.test(source)) {
    throw new XmlProfileError('unsafe-resource', 'DTD and entity declarations are disabled for XML profiles.')
  }
  const Parser = documentRef.defaultView?.DOMParser
  if (!Parser) throw new XmlProfileError('engine-error', 'XML parsing requires a browser document.')
  const doc = new Parser().parseFromString(source, 'application/xml')
  if (!doc.documentElement || doc.getElementsByTagName('parsererror').length) {
    throw new XmlProfileError('invalid-xml', `Malformed ${kind.toUpperCase()} document.`)
  }
  const root = doc.documentElement
  if (kind === 'xsd' && (root.namespaceURI !== XSD || root.localName !== 'schema')) {
    throw new XmlProfileError('invalid-xml', 'Expected an XML Schema document.')
  }
  if (kind === 'xslt' && (root.namespaceURI !== XSL || !['stylesheet', 'transform'].includes(root.localName))) {
    throw new XmlProfileError('invalid-xml', 'Expected an XSLT 1.0 stylesheet.')
  }
  for (const element of Array.from(doc.getElementsByTagName('*'))) {
    if (
      (element.namespaceURI === XSD && ['include', 'import', 'redefine', 'override'].includes(element.localName)) ||
      (element.namespaceURI === XSL && ['include', 'import'].includes(element.localName)) ||
      element.namespaceURI === 'http://www.w3.org/2001/XInclude'
    ) {
      throw new XmlProfileError('unsafe-resource', 'Schema dependencies, XSLT imports/includes and XInclude are disabled.')
    }
    if (kind !== 'xslt') continue
    for (const attribute of Array.from(element.attributes)) {
      // DOM values decode character references, so docum&#101;nt() cannot bypass this guard.
      if (/(?:^|[^\w.-])document\s*\(/.test(attribute.value) ||
          (attribute.localName === 'extension-element-prefixes' && attribute.value.trim())) {
        throw new XmlProfileError('unsafe-resource', 'XSLT document() and extension instructions are disabled.')
      }
    }
    if (element.namespaceURI === XSL && element.localName === 'output') {
      const method = element.getAttribute('method')
      if (method && !['html', 'xml', 'text'].includes(method)) throw new XmlProfileError('transform-error', 'Only standard HTML, XML and text XSLT output is supported.')
    }
  }
  return doc
}

/** Only the engine copy is normalized; the source renderer keeps the original buffer. */
export function xmlEngineText(source: string): string {
  return source.replace(/^(\uFEFF?<\?xml\s[^?]*?encoding\s*=\s*)(["'])[^"']*\2/, '$1"UTF-8"')
}
