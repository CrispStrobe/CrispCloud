# Selected XML validation and transformation tools

The selected Apache File Viewer sources are pinned to
[`d264009ca6efb3daed79a39d1ae63133e0f25558`](https://github.com/flyfish-dev/file-viewer/tree/d264009ca6efb3daed79a39d1ae63133e0f25558/packages/renderers/text).
`UPSTREAM.json` records original source hashes, published runtime versions and
copied grant files. This adapter does not include the complete text renderer.

## Runtime and grants

- `xmllint-wasm` **5.3.0**, MIT wrapper and libxml2 MIT-style grant, performs
  real XSD validation in a disposable module worker. `xmllint-browser.mjs` and
  `xmllint.wasm` are unchanged published assets.
- `xslt-polyfill` **1.0.33**, BSD-3-Clause wrapper, supplies the embedded
  libxml2/libxslt/libexslt MIT-style engine in `xslt-wasm.js`. The published
  asset is unchanged. Before compilation, the inherited Apache memory guard
  caps its defined WASM memory at 1,024 pages (64 MiB), without changing
  instructions or data.
- The libxml2 revisions are `c34742f3017f6d39f3e4ccae4f70172238160ef8`
  for XSLT and `eb0a2f2b91566384f378d870ffcd69c0a24162cc` for XSD;
  libxslt/libexslt uses `923903c59d668af42e3144bc623c9190a0f65988`.
  The published xmllint build links zlib, whose exact version is not identified
  by its npm metadata. The retained upstream notice states that limitation and
  includes the Zlib grant conservatively. No independent native rebuild is
  claimed.
- DOMPurify **3.4.17** offers `MPL-2.0 OR Apache-2.0`; this route selects
  Apache-2.0. Its complete original license is retained. The existing selected
  File Viewer core decoding helper is Apache-2.0.

Preserve `LICENSE`, `licenses/`, this modification notice and the exact
published package inventories from the shared build manifest. Font packages,
remote schemas, full text-formatting runtimes and unrelated File Viewer
renderers are not required by this selection.

## Host and build contract

Stage upstream `packages/renderers/text/src`, then overlay this directory's
`src`. Bundle `entry.ts`; it exports `renderXml` and a default alias with
`(buffer, target, context)`. Keep these files in the same flat runtime directory:

| File | Source |
| --- | --- |
| `xmllint-browser.mjs` | xmllint-wasm 5.3.0 published package |
| `xmllint.wasm` | xmllint-wasm 5.3.0 published package |
| `xslt-wasm.js` | xslt-polyfill 1.0.33 `dist/xslt-wasm.js` |

The host supplies a same-origin HTTP(S) document surface with blob workers,
WebAssembly and sandboxed blob frames. Its `context.signal` must be aborted on
replacement/close. Optional `context.options.xml.limits` can lower the input,
resource and output limits; `timeoutMs` may lower the per-operation deadline
from 15 seconds to at least 100 ms. Higher host values never raise hard caps.

## Local modifications, 2026-11-13

- New local-file/paste UI for independent XSD validation and XSLT 1.0
  transformation. The input source is never rewritten. XML and text
  transformation results are shown as exact output source. HTML also gets an
  inert preview; it is not reported as a faithful executable web page.
- Hard limits: 4 MiB original/decoded UTF-8 XML, 2 MiB schema/stylesheet,
  4 MiB output, 2 MiB per selected runtime asset, 15 seconds per operation,
  64 MiB XML WASM memory. Runtime fetches are same-origin, streamed/bounded
  and reject redirects.
- Keep the upstream DTD/entity, XInclude, schema dependency, XSLT
  import/include, `document()` and extension-instruction rejection. The
  actual worker disables network APIs and XSD also uses `--nonet`.
- Extend the worker result with its engine-reported media type and support
  standard `html`, `xml` and `text` output. Verify result pointers before
  decoding bounded output. Only HTML creates a preview iframe.
- HTML output is sanitized and sandboxed without script permissions. It has
  a `default-src 'none'` CSP; links, forms, refresh/base elements and external
  navigation attributes are removed. File inputs and other form controls are
  also removed because a sandbox alone does not prevent user-activated native
  file pickers. Only the trusted XML tools retain schema/stylesheet selectors.
  The exact original transformation output remains available as text.
- Cancellation destroys disposable workers. New resources invalidate older
  results; local file reads cannot replace a later selection. Destroy aborts
  work, clears data, removes listeners and revokes preview object URLs.

## Validation

Deterministic Node tests run with:

```sh
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node --test packages/file_viewer_documents/engines/xml/test/xml.test.mjs
```

They exercise resource guards and byte/memory limits, genuine xmllint XSD
validation and genuine embedded libxslt transformations. XML DOM guard unit
checks use the real xmldom parser under Node. Those checks are not browser DOM,
worker or CSP qualification.

Real browser acceptance is separately runnable on an enabled Linux CI runner:

```sh
FILE_VIEWER_UPSTREAM_DIR=/path/to/file-viewer node packages/file_viewer_documents/engines/xml/test/browser-smoke.mjs
```

Install the pinned tooling dependencies and Playwright Chromium first (or set
`CHROMIUM_EXECUTABLE` to an available compatible Chromium). Browser cases cover
valid/invalid XSD, real HTML/XML/text transformation, external-resource
rejection, user-click schema/stylesheet file chooser events, output bounds,
cancellation, cleanup and inert HTML without form controls. Browser chooser
events exercise the selected File API inputs; platform-native chooser dialogs
are qualified separately by their host tests. Local Chromium
was unavailable because process socket creation was denied; browser success is
not claimed until the real CI script completes. No fake compiler or replacement
WASM is used by either set of engine tests.
