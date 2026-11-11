import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Scriptable DOCX import, mutation and export. Indexes are zero-based.
/// inspect INPUT; export INPUT OUTPUT; modify INPUT STEPS.json OUTPUT.
Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      !<String>['inspect', 'export', 'modify'].contains(args[0]) ||
      args.length !=
          (args[0] == 'inspect'
              ? 2
              : args[0] == 'export'
              ? 3
              : 4)) {
    stderr.writeln(
      'Usage: dart run tool/fidelity/office_steps.dart inspect INPUT.docx\n'
      '       ... export INPUT.docx OUTPUT.docx\n'
      '       ... modify INPUT.docx STEPS.json OUTPUT.docx',
    );
    exitCode = 64;
    return;
  }
  final WmlDocument doc = WordDeserializer().readBytes(
    File(args[1]).readAsBytesSync(),
  );
  if (args[0] == 'inspect') {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'paragraphs': <Object?>[
          for (final WmlParagraph p in doc.paragraphs)
            <String, Object?>{
              'text': p.text,
              'style': p.properties.styleId,
              'heading': p.properties.headingLevel,
              'list': p.properties.listLabel,
            },
        ],
        'notes': <Object?>[
          for (final WmlNote n in <WmlNote>[...doc.footnotes, ...doc.endnotes])
            <String, Object?>{'id': n.id, 'endnote': n.endnote, 'text': n.text},
        ],
        'images': <Object?>[
          for (final WmlVisual v in doc.visuals)
            <String, Object?>{
              'title': v.visual.title,
              'width': v.visual.width,
              'height': v.visual.height,
            },
        ],
      }),
    );
    return;
  }
  if (args[0] == 'modify') {
    final List<dynamic> steps =
        jsonDecode(File(args[2]).readAsStringSync()) as List<dynamic>;
    for (var i = 0; i < steps.length; i++) {
      try {
        applyStep(doc, (steps[i] as Map).cast<String, dynamic>());
      } on Object catch (e) {
        throw StateError('Step ${i + 1} failed: $e');
      }
    }
  }
  final Uint8List output = await OfficeIsolateSave.word(doc);
  // Do not touch the output until every step and serialization has succeeded.
  final destination = File(args.last);
  destination.parent.createSync(recursive: true);
  final temporary = File(
    '${destination.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    temporary.writeAsBytesSync(output, flush: true);
    temporary.renameSync(destination.path);
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}

