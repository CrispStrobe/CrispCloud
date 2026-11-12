// SPDX-License-Identifier: MPL-2.0
// No native Office application is needed to generate this schema corpus.
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'image_appearance_probe.dart' as image_appearance;
import 'list_sequence_fixture.dart' as list_sequences;
import 'metafile_probe.dart' as metafiles;
import 'note_format_fixture.dart' as note_formats;
import 'packed_shape_probe.dart' as packed_shapes;
import 'review_schema_fixture.dart' as reviews;
import 'section_review_fixture.dart' as sections;
import 'shape_probe.dart' as shapes;
import 'table_borders_fixture.dart' as table_borders;
import 'table_layout_fixture.dart' as table_layout;
import 'table_origin_fixture.dart' as origins;
import 'table_operations_fixture.dart' as table_operations;
import 'table_review_fixture.dart' as table_reviews;
import 'table_text_fixture.dart' as table_text;
import 'table_width_fixture.dart' as table_width;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/schema_corpus.dart NEW_DIR',
    );
  }
  final repository = File.fromUri(Platform.script).parent.parent.parent;
  final root = Directory(arguments.single).absolute;
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final manifest = <Map<String, Object>>[];
  void record(String name, String source, String output, String producer) {
    if (!File('${root.path}/$source').existsSync() ||
        !File('${root.path}/$output').existsSync()) {
      throw StateError('The schema corpus is missing the required case $name.');
    }
    manifest.add({
      'name': name,
      'source': source,
      'output': output,
      'producer': producer,
    });
  }

  origins.main(['${root.path}/table-origin']);
  for (final name in [
    'default',
    'zero-margin',
    'wide-margin',
    'negative-origin',
    'positive-origin',
    'independent-gap',
    'cell-margin',
    'nested',
    'nested-wide',
  ]) {
    record(
      'table-origin/$name',
      'table-origin/$name.doc',
      'table-origin/$name-converted.docx',
      'tool/fidelity/table_origin_fixture.dart',
    );
  }
  table_text.main(['${root.path}/table-text']);
  for (final name in ['table-text-conditions', 'table-text-relative-toggles']) {
    record(
      name,
      'table-text/$name.doc',
      'table-text/$name.docx',
      'tool/fidelity/table_text_fixture.dart',
    );
  }
  table_layout.main(['${root.path}/table-layout']);
  for (final name in [
    'auto',
    'minimum-short',
    'minimum-content',
    'exact-short',
    'exact-content',
    'keep-row',
    'split-row',
    'cell-layout',
  ]) {
    record(
      'table-layout/$name',
      'table-layout/$name.doc',
      'table-layout/$name-converted.docx',
      'tool/fidelity/table_layout_fixture.dart',
    );
  }
  table_borders.main(['${root.path}/table-borders']);
  for (final name in [
    'old-after',
    'old-before',
    'old-nil',
    'old-explicit',
    'modern-after',
    'modern-before',
    'modern-nil',
    'modern-explicit',
    'range-nil',
    'range-none',
    'interior-colors',
    'row-reset',
  ]) {
    record(
      'table-borders/$name',
      'table-borders/$name.doc',
      'table-borders/$name-converted.docx',
      'tool/fidelity/table_borders_fixture.dart',
    );
  }
  table_operations.main(['${root.path}/table-operations']);
  for (final name in [
    'delete-resize',
    'merge',
    'split',
    'rtl-physical-left',
    'rtl-physical-center',
    'rtl-physical-right',
    'rtl-logical-left',
    'rtl-logical-center',
    'rtl-logical-right',
    'row-exceptions',
    'style-identities',
    'indirect-cache',
  ]) {
    record(
      'table-operations/$name',
      'table-operations/$name.doc',
      'table-operations/$name-converted.docx',
      'tool/fidelity/table_operations_fixture.dart',
    );
  }
  table_width.main(['${root.path}/table-width']);
  for (final name in [
    'tc80-nil',
    'range-nil',
    'tc80-auto',
    'range-auto',
    'tc80-percent',
    'range-percent',
    'tc80-dxa',
    'range-dxa',
    'tc80-narrow',
    'range-narrow',
    'dxa-to-auto',
    'auto-to-dxa',
    'range-reset',
    'style-auto',
    'style-dxa',
    'tc80-asymmetric',
    'range-asymmetric',
    'grid-asymmetric-control',
  ]) {
    record(
      'table-width/$name',
      'table-width/$name.doc',
      'table-width/$name-converted.docx',
      'tool/fidelity/table_width_fixture.dart',
    );
  }
  table_reviews.main(['${root.path}/table-reviews']);
  for (final kind in ['height', 'split', 'header']) {
    for (final state in ['review', 'accepted', 'rejected']) {
      final name = 'table-review-$kind-$state';
      record(
        'table-reviews/$name',
        'table-reviews/$name.doc',
        'table-reviews/$name.docx',
        'tool/fidelity/table_review_fixture.dart',
      );
    }
  }
  list_sequences.main(['${root.path}/list-sequences']);
  for (final name in [
    'shared-counter',
    'explicit-start',
    'format-continue',
    'same-instance-ancestor',
    'never-restart',
    'legal-decimal-zero',
    'hidden-marker',
  ]) {
    record(
      'list-sequences/$name',
      'list-sequences/$name.doc',
      'list-sequences/$name-converted.docx',
      'tool/fidelity/list_sequence_fixture.dart',
    );
  }
  shapes.main(['${root.path}/shapes']);
  for (final name in [
    'rect',
    'ellipse',
    'line',
    'custom',
    for (final axis in ['h', 'v'])
      for (final flip in ['none', 'x', 'y', 'xy']) 'line-$axis-$flip',
  ]) {
    record(
      'shapes/$name',
      'shapes/$name.doc',
      'shapes/$name.docx',
      'tool/fidelity/shape_probe.dart',
    );
  }
  metafiles.main(['${root.path}/metafiles']);
  for (final format in ['emf32', 'emf16', 'wmf']) {
    for (final mode in ['alternate', 'winding']) {
      final name = '$format-$mode';
      record(
        'metafiles/$name',
        'metafiles/$name.doc',
        'metafiles/$name.docx',
        'tool/fidelity/metafile_probe.dart',
      );
    }
  }
  image_appearance.main([
    '${repository.path}/test/fixtures/fidelity/image-appearance/binary',
    '${root.path}/image-appearance',
  ]);
  for (final name in [
    'inline-horizontal',
    'floating-control',
    'floating-horizontal',
    'floating-vertical',
    'floating-both',
    'floating-quarter',
    'floating-negative-quarter',
    'floating-margin-quarter',
    'floating-outline-shadow',
  ]) {
    File(
      '${repository.path}/test/fixtures/fidelity/image-appearance/binary/$name.doc',
    ).copySync('${root.path}/image-appearance/$name.doc');
    record(
      'image-appearance/$name',
      'image-appearance/$name.doc',
      'image-appearance/$name.docx',
      'tool/fidelity/image_appearance_probe.dart',
    );
  }
  packed_shapes.main(['${root.path}/packed-shapes']);
  for (final flip in ['none', 'xy']) {
    for (final encoding in ['full', 'packed', 'packed-header-excluded']) {
      final name = '$encoding-$flip';
      record(
        'packed-shapes/$name',
        'packed-shapes/$name.doc',
        'packed-shapes/$name.docx',
        'tool/fidelity/packed_shape_probe.dart',
      );
    }
  }
  note_formats.main(['${root.path}/note-formats']);
  for (final name in [
    'note-formats-east-asian-sepx',
    'note-formats-korean-sepx',
    'note-formats-rtl-dop',
    'note-formats-south-asian-dop',
    'note-formats-cyrillic-sepx',
    'note-formats-none-sepx',
    'note-formats-fallback-sepx',
    'note-formats-unknown-sepx',
    'note-formats-revision',
  ]) {
    record(
      'note-formats/$name',
      'note-formats/$name.doc',
      'note-formats/$name.docx',
      'tool/fidelity/note_format_fixture.dart',
    );
  }
  reviews.main(['${root.path}/reviews']);
  for (final name in [
    'numbering-change',
    'numbering-insertion',
    'listnum-display-change',
  ]) {
    record(
      'reviews/$name',
      'reviews/$name.doc',
      'reviews/$name.docx',
      'tool/fidelity/review_schema_fixture.dart',
    );
  }
  sections.main(['${root.path}/section-review.doc']);
  File('${root.path}/section-review.docx').writeAsBytesSync(
    convertLegacyWordToStructuredDocx(
      File('${root.path}/section-review.doc').readAsBytesSync(),
    ).bytes,
  );
  record(
    'section-review',
    'section-review.doc',
    'section-review.docx',
    'tool/fidelity/section_review_fixture.dart',
  );
  Directory('${root.path}/native-inputs').createSync();
  for (final name in [
    'formatting',
    'linked-textboxes',
    'word14-margin-origin',
    'word16-page-origin',
    'word16-page-origin-lo-blip-count',
    'poi-simple-table2',
  ]) {
    final source = File(
      '${repository.path}/test/fixtures/word_native/$name.doc',
    );
    source.copySync('${root.path}/native-inputs/$name.doc');
    File('${root.path}/native-inputs/$name.docx').writeAsBytesSync(
      convertLegacyWordToStructuredDocx(source.readAsBytesSync()).bytes,
    );
    record(
      'native-inputs/$name',
      'native-inputs/$name.doc',
      'native-inputs/$name.docx',
      'test/fixtures/word_native/$name.doc',
    );
  }
  final outputs = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.toLowerCase().endsWith('.docx'))
      .map((file) => file.path.substring(root.path.length + 1))
      .toSet();
  final expected = manifest.map((entry) => entry['output'] as String).toSet();
  if (outputs.length != manifest.length ||
      outputs.length != expected.length ||
      !outputs.containsAll(expected)) {
    throw StateError('The schema corpus has unexpected or duplicate outputs.');
  }
  File('${root.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'cases': manifest})}\n',
  );
  stdout.writeln('Generated ${manifest.length} deterministic schema cases.');
}
