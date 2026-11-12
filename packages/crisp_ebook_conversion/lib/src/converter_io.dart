import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

const _expectedVersion = 'crisp-kindling 1 (Kindling 0.46.2)';
const _asset = 'package:crisp_ebook_conversion/kindling_bridge';

@Native<Pointer<Utf8> Function()>(
  assetId: _asset,
  symbol: 'crisp_kindling_version',
)
external Pointer<Utf8> _bundledVersion();
@Native<Uint64 Function(Pointer<Uint8>, Size)>(
  assetId: _asset,
  symbol: 'crisp_kindling_start',
)
external int _bundledStart(Pointer<Uint8> data, int length);
@Native<Pointer<Utf8> Function(Uint64)>(
  assetId: _asset,
  symbol: 'crisp_kindling_poll',
)
external Pointer<Utf8> _bundledPoll(int id);
@Native<Void Function(Uint64)>(assetId: _asset, symbol: 'crisp_kindling_cancel')
external void _bundledCancel(int id);
@Native<Void Function(Pointer<Utf8>)>(
  assetId: _asset,
  symbol: 'crisp_kindling_free',
)
external void _bundledFree(Pointer<Utf8> data);

EbookConversionBackend createBackend({
  String? executablePath,
  String? libraryPath,
  required Duration timeout,
  required EbookConversionLimits limits,
}) => _IoBackend(executablePath, libraryPath, timeout, limits);

class _Symbols {
  _Symbols(String? libraryPath) {
    if (libraryPath == null) {
      version = _bundledVersion;
      start = _bundledStart;
      poll = _bundledPoll;
      cancel = _bundledCancel;
      free = _bundledFree;
    } else {
      if (!p.isAbsolute(libraryPath)) {
        throw const EbookConversionException(
          'unavailable',
          'Converter library path must be absolute.',
        );
      }
      final lib = DynamicLibrary.open(libraryPath);
      version = lib
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'crisp_kindling_version',
          );
      start = lib
          .lookupFunction<
            Uint64 Function(Pointer<Uint8>, Size),
            int Function(Pointer<Uint8>, int)
          >('crisp_kindling_start');
      poll = lib
          .lookupFunction<
            Pointer<Utf8> Function(Uint64),
            Pointer<Utf8> Function(int)
          >('crisp_kindling_poll');
      cancel = lib.lookupFunction<Void Function(Uint64), void Function(int)>(
        'crisp_kindling_cancel',
      );
      free = lib
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('crisp_kindling_free');
    }
    if (version().toDartString() != _expectedVersion) {
      throw const EbookConversionException(
        'unavailable',
        'Unreviewed converter version.',
      );
    }
  }
  late final Pointer<Utf8> Function() version;
  late final int Function(Pointer<Uint8>, int) start;
  late final Pointer<Utf8> Function(int) poll;
  late final void Function(int) cancel;
  late final void Function(Pointer<Utf8>) free;
}

class _IoBackend implements EbookConversionBackend {
  _IoBackend(this.executable, this.libraryPath, this.timeout, this.limits);
  final String? executable;
  final String? libraryPath;
  final Duration timeout;
  final EbookConversionLimits limits;
  _Symbols? _symbols;
  bool _busy = false;

