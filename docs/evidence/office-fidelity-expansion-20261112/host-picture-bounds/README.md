# Legal small-slide picture boundary fixture

The complete host producer at `8b96fe9717196aea0ef678c2690aa1fb1195e4a5` passed 1,147 engine tests and 180 host tests and produced all 468 declared packages. Independent SDK validation then found exactly three errors, one in each `slide-picture-bounds` export: the authored slide height was 762,000 EMU, below the schema minimum of 914,400 EMU.

The fixture now uses the legal minimum height. Its expected picture y-position follows the existing ten-percent slide offset (91,440 EMU). Width, aspect ratio, image bytes, three save/reopen assertions, production code, and validation requirements are unchanged. The focused real host test passes and all three corrected packages pass the same frozen SDK validator. These are focused receipts; final acceptance must run at the newly published commit.

`failed-*.gz` preserves the full original 468-file SDK report, log, input manifest and failure summary. `corrected-inputs/` contains the three packages measured by the focused schema report. The original failed complete input snapshot also remains outside the checkout for the final acceptance archive.
