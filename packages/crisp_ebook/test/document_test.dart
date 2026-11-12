import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_ebook/crisp_ebook.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

Map<String, Uint8List> fixtureFiles({bool epub2 = false, String? encryption}) {
  final version = epub2 ? '2.0' : '3.0';
  return {
    'mimetype': bytes('application/epub+zip'),
    'META-INF/container.xml': bytes(
      '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="Books/Edition/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
    'Books/Edition/book.opf': bytes('''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" xmlns:vendor="urn:vendor" version="$version" unique-identifier="original-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="original-id">urn:uuid:12345678-1234-5678-1234-567812345678</dc:identifier>
    <dc:title>Original title</dc:title><dc:creator id="author-1">A. Writer</dc:creator><dc:language>en</dc:language>
    <dc:description>A description</dc:description><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
    <meta property="vendor:quality">Keep this extension</meta><meta name="cover" content="cover"/>
  </metadata>
  <manifest>
    <item id="one" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="Text/chapter%20two.xhtml" media-type="application/xhtml+xml"/>
    <item id="style" href="Styles/book.css" media-type="text/css"/>
    <item id="cover" href="Images/cover.png" media-type="image/png" ${epub2 ? '' : 'properties="cover-image"'}/>
    <item id="font" href="Fonts/book.otf" media-type="font/otf"/>
    ${epub2 ? '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' : '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'}
  </manifest><spine ${epub2 ? 'toc="ncx"' : ''}><itemref idref="one"/><itemref idref="two"/></spine>
  <vendor:extra preserve="yes">untouched</vendor:extra>
</package>'''),
    'Books/Edition/Text/one.xhtml': bytes(
      '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter one</title><link rel="stylesheet" href="../Styles/book.css"/></head><body><h1 id="one">Chapter one</h1><p id="plain" class="keep">Plain text</p><p id="complex">Keep <em>italic</em> text</p><img src="../Images/cover.png" alt="Cover"/></body></html>''',
    ),
    'Books/Edition/Text/chapter two.xhtml': bytes(
      '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter two</title></head><body><h1 id="two">Chapter two</h1><p>More content</p></body></html>''',
    ),
    'Books/Edition/Styles/book.css': bytes(
      '@font-face { font-family: Book; src: url("../Fonts/book.otf"); } body { font-family: Book; }',
    ),
    'Books/Edition/Images/cover.png': Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]),
    'Books/Edition/Fonts/book.otf': Uint8List.fromList(
      List.generate(1600, (i) => i % 251),
    ),
    if (!epub2)
      'Books/Edition/nav.xhtml': bytes(
        '''<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><h1>Contents</h1><ol><li><a href="Text/one.xhtml#one">First</a></li><li><a href="Text/chapter%20two.xhtml">Second</a></li></ol></nav><nav epub:type="landmarks"><ol><li><a href="Text/one.xhtml">Start</a></li></ol></nav></body></html>''',
      ),
    if (epub2)
      'Books/Edition/toc.ncx': bytes(
        '''<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>Original title</text></docTitle><navMap><navPoint id="p1" playOrder="1"><navLabel><text>First</text></navLabel><content src="Text/one.xhtml"/></navPoint><navPoint id="p2" playOrder="2"><navLabel><text>Second</text></navLabel><content src="Text/chapter%20two.xhtml"/></navPoint></navMap></ncx>''',
      ),
    'META-INF/vendor.json': bytes('{"unknown":"must survive"}'),
    'strange-extra.bin': Uint8List.fromList([0, 255, 42, 0, 23]),
    if (encryption != null) 'META-INF/encryption.xml': bytes(encryption),
  };
}

// EPUB namespace prefixes are legal even when no default namespace is set.
String prefixedVocabulary(String source, String namespace, String prefix) =>
    source
        .replaceFirst('xmlns="$namespace"', 'xmlns:$prefix="$namespace"')
        .replaceAllMapped(
          RegExp(r'<(/?)([A-Za-z][\w.-]*)(?=[\s/>])'),
          (match) => '<${match[1]}$prefix:${match[2]}',
        );

