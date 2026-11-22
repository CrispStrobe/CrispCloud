import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _document(WmlFootnoteSeparator separator) {
  final document = WmlDocument.empty(text: 'Body 😀 ')
    ..footnoteSeparator = separator;
  WordNotes.insert(
    document,
    document.paragraphs.single,
    endnote: false,
    text: 'Research note with its own text.',
  );
  return document;
}

XmlElement _root(OpcPackage package, String path) =>
    XmlDocument.parse(package.getPart(path)!.readText()).root!;

List<XmlElement> _definitions(OpcPackage package) =>
    _root(package, '/word/footnotes.xml')
        .childrenNamed('footnote', namespaceUri: OfficeNamespaces.w)
        .where(
          (node) =>
              node.getAttribute('type', namespaceUri: OfficeNamespaces.w) !=
              null,
        )
        .toList();

List<int> _references(OpcPackage package) =>
    _root(package, '/word/settings.xml')
        .firstChild('footnotePr', namespaceUri: OfficeNamespaces.w)!
        .childrenNamed('footnote', namespaceUri: OfficeNamespaces.w)
        .map(
          (node) => int.parse(
            node.getAttribute('id', namespaceUri: OfficeNamespaces.w)!,
          ),
        )
        .toList();

void _rewrite(OpcPackage package, String path, void Function(XmlElement) edit) {
  final document = XmlDocument.parse(package.getPart(path)!.readText());
  edit(document.root!);
  package.getPart(path)!.writeText(document.toXmlString());
}

void _attribute(XmlElement element, String name, String value) => element
    .setAttribute(name, value, prefix: 'w', namespaceUri: OfficeNamespaces.w);

void _duplicateAttribute(
  XmlElement element,
  String name,
  String value, {
  bool alias = false,
}) {
  if (alias) element.setAttribute('q', OfficeNamespaces.w, prefix: 'xmlns');
  element.attributes.add(
    XmlAttribute(
      localName: name,
      value: value,
      prefix: alias ? 'q' : 'w',
      namespaceUri: OfficeNamespaces.w,
    ),
  );
}

Iterable<String> _duplicateSnapshot(XmlElement node) sync* {
  final groups = <String, List<String>>{};
  for (final attribute in node.attributes) {
    final key =
        attribute.prefix == 'xmlns' || attribute.qualifiedName == 'xmlns'
        ? 'xmlns|${attribute.qualifiedName}'
        : '${attribute.namespaceUri}|${attribute.localName}';
    groups.putIfAbsent(key, () => []).add(attribute.value);
  }
  for (final entry in groups.entries) {
    if (entry.value.length > 1) {
      yield '${node.localName}|${entry.key}|${jsonEncode(entry.value)}';
    }
  }
  for (final child in node.childElements) {
    yield* _duplicateSnapshot(child);
  }
}

Object _snapshot(XmlElement node) => [
  node.namespaceUri,
  node.localName,
  (node.attributes
      .where(
        (attribute) =>
            attribute.prefix != 'xmlns' && attribute.qualifiedName != 'xmlns',
      )
      .map(
        (attribute) =>
            '${attribute.namespaceUri}|${attribute.localName}|${attribute.value}',
      )
      .toList()
    ..sort()),
  node.text,
  node.childElements.map(_snapshot).toList(),
];

