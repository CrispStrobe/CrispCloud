import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/custom_toolbar_command.dart';
import 'macos_app_store.dart';

class CommandExecutionResult {
  const CommandExecutionResult({
    required this.exitCode,
    required this.output,
    required this.cancelled,
    required this.timedOut,
    required this.truncated,
  });
  final int exitCode;
  final String output;
  final bool cancelled, timedOut, truncated;
}

typedef CommandProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
  String workingDirectory,
);

/// One owned child process, with bounded output and execution time.
class RunningToolbarCommand extends ChangeNotifier {
  RunningToolbarCommand._(
    this._process,
    Duration timeout,
    this.maxOutputBytes,
  ) {
    _timer = Timer(timeout, () {
      _timedOut = true;
      cancel();
    });
    completed = _collect();
  }
  final Process _process;
  final int maxOutputBytes;
  late final Future<CommandExecutionResult> completed;
  Timer? _timer, _killTimer;
  final _forcedExit = Completer<int>();
  final _subscriptions = <StreamSubscription<String>>[];
  final _output = StringBuffer();
  int _outputBytes = 0;
  bool _running = true,
      _cancelled = false,
      _timedOut = false,
      _truncated = false,
      _disposed = false;
  bool get isRunning => _running;
  String get output => _output.toString();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _read(Stream<List<int>> stream) {
    final done = Completer<void>();
    _subscriptions.add(
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (chunk) {
              final bytes = utf8.encode(chunk);
              final remaining = maxOutputBytes - _outputBytes;
              if (remaining > 0) {
                final kept = bytes.length <= remaining
                    ? bytes
                    : bytes.sublist(0, remaining);
                _output.write(utf8.decode(kept, allowMalformed: true));
                _outputBytes += kept.length;
              }
              if (bytes.length > remaining && !_truncated) {
                _truncated = true;
                _output.write('\n[Output limit reached]\n');
              }
              _changed();
            },
            onDone: done.complete,
            onError: done.completeError,
            cancelOnError: true,
          ),
    );
    return done.future;
  }

  Future<CommandExecutionResult> _collect() async {
    try {
      final reads = Future.wait([
        _read(_process.stdout),
        _read(_process.stderr),
      ]);
      final normal = Future.wait<Object?>([_process.exitCode, reads])
          .then((values) => values.first as int);
      final exitCode = await Future.any([normal, _forcedExit.future]);
      return CommandExecutionResult(
        exitCode: exitCode,
        output: output,
        cancelled: _cancelled,
        timedOut: _timedOut,
        truncated: _truncated,
      );
    } finally {
      _running = false;
      _timer?.cancel();
      _killTimer?.cancel();
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _changed();
    }
  }

  void cancel() {
    if (!_running || _cancelled) return;
    _cancelled = true;
    _process.kill();
    _killTimer = Timer(const Duration(seconds: 2), () {
      if (_running) {
        _process.kill(ProcessSignal.sigkill);
        if (!_forcedExit.isCompleted) _forcedExit.complete(-1);
      }
    });
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  static Future<RunningToolbarCommand> start(
    CustomToolbarCommand command,
    CommandInvocationContext context, {
    CommandProcessStarter? processStarter,
    int maxOutputBytes = 256 * 1024,
  }) async {
    if (kIsWeb ||
        (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux)) {
      throw UnsupportedError('Command execution requires the desktop app.');
    }
    if (Platform.isMacOS && isMacAppStoreBuild()) {
      throw UnsupportedError(
        'Custom commands are not available in the sandboxed Mac App Store build.',
      );
    }
    if (maxOutputBytes < 1 || maxOutputBytes > 4 * 1024 * 1024) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    final prepared = prepareToolbarCommand(command, context);
    final starter =
        processStarter ??
        (String executable, List<String> arguments, String directory) =>
            Process.start(
              executable,
              arguments,
              workingDirectory: directory,
              runInShell: false,
            );
    context.validate();
    final process = await starter(
      prepared.executable,
      prepared.arguments,
      prepared.workingDirectory,
    );
    return RunningToolbarCommand._(
      process,
      Duration(seconds: command.timeoutSeconds),
      maxOutputBytes,
    );
  }
}