Uint8List zipFiles(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      entry.key == 'mimetype'
          ? ArchiveFile.noCompress(entry.key, entry.value.length, entry.value)
          : ArchiveFile.bytes(entry.key, entry.value),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

// Mutate on-wire names after ArchiveFile's path normalization, so the fixture
// actually contains the hostile name received from an untrusted source.
Uint8List rewriteName(Uint8List original, String from, String to) {
  final result = Uint8List.fromList(original);
  final before = utf8.encode(from);
  final after = utf8.encode(to);
  expect(before.length, after.length);
  for (var i = 0; i <= result.length - before.length; i++) {
    if (List.generate(
      before.length,
      (j) => result[i + j] == before[j],
    ).every((v) => v)) {
      result.setRange(i, i + after.length, after);
      i += before.length - 1;
    }
  }
  return result;
}

int centralEntry(Uint8List zip, String name) {
  final data = ByteData.sublistView(zip);
  final target = utf8.encode(name);
  for (var i = 0; i + 46 + target.length <= zip.length; i++) {
    if (data.getUint32(i, Endian.little) == 0x02014b50 &&
        data.getUint16(i + 28, Endian.little) == target.length &&
        List.generate(
          target.length,
          (j) => zip[i + 46 + j] == target[j],
        ).every((v) => v))
      return i;
  }
  throw StateError('Missing ZIP member $name');
}

Uint8List compressedPayload(Uint8List zip, String name) {
  final data = ByteData.sublistView(zip);
  final central = centralEntry(zip, name);
  final local = data.getUint32(central + 42, Endian.little);
  final start =
      local +
      30 +
      data.getUint16(local + 26, Endian.little) +
      data.getUint16(local + 28, Endian.little);
  return Uint8List.sublistView(
    zip,
    start,
    start + data.getUint32(central + 20, Endian.little),
  );
}

void main() {
  group('preserving EPUB package', () {
    test('resolves actual OPF, encoded paths, reading order and metadata', () {
      final document = EpubDocument.open(zipFiles(fixtureFiles()));
      expect(document.packagePath, 'Books/Edition/book.opf');
      expect(document.title, 'Original title');
      expect(document.authors, ['A. Writer']);
      expect(document.chapters.map((e) => e.path), [
        'Books/Edition/Text/one.xhtml',
        'Books/Edition/Text/chapter two.xhtml',
      ]);
      expect(document.chapters.map((e) => e.title), ['First', 'Second']);
      expect(document.coverPath, 'Books/Edition/Images/cover.png');
      expect(document.validate().where((e) => e.isError), isEmpty);
    });

    test('no-op save is byte-identical and caller buffers are isolated', () {
      final input = zipFiles(fixtureFiles());
      final original = Uint8List.fromList(input);
      final document = EpubDocument.open(input);
      input.fillRange(0, input.length, 0);
      final saved = document.toBytes();
      expect(saved, original);
      saved[0] = 0;
      expect(document.toBytes(), original);
      expect(document.dirty, isFalse);
    });

    test(
      'metadata edits preserve identifier, unknown XML and all other payloads',
      () {
        final files = fixtureFiles();
        final zipped = zipFiles(files);
        final archiveComment = bytes('Opaque archive comment — preserved');
        ByteData.sublistView(
          zipped,
        ).setUint16(zipped.length - 2, archiveComment.length, Endian.little);
        final originalZip = Uint8List.fromList([...zipped, ...archiveComment]);
        final document = EpubDocument.open(originalZip);
        document.updateMetadata(
          title: 'New title & details',
          authors: ['B. Author', 'C. Author'],
          language: 'de-DE',
        );
        final output = document.toBytes();
        expect(
          output.sublist(output.length - archiveComment.length),
          archiveComment,
        );
        expect(
          compressedPayload(output, 'Books/Edition/Text/one.xhtml'),
          compressedPayload(originalZip, 'Books/Edition/Text/one.xhtml'),
        );
        final reopened = EpubDocument.open(output);
        expect(reopened.title, 'New title & details');
        expect(
          reopened.identifier,
          'urn:uuid:12345678-1234-5678-1234-567812345678',
        );
        expect(reopened.authors, ['B. Author', 'C. Author']);
        expect(
          reopened.readText(reopened.packagePath),
          contains('vendor:extra'),
        );
        expect(
          reopened.readText(reopened.packagePath),
          contains('Keep this extension'),
        );
        for (final entry in files.entries.where(
          (e) => e.key != document.packagePath,
        )) {
          expect(reopened.readBytes(entry.key), entry.value, reason: entry.key);
        }
        final header = ByteData.sublistView(output);
        expect(header.getUint16(8, Endian.little), 0);
        expect(header.getUint16(28, Endian.little), 0);
        expect(utf8.decode(output.sublist(30, 38)), 'mimetype');
        expect(utf8.decode(output.sublist(38, 58)), 'application/epub+zip');
      },
    );

    test(
      'source edits preserve foreign markup and validation catches broken references',
      () {
        final document = EpubDocument.open(zipFiles(fixtureFiles()));
        const chapter = 'Books/Edition/Text/one.xhtml';
        final original = document.readText(chapter);
        document.updateText(
          chapter,
          original.replaceFirst('Plain text', 'Corrected text'),
        );
        expect(
          EpubDocument.open(document.toBytes()).readText(chapter),
          contains('<em>italic</em>'),
        );
        document.updateText(
          chapter,
          original.replaceFirst('../Images/cover.png', '../Images/missing.png'),
        );
        expect(
          document.validate().any((e) => e.code == 'broken_reference'),
          isTrue,
        );
        expect(document.toBytes, throwsA(isA<EpubException>()));
        document.updateText(
          chapter,
          original.replaceFirst('../Images/cover.png', '../Images/%FF.png'),
        );
        expect(
          document.validate().any((e) => e.code == 'invalid_reference'),
          isTrue,
        );
        document.updateText(chapter, '<html>broken');
        expect(document.validate().any((e) => e.code == 'invalid_xml'), isTrue);
      },
    );

    test(
      'snapshots isolate edits and stale save completions cannot clear dirty state',
      () {
        final document = EpubDocument.open(zipFiles(fixtureFiles()));
        document.updateMetadata(title: 'First edit');
        final checkpoint = document.snapshot();
        document.toBytes();
        final saving = document.revision;
        document.updateMetadata(title: 'Newer edit');
        expect(document.markSaved(revision: saving), isFalse);
        expect(document.dirty, isTrue);
        expect(checkpoint.title, 'First edit');
        document.toBytes();
        expect(document.markSaved(revision: document.revision), isTrue);
        expect(document.dirty, isFalse);
        expect(EpubDocument.open(document.toBytes()).title, 'Newer edit');
      },
    );

    test(
      'add, reorder, delete and regenerate navigation preserve landmarks',
      () {
        final document = EpubDocument.open(zipFiles(fixtureFiles()));
        final added = document.addChapter(
          title: 'Third',
          text: 'A new paragraph.',
        );
        expect(document.chapters.length, 3);
        document.moveChapter(added.id, 0);
        expect(document.chapters.first.id, added.id);
        document.updateToc();
        expect(document.toc.first.label, 'Third');
        expect(
          document.readText('Books/Edition/nav.xhtml'),
          contains('landmarks'),
        );
        document.removeChapter('two', deleteResource: true);
        expect(document.chapters.length, 2);
        expect(
          document.resources.any(
            (r) => r.path == 'Books/Edition/Text/chapter two.xhtml',
          ),
          isFalse,
        );
        expect(EpubDocument.open(document.toBytes()).chapters.length, 2);
      },
    );

    test('prefixed OPF and XHTML namespaces survive editing', () {
      final files = fixtureFiles();
      const packagePath = 'Books/Edition/book.opf';
      const chapterPath = 'Books/Edition/Text/one.xhtml';
      const navPath = 'Books/Edition/nav.xhtml';
      const opfNamespace = 'http://www.idpf.org/2007/opf';
      const xhtmlNamespace = 'http://www.w3.org/1999/xhtml';
      files[packagePath] = bytes(prefixedVocabulary(
        utf8.decode(files[packagePath]!).replaceFirst(
          '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>',
          '',
        ),
        opfNamespace,
        'opf',
      ));
      for (final path in [chapterPath, navPath]) {
        files[path] = bytes(prefixedVocabulary(
          utf8.decode(files[path]!),
          xhtmlNamespace,
          'xhtml',
        ));
      }
      final document = EpubDocument.open(zipFiles(files));
      document.updateMetadata(title: 'Prefixed book', authors: ['Writer']);
      document.addResource(
        'Books/Edition/extra.css',
        bytes('p { color: inherit; }'),
        mediaType: 'text/css',
      );
      final added = document.addChapter(title: 'New prefixed chapter');
      document.updateToc([
        EpubTocEntry(label: 'Part', href: '', children: [
          EpubTocEntry(label: 'First', href: chapterPath),
          EpubTocEntry(label: 'Added', href: added.path),
        ]),
      ]);
      final plain = document.readProse(chapterPath).firstWhere(
        (block) => block.id == 'plain',
      );
      document.updateProseBlock(chapterPath, plain.index, 'First line\nSecond line');
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.title, 'Prefixed book');
      expect(reopened.chapters, hasLength(3));
      final package = XmlDocument.parse(reopened.readText(packagePath));
      for (final node in package.descendants.whereType<XmlElement>().where(
        (node) => {'item', 'itemref', 'meta'}.contains(node.name.local),
      )) {
        expect(node.namespaceUri, opfNamespace, reason: node.toXmlString());
      }
      expect(
        package.descendants.whereType<XmlElement>().singleWhere(
          (node) => node.name.local == 'extra',
        ).namespaceUri,
        'urn:vendor',
      );
      for (final path in [chapterPath, navPath]) {
        final xml = XmlDocument.parse(reopened.readText(path));
        for (final node in xml.descendants.whereType<XmlElement>()) {
          expect(node.namespaceUri, xhtmlNamespace, reason: node.toXmlString());
        }
      }
      expect(reopened.toc.single.children, hasLength(2));
      expect(reopened.validate().where((issue) => issue.isError), isEmpty);
    });

    test('prefixed EPUB2 NCX retains its namespace during TOC updates', () {
      final files = fixtureFiles(epub2: true);
      const ncxPath = 'Books/Edition/toc.ncx';
      const ncxNamespace = 'http://www.daisy.org/z3986/2005/ncx/';
      files[ncxPath] = bytes(prefixedVocabulary(
        utf8.decode(files[ncxPath]!),
        ncxNamespace,
        'ncx',
      ));
      final document = EpubDocument.open(zipFiles(files));
      document.addChapter(title: 'New chapter');
      final reopened = EpubDocument.open(document.toBytes());
      final ncx = XmlDocument.parse(reopened.readText(ncxPath));
      for (final node in ncx.descendants.whereType<XmlElement>()) {
        expect(node.namespaceUri, ncxNamespace, reason: node.toXmlString());
      }
      expect(reopened.toc, hasLength(3));
      expect(reopened.version, '2.0');
    });

    test('visual prose refuses line breaks with embedded or foreign content', () {
      final files = fixtureFiles();
      const chapter = 'Books/Edition/Text/one.xhtml';
      files[chapter] = bytes(utf8.decode(files[chapter]!)
          .replaceFirst('<body>', '<body xmlns:vendor="urn:vendor">')
          .replaceFirst(
            'Plain text',
            'Plain<br><span>Do not lose this</span></br> text',
          )
          .replaceFirst(
            'Keep <em>italic</em> text',
            'Keep <vendor:br/> foreign content',
          ));
      final document = EpubDocument.open(zipFiles(files));
      final blocks = document.readProse(chapter);
      for (final id in ['plain', 'complex']) {
        final block = blocks.firstWhere((block) => block.id == id);
        expect(block.editable, isFalse);
        expect(
          () => document.updateProseBlock(chapter, block.index, 'Flattened'),
          throwsA(isA<EpubException>().having(
            (error) => error.code, 'code', 'complex_prose',
          )),
        );
      }
      expect(document.dirty, isFalse);
    });

    test('chapter deletion refuses inbound links', () {
      final files = fixtureFiles();
      files['Books/Edition/Text/one.xhtml'] = bytes(
        utf8
            .decode(files['Books/Edition/Text/one.xhtml']!)
            .replaceFirst(
              '</body>',
              '<a href="chapter%20two.xhtml">Next</a></body>',
            ),
      );
      final document = EpubDocument.open(zipFiles(files));
      expect(
        () => document.removeChapter('two', deleteResource: true),
        throwsA(
          isA<EpubException>().having(
            (e) => e.code,
            'code',
            'referenced_resource',
          ),
        ),
      );
      expect(document.chapters.length, 2);
    });

    test('removing a grouped chapter prunes newly empty contents headings', () {
      final document = EpubDocument.open(zipFiles(fixtureFiles()));
      document.updateToc([
        const EpubTocEntry(
          label: 'Part one', href: 'Books/Edition/Text/one.xhtml',
        ),
        const EpubTocEntry(label: 'Part two', href: '', children: [
          EpubTocEntry(label: 'Second',
              href: 'Books/Edition/Text/chapter%20two.xhtml'),
        ]),
      ]);
      document.removeChapter('two');
      expect(document.chapters, hasLength(1));
      expect(document.toc.single.label, 'Part one');
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.toc, hasLength(1));
      expect(reopened.resources.any(
        (resource) => resource.path == 'Books/Edition/Text/chapter two.xhtml',
      ), isTrue);
    });

    test('chapter deletion protects landmarks and NCX page-list links', () {
      for (final epub2 in [false, true]) {
        final files = fixtureFiles(epub2: epub2);
        final navPath = epub2
            ? 'Books/Edition/toc.ncx'
            : 'Books/Edition/nav.xhtml';
        final original = utf8.decode(files[navPath]!);
        files[navPath] = bytes(epub2
            ? original.replaceFirst('</ncx>',
                '<pageList><pageTarget id="page-1" type="normal" value="1"><navLabel><text>1</text></navLabel><content src="Text/chapter%20two.xhtml"/></pageTarget></pageList></ncx>')
            : original.replaceFirst(
                '<a href="Text/one.xhtml">Start</a>',
                '<a href="Text/chapter%20two.xhtml">Start</a>',
              ));
        final originalBytes = zipFiles(files);
        final document = EpubDocument.open(originalBytes);
        expect(
          () => document.removeChapter('two', deleteResource: true),
          throwsA(isA<EpubException>().having(
            (error) => error.code, 'code', 'referenced_resource',
          )),
          reason: epub2 ? 'NCX page list' : 'EPUB landmarks',
        );
        expect(document.dirty, isFalse);
        expect(document.chapters, hasLength(2));
        expect(document.toBytes(), originalBytes);
      }
    });

    test('EPUB2 NCX remains supported without upgrading book version', () {
      final document = EpubDocument.open(zipFiles(fixtureFiles(epub2: true)));
      expect(document.toc.map((e) => e.label), ['First', 'Second']);
      document.addChapter(title: 'New EPUB2 chapter', text: 'Text');
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.version, '2.0');
      expect(reopened.toc.length, 3);
      expect(
        reopened.resources.any(
          (r) => r.mediaType == 'application/x-dtbncx+xml',
        ),
        isTrue,
      );
    });

    test(
      'bounded visual changes preserve attributes and reject complex inline content',
      () {
        final document = EpubDocument.open(zipFiles(fixtureFiles()));
        const chapter = 'Books/Edition/Text/one.xhtml';
        final blocks = document.readProse(chapter);
        final plain = blocks.firstWhere((b) => b.id == 'plain');
        final complex = blocks.firstWhere((b) => b.id == 'complex');
        expect(plain.editable, isTrue);
        expect(complex.editable, isFalse);
        document.updateProseBlock(
          chapter,
          plain.index,
          'New text\nSecond line',
          expectedText: plain.text,
        );
        expect(document.readText(chapter), contains('class="keep"'));
        expect(document.readText(chapter), contains('<em>italic</em>'));
        expect(
          () => document.updateProseBlock(
            chapter,
            plain.index,
            'Stale',
            expectedText: plain.text,
          ),
          throwsA(
            isA<EpubException>().having((e) => e.code, 'code', 'stale_edit'),
          ),
        );
        expect(
          () => document.updateProseBlock(chapter, complex.index, 'Flattened'),
          throwsA(
            isA<EpubException>().having((e) => e.code, 'code', 'complex_prose'),
          ),
        );
      },
    );

    test('cover and resource replacement roundtrip without losing extras', () {
      final document = EpubDocument.open(zipFiles(fixtureFiles()));
      final cover = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      document.replaceCover(cover, mediaType: 'image/png');
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.coverBytes, cover);
      expect(reopened.readBytes('strange-extra.bin'), [0, 255, 42, 0, 23]);
    });

    test(
      'failed structural edits roll back changes and source-only edits update modification time',
      () {
        final input = zipFiles(fixtureFiles());
        final document = EpubDocument.open(
          input,
          limits: const EpubLimits(maxEntryBytes: 4000),
        );
        expect(
          () => document.updateMetadata(description: 'x' * 5000),
          throwsA(isA<EpubException>()),
        );
        expect(document.description, 'A description');
        expect(document.revision, 0);
        expect(document.dirty, isFalse);
        expect(document.toBytes(), input);
        final packageBefore = document.readText(document.packagePath);
        final chapter = document.chapters.first.path;
        document.updateText(
          chapter,
          document.readText(chapter).replaceFirst('Plain text', 'Revised text'),
        );
        expect(document.readText(document.packagePath), isNot(packageBefore));
        expect(
          document.readText(document.packagePath),
          isNot(contains('2026-01-01T00:00:00Z')),
        );
        expect(
          EpubDocument.open(document.toBytes()).readText(chapter),
          contains('Revised text'),
        );
      },
    );
  });

  group('protection and input boundaries', () {
    test('standard font obfuscation is readable and edit-safe', () {
      const algorithm = 'http://www.idpf.org/2008/embedding';
      final files = fixtureFiles(
        encryption:
            '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="$algorithm"/><CipherData><CipherReference URI="Books/Edition/Fonts/book.otf"/></CipherData></EncryptedData></encryption>',
      );
      final font = Uint8List.fromList(files['Books/Edition/Fonts/book.otf']!);
      final key = sha1
          .convert(utf8.encode('urn:uuid:12345678-1234-5678-1234-567812345678'))
          .bytes;
      for (var i = 0; i < 1040; i++) {
        files['Books/Edition/Fonts/book.otf']![i] ^= key[i % key.length];
      }
      final document = EpubDocument.open(zipFiles(files));
      expect(document.protection, EpubProtection.fontObfuscation);
      expect(document.readDecodedBytes('Books/Edition/Fonts/book.otf'), font);
      document.updateMetadata(title: 'Font stays readable');
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.readDecodedBytes('Books/Edition/Fonts/book.otf'), font);
      expect(
        reopened.readBytes('Books/Edition/Fonts/book.otf'),
        files['Books/Edition/Fonts/book.otf'],
      );
      expect(
        () => reopened.updateText('Books/Edition/Fonts/book.otf', 'bad font'),
        throwsA(
          isA<EpubException>().having(
            (e) => e.code,
            'code',
            'encrypted_resource',
          ),
        ),
      );
      reopened.updateText(
        reopened.packagePath,
        reopened
            .readText(reopened.packagePath)
            .replaceFirst(
              'urn:uuid:12345678-1234-5678-1234-567812345678',
              'urn:uuid:99999999-1234-5678-1234-567812345678',
            ),
      );
      expect(
        reopened.validate().any(
          (issue) => issue.code == 'font_identifier_changed',
        ),
        isTrue,
      );
      expect(reopened.toBytes, throwsA(isA<EpubException>()));
      expect(
        () => reopened.readDecodedBytes('Books/Edition/Fonts/book.otf'),
        throwsA(isA<EpubException>()),
      );
    });

    test('mixed or conflicting encryption entries remain read-only', () {
      const fontPath = 'Books/Edition/Fonts/book.otf';
      const fontAlgorithm = 'http://www.idpf.org/2008/embedding';
      String entry(String href, String algorithm) =>
          '<EncryptedData><EncryptionMethod Algorithm="$algorithm"/><CipherData><CipherReference URI="$href"/></CipherData></EncryptedData>';
      for (final unsupported in [
        entry('https://example.invalid/cipher', 'urn:unsupported'),
        entry(fontPath, 'urn:unsupported'),
      ]) {
        // An allowed font entry comes last to catch accidental last-write wins.
        final files = fixtureFiles(encryption:
            '<encryption>$unsupported${entry(fontPath, fontAlgorithm)}</encryption>');
        final original = zipFiles(files);
        final document = EpubDocument.open(original);
        expect(document.protection, EpubProtection.drm);
        expect(document.canEdit, isFalse);
        expect(document.toBytes(), original);
        expect(
          () => document.updateMetadata(title: 'Do not invalidate encryption'),
          throwsA(isA<EpubException>().having(
            (error) => error.code, 'code', 'drm',
          )),
        );
      }
    });

    test('DRM and signatures allow exact no-op but block modification', () {
      for (final control in ['drm', 'signature']) {
        final files = fixtureFiles(
          encryption: control == 'drm'
              ? '<encryption><EncryptedData><EncryptionMethod Algorithm="urn:drm"/><CipherData><CipherReference URI="Books/Edition/Text/one.xhtml"/></CipherData></EncryptedData></encryption>'
              : null,
        );
        if (control == 'signature')
          files['META-INF/signatures.xml'] = bytes('<signatures/>');
        final input = zipFiles(files);
        final document = EpubDocument.open(input);
        expect(document.canEdit, isFalse);
        expect(document.toBytes(), input);
        expect(
          () => document.updateMetadata(title: 'No'),
          throwsA(isA<EpubException>()),
        );
      }
    });

    test('rejects traversal, duplicate and symbolic archive entries', () {
      for (final filename in [
        '../outside.xhtml',
        '/absolute.xhtml',
        'C:/drive.xhtml',
        'a/../evil.xhtml',
      ]) {
        final files = fixtureFiles()..[filename] = bytes('bad');
        expect(
          () => EpubDocument.open(zipFiles(files)),
          throwsA(
            isA<EpubException>().having((e) => e.code, 'code', 'unsafe_path'),
          ),
          reason: filename,
        );
      }
      final hostileNames = zipFiles(
        fixtureFiles()..['Books/evil.xhtml'] = bytes('bad'),
      );
      expect(
        () => EpubDocument.open(
          rewriteName(hostileNames, 'Books/evil.xhtml', r'Books\evil.xhtml'),
        ),
        throwsA(
          isA<EpubException>().having((e) => e.code, 'code', 'unsafe_path'),
        ),
      );
      final duplicate = zipFiles(
        fixtureFiles()
          ..['extra-a.bin'] = bytes('a')
          ..['extra-b.bin'] = bytes('b'),
      );
      expect(
        () => EpubDocument.open(
          rewriteName(duplicate, 'extra-b.bin', 'extra-a.bin'),
        ),
        throwsA(
          isA<EpubException>().having((e) => e.code, 'code', 'duplicate_path'),
        ),
      );
      final archive = Archive();
      for (final e in fixtureFiles().entries) {
        archive.addFile(ArchiveFile.bytes(e.key, e.value));
      }
      archive.addFile(ArchiveFile.symlink('link', '../outside'));
      expect(
        () => EpubDocument.open(ZipEncoder().encodeBytes(archive)),
        throwsA(isA<EpubException>()),
      );
    });

    test(
      'inflation is bounded by declared size and corrupt payloads are rejected',
      () {
        final input = zipFiles(fixtureFiles()..['bomb.bin'] = Uint8List(65536));
        final data = ByteData.sublistView(input);
        final central = centralEntry(input, 'bomb.bin');
        final local = data.getUint32(central + 42, Endian.little);
        data.setUint32(central + 24, 1, Endian.little);
        data.setUint32(local + 22, 1, Endian.little);
        final document = EpubDocument.open(input);
        expect(
          () => document.readBytes('bomb.bin'),
          throwsA(isA<EpubException>()),
        );
        document.updateMetadata(title: 'Do not preserve a corrupt payload');
        expect(document.toBytes, throwsA(isA<EpubException>()));
      },
    );

    test('enforces archive, expanded, entry, XML-depth and entity limits', () {
      final input = zipFiles(fixtureFiles());
      expect(
        () => EpubDocument.open(
          input,
          limits: const EpubLimits(maxArchiveBytes: 100),
        ),
        throwsA(isA<EpubException>()),
      );
      expect(
        () => EpubDocument.open(
          input,
          limits: const EpubLimits(maxExpandedBytes: 100),
        ),
        throwsA(isA<EpubException>()),
      );
      expect(
        () => EpubDocument.open(
          input,
          limits: const EpubLimits(maxEntryBytes: 10),
        ),
        throwsA(isA<EpubException>()),
      );
      final document = EpubDocument.open(
        input,
        limits: const EpubLimits(maxXmlDepth: 10),
      );
      document.updateText(
        'Books/Edition/Text/one.xhtml',
        '<html>${List.filled(20, '<div>').join()}${List.filled(20, '</div>').join()}</html>',
      );
      expect(document.validate().any((e) => e.code == 'xml_limit'), isTrue);
      document.updateText(
        'Books/Edition/Text/one.xhtml',
        '<!DOCTYPE html [<!ENTITY x "payload">]><html>&x;</html>',
      );
      expect(document.validate().any((e) => e.code == 'xml_entities'), isTrue);
    });

    test('does not silently save an invalid source package', () {
      final document = EpubDocument.open(zipFiles(fixtureFiles()));
      document.updateText(document.packagePath, '<package>');
      expect(document.validate().first.isError, isTrue);
      expect(document.toBytes, throwsA(isA<EpubException>()));
      expect(
        () => document.updateMetadata(title: 'No'),
        throwsA(isA<EpubException>()),
      );
    });
  });

  group('new and normalized publications', () {
    test('creates a valid EPUB and exports display resources', () {
      final document = EpubDocument.create(
        title: 'A new book',
        authors: ['Writer'],
      );
      expect(document.dirty, isTrue);
      expect(document.validate().where((i) => i.isError), isEmpty);
      final reopened = EpubDocument.open(document.toBytes());
      expect(reopened.title, 'A new book');
      final publication = reopened.toPublication();
      expect(publication['readingOrder'], hasLength(1));
      expect(publication['resources'], isNotEmpty);
    });

    test(
      'normalized MOBI imports become new EPUB without source overwrite semantics',
      () {
        final document = EpubDocument.fromPublication({
          'sourceFormat': 'mobi',
          'metadata': {
            'title': 'Imported novel',
            'authors': ['Author'],
            'language': 'en',
          },
          'readingOrder': [
            {'href': 'sections/ch1.html', 'title': 'Opening'},
          ],
          'toc': [
            {'label': 'Opening', 'href': 'sections/ch1.html'},
          ],
          'resources': [
            {
              'href': 'sections/ch1.html',
              'mediaType': 'text/html',
              'encoding': 'base64',
              'data': base64Encode(
                utf8.encode(
                  '<html><head><title>Opening</title></head><body><h1>Opening</h1><p>Hello<br>world<img src="../images/a.png"></p></body></html>',
                ),
              ),
            },
            {
              'href': 'images/a.png',
              'mediaType': 'image/png',
              'encoding': 'base64',
              'data': base64Encode([1, 2, 3]),
            },
          ],
        });
        expect(document.sourceFormat, 'mobi');
        expect(document.title, 'Imported novel');
        expect(document.importWarnings, isNotEmpty);
        final reopened = EpubDocument.open(document.toBytes());
        expect(reopened.chapters.single.title, 'Opening');
        expect(
          () => XmlDocument.parse(reopened.readText('sections/ch1.html')),
          returnsNormally,
        );
      },
    );

    test('rejects remote and traversing normalized resources', () {
      for (final href in [
        'https://evil.example/file.html',
        '../file.html',
        'file:///etc/passwd',
      ]) {
        expect(
          () => EpubDocument.fromPublication({
            'readingOrder': [
              {'href': href},
            ],
            'resources': [
              {
                'href': href,
                'mediaType': 'text/html',
                'data': base64Encode(utf8.encode('<p>bad</p>')),
              },
            ],
          }),
          throwsA(isA<EpubException>()),
        );
      }
    });
  });
}
