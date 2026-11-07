import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../../lib/models/file_item.dart';
import '../../../../lib/models/storage_analysis.dart';

// Scratch prototype: production model objects, but no application dependency,
// build hook, widget or security-grant acquisition is added to CrispCloud.
class _Api {
  _Api(String path) : library = DynamicLibrary.open(path);
  final DynamicLibrary library;
  late final create = library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'cc_create',
      );
  late final inputAlloc = library
      .lookupFunction<
        Pointer<Uint8> Function(UintPtr),
        Pointer<Uint8> Function(int)
      >('cc_input_alloc');
  late final inputFree = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, UintPtr),
        void Function(Pointer<Uint8>, int)
      >('cc_input_free');
  // A filesystem scan is blocking and must never be marked isLeaf.
  late final run = library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, UintPtr, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('cc_run');
  late final metric = library
      .lookupFunction<
        Uint64 Function(Pointer<Void>, UintPtr),
        int Function(Pointer<Void>, int)
      >('cc_metric');
  late final pages = library
      .lookupFunction<
        UintPtr Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('cc_pages');
  late final pagePtr = library
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, UintPtr),
        Pointer<Uint8> Function(Pointer<Void>, int)
      >('cc_page_ptr');
  late final pageLen = library
      .lookupFunction<
        UintPtr Function(Pointer<Void>, UintPtr),
        int Function(Pointer<Void>, int)
      >('cc_page_len');
  late final destroy = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('cc_destroy');
}

class _Row {
  _Row(
    this.item,
    this.bytes,
    this.files,
    this.folders,
    this.unknown,
    this.links,
    this.complete,
  );
  final FileItem item;
  final int bytes, files, folders, unknown, links;
  final bool complete;
  final children = <int>[];
}

class _Run {
  _Run(this.result, this.metrics, this.bridgeMs, this.decodeMs, this.buildMs);
  final StorageScanResult result;
  final List<int> metrics;
  final double bridgeMs, decodeMs, buildMs;
}

Never _bad(String message) => throw FormatException(message);

