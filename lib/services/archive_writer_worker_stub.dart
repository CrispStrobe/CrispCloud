import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import '../models/archive_endpoint.dart';
import 'archive_compression_writer.dart';
import 'archive_package_writers.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

const supportsArchiveWriterWorker = false;

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
}) async => throw const ArchiveViewException(
  'Background archive packing requires a native codec worker.',
);

Future<void> writeHfsArchiveInWorker(
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  String volumeName = 'CrispCloud',
  bool Function()? isCancelled,
  Future<void> Function()? checkpoint,
  Future<void>? cancellationFuture,
}) async => throw const ArchiveViewException(
  'Background archive packing requires a native codec worker.',
);
