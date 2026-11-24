import 'dart:io';
import 'dart:typed_data';

import 'package:covfuzz/covfuzz.dart';

import 'package:crisp_cloud/services/archive_lz4_codec.dart';
import 'package:crisp_cloud/services/archive_lzip_codec.dart';
import 'package:crisp_cloud/services/archive_lzma_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';
import 'package:crisp_cloud/services/rtf_document.dart';

List<Uint8List> _fixtures(List<String> suffixes) {
  final out = <Uint8List>[];
  final dir = Directory('test/fixtures/archives');
  if (!dir.existsSync()) return out;
  for (final file in dir.listSync().whereType<File>()) {
    final path = file.path.toLowerCase();
    if (!suffixes.any(path.endsWith)) continue;
    if (file.lengthSync() > 64 * 1024) continue;
    out.add(file.readAsBytesSync());
  }
  return out;
}

bool _clean(Object error) =>
    error is ArchiveViewException ||
    error is FormatException ||
    error is RtfDocumentException;

void main(List<String> args) {
  final budget = int.tryParse(args.firstOrNull ?? '') ?? 15000;
  final reports = <FuzzReport>[];

  final lz4 = _fixtures(const ['.lz4']);
  if (lz4.isNotEmpty) {
    reports.add(
      fuzz<Uint8List>(
        seeds: lz4,
        entry: (bytes) => decodeArchiveLz4(bytes, maxOutputBytes: 1 << 20),
        mutate: mutateBytes,
        isClean: _clean,
        iterations: 200000,
        budgetMs: budget,
      ),
    );
  }

  final lzma = _fixtures(const ['.lzma']);
  if (lzma.isNotEmpty) {
    reports.add(
      fuzz<Uint8List>(
        seeds: lzma,
        entry: (bytes) => decodeArchiveLzma(bytes, maxOutputBytes: 1 << 20),
        mutate: mutateBytes,
        isClean: _clean,
        iterations: 100000,
        budgetMs: budget,
      ),
    );
  }

  final lzip = _fixtures(const ['.lz']);
  if (lzip.isNotEmpty) {
    reports.add(
      fuzz<Uint8List>(
        seeds: lzip,
        entry: (bytes) => decodeArchiveLzip(bytes, maxOutputBytes: 1 << 20),
        mutate: mutateBytes,
        isClean: _clean,
        iterations: 100000,
        budgetMs: budget,
      ),
    );
  }

  final compress = _fixtures(const ['.z']);
  if (compress.isNotEmpty) {
    reports.add(
      fuzz<Uint8List>(
        seeds: compress,
        entry: (bytes) =>
            decodeArchiveUnixCompress(bytes, maxOutputBytes: 1 << 20),
        mutate: mutateBytes,
        isClean: _clean,
        iterations: 100000,
        budgetMs: budget,
      ),
    );
  }

  const rtfSeeds = <String>[
    r'{\rtf1\ansi hello \b world\b0\par}',
    r'{\rtf1\ansi\ansicpg1252{\fonttbl{\f0 Times New Roman;}}\f0 text}',
    r'{\rtf1\ansi{\*\generator test;}\pard\qc centered\par}',
  ];
  reports.add(
    fuzz<String>(
      seeds: rtfSeeds,
      entry: (text) => parseRtfDocument(Uint8List.fromList(text.codeUnits)),
      mutate: mutateString,
      isClean: _clean,
      iterations: 100000,
      budgetMs: budget,
    ),
  );

  var code = 0;
  for (final report in reports) {
    final next = report.report();
    if (next > code) code = next;
  }
  exit(code);
}