void main() {
  for (final alignment in WmlFootnoteSeparatorAlignment.values) {
    for (final style in WmlFootnoteSeparatorLineStyle.values) {
      for (final gap in [0.0, 7.25]) {
        test(
          'native DOCX round trips $alignment $style gap=$gap with active notes',
          () async {
            final geometry = WmlFootnoteSeparator(
              beforeSpacing: gap,
              afterSpacing: gap,
              thickness: 0.5,
              relativeWidth: 0.5,
              color: 0x9f2040,
              alignment: alignment,
              lineStyle: style,
            );
            var document = _document(geometry);
            final text = document.footnotes.single.text;
            for (var cycle = 0; cycle < 3; cycle++) {
              final bytes = await OfficeIsolateSave.word(document);
              final package = OpcPackage.openBytes(bytes);
              expect(
                _definitions(package).map((node) => node.getAttribute('type')),
                ['separator', 'continuationSeparator'],
              );
              expect(_references(package), [-1, 0]);
              document = WordDeserializer().read(package);
              expect(document.footnoteSeparator, geometry);
              expect(document.footnotes.single.text, text);
              document.footnotes.single.paragraphs.last.inlines.add(
                WmlRun(text: ''),
              );
            }
          },
        );
      }
    }
  }

  test('zero-thickness hidden rule preserves independent gaps', () {
    const separator = WmlFootnoteSeparator(
      beforeSpacing: 8,
      afterSpacing: 3,
      thickness: 0,
      relativeWidth: 0,
      lineStyle: WmlFootnoteSeparatorLineStyle.none,
    );
    final document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(_document(separator)),
    );
    expect(document.footnoteSeparator, separator);
    expect(document.footnoteSeparator!.reservedHeight, 11);
    expect(document.footnoteSeparator!.visible, isFalse);
  });

  test(
    'dormant separator and deleting the last note retain conformant references',
    () {
      const separator = WmlFootnoteSeparator(relativeWidth: 1);
      var document = WmlDocument.empty(text: 'No notes yet')
        ..footnoteSeparator = separator;
      for (var phase = 0; phase < 3; phase++) {
        final package = WordSerializer().write(document);
        expect(package.getPart('/word/footnotes.xml'), isNotNull);
        expect(_references(package), [-1, 0]);
        expect(
          _definitions(
            package,
          ).map((node) => int.parse(node.getAttribute('id')!)),
          [-1, 0],
        );
        document = WordDeserializer().readBytes(package.save());
        expect(document.footnoteSeparator, separator);
        if (phase == 0) {
          WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: false,
            text: 'One note',
          );
        } else if (phase == 1) {
          expect(
            WordNotes.delete(
              document,
              document.footnotes.single.id,
              endnote: false,
            ),
            isTrue,
          );
        } else {
          expect(document.footnotes, isEmpty);
        }
      }
    },
  );

  test(
    'hidden and zero-relative rules retain nominal thickness through DOCX',
    () {
      for (final separator in [
        const WmlFootnoteSeparator(
          thickness: 3.375,
          beforeSpacing: 0,
          afterSpacing: 2.25,
          relativeWidth: 1,
          lineStyle: WmlFootnoteSeparatorLineStyle.none,
        ),
        const WmlFootnoteSeparator(
          thickness: 3.375,
          beforeSpacing: 0,
          afterSpacing: 2.25,
          relativeWidth: 0,
        ),
      ]) {
        var document = _document(separator);
        for (var cycle = 0; cycle < 3; cycle++) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(document.footnoteSeparator, separator);
          expect(document.footnoteSeparator!.reservedHeight, 5.625);
        }
      }
    },
  );

  test('DOCX quantization is bounded and stable over repeated saves', () {
    const original = WmlFootnoteSeparator(
      beforeSpacing: 3.123,
      afterSpacing: 6.789,
      thickness: 0.51,
      relativeWidth: 0.333,
      alignment: WmlFootnoteSeparatorAlignment.center,
    );
    var document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(_document(original)),
    );
    final normalized = document.footnoteSeparator!;
    expect(normalized.beforeSpacing, closeTo(original.beforeSpacing, 0.025));
    expect(normalized.afterSpacing, closeTo(original.afterSpacing, 0.025));
    expect(normalized.thickness, closeTo(original.thickness, 0.0625));
    expect(
      normalized.relativeWidth,
      closeTo(
        original.relativeWidth,
        0.05 / document.sections.single.contentWidth,
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(document.footnoteSeparator, normalized);
    }
  });

  test(
    'fractional page and margin rounding preserve zero-relative separator ownership',
    () {
      const separator = WmlFootnoteSeparator(relativeWidth: 0, thickness: 0.5);
      var document = _document(separator);
      document.sections.single
        ..pageSize = const WmlPageSize(width: 600.024, height: 844)
        ..margins = const WmlPageMargins(left: 72.026, right: 72.026);
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(document.footnoteSeparator, separator);
      }
    },
  );

  test(
    'native special IDs are type-based and remain reserved for later note insertion',
    () {
      const separator = WmlFootnoteSeparator(relativeWidth: 1);
      final package = WordSerializer().write(_document(separator));
      _rewrite(package, '/word/footnotes.xml', (root) {
        for (final node in root.childrenNamed('footnote')) {
          final type = node.getAttribute('type');
          if (type == 'separator') _attribute(node, 'id', '2');
          if (type == 'continuationSeparator') _attribute(node, 'id', '3');
        }
      });
      _rewrite(package, '/word/settings.xml', (root) {
        final refs = root.firstChild('footnotePr')!.childrenNamed('footnote');
        _attribute(refs[0], 'id', '2');
        _attribute(refs[1], 'id', '3');
      });
      final document = WordDeserializer().read(package);
      expect(document.footnoteSeparator, separator);
      expect(
        WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: false,
          text: 'Another note',
        ).id,
        4,
      );
      final saved = WordSerializer().write(document);
      expect(_references(saved), [2, 3]);
      expect(_definitions(saved).map((node) => node.getAttribute('id')), [
        '2',
        '3',
      ]);
      expect(WordDeserializer().read(saved).footnotes.map((note) => note.id), [
        1,
        4,
      ]);
    },
  );

  test(
    'new separator definitions do not collide with authored zero/negative note IDs',
    () {
      final document = _document(const WmlFootnoteSeparator(relativeWidth: 1));
      document.footnotes.addAll([
        WmlNote(id: -1, endnote: false),
        WmlNote(id: 0, endnote: false),
      ]);
      final package = WordSerializer().write(document);
      expect(_references(package), [-2, -3]);
      expect(
        WordDeserializer().read(package).footnoteSeparator,
        document.footnoteSeparator,
      );
    },
  );

  test(
    'replacing a modeled separator keeps note settings and unrelated native metadata',
    () {
      final package = WordSerializer().write(
        _document(const WmlFootnoteSeparator()),
      );
      _rewrite(package, '/word/settings.xml', (root) {
        root.setAttribute('e', 'urn:separator-extension', prefix: 'xmlns');
        root.addChild(
          XmlElement(
            localName: 'retained',
            prefix: 'e',
            namespaceUri: 'urn:separator-extension',
          )..addText('unknown setting'),
        );
        final properties = root.firstChild('footnotePr')!;
        final numbering = XmlElement(
          localName: 'numStart',
          prefix: 'w',
          namespaceUri: OfficeNamespaces.w,
        );
        _attribute(numbering, 'val', '4');
        properties.children.insert(0, numbering..parent = properties);
      });
      final document = WordDeserializer().read(package)
        ..footnoteSeparator = const WmlFootnoteSeparator(
          relativeWidth: 1,
          beforeSpacing: 12,
          color: 0x112233,
        );
      final saved = WordSerializer().write(document);
      final settings = _root(saved, '/word/settings.xml');
      expect(
        settings
            .firstChild('retained', namespaceUri: 'urn:separator-extension')!
            .text,
        'unknown setting',
      );
      expect(
        settings
            .firstChild('footnotePr')!
            .firstChild('numStart')!
            .getAttribute('val'),
        '4',
      );
      expect(
        WordDeserializer().read(saved).footnoteSeparator,
        document.footnoteSeparator,
      );
    },
  );

  test(
    'canonical separators accept a namespace alias without duplicate attributes',
    () {
      const separator = WmlFootnoteSeparator(
        relativeWidth: 1,
        beforeSpacing: 2,
      );
      final package = WordSerializer().write(_document(separator));
      final part = package.getPart('/word/footnotes.xml')!;
      part.writeText(
        part
            .readText()
            .replaceAll('w:', 'q:')
            .replaceAll('xmlns:w=', 'xmlns:q='),
      );
      final document = WordDeserializer().read(package);
      expect(document.footnoteSeparator, separator);
      expect(
        WordDeserializer()
            .readBytes(WordSerializer().writeBytes(document))
            .footnoteSeparator,
        separator,
      );
    },
  );

  final corruptions = <String, void Function(OpcPackage)>{
    'duplicate separator color': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final border = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!
              .firstChild('pBdr')!
              .firstChild('bottom')!;
          _duplicateAttribute(border, 'color', 'FF0000');
        }),
    'aliased duplicate separator size': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final border = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!
              .firstChild('pBdr')!
              .firstChild('bottom')!;
          _duplicateAttribute(border, 'sz', '16', alias: true);
        }),
    'duplicate separator spacing': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final spacing = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!
              .firstChild('spacing')!;
          _duplicateAttribute(spacing, 'line', '900');
        }),
    'aliased duplicate special note ID': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          _duplicateAttribute(
            root.childrenNamed('footnote').first,
            'id',
            '900',
            alias: true,
          );
        }),
    'duplicate special note type': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          _duplicateAttribute(
            root.childrenNamed('footnote').first,
            'type',
            'continuationNotice',
          );
        }),
    'aliased duplicate special-reference ID': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          _duplicateAttribute(
            root.firstChild('footnotePr')!.childrenNamed('footnote').first,
            'id',
            '900',
            alias: true,
          );
        }),
    'duplicate separator namespace declaration': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final properties = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!;
          properties.attributes.addAll([
            XmlAttribute(
              localName: 'q',
              prefix: 'xmlns',
              value: OfficeNamespaces.w,
            ),
            XmlAttribute(
              localName: 'q',
              prefix: 'xmlns',
              value: OfficeNamespaces.w,
            ),
          ]);
        }),
    'duplicate settings namespace declaration': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          final properties = root.firstChild('footnotePr')!;
          properties.attributes.addAll([
            XmlAttribute(
              localName: 'q',
              prefix: 'xmlns',
              value: OfficeNamespaces.w,
            ),
            XmlAttribute(
              localName: 'q',
              prefix: 'xmlns',
              value: OfficeNamespaces.w,
            ),
          ]);
        }),
    'missing special reference': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          final properties = root.firstChild('footnotePr')!;
          properties.children.removeLast();
        }),
    'duplicate reference': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          final refs = root.firstChild('footnotePr')!.childrenNamed('footnote');
          _attribute(refs.last, 'id', refs.first.getAttribute('id')!);
        }),
    'duplicate footnote properties': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          root.addChild(root.firstChild('footnotePr')!.copy());
        }),
    'unknown special-reference attribute': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          _attribute(
            root.firstChild('footnotePr')!.childrenNamed('footnote').first,
            'futureSetting',
            '1',
          );
        }),
    'special-reference content': (package) =>
        _rewrite(package, '/word/settings.xml', (root) {
          root
              .firstChild('footnotePr')!
              .childrenNamed('footnote')
              .first
              .addText('Unknown payload');
        }),
    'different continuation geometry': (package) => _rewrite(
      package,
      '/word/footnotes.xml',
      (root) {
        final continued = root
            .childrenNamed('footnote')
            .firstWhere(
              (node) => node.getAttribute('type') == 'continuationSeparator',
            );
        _attribute(
          continued.firstChild('p')!.firstChild('pPr')!.firstChild('spacing')!,
          'after',
          '777',
        );
      },
    ),
    'custom separator content': (package) => _rewrite(
      package,
      '/word/footnotes.xml',
      (root) {
        final paragraph = root.childrenNamed('footnote').first.firstChild('p')!;
        paragraph.addChild(
          XmlElement(
            localName: 'r',
            prefix: 'w',
            namespaceUri: OfficeNamespaces.w,
          )..addChild(
            XmlElement(
              localName: 't',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            )..addText('Custom text'),
          ),
        );
      },
    ),
    'unknown effective formatting': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final properties = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!;
          properties.addChild(
            XmlElement(
              localName: 'pStyle',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            )..setAttribute(
              'val',
              'Custom',
              prefix: 'w',
              namespaceUri: OfficeNamespaces.w,
            ),
          );
        }),
    'theme-dependent color': (package) =>
        _rewrite(package, '/word/footnotes.xml', (root) {
          final border = root
              .childrenNamed('footnote')
              .first
              .firstChild('p')!
              .firstChild('pPr')!
              .firstChild('pBdr')!
              .firstChild('bottom')!;
          _attribute(border, 'themeColor', 'accent1');
        }),
  };
  for (final (name, corrupt) in corruptions.entries.map(
    (entry) => (entry.key, entry.value),
  )) {
    test('$name remains opaque and cannot be silently replaced', () {
      final package = WordSerializer().write(
        _document(const WmlFootnoteSeparator()),
      );
      corrupt(package);
      final expected = _definitions(package).map(_snapshot).toList();
      final expectedDuplicates = _definitions(
        package,
      ).expand(_duplicateSnapshot).toList();
      final expectedSettings = package
          .getPart('/word/settings.xml')!
          .readText();
      final document = WordDeserializer().read(package);
      expect(document.footnoteSeparator, isNull);
      expect(
        _definitions(WordSerializer().write(document)).map(_snapshot).toList(),
        expected,
      );
      expect(
        _definitions(package).expand(_duplicateSnapshot).toList(),
        expectedDuplicates,
      );
      expect(
        package.getPart('/word/settings.xml')!.readText(),
        expectedSettings,
      );
      final before = {
        for (final part in package.parts) part.uri: part.readBytes(),
      };
      document.footnoteSeparator = const WmlFootnoteSeparator(
        beforeSpacing: 10,
      );
      expect(() => WordSerializer().write(document), throwsUnsupportedError);
      expect({
        for (final part in package.parts) part.uri: part.readBytes(),
      }, before);
    });
  }

  test('DOCX rejects mixed section widths without changing source parts', () {
    final document = _document(const WmlFootnoteSeparator());
    document.sections.add(
      WmlSection(pageSize: const WmlPageSize(width: 100, height: 200)),
    );
    expect(() => WordSerializer().writeBytes(document), throwsUnsupportedError);
    expect(document.package, isNull);
  });

  test(
    'active separator and rounded geometry cannot exhaust the body height',
    () {
      for (final before in [699.49, 700.0]) {
        final document = _document(
          WmlFootnoteSeparator(
            beforeSpacing: before,
            afterSpacing: 0,
            thickness: 0.5,
          ),
        );
        document.sections.single.pageSize = const WmlPageSize(
          width: 600,
          height: 844,
        );
        expect(
          () => WordSerializer().writeBytes(document),
          throwsUnsupportedError,
        );
        expect(document.package, isNull);
      }
      final dormant = WmlDocument.empty(text: 'No anchor')
        ..footnoteSeparator = const WmlFootnoteSeparator(
          beforeSpacing: 800,
          relativeWidth: 1,
        );
      expect(
        WordDeserializer()
            .readBytes(WordSerializer().writeBytes(dormant))
            .footnoteSeparator,
        dormant.footnoteSeparator,
      );
    },
  );

  test(
    'fractional vertical page dimensions cannot conceal rounded separator exhaustion',
    () {
      final document = _document(
        const WmlFootnoteSeparator(
          beforeSpacing: 699.46,
          afterSpacing: 0,
          thickness: 0.5,
        ),
      );
      document.sections.single
        ..pageSize = const WmlPageSize(width: 600, height: 844.024)
        ..margins = const WmlPageMargins(top: 72.026, bottom: 72.026);
      expect(
        document.footnoteSeparator!.reservedHeight,
        lessThan(document.sections.single.contentHeight),
      );
      expect(
        () => WordSerializer().writeBytes(document),
        throwsUnsupportedError,
      );
      expect(document.package, isNull);
    },
  );

  test('hidden nominal thickness overflow refuses before package creation', () {
    final document = WmlDocument.empty(text: 'Dormant')
      ..footnoteSeparator = const WmlFootnoteSeparator(
        beforeSpacing: 107374182.35,
        thickness: 12,
        lineStyle: WmlFootnoteSeparatorLineStyle.none,
      );
    expect(() => WordSerializer().writeBytes(document), throwsUnsupportedError);
    expect(document.package, isNull);
  });

  for (final thickness in [0.0, 0.24, 12.01, 1e300]) {
    test(
      'unrepresentable solid thickness $thickness refuses before package mutation',
      () {
        final document = _document(WmlFootnoteSeparator(thickness: thickness));
        expect(
          () => WordSerializer().writeBytes(document),
          throwsUnsupportedError,
        );
        expect(document.package, isNull);
      },
    );
  }

  test('invalid native dimensions and colors fail before writing', () {
    for (final separator in [
      const WmlFootnoteSeparator(beforeSpacing: -1),
      const WmlFootnoteSeparator(afterSpacing: double.infinity),
      const WmlFootnoteSeparator(thickness: double.nan),
      const WmlFootnoteSeparator(relativeWidth: 1.01),
      const WmlFootnoteSeparator(color: -1),
      const WmlFootnoteSeparator(color: 0x1000000),
    ]) {
      final document = _document(separator);
      expect(
        () => WordSerializer().writeBytes(document),
        throwsFormatException,
      );
      expect(document.package, isNull);
    }
  });

  test(
    'Zotero transfer keeps geometry detached and rejects stale separator changes',
    () {
      final document = _document(const WmlFootnoteSeparator(color: 0x123456));
      final preferences = jsonEncode({
        'dataVersion': 4,
        'sessionID': 'separator-test',
        'style': {
          'styleID': 'http://www.zotero.org/styles/apa',
          'locale': 'en-US',
        },
        'prefs': {'fieldType': 'Http', 'noteType': 0},
      });
      final plan = WordZoteroTransfer.prepareExport(
        document,
        instructions: 'Refresh in the destination.',
        documentData: preferences,
      );
      expect(plan.document.footnoteSeparator, same(document.footnoteSeparator));
      document.footnoteSeparator = const WmlFootnoteSeparator(color: 0xff0000);
      expect(plan.apply, throwsStateError);
      expect(document.paragraphs.first.text, startsWith('Body'));
    },
  );
}
