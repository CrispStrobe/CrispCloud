/// How an SSH terminal selects its remote tmux session.
enum TmuxSessionMode { createOrAttach, attach }

/// A named remote tmux session, without arbitrary shell startup commands.
class TmuxSessionOptions {
  const TmuxSessionOptions({
    required this.sessionName,
    this.mode = TmuxSessionMode.createOrAttach,
  });

  final String sessionName;
  final TmuxSessionMode mode;

  /// Keep names unambiguous both to the login shell and tmux's target parser.
  /// In particular, exclude target separators, pattern syntax and leading '-'.
  static bool isValidSessionName(String value) =>
      value.isNotEmpty &&
      value.length <= 64 &&
      RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_-]*$').hasMatch(value);

  /// Execute tmux directly in the SSH PTY rather than typing into a shell.
  /// No mode detaches another client or terminates an existing session.
  String get command {
    if (!isValidSessionName(sessionName)) {
      throw ArgumentError.value(
        sessionName,
        'sessionName',
        'Invalid tmux name',
      );
    }
    return switch (mode) {
      TmuxSessionMode.createOrAttach =>
        "exec tmux new-session -A -s '$sessionName'",
      TmuxSessionMode.attach => "exec tmux attach-session -t '=$sessionName'",
    };
  }
}
