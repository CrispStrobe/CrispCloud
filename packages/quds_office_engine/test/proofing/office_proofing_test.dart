import 'dart:async';

import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest request(String text, {int startOffset = 0}) =>
    OfficeProofingRequest(
      documentId: 'doc',
      blockId: 'body:1',
      revision: 7,
      text: text,
      startOffset: startOffset,
    );

class FakeProvider extends OfficeProofingProvider {
  FakeProvider(this.run, {this.supported = true, this.name = 'test'});
  final Future<OfficeProofingResult> Function(OfficeProofingRequest) run;
  final bool supported;
  final String name;
  bool disposed = false;
  @override
  String get id => name;
  @override
  bool supportsLanguage(String language) => supported;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) =>
      run(request);
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

OfficeProofingResult clean(OfficeProofingRequest r) => OfficeProofingResult(
  request: r,
  providerId: 'test',
  status: OfficeProofingStatus.success,
);

void main() {
  test('validated provider results can be shared with the report', () async {
    final input = request('Feler, Huas', startOffset: 20);
    final result = OfficeProofingResult(
      request: input,
      providerId: 'test',
      status: OfficeProofingStatus.success,
      findings: [
        for (final (start, end) in [(0, 5), (7, 11)])
          OfficeProofingFinding.forRequest(
            input,
            providerId: 'test',
            start: start,
            end: end,
            ruleId: 'spelling',
            message: 'Spelling',
            category: OfficeProofingCategory.spelling,
          ),
      ],
    );
    final service = OfficeProofingService(
      providers: [FakeProvider((_) async => result)],
    );
    addTearDown(service.dispose);

    final report = await service.check(input);
    expect(report.results.single, same(result));
    expect(report.findings, orderedEquals(result.findings));
    expect(report.findings.map((finding) => finding.start), [20, 27]);
    expect(report.findings.clear, throwsUnsupportedError);
  });

  test('missing provider is unavailable, never a clean check', () async {
    final OfficeProofingReport report = await OfficeProofingService(
      providers: <OfficeProofingProvider>[],
    ).check(request('Hallo'));
    expect(report.results.single.status, OfficeProofingStatus.unavailable);
    expect(report.complete, isFalse);
    expect(report.isClean, isFalse);
  });

  test(
    'unsupported locale stays distinct from successful empty output',
    () async {
      final FakeProvider provider = FakeProvider(
        (OfficeProofingRequest r) async => clean(r),
        supported: false,
      );
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[provider],
      ).check(request('Hallo'));
      expect(report.results.single.status, OfficeProofingStatus.unsupported);
      expect(report.isClean, isFalse);
    },
  );

  test(
    'optional unsupported provider does not invalidate an applicable success',
    () async {
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider((OfficeProofingRequest r) async => clean(r)),
          FakeProvider(
            (OfficeProofingRequest r) async => throw StateError('must not run'),
            supported: false,
            name: 'english',
          ),
        ],
      ).check(request('Hallo'));
      expect(report.isClean, isTrue);
      expect(report.results.last.status, OfficeProofingStatus.unsupported);
    },
  );

  test('throwing provider is a failed result and never clean', () async {
    final OfficeProofingReport report = await OfficeProofingService(
      providers: <OfficeProofingProvider>[
        FakeProvider(
          (OfficeProofingRequest r) async => throw StateError('backend failed'),
        ),
      ],
    ).check(request('Hallo'));
    expect(report.results.single.status, OfficeProofingStatus.failed);
    expect(report.results.single.message, contains('backend failed'));
    expect(report.isClean, isFalse);
  });

  test(
    'non-BMP scalars map to original UTF16 positions and enforce bounds',
    () {
      expect(scalarOffsetToUtf16('🙂Haus', 1), 2);
      expect(scalarOffsetToUtf16('🙂Haus', 5), 6);
      expect(() => scalarOffsetToUtf16('🙂Haus', 6), throwsRangeError);
      expect(() => scalarOffsetToUtf16('🙂Haus', -1), throwsRangeError);
    },
  );

  test(
    'language segments produce absolute source-bound offsets exactly once',
    () async {
      final OfficeProofingRequest r = request('🙂Huas', startOffset: 20);
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider(
            (OfficeProofingRequest input) async => OfficeProofingResult(
              request: input,
              providerId: 'test',
              status: OfficeProofingStatus.success,
              findings: <OfficeProofingFinding>[
                OfficeProofingFinding.forRequest(
                  input,
                  providerId: 'test',
                  start: 2,
                  end: 6,
                  ruleId: 'typo',
                  message: 'Typo',
                  category: OfficeProofingCategory.spelling,
                  replacements: <String>['Haus'],
                ),
              ],
            ),
          ),
        ],
      ).check(r);
      expect(report.complete, isTrue);
      expect(report.findings.single.start, 22);
      expect(report.findings.single.end, 26);
      expect(report.findings.single.originalText, 'Huas');
      expect(report.findings.single.documentId, 'doc');
      expect(report.findings.single.revision, 7);
    },
  );

  for (final (String label, String source, int start, int end) probe
      in <(String, String, int, int)>[
        ('surrogate pair', '🙂Hallo', 1, 2),
        ('combining character', 'a\u0308h', 0, 1),
        ('ZWJ sequence', '👩‍💻Hallo', 0, 2),
      ]) {
    test('rejects range splitting ${probe.$1}', () async {
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider(
            (OfficeProofingRequest input) async => OfficeProofingResult(
              request: input,
              providerId: 'test',
              status: OfficeProofingStatus.success,
              findings: <OfficeProofingFinding>[
                OfficeProofingFinding.forRequest(
                  input,
                  providerId: 'test',
                  start: probe.$3,
                  end: probe.$4,
                  ruleId: 'bad',
                  message: 'Bad range',
                  category: OfficeProofingCategory.style,
                ),
              ],
            ),
          ),
        ],
      ).check(request(probe.$2));
      expect(report.results.single.status, OfficeProofingStatus.failed);
      expect(report.findings, isEmpty);
    });
  }

  test('zero-length insertion at a grapheme boundary is valid', () async {
    final OfficeProofingReport report = await OfficeProofingService(
      providers: <OfficeProofingProvider>[
        FakeProvider(
          (OfficeProofingRequest input) async => OfficeProofingResult(
            request: input,
            providerId: 'test',
            status: OfficeProofingStatus.success,
            findings: <OfficeProofingFinding>[
              OfficeProofingFinding.forRequest(
                input,
                providerId: 'test',
                start: 5,
                end: 5,
                ruleId: 'period',
                message: 'Consider a period',
                category: OfficeProofingCategory.style,
                replacements: <String>['.'],
              ),
            ],
          ),
        ),
      ],
    ).check(request('Hallo'));
    expect(report.complete, isTrue);
    expect(report.findings.single.originalText, isEmpty);
  });

  test('invalid source text and stale identity fail validation', () async {
    for (final bool wrongText in <bool>[true, false]) {
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider(
            (OfficeProofingRequest input) async => OfficeProofingResult(
              request: input,
              providerId: 'test',
              status: OfficeProofingStatus.success,
              findings: <OfficeProofingFinding>[
                OfficeProofingFinding(
                  documentId: 'doc',
                  blockId: 'body:1',
                  revision: wrongText ? 7 : 6,
                  providerId: 'test',
                  start: 0,
                  end: 5,
                  originalText: wrongText ? 'other' : 'Hallo',
                  ruleId: 'bad',
                  message: 'Bad',
                  category: OfficeProofingCategory.spelling,
                ),
              ],
            ),
          ),
        ],
      ).check(request('Hallo'));
      expect(report.results.single.status, OfficeProofingStatus.failed);
    }
  });

  test(
    'rule opt-out filters findings without changing provider availability',
    () async {
      final OfficeProofingRequest r = OfficeProofingRequest(
        documentId: 'doc',
        blockId: 'body:1',
        revision: 7,
        text: 'Hallo',
        ignoredRuleIds: <String>{'style'},
      );
      final OfficeProofingReport report = await OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider(
            (OfficeProofingRequest input) async => OfficeProofingResult(
              request: input,
              providerId: 'test',
              status: OfficeProofingStatus.success,
              findings: <OfficeProofingFinding>[
                OfficeProofingFinding.forRequest(
                  input,
                  providerId: 'test',
                  start: 0,
                  end: 5,
                  ruleId: 'style',
                  message: 'Advisory',
                  category: OfficeProofingCategory.style,
                ),
              ],
            ),
          ),
        ],
      ).check(r);
      expect(report.isClean, isTrue);
    },
  );

  test('deadline disposes stalled backend and prevents reusing it', () async {
    final Completer<OfficeProofingResult> pending =
        Completer<OfficeProofingResult>();
    final FakeProvider provider = FakeProvider(
      (OfficeProofingRequest r) => pending.future,
    );
    final OfficeProofingService service = OfficeProofingService(
      providers: <OfficeProofingProvider>[provider],
      timeout: const Duration(milliseconds: 10),
    );
    final OfficeProofingReport first = await service.check(request('Hallo'));
    expect(first.results.single.status, OfficeProofingStatus.failed);
    expect(provider.disposed, isTrue);
    final OfficeProofingReport next = await service.check(request('Hallo'));
    expect(next.results.single.status, OfficeProofingStatus.unavailable);
    pending.complete(clean(request('late')));
    await service.dispose();
  });

  test(
    'a bounded provider can continue after an individual deadline',
    () async {
      final pending = Completer<OfficeProofingResult>();
      final first = request('slow');
      final provider = FakeProvider(
        (input) async =>
            identical(input, first) ? pending.future : clean(input),
      );
      final service = OfficeProofingService(
        providers: [provider],
        timeout: const Duration(milliseconds: 10),
        disposeOnTimeout: false,
      );
      addTearDown(service.dispose);
      final slow = await service.check(first);
      expect(slow.results.single.status, OfficeProofingStatus.failed);
      expect(provider.disposed, isFalse);
      expect((await service.check(request('next'))).isClean, isTrue);
      pending.complete(clean(first));
    },
  );

  test(
    'disposed service stays unavailable and duplicate provider ids rejected',
    () async {
      final OfficeProofingService service = OfficeProofingService(
        providers: <OfficeProofingProvider>[
          FakeProvider((OfficeProofingRequest r) async => clean(r)),
        ],
      );
      await service.dispose();
      expect((await service.check(request('Hallo'))).isClean, isFalse);
      expect(
        () => OfficeProofingService(
          providers: <OfficeProofingProvider>[
            FakeProvider((OfficeProofingRequest r) async => clean(r)),
            FakeProvider((OfficeProofingRequest r) async => clean(r)),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
}
