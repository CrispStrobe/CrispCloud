# Foreground read-aloud

The enhanced reader can read the already sanitized publication text with a
locally installed voice exposed by its browser runtime. A runtime without that
capability reports it as unavailable. The portable Flutter chapter reader does
not provide this speech backend.

## Reusable Flutter controls

Open the dialog with the same controller that owns the enhanced reader:

```dart
await showDialog<void>(
  context: context,
  builder: (_) => EbookSpeechDialog(
    controller: readerController,
    translate: appTranslate,
  ),
);
```

`EbookSpeechDialog` is exported by `package:crisperbooks/crisperbooks.dart`. It
refreshes local voice availability, follows live state, and exposes start,
pause, resume, stop, voice selection and reading speed from 0.5× to 2.0×. A
voice or speed change pauses active reading; resuming is an explicit action.
Errors remain in the controls and leave the book open. Closing the dialog
leaves speech active so the reader can follow the text.

Some embedded browsers require activation inside the book frame. If the voice
rejects activation or fails to start, the reader offers **Continue reading**.
The dialog explains this and provides **Return to book** so its modal barrier
does not prevent pressing that in-reader button. This does not bypass the
browser's activation policy.

Applications can supply their own controls with
`CrispEbookController.refreshSpeech`, `startSpeech`, `pauseSpeech`,
`resumeSpeech`, `stopSpeech` and `setSpeechOptions`. Listen to the controller or
`CrispEbookReader.onSpeechChanged` for `EbookSpeechState`; availability must come
from this state, rather than from the operating system name. The host retains
ownership of the controller, the book and its persistence.

## Reading behavior

Reading begins at the visible publication range and advances across linear
chapters. Text is divided into bounded Unicode chunks while retaining the
original DOM offsets. Highlights are drawn in the reader's overlay; publication
text nodes are not rewritten, so their CFI locations remain unchanged. Pause
retains the latest word boundary reported by the voice. If the backend does
not report boundaries, resume may repeat the current chunk.

Explicit navigation cancels speech. Hiding or backgrounding the reader pauses
it, and disposing or replacing the publication cancels its pending work. Late
utterance callbacks and asynchronous chapter transitions cannot restart a
stopped reader. The Flutter controller rejects stale state revisions and
replies from a replaced transport.

Only voices explicitly marked `localService: true` by the platform are
selectable. No publication text is submitted to an explicitly remote voice.
This relies on the platform's classification; it does not install a speech
engine or download voice data. Missing voices remain visibly unavailable and
can be checked again with **Refresh voices**.

## Qualification and limits

The deterministic JavaScript tests exercise Unicode text ranges, hidden-content
filtering, local-only voice selection, exact resumed offsets, activation
failure, navigation cancellation, visibility changes and disposal. The actual
browser harness exercises the real reader DOM, bridge and overlay with a
deterministic speech adapter. Flutter controller and dialog tests cover command
transitions, unavailable voices, recoverable errors, explicit voice/rate
changes, activation handoff, late replies, and a small viewport.

These checks do not establish audible speech on a device or the presence of a
voice in a particular WebView. Platform voice availability, audible output,
audio focus and device accessibility remain runtime qualification items.
Background playback, lock-screen controls, voice downloads, media overlays and
selection-to-speech are not implemented by this foreground backend.
