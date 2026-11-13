// SPDX-License-Identifier: Apache-2.0
// Modified by CrispCloud on 2026-11-13 from File Viewer d264009.
// See ../UPSTREAM.md for retained grants and the exact modification record.
export interface PostscriptSafetyLimits {
  maxFileBytes: number
  maxPages: number
  maxSourceDimension: number
  maxCanvasDimension: number
  maxRenderedPixels: number
  maxVmBytes: number
  minDpi: number
  maxDpi: number
  workerTimeoutMs: number
}

export const DEFAULT_POSTSCRIPT_SAFETY_LIMITS: PostscriptSafetyLimits = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  maxPages: 200,
  maxSourceDimension: 100_000,
  maxCanvasDimension: 8_192,
  maxRenderedPixels: 16 * 1024 * 1024,
  maxVmBytes: 128 * 1024 * 1024,
  minDpi: 36,
  maxDpi: 300,
  workerTimeoutMs: 30_000,
})

const finiteInteger = (value: unknown, fallback: number, min: number, max: number) => {
  const number = Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.min(max, Math.max(min, Math.floor(number)))
}

export const resolvePostscriptSafetyLimits = (
  value: Partial<PostscriptSafetyLimits> = {}
): PostscriptSafetyLimits => {
  const minDpi = finiteInteger(value.minDpi, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.minDpi, 18, 300)
  const maxDpi = Math.max(
    minDpi,
    finiteInteger(value.maxDpi, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxDpi, 36, 600)
  )
  return {
    maxFileBytes: finiteInteger(value.maxFileBytes, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxFileBytes, 1, 32 * 1024 * 1024),
    maxPages: finiteInteger(value.maxPages, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxPages, 1, 200),
    maxSourceDimension: finiteInteger(
    value.maxSourceDimension,
    DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxSourceDimension,
    1,
    100_000
    ),
    maxCanvasDimension: finiteInteger(
    value.maxCanvasDimension,
    DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxCanvasDimension,
    1,
    8_192
    ),
    maxRenderedPixels: finiteInteger(
    value.maxRenderedPixels,
    DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxRenderedPixels,
    1,
    16 * 1024 * 1024
    ),
    maxVmBytes: finiteInteger(
    value.maxVmBytes,
    DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxVmBytes,
    16 * 1024 * 1024,
    128 * 1024 * 1024
    ),
    minDpi,
    maxDpi,
    workerTimeoutMs: finiteInteger(
    value.workerTimeoutMs,
    DEFAULT_POSTSCRIPT_SAFETY_LIMITS.workerTimeoutMs,
    1_000,
    30_000
    ),
  }
}