  @override
  Future<EbookConversionCapabilities> capabilities() async {
    try {
      if (timeout <= Duration.zero) {
        throw const EbookConversionException(
          'unavailable',
          'Conversion timeout must be positive.',
        );
      }
      if (executable != null) {
        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
          throw const EbookConversionException(
            'unavailable',
            'The process converter is available only on desktop.',
          );
        }
        if (!p.isAbsolute(executable!)) {
          throw const EbookConversionException(
            'unavailable',
            'Converter executable path must be absolute.',
          );
        }
        final result = await _execute(executable!, [
          '--version',
        ], timeout: const Duration(seconds: 3));
        if (result.stdout.trim() != _expectedVersion || result.exitCode != 0) {
          throw const EbookConversionException(
            'unavailable',
            'The bundled converter version does not match Kindling 0.46.2.',
          );
        }
        return const EbookConversionCapabilities(
          available: true,
          runtime: EbookConversionRuntime.process,
          cancellationMode: EbookCancellationMode.processTermination,
          engineVersion: '0.46.2',
        );
      }
      _symbols ??= _Symbols(libraryPath);
      return const EbookConversionCapabilities(
        available: true,
        runtime: EbookConversionRuntime.native,
        cancellationMode: EbookCancellationMode.cooperative,
        engineVersion: '0.46.2',
      );
    } catch (error) {
      return EbookConversionCapabilities(
        available: false,
        runtime: EbookConversionRuntime.unavailable,
        cancellationMode: EbookCancellationMode.unavailable,
        reason: error is EbookConversionException
            ? error.message
            : 'The native Kindle converter is not included in this build.',
      );
    }
  }

  @override
  Future<EbookConversionResult> convert(
    Uint8List input, {
    required bool metadataOnly,
    required KindleExportFormat format,
    KindleMetadataPatch? patch,
    Uint8List? cover,
    EbookCancellationToken? cancellation,
  }) {
    // Copy before the first await. The caller can continue editing its buffer
    // without changing the operation's immutable baseline.
    if (input.isEmpty || input.length > limits.maxInputBytes) {
      return Future.error(
        const EbookConversionException(
          'limitExceeded',
          'Ebook size exceeds the conversion limit.',
        ),
      );
    }
    if (cover != null && cover.length > limits.maxEntryBytes) {
      return Future.error(
        const EbookConversionException(
          'limitExceeded',
          'Cover size exceeds the conversion limit.',
        ),
      );
    }
    if (_busy) {
      return Future.error(
        const EbookConversionException(
          'busy',
          'A conversion is still running.',
        ),
      );
    }
    if (cancellation?.isCancelled ?? false) {
      return Future.error(
        const EbookConversionException(
          'cancelled',
          'Conversion was cancelled.',
        ),
      );
    }
    _busy = true;
    return _convert(
      Uint8List.fromList(input),
      metadataOnly: metadataOnly,
      format: format,
      patch: patch,
      cover: cover == null ? null : Uint8List.fromList(cover),
      cancellation: cancellation,
    );
  }

  Future<EbookConversionResult> _convert(
    Uint8List snapshot, {
    required bool metadataOnly,
    required KindleExportFormat format,
    KindleMetadataPatch? patch,
    Uint8List? cover,
    EbookCancellationToken? cancellation,
  }) async {
    Directory? work;
    _NativeJob? native;
    var cleanupDeferred = false;
    try {
      final available = await capabilities();
      if (!available.available) {
        throw EbookConversionException(
          'unavailable',
          available.reason ?? 'Converter unavailable.',
        );
      }
      _checkCancelled(cancellation);
      work = await Directory.systemTemp.createTemp('crisp_ebook_');
      final inputFile = File(
        p.join(work.path, metadataOnly ? 'input.mobi' : 'input.epub'),
      );
      await inputFile.writeAsBytes(snapshot, flush: true);
      if (cover != null) {
        await File(p.join(work.path, 'cover')).writeAsBytes(cover, flush: true);
      }
      _checkCancelled(cancellation);
      final request = jsonEncode({
        'work_dir': work.absolute.path,
        'operation': metadataOnly ? 'metadata' : 'export',
        'format': format.extension,
        'metadata': patch?.toJson() ?? <String, Object?>{},
        'cover': cover != null,
        'limits': limits.toJson(),
      });
      if (utf8.encode(request).length > 131072) {
        throw const EbookConversionException(
          'limitExceeded',
          'Metadata is too large.',
        );
      }
      late Map<String, dynamic> response;
      if (executable != null) {
        final result = await _execute(
          executable!,
          const [],
          timeout: timeout,
          cancellation: cancellation,
          input: request,
          directory: work.path,
        );
        // Kindling may emit informational lines before the worker's final JSON.
        final lines = const LineSplitter().convert(result.stdout);
        final json = lines.lastWhere(
          (line) => line.startsWith('{'),
          orElse: () => '',
        );
        if (result.exitCode != 0 || json.isEmpty) {
          throw EbookConversionException(
            'conversionFailed',
            'Kindle converter failed (${result.exitCode}). ${result.stderr.take(4000)}',
          );
        }
        response = jsonDecode(json) as Map<String, dynamic>;
      } else {
        native = _NativeJob(_symbols!, utf8.encode(request));
        response = await _withCancellation(native, cancellation, timeout);
      }
      _checkCancelled(cancellation);
      if (response['ok'] != true) {
        throw EbookConversionException(
          response['code'] as String? ?? 'conversionFailed',
          response['message'] as String? ?? 'Kindle conversion failed.',
        );
      }
      if (response['version'] != '0.46.2' ||
          response['format'] != format.extension) {
        throw const EbookConversionException(
          'validationFailed',
          'Unexpected converter response.',
        );
      }
      final output = File(p.join(work.path, 'output.${format.extension}'));
      final stat = await output.stat();
      if (await FileSystemEntity.type(output.path, followLinks: false) !=
              FileSystemEntityType.file ||
          stat.size > limits.maxOutputBytes ||
          stat.size < 78) {
        throw const EbookConversionException(
          'validationFailed',
          'Converter output is invalid or too large.',
        );
      }
      final bytes = await output.readAsBytes();
      if (bytes.length > limits.maxOutputBytes ||
          ascii.decode(bytes.sublist(60, 68), allowInvalid: true) !=
              'BOOKMOBI') {
        throw const EbookConversionException(
          'validationFailed',
          'Converter did not produce a Kindle ebook.',
        );
      }
      // The adapter must not mutate even its private input snapshot.
      final after = await inputFile.readAsBytes();
      if (!_equal(snapshot, after)) {
        throw const EbookConversionException(
          'validationFailed',
          'Converter changed its source snapshot.',
        );
      }
      return EbookConversionResult(
        bytes: bytes,
        format: format,
        engineVersion: response['version'] as String,
        warnings: (response['warnings'] as List? ?? const []).cast<String>(),
        noOp: response['noOp'] == true,
        changes: (response['changes'] as List? ?? const []).map((value) {
          final change = value as Map<String, dynamic>;
          return EbookMetadataChange(
            change['record'] as int,
            change['action'] as String,
          );
        }),
      );
    } on EbookConversionException {
      rethrow;
    } catch (error) {
      throw EbookConversionException(
        'conversionFailed',
        'Kindle conversion failed: $error',
      );
    } finally {
      if (native != null && !native.finished) {
        // Do not remove files underneath an upstream call still in progress.
        // The caller is released immediately; no late result can be saved.
        cleanupDeferred = true;
        native.cancel();
        final abandoned = work;
        unawaited(
          native.settled.then((_) async {
            await _remove(abandoned);
            _busy = false;
          }),
        );
      }
      if (!cleanupDeferred) {
        await _remove(work);
        _busy = false;
      }
    }
  }
}

