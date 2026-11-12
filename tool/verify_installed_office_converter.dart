// Opt-in acceptance against an existing desktop Office installation.
// No packages or office binaries are downloaded. Does not write converted files.
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
  final installations = await discoverInstalledOfficeConverters(
    libreOfficeExecutable: arguments
        .where((argument) => argument != '--word')
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
  for (final format in InstalledOfficeOutput.values) {
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
    final checks = <String, bool>{
      'sourceUnchanged':
          sha256.convert(await source.readAsBytes()).toString() == originalHash,
      'sourceHeadersDetected': sourceInspection.hasHeaders,
      'sourceFootnotesDetected': sourceInspection.hasFootnotes,
      'packageAccepted': true,
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
    reports.add({
      'engine': engine.displayName,
      'version': engine.version,
      'format': format.extension,
      'sourceBytes': original.length,
      'outputBytes': result.bytes.length,
      'elapsedMilliseconds': result.elapsed.inMilliseconds,
      'inspectionCounts': inspection.counts,
      'inspectionLosses': inspection.losses.map((loss) => loss.name).toList(),
      'checks': checks,
    });
    if (checks.values.any((success) => !success)) exitCode = 1;
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(reports));
}