_Run runFfi(String library, String root, {bool fastNames = false}) {
  final total = Stopwatch()..start();
  final api = _Api(library);
  final rootBytes = utf8.encode(root);
  final input = api.inputAlloc(rootBytes.length);
  if (input == nullptr) throw StateError('Native root allocation failed.');
  final job = api.create();
  if (job == nullptr) {
    api.inputFree(input, rootBytes.length);
    throw StateError('Native scan allocation failed.');
  }
  try {
    input.asTypedList(rootBytes.length).setAll(0, rootBytes);
    if (api.run(job, input, rootBytes.length, 1) != 0) {
      throw StateError('Native scan failed.');
    }
    final metrics = List<int>.generate(10, (i) => api.metric(job, i));
    final pageCount = api.pages(job);
    if (pageCount < 1 ||
        pageCount > 2048 ||
        metrics[5] > 200001 ||
        metrics[9] > 128 * 1024 * 1024) {
      _bad('Native result exceeds its limits.');
    }
    final decode = Stopwatch()..start();
    final rows = <_Row>[];
    final seen = <String>{};
    final issues = <StorageScanIssue>[];
    var payloadBytes = 0;
    const issueCodes = [
      StorageScanIssueCode.rootUnavailable,
      StorageScanIssueCode.unreadableDirectory,
      StorageScanIssueCode.invalidEntry,
      StorageScanIssueCode.depthLimit,
      StorageScanIssueCode.entryLimit,
      StorageScanIssueCode.byteLimit,
    ];
    for (var page = 0; page < pageCount; page++) {
      final length = api.pageLen(job, page);
      if (length < 16 || length > 65536) _bad('Invalid native batch size.');
      payloadBytes += length;
      final address = api.pagePtr(job, page);
      if (address == nullptr) _bad('Missing native batch.');
      // This immutable view is used only while its native owner is alive.
      // Names are decoded to owned Dart strings; no view escapes this method.
      final bytes = address.asTypedList(length);
      final data = ByteData.sublistView(bytes);
      if (data.getUint32(0, Endian.little) != 0x4353434e ||
          data.getUint32(4, Endian.little) != 1) {
        _bad('Unsupported native batch version.');
      }
      final kind = data.getUint32(8, Endian.little);
      final count = data.getUint32(12, Endian.little);
      if (count < 1 || count > 500) _bad('Invalid native batch row count.');
      var offset = 16;
      for (var row = 0; row < count; row++) {
        if (kind == 1) {
          if (offset + 52 > length) _bad('Truncated native node.');
          final parent = data.getInt32(offset, Endian.little);
          final type = data.getUint8(offset + 4);
          final flags = data.getUint8(offset + 5);
          final size = data.getUint64(offset + 8, Endian.little);
          final modified = data.getInt64(offset + 16, Endian.little);
          final subtree = data.getUint64(offset + 24, Endian.little);
          final files = data.getUint32(offset + 32, Endian.little);
          final folders = data.getUint32(offset + 36, Endian.little);
          final unknown = data.getUint32(offset + 40, Endian.little);
          final links = data.getUint32(offset + 44, Endian.little);
          final nameLength = data.getUint32(offset + 48, Endian.little);
          offset += 52;
          if (type > 2 ||
              flags > 7 ||
              nameLength == 0 ||
              offset + nameLength > length ||
              parent < -1 ||
              parent >= rows.length ||
              (rows.isEmpty != (parent == -1)) ||
              subtree < 0 ||
              subtree > 9007199254740991 ||
              size < 0 ||
              size > 9007199254740991 ||
              files > 200001 ||
              folders > 200001 ||
              unknown > 200001 ||
              links > 200001) {
            _bad('Invalid native node fields.');
          }
          final name = fastNames
              ? utf8.decoder.convert(bytes, offset, offset + nameLength)
              : utf8.decode(
                  Uint8List.sublistView(bytes, offset, offset + nameLength),
                );
          offset += nameLength;
          final parentPath = parent < 0 ? null : rows[parent].item.path!;
          final path = parentPath == null
              ? root
              : fastNames
              ? parentPath +
                    (parentPath.endsWith(Platform.pathSeparator)
                        ? ''
                        : Platform.pathSeparator) +
                    name
              : p.join(parentPath, name);
          // A known parent plus one validated filename proves containment
          // structurally, without repeatedly normalizing the entire path.
          final invalidName = fastNames
              ? name.contains(Platform.pathSeparator) ||
                    (Platform.isWindows &&
                        (name.contains('/') || name.contains(':')))
              : p.isAbsolute(name) || p.basename(name) != name;
          if (!seen.add(path) ||
              rows.length >= 200001 ||
              (parent >= 0 &&
                  (!rows[parent].item.isFolder ||
                      rows[parent].item.isSymlink == true ||
                      invalidName ||
                      name == '.' ||
                      name == '..' ||
                      name.contains('\u0000')))) {
            _bad('Invalid native tree relationship.');
          }
          if (parent >= 0) rows[parent].children.add(rows.length);
          rows.add(
            _Row(
              FileItem(
                name: name,
                path: path,
                isFolder: type == 1,
                isSymlink: type == 2,
                size: (flags & 2) == 0 ? null : size,
                updatedAt: (flags & 4) == 0
                    ? null
                    : DateTime.fromMicrosecondsSinceEpoch(modified),
              ),
              subtree,
              files,
              folders,
              unknown,
              links,
              (flags & 1) != 0,
            ),
          );
        } else if (kind == 2) {
          if (offset + 12 > length || issues.length >= 1000) {
            _bad('Invalid native diagnostic.');
          }
          final code = data.getUint32(offset, Endian.little);
          final pathLength = data.getUint32(offset + 4, Endian.little);
          final messageLength = data.getUint32(offset + 8, Endian.little);
          offset += 12;
          if (code >= issueCodes.length ||
              offset + pathLength + messageLength > length) {
            _bad('Invalid native diagnostic fields.');
          }
          final path = utf8.decode(
            Uint8List.sublistView(bytes, offset, offset + pathLength),
          );
          offset += pathLength;
          final message = utf8.decode(
            Uint8List.sublistView(bytes, offset, offset + messageLength),
          );
          offset += messageLength;
          issues.add(
            StorageScanIssue(
              path: path,
              code: issueCodes[code],
              message: message,
            ),
          );
        } else {
          _bad('Unknown native batch type.');
        }
      }
      if (offset != length) _bad('Unexpected bytes in native batch.');
    }
    if (rows.length != metrics[5] ||
        payloadBytes != metrics[9] ||
        issues.length != metrics[6]) {
      _bad('Native result count mismatch.');
    }
    decode.stop();
    final build = Stopwatch()..start();
    final built = List<StorageNode?>.filled(rows.length, null);
    for (var index = rows.length - 1; index >= 0; index--) {
      final row = rows[index];
      built[index] = StorageNode(
        item: row.item,
        children: [for (final child in row.children) built[child]!],
        bytes: row.bytes,
        fileCount: row.files,
        folderCount: row.folders,
        unknownSizeCount: row.unknown,
        skippedLinkCount: row.links,
        isComplete: row.complete,
      );
    }
    final result = StorageScanResult(
      root: built.first!,
      issues: issues,
      cancelled: (metrics[8] & 1) != 0,
      limited: (metrics[8] & 2) != 0,
      sourceChanged: false,
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      suppressedIssueCount: metrics[7],
    );
    build.stop();
    total.stop();
    return _Run(
      result,
      metrics,
      total.elapsedMicroseconds / 1000,
      decode.elapsedMicroseconds / 1000,
      build.elapsedMicroseconds / 1000,
    );
  } finally {
    api.destroy(job);
    api.inputFree(input, rootBytes.length);
  }
}

