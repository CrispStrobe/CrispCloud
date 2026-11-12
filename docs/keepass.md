# KeePass database viewing and editing

`.kdbx` opens in a dedicated database surface. It is distinct from Autodesk's
`.kbdx` keyboard-profile XML format.

## Using the viewer and editor

- **F3** opens a read-only viewer. Enter the master password, choose a key file,
  or use both. For a key-file-only database, turn off the password component.
  An explicitly empty password and no password component are distinct.
- The compact **preview pane** displays a locked card. Selecting a database
  does not download or unlock it; choose **Unlock database** to open the viewer.
- **F4** opens the editor. Browse existing groups or search entry titles and
  usernames. View the title, username, password, URL and notes. Passwords remain
  obscured until explicitly revealed or copied.
- **New entry**, **Edit entry** and **Delete entry** modify the unlocked
  in-memory database. New entries can use the selected existing group. Deletion
  follows the database's recycle-bin setting; deleting an already recycled
  entry creates a deletion tombstone. Recycled entries are excluded from
  **All groups** and remain visible when their group is selected.
- **Save** encrypts the complete edited database and writes through its captured
  file target. A changed/disconnected source or save conflict leaves the work
  dirty. A platform download of a copy does not count as saving the original.
  The close dialog offers save/discard when there are changes.

Detached attachment bytes and archive-origin files are read only. A different
pane location or account never becomes a replacement save destination.

## Locking and sensitive data

Manual lock, app backgrounding and five minutes of inactivity immediately hide
the unlocked surface. Pending changes are encrypted into an in-memory checkpoint
before the decrypted session and editing controllers are released. Unlocking
that checkpoint requires the password/key file again. This checkpoint is not a
persistent backup: use **Save** to retain changes across app closure.

If checkpoint encryption fails, the dialog keeps the unsaved session hidden
instead of silently discarding edits, displays an error, and requires successful
reauthentication to recover the retained work. An in-flight save keeps ownership
of its original document; its completion cannot mark a replacement document as
saved or locked.

Only encrypted bytes go to storage. This editor does not use plaintext text
editor recovery files, remember credentials, log secrets, send network requests
to a conversion service or automatically open entry URLs. Master-password and
key-file inputs are cleared after unlocking. Mutable buffers are cleared on a
best-effort basis; Dart cannot guarantee erasure of immutable strings or all
garbage-collected copies.

A copied password is cleared after 30 seconds or on lock/close if the clipboard
still contains that value and the copy operation still owns it. Clipboard reads
can be refused by browsers/platforms, so clipboard clearing is best effort.

## Supported database features

| Feature | Support |
| --- | --- |
| Versions | KDBX 3.0/3.1 and 4.0/4.1 |
| Outer encryption | AES-256-CBC and ChaCha20 |
| Key derivation | AES-KDF and Argon2d/Argon2id, versions 0x10 and 0x13, within the limits below |
| Credentials | Master password, key file, or both; XML v1/v2 key files, raw 32-byte, 64-character hex and arbitrary-file SHA-256 key material |
| Entry editing | Title, username, password, URL and notes; add/delete entries in existing groups |
| Existing data | Preserve unknown XML elements/attributes, custom fields, auto-type data, attachments, entry history and database metadata |
| Changes recorded | Keep a history snapshot before editing an existing entry; update modification/location times as appropriate |
| Database format | Keep its version, cipher, compression and KDF parameters; generate fresh encryption salts/IVs on save |

This is an editor for existing databases. It does not create a new vault, change
the master key, edit groups/custom fields/attachments, provide auto-type, or
implement hardware challenge-response and Windows-account key providers.
Unsupported ciphers, KDF features and malformed structures fail with a fixed
error; they are never silently downgraded.

The service uses the authenticated raw XML document instead of reconstructing
it from a reduced entry model. Protected values are tracked independently and
re-encrypted in document order. Inner binary attachment IDs and flags retain
their positions, including duplicate attachment contents. KDBX4 block HMACs,
including the terminal block, are checked before content is exposed.

## Resource limits

These are application limits, not restrictions of the KDBX specification.

| Limit | Value |
| --- | --- |
| Encrypted file and decoded document | 32 MiB each |
| Key file / individual edited field | 1 MiB each |
| Active groups and entries | 20,000 combined |
| XML structure | 200,000 parser events; depth 64; group depth 48 |
| KDBX4 inner binary attachments | 4,096 records |
| AES-KDF | At most 2,000,000 rounds |
| Argon2 memory | 64 MiB native; 16 MiB web |
| Argon2 memory × iterations | 256 MiB native; 32 MiB web |
| Argon2 iterations / parallelism | At most 10 / 16 |

Saved output must pass the same structural limits as input. Existing databases
above a limit receive a resource-limit error. The editor does not reduce their
KDF settings. Native unlock/save uses a worker isolate; browser AES-KDF work
yields between bounded chunks. Browser Argon2 still runs in the Dart JavaScript
runtime, so the web limits are lower.

## Dependencies and verification

The runtime is the MIT-licensed [KPassLib](https://github.com/vladimir-skorokhodov/kpasslib)
1.1.2, pinned to commit `81d51d9f3575f72136441ea5a271f6748e3ca77c` and vendored
with its license. It is a Dart port of KdbxWeb. The
[provenance record](../packages/kpasslib/UPSTREAM.md) lists local adaptations.
Argon2 delegates to the already-present PointyCastle implementation, using its
portable arithmetic on JavaScript. All runtime dependencies are permissively
licensed; no FFI/native shared library is required for this feature.

`test/keepass_service_test.dart` uses public, unchanged KeePass-generated files
from upstream, including KDBX3, KDBX4.1, Argon2d/id, AES/ChaCha20 and different
key-file variants. It checks editing/reopening, unchanged unknown/protected data,
attachments/history, incorrect credentials, corrupt authentication, resource
limits and disposal. The fixture directory records source and license details.

Widget tests exercise real and deterministic encrypted saves, read-only
attachments, conflicts, dirty close behavior, locking during work, failed lock
recovery, key-file-only unlock and asynchronous source/clipboard ownership.
Routing tests cover F3/F4 and the locked compact preview. UI controls are
translated into all nine supported languages.

`tool/verify_keepass_crypto.dart` checks a known Argon2 answer on VM/JavaScript.
`tool/verify_keepass_database.dart` also passes complete JavaScript
open/edit/save/reopen cycles for KDBX3/AES-KDF/AES, KDBX4/Argon2id/AES and
KDBX4/Argon2d/ChaCha20, including history and unknown protected XML. It can run
under Node with the browser-style `self` global provided:

```sh
dart compile js -O1 --no-source-maps tool/verify_keepass_database.dart -o /tmp/keepass.js
node -e 'globalThis.self = globalThis; require("/tmp/keepass.js")'
```

The combined development run passed **360 tests across 28 suites**, including
all new KeePass and Word-conversion suites and existing parser, viewer, archive,
favorites and editor regressions.
After the final inner-header allocation guard, a focused rerun passed all
18 backend/crypto tests, including rejection of a 4,097th inner binary record
before allocation and refusal to save a database beyond that limit.

These tests do not constitute a third-party security audit. A full Flutter web
release build and end-user platform acceptance remain CI/release checks; the
local cached SDK lacks the Flutter web target artifacts. Exact combined test
results are recorded in the PR.
