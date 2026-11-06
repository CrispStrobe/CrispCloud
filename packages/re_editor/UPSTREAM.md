# Re-Editor provenance

This directory contains the runtime sources of **re_editor 0.10.0**, published
by Reqable under the MIT license. The original copyright and complete license
are retained in `LICENSE`.

- Upstream repository: https://github.com/reqable/re-editor
- Published archive: https://pub.dev/api/archives/re_editor-0.10.0.tar.gz
- Archive SHA-256 from CrispCloud's original lockfile and the matching pub cache
  verification record:
  `66671c4774a6b4c5254c9a53ab35a083e7e7da9ae371c519bcf491c70a2a4e56`

`UPSTREAM.json` records the SHA-256 of every copied upstream file before local
changes. The runtime library, package manifest, analyzer configuration and
license are copied from that cached release. Example applications, screenshots,
generated files and build output are excluded.

## Local maintenance

The only changed upstream file is `lib/src/_code_editable.dart`. Its cursor
blink controller now keeps the mobile cursor's 100 ms delayed reveal in a
`Timer`, cancels that timer when blinking restarts or stops, and clears the
timer reference after it fires. Disposal already calls `stopBlink`, so it
also cancels the pending reveal. The periodic blink timer and reveal delay
are otherwise unchanged.

The hosted release used an untracked `Future.delayed`. Closing a focused
Android or iOS editor before the delay elapsed could therefore notify the
cursor controller after disposal. Unfocusing first did not cancel that
callback. The regression failed on both mobile platform variants against
the hosted release before this patch was applied. The original file hashes
in `UPSTREAM.json` remain the upstream hashes, including the patched file's
original hash.

The host's mobile cursor disposal regression is in
`test/code_editor_widget_test.dart` at the application root. It focuses the real
`CodeEditor`, disables further focus requests, removes the widget immediately,
then advances the test clock beyond the delayed mobile cursor reveal. Android
and iOS variants cover removal without a route animation.

The application manifest and lockfile control whether this maintained copy is
selected. They must change together. Check the hosted-release failure before
switching, then check the maintained-copy success before merging or publishing.
