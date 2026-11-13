// SPDX-License-Identifier: MIT
// Small, fail-closed changes to the immutable reviewed Apache PPT runtime.
// The SVG hook carries only locally loaded fonts into its standalone image.
export const pptFontPatches = [
  {
    path: 'runtime.js',
    before: "const blob = new Blob([output.html], { type: 'image/svg+xml' });",
    after: "const svg = options.transformSvg ? await options.transformSvg(output.html) : output.html;\n                const blob = new Blob([svg], { type: 'image/svg+xml' });",
  },
  {
    path: 'layout/measure.js',
    before: 'px "${family}",sans-serif`;',
    after: 'px "${family}","Liberation Sans","Noto Naskh Arabic",sans-serif`;',
  },
  {
    path: 'render/safe.js',
    before: "}', sans-serif`; }",
    after: "}', 'Liberation Sans', 'Noto Naskh Arabic', sans-serif`; }",
  },
];

export function patchPptFontSource(source, patch) {
  if (source.split(patch.before).length !== 2) {
    throw new Error(`The pinned PPT font hook no longer matches exactly: ${patch.path}`);
  }
  return source.replace(patch.before, patch.after);
}