void applyStep(WmlDocument doc, Map<String, dynamic> step) {
  WmlParagraph paragraph() =>
      doc.paragraphs.elementAt(step['paragraph'] as int);
  final String op = step['op'] as String;
  switch (op) {
    case 'replaceText':
      final WmlParagraph p = paragraph();
      WmlRunEdit.replaceRange(
        p,
        step['start'] as int? ?? 0,
        step['end'] as int? ?? p.text.length,
        step['text'] as String,
      );
    case 'characterStyle':
      final run = paragraph().inlines.whereType<WmlRun>().elementAt(
        step['run'] as int,
      );
      run.properties.styleId = step['style'] as String;
      WordDeserializer().refreshStyles(doc);
    case 'tableStyle':
      final tables = doc.sections.expand((s) => s.blocks).whereType<WmlTable>();
      tables.elementAt(step['table'] as int).properties.styleId =
          step['style'] as String;
      WordDeserializer().refreshStyles(doc);
    case 'styleDefinition':
      final package = doc.package;
      if (package == null) {
        throw ArgumentError('Style editing requires an imported package');
      }
      final office = package.packageRelationships.firstByType(
        RelationshipTypes.officeDocument,
      );
      final uri = office == null
          ? '/word/document.xml'
          : package.packageRelationships.resolve(office);
      final rels = package.relationshipsFor(uri);
      final rel = rels.firstByType(RelationshipTypes.styles);
      final part = package.getPart(
        rel == null ? '/word/styles.xml' : rels.resolve(rel),
      );
      if (part == null) throw ArgumentError('No styles part');
      final xml = XmlDocument.parse(part.readText());
      final style = xml.root!
          .childrenNamed('style')
          .where((s) => s.getAttribute('styleId') == step['style'])
          .firstOrNull;
      if (style == null) throw ArgumentError('Unknown style id');
      if (step.containsKey('type') &&
          style.getAttribute('type') != step['type']) {
        throw ArgumentError('Style type mismatch');
      }
      for (final group in ['rPr', 'pPr', 'tblPr', 'tcPr']) {
        if (!step.containsKey(group)) continue;
        XmlElement? props = style.firstChild(group);
        if (props == null) {
          props = XmlElement(localName: group, prefix: 'w');
          style.addChild(props);
        }
        final values = (step[group] as Map).cast<String, dynamic>();
        for (final entry in values.entries) {
          props.children.removeWhere(
            (n) => n is XmlElement && n.localName == entry.key,
          );
          if (entry.value == null) continue;
          final element = XmlElement(localName: entry.key, prefix: 'w');
          for (final attr in (entry.value as Map).entries) {
            element.setAttribute(
              attr.key as String,
              '${attr.value}',
              prefix: 'w',
            );
          }
          props.addChild(element);
        }
      }
      part.writeText(xml.toXmlString());
      WordDeserializer().refreshStyles(doc);
    case 'applyStyle':
      WordStyles.apply(paragraph(), step['style'] as String, document: doc);
    case 'heading':
      WordToc.applyHeading(paragraph(), step['level'] as int);
    case 'paragraphFormat':
      final WmlParagraphProps p = paragraph().properties;
      if (step.containsKey('alignment')) {
        p.justification = WmlJustification.values.byName(
          step['alignment'] as String,
        );
      }
      if (step.containsKey('before')) {
        p.spacingBefore = (step['before'] as num).toDouble();
      }
      if (step.containsKey('after')) {
        p.spacingAfter = (step['after'] as num).toDouble();
      }
      if (step.containsKey('lineSpacing')) {
        p.lineSpacing = (step['lineSpacing'] as num).toDouble();
      }
      if (step.containsKey('keepTogether')) {
        p.keepTogether = step['keepTogether'] as bool;
      }
      if (step.containsKey('pageBreakBefore')) {
        p.pageBreakBefore = step['pageBreakBefore'] as bool;
      }
    case 'runFormat':
      final WmlParagraph p = paragraph();
      WmlRunEdit.applyRange(
        p,
        step['start'] as int? ?? 0,
        step['end'] as int? ?? p.text.length,
        (WmlRunProps r) {
          if (step.containsKey('bold')) r.bold = step['bold'] as bool;
          if (step.containsKey('italic')) r.italic = step['italic'] as bool;
          if (step.containsKey('color')) r.color = step['color'] as String;
          if (step.containsKey('highlight')) {
            r.highlight = step['highlight'] as String?;
          }
          if (step.containsKey('font')) r.asciiFont = step['font'] as String;
          if (step.containsKey('size')) {
            r.fontSizeHalfPoints = ((step['size'] as num) * 2).round();
          }
        },
      );
    case 'addNote':
      WordNotes.insert(
        doc,
        paragraph(),
        endnote: step['endnote'] as bool? ?? false,
        text: step['text'] as String,
      );
    case 'editNote':
      final WmlNote? note = WordNotes.byId(
        doc,
        step['id'] as int,
        endnote: step['endnote'] as bool? ?? false,
      );
      if (note == null) throw ArgumentError('Unknown note id');
      note.text = step['text'] as String;
    case 'deleteNote':
      if (!WordNotes.delete(
        doc,
        step['id'] as int,
        endnote: step['endnote'] as bool? ?? false,
      )) {
        throw ArgumentError('Unknown note id');
      }
    case 'imageSize':
      final OfficeVisual image = doc.visuals
          .elementAt(step['image'] as int)
          .visual;
      if (step.containsKey('width')) {
        image.width = (step['width'] as num).toDouble();
      }
      if (step.containsKey('height')) {
        image.height = (step['height'] as num).toDouble();
      }
    case 'imageReplace':
      doc.visuals.elementAt(step['image'] as int).visual.imageBytes = File(
        step['file'] as String,
      ).readAsBytesSync();
    default:
      throw ArgumentError('Unknown operation: $op');
  }
}
