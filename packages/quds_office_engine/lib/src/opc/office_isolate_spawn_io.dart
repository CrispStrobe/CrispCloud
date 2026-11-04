import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'office_open_decode.dart';
import 'office_open_types.dart';

/// VM path: decode an Office package on a worker isolate.
Future<Object?> officeTrySpawnOpen({
  required Uint8List bytes,
  required String? password,
  required String kind,

  /// Function API.
  void Function(OfficeOpenProgress progress)? onProgress,
}) async {
  /// port API.
  final ReceivePort port = ReceivePort();
  try {
    await Isolate.spawn(_openIsolateWorker, <Object?>[
      port.sendPort,
      bytes,
      password,
      kind,
    ]);
  } on IsolateSpawnException {
    return null;
  } on UnsupportedError {
    return null;
  } on ArgumentError {
    return null;
  }

  /// done API.
  final Completer<Object> done = Completer<Object>();

  /// sub API.
  final StreamSubscription<dynamic> sub = port.listen((Object? message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    final String type = message.first as String;
    if (type == 'progress' && message.length >= 3) {
      onProgress?.call(
        OfficeOpenProgress(
          value: (message[1] as num).toDouble(),
          stage: message[2] as String,
        ),
      );
      return;
    }
    if (type == 'done' && message.length >= 2) {
      if (!done.isCompleted) {
        done.complete(message[1] as Object);
      }
      return;
    }
    if (type == 'unsendable') {
      if (!done.isCompleted) {
        done.completeError(ArgumentError('unsendable isolate message'));
      }
      return;
    }
    if (type == 'error') {
      if (!done.isCompleted) {
        final String text = message.length > 1
            ? '${message[1]}'
            : 'Open failed';
        if (text.contains('isolate message') || text.contains('unsendable')) {
          done.completeError(ArgumentError(text));
        } else {
          done.completeError(StateError(text));
        }
      }
    }
  });
  try {
    return await done.future;
  } on ArgumentError catch (error) {
    final String text = error.toString();
    if (text.contains('isolate message') || text.contains('unsendable')) {
      return null;
    }
    rethrow;
  } finally {
    await sub.cancel();
    port.close();
  }
}

void _openIsolateWorker(List<Object?> args) {
  /// port API.
  final SendPort port = args[0] as SendPort;

  /// bytes API.
  final Uint8List bytes = args[1] as Uint8List;

  /// password API.
  final String? password = args[2] as String?;

  /// kind API.
  final String kind = args[3] as String;
  try {
    final Object result = decodeOfficeOpen(bytes, password, kind, (
      OfficeOpenProgress p,
    ) {
      port.send(<Object>['progress', p.value, p.stage]);
    });
    try {
      port.send(<Object>['done', result]);
    } catch (error) {
      final String text = error.toString();
      if (text.contains('isolate') || text.contains('unsendable')) {
        port.send(const <Object>['unsendable']);
      } else {
        port.send(<Object>['error', error.toString()]);
      }
    }
  } catch (error) {
    port.send(<Object>['error', error.toString()]);
  }
}
