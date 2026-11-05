import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'models.dart';

/// Offline native audio processing. Heavy decoder/render calls run in separate
/// isolates; only atomic progress/cancellation calls run on the UI isolate.
class CrispAudio {
  /// [libraryPath] is useful for independent integration tests which compile
  /// the same C++ source without launching a Flutter platform runner.
  CrispAudio({String? libraryPath}) : _libraryPath = libraryPath;

  final String? _libraryPath;
  _Bindings? _loadedBindings;

  _Bindings get _bindings => _loadedBindings ??= _Bindings(_libraryPath);

  Future<AudioMetadata> probe(
    String inputPath, {
    AudioCancellationToken? cancellation,
  }) async {
    _validatePath(inputPath);
    final result = await _run(
      _WorkKind.probe,
      inputPath: inputPath,
      cancellation: cancellation,
    );
    return result as AudioMetadata;
  }

  Future<List<double>> waveform(
    String inputPath, {
    int points = 800,
    AudioCancellationToken? cancellation,
    void Function(double)? onProgress,
  }) async {
    _validatePath(inputPath);
    if (points < 1 || points > 32768) {
      throw const AudioException(AudioFailure.invalidArgument);
    }
    final result = await _run(
      _WorkKind.waveform,
      inputPath: inputPath,
      points: points,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    return result as List<double>;
  }

  /// Export never overwrites an existing path, even when called outside the
  /// editor. The caller must use a new, private staging filename.
  Future<void> render(
    AudioRenderRequest request, {
    AudioCancellationToken? cancellation,
    void Function(double)? onProgress,
  }) async {
    _validatePath(request.inputPath);
    _validatePath(request.outputPath);
    await _run(
      _WorkKind.render,
      inputPath: request.inputPath,
      render: request,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  Future<Object?> _run(
    _WorkKind kind, {
    required String inputPath,
    int points = 0,
    AudioRenderRequest? render,
    AudioCancellationToken? cancellation,
    void Function(double)? onProgress,
  }) async {
    cancellation?.throwIfCancelled();
    final native = _bindings;
    final job = native.createJob();
    if (job == nullptr) throw const AudioException(AudioFailure.outOfMemory);
    void cancel() => native.cancelJob(job);
    cancellation?.addListener(cancel);
    Timer? timer;
    try {
      onProgress?.call(0);
      if (onProgress != null) {
        timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          onProgress(native.jobProgress(job) / 1000000);
        });
      }
      final request = _WorkRequest(
        kind: kind,
        jobAddress: job.address,
        libraryPath: _libraryPath,
        inputPath: inputPath,
        points: points,
        render: render,
      );
      // This helper creates the isolate closure in a scope containing only
      // the sendable request, never the bindings, Timer or native pointers.
      final result = await _launchWorker(request);
      onProgress?.call(1);
      return result;
    } finally {
      // The worker has returned (including errors) before native memory is
      // released. No timer/listener is allowed to touch the handle afterward.
      timer?.cancel();
      cancellation?.removeListener(cancel);
      native.destroyJob(job);
    }
  }
}

void _validatePath(String path) {
  if (path.isEmpty || path.contains('\u0000')) {
    throw const AudioException(AudioFailure.invalidArgument);
  }
}

enum _WorkKind { probe, waveform, render }

class _WorkRequest {
  const _WorkRequest({
    required this.kind,
    required this.jobAddress,
    required this.libraryPath,
    required this.inputPath,
    required this.points,
    required this.render,
  });

  final _WorkKind kind;
  final int jobAddress;
  final String? libraryPath;
  final String inputPath;
  final int points;
  final AudioRenderRequest? render;
}

Future<Object?> _launchWorker(_WorkRequest request) =>
    Isolate.run(() => _runAudioWork(request));

Object? _runAudioWork(_WorkRequest request) {
  final native = _Bindings(request.libraryPath);
  final job = Pointer<Void>.fromAddress(request.jobAddress);
  final input = request.inputPath.toNativeUtf8();
  try {
    switch (request.kind) {
      case _WorkKind.probe:
        final info = calloc<_NativeAudioInfo>();
        try {
          _check(native.probe(job, input, info));
          return AudioMetadata(
            frames: info.ref.frames,
            sampleRate: info.ref.sampleRate,
            channels: info.ref.channels,
          );
        } finally {
          calloc.free(info);
        }
      case _WorkKind.waveform:
        final peaks = calloc<Float>(request.points);
        try {
          _check(native.waveform(job, input, peaks, request.points));
          // Copy before the allocation is freed; never transfer a pointer or a
          // view of native memory to the UI isolate.
          return List<double>.of(peaks.asTypedList(request.points));
        } finally {
          calloc.free(peaks);
        }
      case _WorkKind.render:
        final render = request.render!;
        final output = render.outputPath.toNativeUtf8();
        try {
          _check(
            native.render(
              job,
              input,
              output,
              render.start.inMicroseconds,
              render.end.inMicroseconds,
              render.gainDb,
              render.fadeIn.inMicroseconds,
              render.fadeOut.inMicroseconds,
              render.muted ? 1 : 0,
            ),
          );
          return null;
        } finally {
          calloc.free(output);
        }
    }
  } finally {
    calloc.free(input);
  }
}

void _check(int result) {
  if (result == 0) return;
  if (result == 5) throw const AudioCancelled();
  throw AudioException(switch (result) {
    1 => AudioFailure.invalidArgument,
    2 => AudioFailure.invalidInput,
    3 => AudioFailure.unsupported,
    4 => AudioFailure.io,
    6 => AudioFailure.outOfMemory,
    7 => AudioFailure.outputExists,
    _ => AudioFailure.invalidInput,
  });
}

final class _NativeAudioInfo extends Struct {
  @Uint64()
  external int frames;

  @Uint32()
  external int sampleRate;

  @Uint32()
  external int channels;
}

DynamicLibrary _openLibrary(String? path) {
  if (path != null) return DynamicLibrary.open(path);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  if (Platform.isWindows) return DynamicLibrary.open('crisp_audio.dll');
  if (Platform.isLinux || Platform.isAndroid) {
    return DynamicLibrary.open('libcrisp_audio.so');
  }
  throw const AudioException(AudioFailure.unsupported);
}

class _Bindings {
  _Bindings(String? path) : library = _openLibrary(path) {
    final abi = library.lookupFunction<Int32 Function(), int Function()>(
      'crisp_audio_abi_version',
    );
    if (abi() != 1) throw const AudioException(AudioFailure.unsupported);
  }

  final DynamicLibrary library;

  late final createJob = library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'crisp_audio_job_create',
      );

  late final cancelJob = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('crisp_audio_job_cancel');

  late final jobProgress = library
      .lookupFunction<
        Uint32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('crisp_audio_job_progress');

  late final destroyJob = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('crisp_audio_job_destroy');

  late final probe = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<_NativeAudioInfo>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<_NativeAudioInfo>)
      >('crisp_audio_probe');

  late final waveform = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, Uint32),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int)
      >('crisp_audio_waveform');

  late final render = library
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          Int64,
          Int64,
          Double,
          Int64,
          Int64,
          Int32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Utf8>,
          int,
          int,
          double,
          int,
          int,
          int,
        )
      >('crisp_audio_render');
}
