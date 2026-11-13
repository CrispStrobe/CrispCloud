import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart';
import 'archive_package_writers.dart';
import 'archive_write_model.dart';
import 'archive_writer_worker_stub.dart'
    if (dart.library.io) 'archive_writer_worker_io.dart'
    as platform;

/// Codec isolates are available on native Dart. Browser callers must use the
/// existing bounded foreground writers instead of claiming background work.
bool get supportsArchiveWriterWorker => platform.supportsArchiveWriterWorker;

/// Packs in a separate isolate while the caller retains all source streams,
/// backend clients and the unpublished output sink. At most one bounded
/// protocol request is outstanding. Every payload message is <= 256 KiB.
///
/// [checkpoint] gates input, output and codec checkpoints, so a paused operation
/// stops making progress without losing its live compression state. Supplying
/// [cancellationFuture] also interrupts a stalled input or checkpoint. A boolean
/// cancellation callback is polled while the worker performs CPU-only work.
/// Cancellation cannot undo a sink call already in progress; this sink must
/// own an unpublished candidate, and publication remains the caller's job.
///
/// [source] crosses the same-code isolate boundary as its actual object graph.
/// In particular, opaque verified filesystem profiles are never converted to
/// JSON or replaced with forgeable marker fields.
///
/// [entryCompression] selects the existing small creation path for ZIP/7z.
/// Use it only for a fresh buffered archive; streamed writers select Store with
/// level zero. All other arguments retain their existing writer semantics.
Future<void> writeArchiveEntriesInWorker(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  bool streamed = false,
  ArchiveRewriteInspection? source,
  ArchiveCpioFormat cpioFormat = ArchiveCpioFormat.newc,
  ArchiveCompressionKind? compression,
  bool singlePayload = false,
  Uint8List? gzipHeader,
  int xzCheck = 4,
  int level = 6,
  String? password,
  bool encryptNames = false,
  koni.ArchiveCompression? entryCompression,
  bool Function()? isCancelled,
  Future<void> Function()? checkpoint,
  Future<void>? cancellationFuture,
}) => platform.writeArchiveEntriesInWorker(
  format,
  entries,
  sink: sink,
  maxOutputBytes: maxOutputBytes,
  streamed: streamed,
  source: source,
  cpioFormat: cpioFormat,
  compression: compression,
  singlePayload: singlePayload,
  gzipHeader: gzipHeader,
  xzCheck: xzCheck,
  level: level,
  password: password,
  encryptNames: encryptNames,
  entryCompression: entryCompression,
  isCancelled: isCancelled,
  checkpoint: checkpoint,
  cancellationFuture: cancellationFuture,
);

/// Raw HFSX creation has no archive endpoint enum, so it has an explicit route.
Future<void> writeHfsArchiveInWorker(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  String volumeName = 'CrispCloud',
  bool Function()? isCancelled,
  Future<void> Function()? checkpoint,
  Future<void>? cancellationFuture,
}) => platform.writeHfsArchiveInWorker(
  entries,
  sink: sink,
  maxOutputBytes: maxOutputBytes,
  source: source,
  volumeName: volumeName,
  isCancelled: isCancelled,
  checkpoint: checkpoint,
  cancellationFuture: cancellationFuture,
);
