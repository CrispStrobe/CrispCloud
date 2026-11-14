import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/services/office_device_export.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

import '../support/office_test_harness.dart';

xml.XmlDocument _part(Uint8List bytes, String name) {
  final part = ZipDecoder().decodeBytes(bytes).findFile(name)!;
  return xml.XmlDocument.parse(utf8.decode(part.content));
}

String _text(Uint8List bytes) => _part(bytes, 'word/document.xml').descendants
    .whereType<xml.XmlElement>()
    .where((element) => element.name.local == 't')
    .map((element) => element.innerText)
    .join();

bool _setting(Uint8List bytes, String name) {
  const ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final part = ZipDecoder().decodeBytes(bytes).findFile('word/settings.xml');
  if (part == null) return false;
  final settings = xml.XmlDocument.parse(utf8.decode(part.content));
  final elements = settings.findAllElements(name, namespace: ns);
  if (elements.isEmpty) return false;
  expect(elements, hasLength(1));
  final protection = name == 'documentProtection';
  final value = elements.single.getAttribute(
    protection ? 'enforcement' : 'val',
    namespace: ns,
  );
  return value == null
      ? !protection
      : const {'1', 'true', 'on'}.contains(value);
}

void _evidence(String name, Uint8List bytes, {String extension = 'docx'}) {
  File('build/fidelity-host/$name.$extension')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('system Back prompts once and Cancel retains unsaved edits', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      final word = host.controller as WordEditorController;
      word.insertText('Retain this edit ');
      await tester.pump();
      await host.back();
      expect(find.text('Unsaved changes'), findsOneWidget);
      host.ribbon.onClose();
      host.ribbon.onClose();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await _choose(tester, 'Cancel');
      expect(find.byType(OfficeEditorDialog), findsOneWidget);
      expect(word.isDirty, isTrue);
      expect(
        word.document.paragraphs.first.text,
        contains('Retain this edit '),
      );
      expect(host.cloud.writes, isEmpty);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('system Back discards only after explicit confirmation', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      final original = Uint8List.fromList(host.savedBytes);
      (host.controller as WordEditorController).insertText('Discarded edit ');
      await tester.pump();
      await host.back();
      await _choose(tester, 'Discard');
      expect(find.byType(OfficeEditorDialog), findsNothing);
      expect(host.savedBytes, orderedEquals(original));
      expect(host.cloud.writes, isEmpty);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('system Back closes a clean document without a prompt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      await host.back();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(OfficeEditorDialog), findsNothing);
      expect(host.cloud.writes, isEmpty);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('system Back Save writes the captured original before closing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      (host.controller as WordEditorController).insertText('Saved by Back ');
      await tester.pump();
      await host.back();
      await _choose(tester, 'Save');
      await officePumpUntil(
        tester,
        () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
      );
      expect(host.cloud.writes, ['/report.docx']);
      expect(_text(host.savedBytes), contains('Saved by Back '));
      _evidence('back-save', host.savedBytes);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back and Close cannot discard an in-flight save', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      final word = host.controller as WordEditorController;
      word.insertText('Uploaded edit ');
      host.cloud.pauseNextUpload();
      host.ribbon.onSave();
      await officePumpUntil(tester, () => host.cloud.pendingBytes != null);
      word.insertText('Newer edit ');
      await host.back();
      host.ribbon.onClose();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(OfficeEditorDialog), findsOneWidget);
      host.cloud.releaseUpload();
      await officePumpUntil(tester, () => !host.ribbon.saving);
      expect(word.isDirty, isTrue);
      expect(_text(host.savedBytes), isNot(contains('Newer edit ')));
      expect(word.document.paragraphs.first.text, contains('Newer edit '));
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back Save keeps later edits open until their own save', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      final word = host.controller as WordEditorController;
      word.insertText('First revision ');
      host.cloud.pauseNextUpload();
      await host.back();
      await _choose(tester, 'Save');
      await officePumpUntil(tester, () => host.cloud.pendingBytes != null);
      word.insertText('Later revision ');
      host.cloud.releaseUpload();
      await officePumpUntil(tester, () => !host.ribbon.saving);
      expect(word.isDirty, isTrue);
      expect(find.byType(OfficeEditorDialog), findsOneWidget);
      await host.back();
      await _choose(tester, 'Save');
      await officePumpUntil(
        tester,
        () => find.byType(OfficeEditorDialog).evaluate().isEmpty,
      );
      expect(_text(host.savedBytes), contains('Later revision '));
      expect(host.cloud.writes, ['/report.docx', '/report.docx']);
      _evidence('back-save-later-revision', host.savedBytes);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected original can export edited copy without cleaning', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Uint8List? copied;
      final host = await OfficeTestHarness.open(
        tester,
        copyExporter: (bytes, name, title) async {
          copied = bytes;
          expect(name, 'report.docx');
          expect(title, 'Save a copy');
          return OfficeCopyOutcome.savedCopy;
        },
      );
      final original = Uint8List.fromList(host.savedBytes);
      final word = host.controller as WordEditorController;
      word.insertText('Recover after disconnect ');
      host.cloud.current = false;
      await host.save();
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(host.cloud.uploadAttempts, 0);
      await host.copy();
      expect(_text(copied!), contains('Recover after disconnect '));
      expect(() => copied![0] = 0, throwsUnsupportedError);
      expect(word.isDirty, isTrue);
      expect(host.ribbon.dirty, isTrue);
      expect(host.savedBytes, orderedEquals(original));
      expect(host.cloud.writes, isEmpty);
      expect(find.byType(OfficeEditorDialog), findsOneWidget);
      _evidence('recovery-disconnected-copy', copied!);
      await host.back();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await _choose(tester, 'Cancel');
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  for (final failure in ['cancel', 'error']) {
    testWidgets('copy $failure retains edits and permits a successful retry', (
      tester,
    ) async {
      await tester.runAsync(() async {
        var calls = 0;
        Uint8List? copied;
        final host = await OfficeTestHarness.open(
          tester,
          copyExporter: (bytes, name, title) async {
            calls++;
            if (calls == 1) {
              if (failure == 'error') throw StateError('Destination full');
              return null;
            }
            copied = bytes;
            return OfficeCopyOutcome.downloadedCopy;
          },
        );
        final original = Uint8List.fromList(host.savedBytes);
        final word = host.controller as WordEditorController;
        word.insertText('Retry copy edit ');
        await host.copy();
        expect(calls, 1);
        expect(word.isDirty, isTrue);
        expect(
          find.text('Copy saved. The original is unchanged.'),
          findsNothing,
        );
        expect(host.savedBytes, orderedEquals(original));
        await host.copy();
        expect(calls, 2);
        expect(_text(copied!), contains('Retry copy edit '));
        expect(word.isDirty, isTrue);
        expect(host.cloud.writes, isEmpty);
        _evidence('recovery-$failure-retry', copied!);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'copy picker owns one revision while newer edits remain unsaved',
    (tester) async {
      await tester.runAsync(() async {
        final picker = Completer<OfficeCopyOutcome?>();
        Uint8List? copied;
        var copies = 0;
        final host = await OfficeTestHarness.open(
          tester,
          copyExporter: (bytes, name, title) {
            copies++;
            copied = bytes;
            return picker.future;
          },
        );
        final word = host.controller as WordEditorController;
        word.insertText('Copied revision ');
        host.ribbon.onSaveCopy!();
        await officePumpUntil(tester, () => copied != null);
        word.insertText('Later edit ');
        host.ribbon.onSave();
        host.ribbon.onSaveCopy!();
        await host.back();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(OfficeEditorDialog), findsOneWidget);
        expect(copies, 1);
        expect(host.cloud.uploadAttempts, 0);
        picker.complete(OfficeCopyOutcome.savedCopy);
        await officePumpUntil(tester, () => !host.ribbon.saving);
        expect(_text(copied!), contains('Copied revision '));
        expect(_text(copied!), isNot(contains('Later edit ')));
        expect(word.isDirty, isTrue);
        await host.save();
        expect(word.isDirty, isFalse);
        expect(_text(host.savedBytes), contains('Later edit '));
        _evidence('recovery-picker-copy', copied!);
        _evidence('recovery-picker-later-save', host.savedBytes);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copying an unchanged document leaves it clean', (tester) async {
    await tester.runAsync(() async {
      var copies = 0;
      final host = await OfficeTestHarness.open(
        tester,
        copyExporter: (bytes, name, title) async {
          copies++;
          expect(_text(bytes), isNotEmpty);
          return OfficeCopyOutcome.savedCopy;
        },
      );
      final original = Uint8List.fromList(host.savedBytes);
      await host.copy();
      expect(copies, 1);
      expect(host.controller.isDirty, isFalse);
      expect(host.savedBytes, orderedEquals(original));
      expect(host.cloud.writes, isEmpty);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  for (final sheet in [true, false]) {
    final extension = sheet ? 'xlsx' : 'pptx';
    final kind = sheet ? 'cell' : 'slide';
    testWidgets('recovery copy commits pending $kind text after disconnect', (
      tester,
    ) async {
      await tester.runAsync(() async {
        Uint8List? copied;
        final host = await OfficeTestHarness.open(
          tester,
          name: 'recovery.$extension',
          fixture: 'native.$extension',
          copyExporter: (bytes, name, title) async {
            copied = bytes;
            expect(name, 'recovery.$extension');
            return OfficeCopyOutcome.savedCopy;
          },
        );
        final original = Uint8List.fromList(host.savedBytes);
        const expected = 'Recovered pending text';
        final controller = host.controller;
        if (controller is SheetEditorController) {
          controller.selection.selectCell(const SmlCellRef(0, 0));
          controller.beginCellEdit(initial: expected);
          expect(controller.cellEditor.editing, isTrue);
        } else if (controller is SlideEditorController) {
          controller.selectShape(
            controller.slide.shapes.singleWhere((shape) => shape.id == 2),
          );
          controller.beginTextEdit(initial: expected);
          expect(controller.textEditor.editing, isTrue);
        }
        expect(controller.isDirty, isTrue);
        host.cloud.current = false;
        await host.copy();
        expect(copied, isNotNull);
        if (sheet) {
          const ns =
              'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
          final cell = _part(copied!, 'xl/worksheets/sheet1.xml')
              .findAllElements('c', namespace: ns)
              .singleWhere((node) => node.getAttribute('r') == 'A1');
          final String value;
          if (cell.getAttribute('t') == 's') {
            final index = int.parse(
              cell.getElement('v', namespace: ns)!.innerText,
            );
            value = _part(copied!, 'xl/sharedStrings.xml')
                .findAllElements('si', namespace: ns)
                .elementAt(index)
                .findAllElements('t', namespace: ns)
                .map((node) => node.innerText)
                .join();
          } else {
            value = cell
                .findAllElements('t', namespace: ns)
                .map((node) => node.innerText)
                .join();
          }
          expect(value, expected);
        } else {
          const pns =
              'http://schemas.openxmlformats.org/presentationml/2006/main';
          const ans = 'http://schemas.openxmlformats.org/drawingml/2006/main';
          final shape = _part(copied!, 'ppt/slides/slide1.xml')
              .findAllElements('sp', namespace: pns)
              .singleWhere(
                (shape) =>
                    shape
                        .getElement('nvSpPr', namespace: pns)!
                        .getElement('cNvPr', namespace: pns)!
                        .getAttribute('id') ==
                    '2',
              );
          expect(
            shape
                .findAllElements('t', namespace: ans)
                .map((node) => node.innerText)
                .join(),
            expected,
          );
        }
        expect(controller.isDirty, isTrue);
        expect(host.savedBytes, orderedEquals(original));
        expect(host.cloud.writes, isEmpty);
        _evidence('recovery-pending-$kind', copied!, extension: extension);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'refused input exports its captured original without reserializing',
    (tester) async {
      await tester.runAsync(() async {
        final supplied = Uint8List.fromList(
          utf8.encode('not an Office package'),
        );
        final original = Uint8List.fromList(supplied);
        Uint8List? exported;
        final host = await OfficeTestHarness.open(
          tester,
          bytesOverride: supplied,
          expectEditor: false,
          copyExporter: (bytes, name, title) async {
            exported = bytes;
            expect(title, 'Export original');
            return OfficeCopyOutcome.savedCopy;
          },
        );
        supplied.fillRange(0, supplied.length, 0);
        await tester.tap(find.text('Export original'));
        await officePumpUntil(tester, () => exported != null);
        expect(exported, orderedEquals(original));
        expect(() => exported![0] = 0, throwsUnsupportedError);
        expect(host.cloud.writes, isEmpty);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final extension in ['xlsx', 'pptx']) {
    testWidgets(
      'signed-marker $extension refusal retains an exact original copy',
      (tester) async {
        await tester.runAsync(() async {
          final archive = ZipDecoder().decodeBytes(
            File(
              'packages/quds_office_engine/test/fixtures/fidelity/native.$extension',
            ).readAsBytesSync(),
          );
          // A synthetic OPC signature marker exercises safe admission. It is
          // deliberately not evidence of cryptographic signature verification.
          archive.add(ArchiveFile('_xmlsignatures/origin.sigs', 1, [0]));
          final supplied = Uint8List.fromList(ZipEncoder().encode(archive));
          final original = Uint8List.fromList(supplied);
          Uint8List? exported;
          final host = await OfficeTestHarness.open(
            tester,
            name: 'signed.$extension',
            bytesOverride: supplied,
            expectEditor: false,
            copyExporter: (bytes, name, title) async {
              exported = bytes;
              expect(name, 'signed.$extension');
              expect(title, 'Export original');
              return OfficeCopyOutcome.savedCopy;
            },
          );
          expect(
            find.textContaining(
              RegExp('signed|signature', caseSensitive: false),
            ),
            findsOneWidget,
          );
          expect(find.byType(QudsSheetEditor), findsNothing);
          expect(find.byType(QudsSlideEditor), findsNothing);
          supplied.fillRange(0, supplied.length, 0);
          await tester.tap(find.text('Export original'));
          await officePumpUntil(tester, () => exported != null);
          expect(exported, orderedEquals(original));
          expect(host.cloud.uploadAttempts, 0);
          expect(host.cloud.writes, isEmpty);
          await host.dispose();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('copy completion after host disposal has no late UI callbacks', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final picker = Completer<OfficeCopyOutcome?>();
      var copying = false;
      final host = await OfficeTestHarness.open(
        tester,
        copyExporter: (bytes, name, title) {
          copying = true;
          return picker.future;
        },
      );
      (host.controller as WordEditorController).insertText('Retained export ');
      host.ribbon.onSaveCopy!();
      await officePumpUntil(tester, () => copying);
      await host.dispose();
      picker.complete(OfficeCopyOutcome.savedCopy);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
      expect(host.cloud.writes, isEmpty);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('protection changed during upload remains dirty until saved', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final host = await OfficeTestHarness.open(tester);
      final word = host.controller as WordEditorController;
      word.insertText('Saved content ');
      host.cloud.pauseNextUpload();
      host.ribbon.onSave();
      await officePumpUntil(tester, () => host.cloud.pendingBytes != null);
      word.setRestrictEditing(true);
      await tester.pump();
      host.cloud.releaseUpload();
      await officePumpUntil(tester, () => !host.ribbon.saving);
      expect(word.isDirty, isTrue);
      expect(_setting(host.savedBytes, 'documentProtection'), isFalse);
      _evidence('protection-before-late-change', host.savedBytes);
      await host.save();
      expect(word.isDirty, isFalse);
      expect(_setting(host.savedBytes, 'documentProtection'), isTrue);
      _evidence('protection-after-late-change', host.savedBytes);
      word.undo();
      await tester.pump();
      expect(word.document.restrictEditing, isFalse);
      expect(word.isDirty, isTrue);
      await host.save();
      expect(_setting(host.savedBytes, 'documentProtection'), isFalse);
      _evidence('protection-undo-save', host.savedBytes);
      await host.dispose();
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Track Changes follows save, undo and redo in actual host bytes',
    (tester) async {
      await tester.runAsync(() async {
        final host = await OfficeTestHarness.open(tester);
        final word = host.controller as WordEditorController;
        word.setTrackRevisions(true);
        await host.save();
        expect(_setting(host.savedBytes, 'trackRevisions'), isTrue);
        _evidence('tracking-enabled-save', host.savedBytes);
        word.undo();
        await host.save();
        expect(_setting(host.savedBytes, 'trackRevisions'), isFalse);
        _evidence('tracking-undo-save', host.savedBytes);
        word.redo();
        await host.save();
        expect(_setting(host.savedBytes, 'trackRevisions'), isTrue);
        _evidence('tracking-redo-save', host.savedBytes);
        await host.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
