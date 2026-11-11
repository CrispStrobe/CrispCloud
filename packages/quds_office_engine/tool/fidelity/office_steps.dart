import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'sheet_steps.dart';
import 'slide_steps.dart';
import 'step_input.dart';
import 'word_steps.dart';
export 'word_steps.dart' show applyStep;

/// Import, inspect, edit, and export real DOCX/XLSX/PPTX using host async saves.
Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == 'operations') {
    _print(<String, Object?>{
      'docx': wordOperations,
      'xlsx': sheetOperations,
      'pptx': slideOperations,
    });
    return;
  }
  if (args.length < 2 ||
      !<String>['inspect', 'export', 'modify', 'roundtrip'].contains(args[0]) ||
      (args[0] == 'inspect' && args.length != 2) ||
      (args[0] == 'export' && args.length != 3) ||
      (args[0] == 'modify' && args.length != 4) ||
      (args[0] == 'roundtrip' && (args.length < 3 || args.length > 4))) {
    stderr.writeln(
      'Usage: dart run tool/fidelity/office_steps.dart\n'
      '  operations\n  inspect INPUT\n  export INPUT OUTPUT\n'
      '  modify INPUT STEPS.json OUTPUT\n  roundtrip INPUT OUTPUT_DIRECTORY [CYCLES]\n'
      'Formats: .docx, .xlsx, .pptx. Assets are relative to STEPS.json.',
    );
    exitCode = 64;
    return;
  }
  try {
    await execute(args);
  } on Object catch (error) {
    stderr.writeln('Office scenario failed: $error');
    exitCode = 1;
  }
}

void _print(Object? value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
String _format(String path) {
  final extension = path.split('.').last.toLowerCase();
  if (!<String>['docx', 'xlsx', 'pptx'].contains(extension)) {
    throw ArgumentError('Unsupported Office extension: $path');
  }
  return extension;
}

Object _read(Uint8List bytes, String format) => switch (format) {
  'docx' => WordDeserializer().readBytes(bytes),
  'xlsx' => SheetDeserializer().readBytes(bytes),
  'pptx' => SlideDeserializer().readBytes(bytes),
  _ => throw ArgumentError('Unsupported format'),
};
Future<Uint8List> _save(Object doc) => switch (doc) {
  WmlDocument() => OfficeIsolateSave.word(doc),
  SmlWorkbook() => OfficeIsolateSave.workbook(doc),
  PmlPresentation() => OfficeIsolateSave.presentation(doc),
  _ => throw ArgumentError('Unsupported document'),
};

Future<void> execute(List<String> args) async {
  final format = _format(args[1]);
  Object doc = _read(File(args[1]).readAsBytesSync(), format);
  if (args[0] == 'inspect') {
    _print(switch (doc) {
      WmlDocument() => inspectWord(doc),
      SmlWorkbook() => inspectSheet(doc),
      PmlPresentation() => inspectSlides(doc),
      _ => throw StateError('Unknown document'),
    });
    return;
  }
  if (args[0] == 'roundtrip') {
    final cycles = args.length == 4 ? int.tryParse(args[3]) : 3;
    if (cycles == null || cycles < 1 || cycles > 100) {
      throw ArgumentError('CYCLES must be in 1..100');
    }
    for (var cycle = 1; cycle <= cycles; cycle++) {
      final bytes = await _save(doc);
      writeOutput('${args[2]}/roundtrip-$cycle.$format', bytes);
      doc = _read(bytes, format);
    }
    return;
  }
  if (_format(args.last) != format) {
    throw ArgumentError(
      'Output format must match input; export does not convert formats',
    );
  }
  if (args[0] == 'modify') {
    final steps = readSteps(args[2]);
    final assetDirectory = File(args[2]).absolute.parent.path;
    for (var i = 0; i < steps.length; i++) {
      try {
        switch (doc) {
          case WmlDocument():
            applyStep(doc, steps[i], assetDirectory: assetDirectory);
          case SmlWorkbook():
            applySheetStep(doc, steps[i]);
          case PmlPresentation():
            applySlideStep(doc, steps[i], assetDirectory: assetDirectory);
          default:
            throw StateError('Unknown document');
        }
      } on Object catch (error) {
        throw StateError('Step ${i + 1} (${steps[i]['op']}) failed: $error');
      }
    }
    if (doc is SmlWorkbook) FormulaEvaluator.recalculate(doc);
  }
  writeOutput(args.last, await _save(doc));
}

Map<String, Object?> inspectWord(WmlDocument doc) {
  Map<String, Object?> p(WmlParagraph value) => <String, Object?>{
    'text': value.text,
    'style': value.properties.styleId,
    'heading': value.properties.headingLevel,
    'list': value.properties.listLabel,
    'runs': <Object?>[
      for (final run in value.inlines.whereType<WmlRun>())
        <String, Object?>{
          'text': run.text,
          'style': run.properties.styleId,
          'note': run.noteRefId,
          'endnote': run.noteRefEndnote,
          'link': run.hyperlink?.displayTarget,
        },
    ],
  };
  Map<String, Object?> image(WmlVisual value) => <String, Object?>{
    'title': value.visual.title,
    'width': value.visual.width,
    'height': value.visual.height,
    'picture': value.visual.isPicture,
  };
  return <String, Object?>{
    'format': 'docx',
    'paragraphs': <Object?>[for (final value in doc.paragraphs) p(value)],
    'notes': <Object?>[
      for (final n in <WmlNote>[...doc.footnotes, ...doc.endnotes])
        <String, Object?>{
          'id': n.id,
          'endnote': n.endnote,
          'text': n.text,
          'paragraphs': <Object?>[
            for (final value in n.allParagraphs) p(value),
          ],
          'images': <Object?>[for (final value in n.visuals) image(value)],
        },
    ],
    'images': <Object?>[for (final v in doc.visuals) image(v)],
    'sections': <Object?>[
      for (final s in doc.sections)
        <String, Object?>{
          'width': s.pageSize.width,
          'height': s.pageSize.height,
          'columns': s.columnCount,
          'blocks': <String>[
            for (final b in s.blocks) b.runtimeType.toString(),
          ],
          'header': <Object?>[for (final v in s.header) p(v)],
          'footer': <Object?>[for (final v in s.footer) p(v)],
          'firstHeader': <Object?>[for (final v in s.firstHeader) p(v)],
          'firstFooter': <Object?>[for (final v in s.firstFooter) p(v)],
          'evenHeader': <Object?>[for (final v in s.evenHeader) p(v)],
          'evenFooter': <Object?>[for (final v in s.evenFooter) p(v)],
          'headerImages': <Object?>[for (final v in s.headerVisuals) image(v)],
          'footerImages': <Object?>[for (final v in s.footerVisuals) image(v)],
          'firstHeaderImages': <Object?>[
            for (final v in s.firstHeaderVisuals) image(v),
          ],
          'firstFooterImages': <Object?>[
            for (final v in s.firstFooterVisuals) image(v),
          ],
          'evenHeaderImages': <Object?>[
            for (final v in s.evenHeaderVisuals) image(v),
          ],
          'evenFooterImages': <Object?>[
            for (final v in s.evenFooterVisuals) image(v),
          ],
        },
    ],
  };
}
