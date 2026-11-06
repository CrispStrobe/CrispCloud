# Native hex package provenance

Upstream: https://github.com/madedit/madedit2
Revision: `288d35747faccb1cb997c4a30afc40c6cb48b0ae` (v1.0.2), MIT.
The original copyright and permission notice are retained in LICENSE.

`lib/hex_layout.dart` adapts the byte-column layout, offset and nibble helpers
from upstream `lib/editor/hex_view.dart`. The embeddable Flutter widget,
serialized controller, persistent byte-only AVL document and CrispCloud storage
adapter are integration code developed here, not an unchanged upstream widget.
They deliberately omit text newline indexing, encoding-aligned byte mutations,
global app settings, Rust, scripting, and Tree-sitter.

The package is vendored so the app does not depend on an uncreated fork or an
unpublished package. A separate GitHub fork is being retried independently;
no fork success is asserted by this file. Keep this provenance when migrating
the maintained package into the eventual fork.
