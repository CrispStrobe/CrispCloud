import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage source(String attributes, {String extra = ''}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.createPart(
    '/custom/settings.xml',
    OfficeContentTypes.wordSettings,
    utf8.encode(
      '<q:settings xmlns:q="${OfficeNamespaces.w}" xmlns:f="urn:foreign">'
      '<q:zoom q:percent="125"/><q:documentProtection $attributes/>'
      '$extra<q:compat/></q:settings>',
    ),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.settings, target: '../custom/settings.xml');
  return package;
}

void main() {
  for (final mode in WmlRestrictMode.values) {
    for (final enforced in [true, false]) {
      test(
        'native ${mode.name} enforcement=$enforced survives three saves',
        () async {
          final input = source(
            'q:edit="${mode.name}" q:enforcement="${enforced ? 1 : 0}" '
            'q:hash="AAAA" q:salt="AQID" f:edit="foreign"',
          );
          final original = input.getPart('/custom/settings.xml')!.readText();
          var document = WordDeserializer().read(input);
          for (var cycle = 0; cycle < 3; cycle++) {
            expect(document.restrictMode, mode);
            expect(document.restrictEditing, enforced);
            expect(document.protectionHasPassword, isTrue);
            final saved = OpcPackage.openBytes(
              await OfficeIsolateSave.word(document),
            );
            expect(saved.getPart('/custom/settings.xml')!.readText(), original);
            expect(saved.getPart('/word/settings.xml'), isNull);
            document = WordDeserializer().read(saved);
          }
        },
      );
    }
  }

  test('changing native restriction keeps hash and foreign attributes', () {
    var document = WordDeserializer().read(
      source(
        'q:edit="forms" q:enforcement="1" q:hash="AAAA" q:salt="AQID" f:edit="retain"',
      ),
    );
    document.restrictMode = WmlRestrictMode.comments;
    document.trackRevisions = true;
    for (var cycle = 0; cycle < 3; cycle++) {
      final saved = WordSerializer().write(document);
      final node =
          XmlDocument.parse(saved.getPart('/custom/settings.xml')!.readText())
              .root!
              .firstChild(
                'documentProtection',
                namespaceUri: OfficeNamespaces.w,
              )!;
      expect(
        node.getAttribute('edit', namespaceUri: OfficeNamespaces.w),
        'comments',
      );
      expect(node.getAttribute('edit', namespaceUri: 'urn:foreign'), 'retain');
      expect(
        node.getAttribute('hash', namespaceUri: OfficeNamespaces.w),
        'AAAA',
      );
      expect(
        node.getAttribute('salt', namespaceUri: OfficeNamespaces.w),
        'AQID',
      );
      document = WordDeserializer().read(saved);
      expect(document.restrictMode, WmlRestrictMode.comments);
      expect(document.trackRevisions, isTrue);
    }
  });

  test('new protection writes the requested native edit mode', () {
    for (final mode in WmlRestrictMode.values) {
      final document = WmlDocument.empty()
        ..restrictEditing = true
        ..restrictMode = mode;
      final bytes = WordSerializer().writeBytes(document);
      final reopened = WordDeserializer().readBytes(bytes);
      expect(reopened.restrictEditing, isTrue);
      expect(reopened.restrictMode, mode);
      expect(reopened.protectionHasPassword, isFalse);
    }
  });

  test('omitted edit means none but formatting restriction is retained', () {
    final package = source(
      'q:enforcement="1" q:formatting="on" f:hash="irrelevant"',
    );
    final document = WordDeserializer().read(package);
    expect(document.restrictMode, WmlRestrictMode.none);
    expect(document.protectionFormattingRestricted, isTrue);
    expect(document.protectionHasPassword, isFalse);
    final original = package.getPart('/custom/settings.xml')!.readText();
    expect(
      WordSerializer()
          .write(document)
          .getPart('/custom/settings.xml')!
          .readText(),
      original,
    );
  });

  test('an unrecognized restriction stays opaque on unrelated saves', () {
    final package = source('q:edit="futureRestriction" q:enforcement="1"');
    final original = package.getPart('/custom/settings.xml')!.readText();
    final document = WordDeserializer().read(package);
    expect(document.restrictMode, WmlRestrictMode.readOnly);
    expect(
      WordSerializer()
          .write(document)
          .getPart('/custom/settings.xml')!
          .readText(),
      original,
    );
  });
}
