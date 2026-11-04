import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/pdf_file_store.dart';
import 'package:crisp_cloud/services/pdf_operations_host.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfTextExtractor;
import 'package:pdf_operations/pdf_operations.dart';

import 'support/pdf_editor_fixture.dart';
import 'support/pdf_operations_fixture.dart';

class _Store implements PdfFileStore {
  _Store(this.displayName, {Uint8List? input})
    : input = input ?? buildPdfEditorFixture();

  final Uint8List input;
  int reads = 0;
  int overwrites = 0;
  final copies = <(String, Uint8List)>[];
  Future<Uint8List> Function()? reader;
  Future<PdfSaveOutcome> Function(Uint8List, String)? writer;

  @override
  final String displayName;
  @override
  String get documentId => 'test:$displayName';
  @override
  String get path => '/folder/$displayName';
  @override
  bool get isRemote => true;
  @override
  Future<Uint8List> load() async {
    reads++;
    return reader == null ? input : await reader!();
  }

  @override
  Future<PdfSaveOutcome> save(Uint8List bytes) async {
    overwrites++;
    return PdfSaveOutcome.savedOriginal;
  }

  @override
  Future<PdfSaveOutcome> saveCopy(Uint8List bytes, String name) async {
    copies.add((name, Uint8List.fromList(bytes)));
    return writer == null
        ? PdfSaveOutcome.savedCopy
        : await writer!(bytes, name);
  }
}

class _PasswordOperations extends PdfOperationsService {
  @override
  PdfInspection inspect(PdfInput input) {
    if (input.password != 'correct') {
      throw PdfOperationException(
        input.password.isEmpty ? 'passwordRequired' : 'invalidPassword',
        'A password is needed.',
      );
    }
    return super.inspect(input);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh source reads are owned snapshots; mutations save only a new sibling',
    () async {
      final first = _Store('one.pdf');
      final second = _Store('two.pdf');
      final host = PdfOperationsHost(stores: [first, second], useWorker: false);
      addTearDown(host.dispose);
      final progress = <int>[];
      final sources = await host.load(
        requestPassword: (_, _) async => fail('Unexpected password prompt'),
        onProgress: (count, total) {
          expect(total, 2);
          progress.add(count);
        },
      );
      expect(first.reads, 1);
      expect(second.reads, 1);
      expect(progress, [1, 2]);
      final expected = Uint8List.fromList(sources.first.input.bytes);
      first.input[0] = 0;
      expect(sources.first.input.bytes, orderedEquals(expected));
      expect(() => sources.first.input.bytes[0] = 0, throwsUnsupportedError);

      final result = await host.perform(
        PdfOperationRequest(
          action: PdfOperationAction.merge,
          sources: [
            PdfMergeInput(sources[1].input, pages: '2'),
            PdfMergeInput(sources[0].input),
          ],
        ),
      );
      expect(result.pageCount, 3);
      await host.saveSibling(result.bytes, 'combined.pdf');
      expect(first.copies.single.$1, 'combined.pdf');
      expect(PdfDocument.open(first.copies.single.$2).pageCount, 3);
      expect(second.copies, isEmpty);
      expect(first.overwrites + second.overwrites, 0);
      expect(host.destinationPath, '/folder/one.pdf');
    },
  );

  test('per-file password retries report incorrect input and retain no password in metadata', () async {
    final host = PdfOperationsHost(
      stores: [_Store('locked.pdf')],
      operations: _PasswordOperations(),
      useWorker: false,
    );
    addTearDown(host.dispose);
    final prompts = <(String, bool)>[];
    final sources = await host.load(
      requestPassword: (name, incorrect) async {
        prompts.add((name, incorrect));
        return prompts.length == 1 ? 'wrong' : 'correct';
      },
    );
    expect(prompts, [('locked.pdf', false), ('locked.pdf', true)]);
    expect(
      sources.single.inspection.toJson().toString(),
      isNot(contains('correct')),
    );
  });

  test('cancelled password prompt does not continue to other sources or enable saving', () async {
    final first = _Store('locked.pdf');
    final second = _Store('later.pdf');
    final host = PdfOperationsHost(
      stores: [first, second],
      operations: _PasswordOperations(),
    );
    addTearDown(host.dispose);
    await expectLater(
      host.load(requestPassword: (_, _) async => null),
      throwsA(isA<PdfOperationCancelled>()),
    );
    expect(second.reads, 0);
    await expectLater(
      host.saveSibling(first.input, 'copy.pdf'),
      throwsStateError,
    );
    expect(first.copies, isEmpty);
  });

