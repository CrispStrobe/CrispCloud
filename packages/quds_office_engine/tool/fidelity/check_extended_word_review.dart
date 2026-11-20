// Explicit live gate for the synthetic extended-review fixture after Word saves
// it. Missing inputs fail rather than skipping. This does not inspect user docs.
// dart run tool/fidelity/check_extended_word_review.dart input.docx output-dir
import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

WmlRun firstRun(WmlDocument document) =>
    document.paragraphs.first.inlines.whereType<WmlRun>().first;
void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError('Expected Word-saved fixture and output directory');
  }
  final source = File(args.first).readAsBytesSync();
  final output = Directory(args.last)..createSync(recursive: true);
  final document = WordDeserializer().readBytes(source);
  const kinds = {
    WmlRevisionKind.runFormat,
    WmlRevisionKind.paragraphFormat,
    WmlRevisionKind.moveFrom,
    WmlRevisionKind.moveTo,
  };
  require(
    document.revisions.length == 4 &&
        document.revisions.map((r) => r.kind).toSet().containsAll(kinds),
    'Word revision types changed',
  );
  require(
    document.revisions.every(
      (r) =>
          r.author == 'Original reviewer' &&
          r.dateIso == '2026-11-19T10:00:00Z',
    ),
    'Author/date changed',
  );
  WordRevisions.validate(document);
  final pending = WordSerializer().writeBytes(document);
  File('${output.path}/quds-pending.docx').writeAsBytesSync(pending);
  require(
    WordDeserializer().readBytes(pending).revisions.length == 4,
    'Pending changes lost',
  );
  for (final accept in [true, false]) {
    final d = WordDeserializer().readBytes(source);
    if (accept) {
      WordRevisions.acceptAll(d);
    } else {
      WordRevisions.rejectAll(d);
    }
    require(d.revisions.isEmpty, 'Changes left after decision');
    require(
      firstRun(d).properties.bold == accept &&
          firstRun(d).properties.italic != accept,
      'Run properties incorrect',
    );
    require(
      d.paragraphs.last.properties.justification ==
          (accept ? WmlJustification.center : WmlJustification.right),
      'Paragraph properties incorrect',
    );
    require(
      d.paragraphs.elementAt(1).text ==
          (accept
              ? 'Some other text.Moved sentence.'
              : 'Moved sentence.Some other text.'),
      'Paired move text incorrect',
    );
    final bytes = WordSerializer().writeBytes(d);
    File(
      '${output.path}/quds-${accept ? 'accepted' : 'rejected'}.docx',
    ).writeAsBytesSync(bytes);
    require(
      WordDeserializer().readBytes(bytes).revisions.isEmpty,
      'Resolved revisions reappeared',
    );
  }
  print(
    jsonEncode({
      'passed': true,
      'revisionKinds': kinds.map((k) => k.name).toList(),
      'authorDatePreserved': true,
      'pendingReexport': true,
      'acceptAll': true,
      'rejectAll': true,
      'runPropertiesRestored': true,
      'paragraphPropertiesRestored': true,
      'pairedMoveTextVerified': true,
    }),
  );
}
