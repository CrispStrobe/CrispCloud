import 'package:xterm2/xterm.dart';

/// An explicit keyboard, IME or paste operation. Each recipient re-encodes it
/// with its own keyboard and bracketed-paste modes. Nothing is serialized.
class TerminalUserInput {
  TerminalUserInput._(this._apply, this.textLength);

  factory TerminalUserInput.text(String text) =>
      TerminalUserInput._((terminal) => terminal.textInput(text), text.length);

  factory TerminalUserInput.paste(String text) =>
      TerminalUserInput._((terminal) => terminal.paste(text), text.length);

  factory TerminalUserInput.character(
    int charCode, {
    bool alt = false,
    bool ctrl = false,
  }) => TerminalUserInput._((terminal) {
    terminal.charInput(charCode, alt: alt, ctrl: ctrl);
  }, 1);

  factory TerminalUserInput.key(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool superKey = false,
    bool capsLock = false,
    bool numLock = false,
    TerminalKeyEventType type = TerminalKeyEventType.press,
    String? text,
  }) => TerminalUserInput._((terminal) {
    terminal.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
      superKey: superKey,
      capsLock: capsLock,
      numLock: numLock,
      type: type,
      text: text,
    );
  }, text?.length ?? 0);

  /// A complete user-requested key tap. Recipients encode both edges using
  /// their own keyboard protocol, including Kitty release reporting.
  factory TerminalUserInput.keyTap(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool superKey = false,
    String? text,
  }) => TerminalUserInput._((terminal) {
    final accepted = terminal.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
      superKey: superKey,
      text: text,
    );
    if (accepted) {
      terminal.keyInput(
        key,
        shift: shift,
        alt: alt,
        ctrl: ctrl,
        superKey: superKey,
        text: text,
        type: TerminalKeyEventType.release,
      );
    } else if (text != null && !ctrl && !alt && !superKey) {
      // Legacy keyboard handlers leave ordinary text to the viewport's IME.
      // A configured key tap has no IME event, so provide its explicit text.
      terminal.textInput(text);
    }
  }, text?.length ?? 0);

  final void Function(Terminal) _apply;
  final int textLength;
  void applyTo(Terminal terminal) => _apply(terminal);
}

/// Records an origin only while an explicit input API is running. A session
/// consumes it at most once when the emulator actually produces output.
/// Ignored/locked input, protocol replies, mouse and focus reports stay local.
class InputAwareTerminal extends Terminal {
  InputAwareTerminal({
    super.maxLines,
    super.platform,
    super.windowsPtyMode,
    super.onClipboardQuery,
    super.onClipboardStore,
    super.clipboardDecoder,
    super.allowITerm2ClipboardCapture,
    super.allowKittyClipboard,
  });

  TerminalUserInput? _currentInput;
  bool _inputTaken = false;

  /// True throughout every chunk of one explicit input operation, including
  /// after its one-shot broadcast origin has been consumed. A tmux client
  /// uses this to avoid duplicating tmux's own terminal-protocol replies.
  bool get hasActiveUserInput => _currentInput != null;

  /// Submits a compound explicit action as one source operation for broadcast.
  /// Replay still uses TerminalSession.sendUserInput to suppress notification.
  void submitUserInput(TerminalUserInput input) =>
      _input(input, () => input.applyTo(this));

  TerminalUserInput? takeUserInput() {
    if (_currentInput == null || _inputTaken) return null;
    _inputTaken = true;
    return _currentInput;
  }

  T _input<T>(TerminalUserInput input, T Function() action) {
    final outer = _currentInput == null;
    if (outer) {
      _currentInput = input;
      _inputTaken = false;
    }
    try {
      return action();
    } finally {
      if (outer) {
        _currentInput = null;
        _inputTaken = false;
      }
    }
  }

  @override
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
    bool superKey = false,
    bool capsLock = false,
    bool numLock = false,
    TerminalKeyEventType type = TerminalKeyEventType.press,
    String? text,
  }) => _input(
    TerminalUserInput.key(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
      superKey: superKey,
      capsLock: capsLock,
      numLock: numLock,
      type: type,
      text: text,
    ),
    () => super.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl,
      superKey: superKey,
      capsLock: capsLock,
      numLock: numLock,
      type: type,
      text: text,
    ),
  );

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) => _input(
    TerminalUserInput.character(charCode, alt: alt, ctrl: ctrl),
    () => super.charInput(charCode, alt: alt, ctrl: ctrl),
  );

  @override
  void textInput(String text) =>
      _input(TerminalUserInput.text(text), () => super.textInput(text));

  @override
  void paste(String text) =>
      _input(TerminalUserInput.paste(text), () => super.paste(text));
}
