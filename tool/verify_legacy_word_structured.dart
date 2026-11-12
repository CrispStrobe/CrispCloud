// Opt-in acceptance for the built-in DOC -> DOCX converter. An already
// installed LibreOffice renders the generated package; existing pdfinfo and
// pdftotext inspect the result independently. No tools are downloaded.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:quds_office_engine/quds_office_engine.dart' hide XmlDocument, XmlElement, XmlNode, XmlText, XmlAttribute;
import 'package:crisp_cloud/services/word_conversion_inspection.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show OpcPackage;
import 'package:xml/xml.dart';

Future<void> main(List<String> arguments) async {
  final installations = await discoverInstalledOfficeConverters(
    libreOfficeExecutable: arguments.firstOrNull,
  );
  final engine = installations
      .where(
        (engine) =>
            engine.kind == InstalledOfficeKind.libreOffice &&
            engine.supportsPagePreview,
      )
      .firstOrNull;
  if (engine == null) {
    stderr.writeln(
      'No supported installed LibreOffice PDF renderer was found.',
    );
    exitCode = 2;
    return;
  }
  final source = File('test/fixtures/word_native/formatting.doc');
  final original = await source.readAsBytes();
  final sourceHash = sha256.convert(original).toString();
  final result = convertLegacyWordToStructuredDocx(original);
  final copyHash = sha256.convert(result.bytes).toString();
  final report = await inspectConvertedWord(
    result.bytes,
    extension: 'docx',
    source: inspectLegacyWordSource(original),
  );
  final package = OpcPackage.openBytes(result.bytes);
  const ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final document = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  );
  final bold = document
      .findAllElements('r', namespace: ns)
      .firstWhere(
        (run) => run
            .findAllElements('t', namespace: ns)
            .any((t) => t.innerText == 'Bold red text'),
      );
  final checks = <String, bool>{
    'tableAndCells':
        report.counts['tables'] == 1 && report.counts['cells'] == 4,
    'bold':
        bold
            .findAllElements('b', namespace: ns)
            .single
            .getAttribute('val', namespace: ns) ==
        '1',
    'fontSize':
        bold
            .findAllElements('sz', namespace: ns)
            .single
            .getAttribute('val', namespace: ns) ==
        '36',
    'fontColor':
        bold
            .findAllElements('color', namespace: ns)
            .single
            .getAttribute('val', namespace: ns) ==
        'C02030',
    'pageDimensions': document
        .findAllElements('pgSz', namespace: ns)
        .isNotEmpty,
    'omittedHeadersDisclosed':
        result.limitations.contains(
          LegacyWordConversionLimitation.headersFooters,
        ) &&
        report.losses.contains(WordConversionLoss.headersMissing),
    'omittedNotesDisclosed':
        result.limitations.contains(
          LegacyWordConversionLimitation.notesComments,
        ) &&
        report.losses.contains(WordConversionLoss.footnotesMissing),
    'omittedImagesDisclosed': result.limitations.contains(
      LegacyWordConversionLimitation.images,
    ),
  };
  final pdf = await convertWithInstalledOffice(
    bytes: result.bytes,
    sourceName: 'structured.docx',
    installation: engine,
    output: InstalledOfficeOutput.pdf,
  );
  validateInstalledOfficePdf(pdf.bytes);
  final temporary = await Directory.systemTemp.createTemp(
    'structured-word-acceptance-',
  );
  try {
    final file = File('${temporary.path}/structured.pdf');
    await file.writeAsBytes(pdf.bytes);
    final info = await Process.run('pdfinfo', [file.path]);
    final text = await Process.run('pdftotext', [
      '-enc',
      'UTF-8',
      file.path,
      '-',
    ]);
    checks['independentPdfInfo'] =
        info.exitCode == 0 &&
        RegExp(r'Pages:\s+[1-9]').hasMatch('${info.stdout}');
    checks['independentPdfText'] =
        text.exitCode == 0 &&
        [
          'Installed Office conversion fixture',
          'Bold red text',
          'Column A',
          'Cell two',
        ].every('${text.stdout}'.contains);
    checks['sourceUnchanged'] =
        sha256.convert(await source.readAsBytes()).toString() == sourceHash;
    checks['preparedPackageUnchanged'] =
        sha256.convert(result.bytes).toString() == copyHash;
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'engine': engine.displayName,
        'checks': checks,
        'counts': report.counts,
        'limitations': result.limitations.map((value) => value.name).toList(),
        'sourceSha256': sourceHash,
        'docxSha256': copyHash,
      }),
    );
    if (checks.values.any((passed) => !passed)) exitCode = 1;
  } finally {
    await temporary.delete(recursive: true);
  }
}
