import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'archive_viewer_service.dart';

bool isSearchableOfficeDocument(String name) => const [
  '.docx',
  '.docm',
  '.xlsx',
  '.xlsm',
  '.pptx',
  '.pptm',
  '.odt',
  '.ods',
  '.odp',
].any((extension) => name.toLowerCase().endsWith(extension));

/// Extract bounded document XML text without activating macros or external
/// resources. Unsupported legacy binary Office formats remain ordinary files.
Future<String> officeSearchText(
  Uint8List bytes,
  String name,
  int maxBytes,
) async {
  final archive = await openViewerArchive(
    bytes,
    name: name,
    maxMemberBytes: maxBytes,
  );
  try {
    final members =
        archive.members
            .where(
              (entry) =>
                  entry.isFile &&
                  !entry.isSpecial &&
                  !entry.pathEscapedRoot &&
                  (entry.name == 'word/document.xml' ||
                      entry.name == 'content.xml' ||
                      entry.name == 'xl/sharedStrings.xml' ||
                      RegExp(r'^xl/worksheets/sheet\d+\.xml$')
                          .hasMatch(entry.name) ||
                      RegExp(r'^ppt/slides/slide\d+\.xml$')
                          .hasMatch(entry.name)),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    var used = 0;
    final texts = <String>[];
    for (final member in members) {
      final content = await archive.readMember(
        member,
        maxBytes: maxBytes - used,
      );
      used += content.length;
      if (used > maxBytes)
        throw const ArchiveViewException(
          'Office text exceeds the content limit.',
        );
      final document = XmlDocument.parse(utf8.decode(content));
      texts.add(
        document.descendants
            .whereType<XmlText>()
            .map((text) => text.value)
            .join(' '),
      );
    }
    return texts.join('\n');
  } finally {
    await archive.close();
  }
}
