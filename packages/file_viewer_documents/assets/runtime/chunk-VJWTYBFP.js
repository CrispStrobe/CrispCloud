// packages/renderers/design/src/postscriptLimits.ts
var DEFAULT_POSTSCRIPT_SAFETY_LIMITS = Object.freeze({
  maxFileBytes: 32 * 1024 * 1024,
  maxPages: 200,
  maxSourceDimension: 1e5,
  maxCanvasDimension: 8192,
  maxRenderedPixels: 16 * 1024 * 1024,
  maxVmBytes: 128 * 1024 * 1024,
  minDpi: 36,
  maxDpi: 300,
  workerTimeoutMs: 3e4
});
var finiteInteger = (value, fallback, min, max) => {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(number)));
};
var resolvePostscriptSafetyLimits = (value = {}) => {
  const minDpi = finiteInteger(value.minDpi, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.minDpi, 18, 300);
  const maxDpi = Math.max(
    minDpi,
    finiteInteger(value.maxDpi, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxDpi, 36, 600)
  );
  return {
    maxFileBytes: finiteInteger(value.maxFileBytes, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxFileBytes, 1, 32 * 1024 * 1024),
    maxPages: finiteInteger(value.maxPages, DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxPages, 1, 200),
    maxSourceDimension: finiteInteger(
      value.maxSourceDimension,
      DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxSourceDimension,
      1,
      1e5
    ),
    maxCanvasDimension: finiteInteger(
      value.maxCanvasDimension,
      DEFAULT_POSTSCRIPT_SAFETY_LIMITS.maxCanvasDimension,
      1,
      8192
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
      1e3,
      3e4
    )
  };
};

export {
  resolvePostscriptSafetyLimits
};
