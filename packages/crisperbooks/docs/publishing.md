# Preparing a pub.dev release

No package has been published. `publish_to: none` remains until the version is
qualified and publication is requested.

This is a Dart pub workspace. Internal dependencies use version constraints;
development resolution uses matching workspace packages. Future published
manifests therefore do not need internal path or Git dependencies.

Release order:

1. `crisp_ebook` (pure Dart model and editing/export core).
2. `crisp_ebook_reader` (Flutter reader).
3. `crisp_ebook_conversion` (optional converter).
4. `crisperbooks` (Flutter facade and editing/portable-reader controls).

Before removing `publish_to: none`, run package and application checks at the
intended immutable revision, confirm runtime results on claimed platforms, run
`dart pub publish --dry-run` for each package, inspect archives and API docs,
review existing licenses and third-party notices, choose versions, and confirm
package names and publisher ownership. Compilation is not a device test.

`.pubignore` excludes generated outputs and workspace sibling sources. The
converter retains Rust sources, build hook, lockfiles, browser assets and notices.
Generated Wasm has recorded source/asset hashes and rebuild commands.

Until publication, applications pin unpublished packages to one full Git SHA and
override internal hosted constraints to that same Git source. After publication,
normal hosted constraints replace those temporary overrides. Do not use a moving
feature branch in a release application.

References: [pub workspaces](https://dart.dev/tools/pub/workspaces),
[package dependencies](https://dart.dev/tools/pub/dependencies), and
[publishing packages](https://dart.dev/tools/pub/publishing).
