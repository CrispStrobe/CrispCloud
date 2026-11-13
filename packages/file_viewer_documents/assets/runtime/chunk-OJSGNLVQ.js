// packages/renderers/wordperfect/src/parser.ts
var MAX_WORDPERFECT_INPUT_BYTES = 64 * 1024 * 1024;
var MAX_WORDPERFECT_WIRE_BYTES = 32 * 1024 * 1024;
var MAX_WORDPERFECT_EVENTS = 2e5;
var MAX_WORDPERFECT_TEXT_BYTES = 8 * 1024 * 1024;
var MAX_WORDPERFECT_BLOCKS = 2e4;
var MAX_WORDPERFECT_CELLS = 5e4;
var assertWordPerfectInput = (buffer) => {
  if (!(buffer instanceof ArrayBuffer) || buffer.byteLength === 0) {
    throw new Error("WordPerfect input is empty or is not an ArrayBuffer.");
  }
  if (buffer.byteLength > MAX_WORDPERFECT_INPUT_BYTES) {
    throw new Error("WordPerfect file exceeds the 64 MiB preview limit.");
  }
};

export {
  MAX_WORDPERFECT_WIRE_BYTES,
  MAX_WORDPERFECT_EVENTS,
  MAX_WORDPERFECT_TEXT_BYTES,
  MAX_WORDPERFECT_BLOCKS,
  MAX_WORDPERFECT_CELLS,
  assertWordPerfectInput
};