void _checkCancelled(EbookCancellationToken? token) {
  if (token?.isCancelled ?? false) {
    throw const EbookConversionException(
      'cancelled',
      'Conversion was cancelled.',
    );
  }
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> _remove(Directory? directory) async {
  if (directory == null) return;
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // Cleanup failure must not hide the original conversion error.
  }
}

class _NativeJob {
  _NativeJob(this.symbols, List<int> request) {
    final data = calloc<Uint8>(request.length);
    try {
      data.asTypedList(request.length).setAll(0, request);
      id = symbols.start(data, request.length);
    } finally {
      calloc.free(data);
    }
    if (id == 0) {
      throw const EbookConversionException(
        'busy',
        'The native converter is already running.',
      );
    }
    response = _poll();
    settled = response.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
  }
  final _Symbols symbols;
  late final int id;
  late final Future<Map<String, dynamic>> response;
  late final Future<void> settled;
  bool finished = false;

  void cancel() {
    if (!finished) symbols.cancel(id);
  }

  Future<Map<String, dynamic>> _poll() async {
    while (true) {
      final result = symbols.poll(id);
      if (result != nullptr) {
        finished = true;
        try {
          return jsonDecode(result.toDartString()) as Map<String, dynamic>;
        } finally {
          symbols.free(result);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}

Future<Map<String, dynamic>> _withCancellation(
  _NativeJob job,
  EbookCancellationToken? token,
  Duration timeout,
) async {
  final completer = Completer<Map<String, dynamic>>();
  void abort(String code, String message) {
    if (!completer.isCompleted) {
      job.cancel();
      completer.completeError(EbookConversionException(code, message));
    }
  }

  final timer = Timer(
    timeout,
    () => abort('timeout', 'Kindle conversion timed out.'),
  );
  unawaited(
    job.response.then(
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    ),
  );
  unawaited(
    token?.whenCancelled.then(
      (_) => abort('cancelled', 'Conversion was cancelled.'),
    ),
  );
  try {
    _checkCancelled(token);
    return await completer.future;
  } finally {
    timer.cancel();
  }
}

class _ProcessResult {
  const _ProcessResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<_ProcessResult> _execute(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  EbookCancellationToken? cancellation,
  String? input,
  String? directory,
}) async {
  _checkCancelled(cancellation);
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    runInShell: false,
    includeParentEnvironment: false,
    environment: {
      if (Platform.environment['SystemRoot'] case final String value)
        'SystemRoot': value,
      if (directory != null) ...{
        'TMPDIR': directory,
        'TEMP': directory,
        'TMP': directory,
      },
    },
  );
  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  final aborted = Completer<void>();
  var exited = false;
  var settled = false;
  final exitCode = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  EbookConversionException? failure;
  void abort(String code, String message) {
    if (!settled && failure == null) {
      failure = EbookConversionException(code, message);
      if (!exited) process.kill();
      if (!aborted.isCompleted) aborted.complete();
    }
  }

  Future<void> collect(Stream<List<int>> stream, BytesBuilder target) async {
    await for (final bytes in stream) {
      if (stdout.length + stderr.length + bytes.length > 1024 * 1024) {
        abort(
          'limitExceeded',
          'Converter diagnostic output exceeded its limit.',
        );
      } else {
        target.add(bytes);
      }
    }
  }

  final outDone = collect(process.stdout, stdout);
  final errDone = collect(process.stderr, stderr);
  final timer = Timer(
    timeout,
    () => abort('timeout', 'Kindle conversion timed out.'),
  );
  unawaited(
    cancellation?.whenCancelled.then(
      (_) => abort('cancelled', 'Conversion was cancelled.'),
    ),
  );
  try {
    if (input != null) process.stdin.add(utf8.encode(input));
    await process.stdin.close();
    await Future.any<void>([exitCode.then((_) {}), aborted.future]);
    if (failure != null) {
      try {
        await exitCode.timeout(const Duration(milliseconds: 300));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await exitCode;
      }
    }
    final code = await exitCode;
    await Future.wait([outDone, errDone]);
    if (failure != null) throw failure!;
    return _ProcessResult(
      code,
      utf8.decode(stdout.takeBytes(), allowMalformed: true),
      utf8.decode(stderr.takeBytes(), allowMalformed: true),
    );
  } catch (_) {
    if (failure != null) throw failure!;
    rethrow;
  } finally {
    settled = true;
    timer.cancel();
    if (!exited) {
      process.kill();
      try {
        await exitCode.timeout(const Duration(milliseconds: 300));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await exitCode;
      }
    }
    await Future.wait([outDone, errDone]);
  }
}

extension on String {
  String take(int max) => length <= max ? this : substring(0, max);
}
