import 'dart:async';

/// A terminal-owned resource whose release can be retried after failure.
abstract interface class TerminalCloseable {
  Future<void> close();
}

/// A single interactive terminal transport. The emulator owns no process.
abstract interface class TerminalConnection implements TerminalCloseable {
  /// True when this is the pure-Dart, sandbox-safe shell rather than a host
  /// process. The UI uses it to label the session honestly.
  bool get isSandbox;

  /// Buffered until listened to; closes only after final output has drained.
  Stream<String> get output;

  /// Null when the transport does not expose a process exit status.
  /// For a scoped local transport, this must settle only after the owned
  /// runtime has released its resources, even when it reports a transport
  /// error: the wrapper releases its folder grant at that point. A failed
  /// [close] leaves it pending while native cleanup is unconfirmed.
  Future<int?> get exitCode;

  Future<void> write(String data);
  Future<void> resize(int columns, int rows);
}

/// The engine behind a connection, independent of the terminal viewport.
enum TerminalBackend { host, sandbox, ios, ssh }

/// Optional metadata keeps existing transports and test doubles compatible.
///
/// The embedded iOS engine runs inside the application sandbox, but it is not
/// the limited pure-Dart command interpreter identified by [isSandbox].
abstract interface class TerminalConnectionMetadata {
  TerminalBackend get backend;
}

/// An optional capability to open an independent shell on the exact verified
/// transport already owned by this connection. This never looks up a different
/// connection by destination or copies a remote multiplexer launch command.
abstract interface class TerminalConnectionSharing {
  bool get canOpenSibling;

  /// Logical terminals currently retaining this transport, including this one.
  int get sharedSessionCount;

  /// Reserves a new transport lease before awaiting the remote shell channel.
  /// The returned connection owns that lease independently of its source.
  /// Unregister startup cancellation when ownership transfers to the result.
  Future<TerminalConnection> openSibling(
    int columns,
    int rows, {
    TerminalConnectionCancellation? cancellation,
  });
}

/// Cancellation belongs to a destination opening, independently of the source
/// connection that authorized it. Late ownership registration is canceled too.
class TerminalConnectionCancellation {
  bool _cancelled = false;
  final _callbacks = <Future<void> Function()>{};
  Future<void>? _cancelling;

  bool get isCancelled => _cancelled;

  Future<void> register(Future<void> Function() release) {
    _callbacks.add(release);
    return _cancelled ? _release(release) : Future<void>.value();
  }

  void unregister(Future<void> Function() release) =>
      _callbacks.remove(release);

  Future<void> _release(Future<void> Function() release) async {
    await release();
    _callbacks.remove(release);
  }

  Future<void> cancel() {
    _cancelled = true;
    return _cancelling ??= Future.wait([
      for (final release in _callbacks.toList()) _release(release),
    ]).then<void>((_) {}).whenComplete(() => _cancelling = null);
  }
}

/// A factory and its cancellation authority travel together. Existing plain
/// factories remain supported for transports without cancelable startup.
class TerminalConnectionOpening implements TerminalCloseable {
  TerminalConnectionOpening(TerminalConnectionFactory open, this.cancellation)
    : _open = open;

  final TerminalConnectionFactory _open;
  final TerminalConnectionCancellation cancellation;
  bool _claimed = false;

  /// Exactly one destination can claim this opening, and its factory can run
  /// once. Reusing a menu snapshot must never join two cancellation owners.
  TerminalConnectionFactory claim() {
    if (_claimed) throw StateError('Terminal opening has already been claimed');
    _claimed = true;
    var opened = false;
    return (columns, rows) {
      if (opened) throw StateError('Terminal opening has already been started');
      opened = true;
      return _open(columns, rows);
    };
  }

  @override
  Future<void> close() => cancellation.cancel();
}

/// A transport may own a workspace whose individual panes receive input.
/// The outer connection must not be offered as a broadcast destination: its
/// active pane can change without replacing the verified SSH connection.
abstract interface class TerminalWorkspaceConnection {
  bool get acceptsDirectInput;

  /// View state owned by the session rather than one mounted viewport.
  /// It remains available for read-only inspection after disconnect.
  Object get workspace;

  /// Releases retained buffers when the session is replaced or disposed.
  /// Implementations may defer actual disposal until mounted views detach.
  void disposeWorkspace();
}

extension TerminalConnectionBackend on TerminalConnection {
  TerminalBackend get terminalBackend => this is TerminalConnectionMetadata
      ? (this as TerminalConnectionMetadata).backend
      : isSandbox
      ? TerminalBackend.sandbox
      : TerminalBackend.host;
}

typedef TerminalConnectionFactory = Future<TerminalConnection> Function(
  int columns,
  int rows,
);