  test(
    'disposing during a read discards completion and prevents writes',
    () async {
      final pending = Completer<Uint8List>();
      final store = _Store('slow.pdf')..reader = () => pending.future;
      final host = PdfOperationsHost(stores: [store]);
      final load = host.load(requestPassword: (_, _) async => null);
      final assertion = expectLater(
        load,
        throwsA(isA<PdfOperationCancelled>()),
      );
      host.dispose();
      pending.complete(store.input);
      await assertion;
      await expectLater(
        host.saveSibling(store.input, 'copy.pdf'),
        throwsA(isA<PdfOperationCancelled>()),
      );
      expect(store.copies, isEmpty);
    },
  );

  test(
    'failed sibling write leaves independent device export available',
    () async {
      final store = _Store('remote.pdf')
        ..writer = (_, _) async => throw const PdfAccountChangedException();
      final exports = <Uint8List>[];
      final host = PdfOperationsHost(
        stores: [store],
        useWorker: false,
        deviceExporter: (bytes, name) async {
          expect(name, 'recovered.pdf');
          exports.add(bytes);
          return PdfSaveOutcome.savedCopy;
        },
      );
      addTearDown(host.dispose);
      final source = (await host.load(requestPassword: (_, _) async => null))
          .single;
      final result = await host.perform(
        PdfOperationRequest(
          action: PdfOperationAction.rotate,
          sources: [PdfMergeInput(source.input)],
          pages: '2',
          degrees: 90,
        ),
      );
      await expectLater(
        host.saveSibling(result.bytes, 'rotated.pdf'),
        throwsA(isA<PdfAccountChangedException>()),
      );
      expect(
        await host.export(result.bytes, 'recovered'),
        PdfSaveOutcome.savedCopy,
      );
      expect(exports.single, orderedEquals(result.bytes));
      expect(store.overwrites, 0);
    },
  );

  test(
    'one write is allowed at a time; cancelled device chooser is not success',
    () async {
      final pending = Completer<PdfSaveOutcome>();
      final store = _Store('sample.pdf')..writer = (_, _) => pending.future;
      final host = PdfOperationsHost(
        stores: [store],
        deviceExporter: (_, _) async => null,
      );
      addTearDown(host.dispose);
      await host.load(requestPassword: (_, _) async => null);
      final write = host.saveSibling(store.input, 'copy.pdf');
      await expectLater(
        host.saveSibling(store.input, 'other.pdf'),
        throwsStateError,
      );
      await expectLater(
        host.export(store.input, 'other.pdf'),
        throwsStateError,
      );
      pending.complete(PdfSaveOutcome.savedCopy);
      expect(await write, PdfSaveOutcome.savedCopy);
      expect(await host.export(store.input, 'cancelled.pdf'), isNull);
      expect(store.copies, hasLength(1));
    },
  );

  test('worker inspection and mutation return usable PDF snapshots', () async {
    final host = PdfOperationsHost(stores: [_Store('worker.pdf')]);
    addTearDown(host.dispose);
    final input = (await host.load(requestPassword: (_, _) async => null))
        .single
        .input;
    final result = await host.perform(
      PdfOperationRequest(
        action: PdfOperationAction.rotate,
        sources: [PdfMergeInput(input)],
        pages: '1',
        degrees: 180,
      ),
    );
    final document = PdfDocument.open(result.bytes);
    expect(document.pages[0].rotation, 180);
    expect(document.pages[1].rotation, 0);
  });

  test(
    'worker receives an embedded font and returns a usable Unicode form appearance',
    () async {
      final host = PdfOperationsHost(
        stores: [_Store('form.pdf', input: buildPdfOperationsFixture())],
      );
      addTearDown(host.dispose);
      final data = await rootBundle.load(
        'packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf',
      );
      final font = PdfEmbeddedFont.parse(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final input = (await host.load(requestPassword: (_, _) async => null))
          .single
          .input;
      final result = await host.perform(
        PdfOperationRequest(
          action: PdfOperationAction.fillForm,
          sources: [PdfMergeInput(input)],
          fields: const {'customer.name': 'Жук'},
          appearanceFont: font,
        ),
      );
      final document = PdfDocument.open(result.bytes);
      expect(PdfAcroForm.of(document)!.fieldNamed('customer.name')!.value, 'Жук');
      final flattened = PdfEditor(document)..flattenForm();
      expect(
        PdfTextExtractor.extract(PdfDocument.open(flattened.save()), 0).text,
        contains('Жук'),
      );
    },
  );

  test('ambiguous duplicate sources and empty selections are rejected', () {
    final store = _Store('sample.pdf');
    expect(() => PdfOperationsHost(stores: []), throwsArgumentError);
    expect(
      () => PdfOperationsHost(stores: [store, store]),
      throwsArgumentError,
    );
  });
}
