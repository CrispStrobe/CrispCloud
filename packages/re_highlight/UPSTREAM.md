# Re-highlight source

Vendored from the published `re_highlight` 0.0.3 package. Its original MIT
license, generated grammars and notices are retained unchanged. The fork adds
`Highlight.highlightChunks`: line-aligned bounded regex work with continuation
state, consumed by the app viewer and the vendored Re-Editor worker. This avoids
whole-document highlighting stalls on large generated source. The package is a
source-only consumer dependency; no new package has been published.
