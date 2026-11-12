// Opt-in acceptance against an existing desktop Office installation.
// No packages or office binaries are downloaded. With --verify-pdf-tools,
// existing pdfinfo/pdftotext independently inspect a temporary PDF preview.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/services/word_conversion_inspection.dart';
import 'package:quds_office_engine/quds_office_engine.dart'
    show OpcPackage, OfficeContentTypes;
import 'package:xml/xml.dart';

Future<void> main(List<String> arguments) async {
  final word = arguments.contains('--word');
  final verifyPdfTools = arguments.contains('--verify-pdf-tools');
  final installations = await discoverInstalledOfficeConverters(
    libreOfficeExecutable: arguments
        .where((argument) => !argument.startsWith('--'))
        .firstOrNull,
  );
  final engine = installations
      .where(
        (installation) =>
            installation.kind ==
            (word
                ? InstalledOfficeKind.microsoftWord
                : InstalledOfficeKind.libreOffice),
      )
      .firstOrNull;
  if (engine == null) {
    stderr.writeln(
      'No supported installed ${word ? 'Microsoft Word' : 'LibreOffice'} converter was found.',
    );
    exitCode = 2;
    return;
  }
  final source = File('test/fixtures/word_native/formatting.doc');
  final original = await source.readAsBytes();
  final originalHash = sha256.convert(original).toString();
  final sourceInspection = inspectLegacyWordSource(original);
  final reports = <Map<String, Object?>>[];
  for (final format in [
    InstalledOfficeOutput.docx,
    InstalledOfficeOutput.docm,
  ]) {
    final result = await convertWithInstalledOffice(
      bytes: original,
      sourceName: 'formatting.doc',
      installation: engine,
      output: format,
    );
    final inspection = await inspectConvertedWord(
      result.bytes,
      extension: format.extension,
      source: sourceInspection,
    );
    final package = OpcPackage.openBytes(result.bytes);
    final xml = XmlDocument.parse(
      package.getPart('/word/document.xml')!.readText(),
    );
    const namespaces =
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
    final text = xml
        .findAllElements('t', namespace: namespaces)
        .map((node) => node.innerText)
        .join();
    final header = package.partNames
        .where(
          (name) => name.startsWith('/word/header') && name.endsWith('.xml'),
        )
        .map((name) => package.getPart(name)!.readText())
        .join();
    final footer = package.partNames
        .where(
          (name) => name.startsWith('/word/footer') && name.endsWith('.xml'),
        )
        .map((name) => package.getPart(name)!.readText())
        .join();
    final footnotes = package.getPart('/word/footnotes.xml')?.readText() ?? '';
    final packageHash = sha256.convert(result.bytes).toString();
    final preview = await convertWithInstalledOffice(
      bytes: result.bytes,
      sourceName: 'formatting.${format.extension}',
      installation: engine,
      output: InstalledOfficeOutput.pdf,
    );
    validateInstalledOfficePdf(preview.bytes);
    final checks = <String, bool>{
      'sourceUnchanged':
          sha256.convert(await source.readAsBytes()).toString() == originalHash,
      'sourceHeadersDetected': sourceInspection.hasHeaders,
      'sourceFootnotesDetected': sourceInspection.hasFootnotes,
      'packageAccepted': true,
      'pdfPreviewAccepted': true,
      'packageUnchangedByPreview':
          sha256.convert(result.bytes).toString() == packageHash,
      'noDetectedLosses': inspection.losses.isEmpty,
      'unicode': text.contains('Unicode café — 東京 😀.'),
      'table':
          xml.findAllElements('tbl', namespace: namespaces).length == 1 &&
          text.contains('Cell two'),
      'bold': xml.findAllElements('b', namespace: namespaces).isNotEmpty,
      'italic': xml.findAllElements('i', namespace: namespaces).isNotEmpty,
      'image': package.partNames.any((name) => name.startsWith('/word/media/')),
      'header': header.contains('Fixture header'),
      'footer': footer.contains('Fixture footer'),
      'footnote': footnotes.contains('Footnote content survives conversion.'),
      'correctContentType':
          package.contentTypes.contentTypeFor('/word/document.xml') ==
          (format == InstalledOfficeOutput.docm
              ? 'application/vnd.ms-word.document.macroEnabled.main+xml'
              : OfficeContentTypes.wordMain),
    };
    if (verifyPdfTools) {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-pdf-acceptance-',
      );
      try {
        final pdf = File('${directory.path}/preview.pdf');
        await pdf.writeAsBytes(preview.bytes);
        final info = await Process.run(
          'pdfinfo',
          [pdf.path],
          environment: {'LC_ALL': 'C'},
        );
        final extracted = await Process.run('pdftotext', [
          '-layout',
          pdf.path,
          '-',
        ]);
        final pageCount = int.tryParse(
          RegExp(r'Pages:\s+(\d+)').firstMatch('${info.stdout}')?.group(1) ??
              '',
        );
        final text = '${extracted.stdout}';
        checks.addAll({
          'independentPdfPages': info.exitCode == 0 && (pageCount ?? 0) > 0,
          'independentPdfBody':
              extracted.exitCode == 0 && text.contains('Cell two'),
          'independentPdfHeader': text.contains('Fixture header'),
          'independentPdfFooter': text.contains('Fixture footer'),
          'independentPdfFootnote': text.contains(
            'Footnote content survives conversion.',
          ),
        });
      } finally {
        await directory.delete(recursive: true);
      }
    }
    reports.add({
      'engine': engine.displayName,
      'version': engine.version,
      'format': format.extension,
      'sourceBytes': original.length,
      'outputBytes': result.bytes.length,
      'previewBytes': preview.bytes.length,
      'elapsedMilliseconds': result.elapsed.inMilliseconds,
      'inspectionCounts': inspection.counts,
      'inspectionLosses': inspection.losses.map((loss) => loss.name).toList(),
      'checks': checks,
    });
    if (checks.values.any((success) => !success)) exitCode = 1;
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(reports));
}