void validate(
  StorageScanResult result,
  String root,
  Map<String, dynamic> expected,
) {
  if (!result.isComplete) {
    throw StateError('Incomplete result: ' + result.issues.toString());
  }
  final pending = [result.root];
  final records = <List<Object>>[];
  final directories = <List<Object>>[];
  final directoryTotals = <String, List<int>>{};
  while (pending.isNotEmpty) {
    final n = pending.removeLast();
    pending.addAll(n.children);
    final rel = n.path == root
        ? ''
        : p.relative(n.path, from: root).split(p.separator).join('/');
    if (n.isFolder) {
      directories.add([rel, n.item.updatedAt!.microsecondsSinceEpoch]);
      directoryTotals[rel] = [n.bytes, n.fileCount, n.folderCount];
    } else if (n.item.isSymlink != true) {
      records.add([
        rel,
        n.item.size!,
        n.item.updatedAt!.microsecondsSinceEpoch,
      ]);
    }
  }
  records.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  directories.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  if (jsonEncode(records) != jsonEncode(expected['records']) ||
      jsonEncode(directories) != jsonEncode(expected['directories']) ||
      result.root.fileCount != expected['files'] ||
      result.root.folderCount != expected['foldersExcludingRoot'] ||
      result.root.bytes != expected['logicalBytes']) {
    throw StateError('File/path/size/mtime/directory validation failed.');
  }
  final totals = expected['directoryTotals'] as Map<String, dynamic>;
  if (totals.length != directoryTotals.length) {
    throw StateError('Wrong folder count.');
  }
  for (final entry in directoryTotals.entries) {
    if (jsonEncode(entry.value) != jsonEncode(totals[entry.key])) {
      throw StateError('Wrong folder totals for ' + entry.key);
    }
  }
}

double median(List<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    throw ArgumentError('usage: ffi_bench LIBRARY ROOT EXPECTED.json [REPS]');
  }
  final library = args[0];
  final root = args[1];
  final expected =
      jsonDecode(await File(args[2]).readAsString()) as Map<String, dynamic>;
  final repetitions = args.length > 3 ? int.parse(args[3]) : 5;
  final fastNames = Platform.environment['SCANNER_FFI_FAST_NAMES'] == '1';
  if (repetitions < 1)
    throw ArgumentError('Positive repetition count required');
  for (final isolate in [false, true]) {
    final times = <double>[];
    final native = <double>[],
        encode = <double>[],
        decode = <double>[],
        build = <double>[];
    _Run? last;
    for (var iteration = 0; iteration <= repetitions; iteration++) {
      final clock = Stopwatch()..start();
      final value = isolate
          ? await runFfiIsolated(library, root, fastNames)
          : runFfi(library, root, fastNames: fastNames);
      clock.stop();
      if (iteration > 0) {
        times.add(clock.elapsedMicroseconds / 1000);
        native.add(value.metrics[0] / 1000000);
        encode.add(value.metrics[1] / 1000000);
        decode.add(value.decodeMs);
        build.add(value.buildMs);
      }
      validate(value.result, root, expected);
      last = value;
    }
    print(
      jsonEncode({
        'variant': isolate
            ? 'ffi_strict_tree_one_isolate'
            : 'ffi_strict_tree_sync_cli',
        'filenameValidation': fastNames
            ? 'parent_and_component'
            : 'package_path',
        'milliseconds': times,
        'medianMs': median(times),
        'nativeScanMedianMs': median(native),
        'nativePackMedianMs': median(encode),
        'dartDecodeMedianMs': median(decode),
        'dartModelBuildMedianMs': median(build),
        'files': last!.result.root.fileCount,
        'folders': last.result.root.folderCount,
        'logicalBytes': last.result.root.bytes,
        'payloadBytes': last.metrics[9],
        'warmups': 1,
        'repetitions': repetitions,
        'allPathsSizesMicrosecondMtimesAndFolderTotalsValidated': true,
        'runtime': Platform.version,
        'notes': 'Scratch prototype, not app-integrated; includes bounded native batches, decoding, actual FileItem/StorageNode construction and explicit frees.',
      }),
    );
  }
}

Future<_Run> runFfiIsolated(String library, String root, bool fastNames) =>
    Isolate.run(() => runFfi(library, root, fastNames: fastNames));
