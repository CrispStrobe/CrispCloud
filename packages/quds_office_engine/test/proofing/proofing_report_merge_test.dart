import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

OfficeProofingRequest _request() => OfficeProofingRequest(
  documentId: 'merge-document',
  blockId: 'paragraph',
  revision: 3,
  text: 'abcdefghij',
  startOffset: 37,
  language: 'de-DE',
);

OfficeProofingFinding _finding(
  OfficeProofingRequest request,
  String provider,
  int start,
  int end, {
  List<String> replacements = const <String>['replacement'],
}) => OfficeProofingFinding.forRequest(
  request,
  providerId: provider,
  start: start,
  end: end,
  ruleId: '$provider.rule',
  message: 'Review this range.',
  category: OfficeProofingCategory.grammar,
  replacements: replacements,
);

OfficeProofingResult _result(
  OfficeProofingRequest request,
  String provider, {
  List<OfficeProofingFinding> findings = const <OfficeProofingFinding>[],
  OfficeProofingStatus status = OfficeProofingStatus.success,
  String? message,
}) => OfficeProofingResult(
  request: request,
  providerId: provider,
  status: status,
  findings: findings,
  message: message,
);

OfficeProofingReport _report(
  OfficeProofingRequest request,
  List<OfficeProofingResult> results,
) => OfficeProofingReport(request: request, results: results);

void main() {
  test('primary wins competing edits without rebasing source offsets', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding first = _finding(request, 'rules', 2, 5);
    final OfficeProofingFinding competing = _finding(request, 'model', 3, 6);
    final OfficeProofingFinding independent = _finding(request, 'model', 7, 9);
    final OfficeProofingResult ordinary = _result(
      request,
      'rules',
      findings: <OfficeProofingFinding>[first],
    );
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[ordinary]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'model',
          findings: <OfficeProofingFinding>[competing, independent],
          message: 'Local model completed.',
        ),
      ]),
    );
    expect(report.request, same(request));
    expect(report.results.first, same(ordinary));
    expect(report.findings, <OfficeProofingFinding>[first, independent]);
    expect(report.findings.last.start, 44);
    expect(report.findings.last.end, 46);
    expect(report.findings.last.originalText, 'hi');
    expect(report.results.last.message, 'Local model completed.');
    expect(report.complete, isTrue);
  });

  test('exact duplicate proposals retain both provider statuses', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding first = _finding(request, 'rules', 2, 5);
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(request, 'rules', findings: <OfficeProofingFinding>[first]),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'model',
          findings: <OfficeProofingFinding>[_finding(request, 'model', 2, 5)],
        ),
      ]),
    );
    expect(report.findings, <OfficeProofingFinding>[first]);
    expect(report.results, hasLength(2));
    expect(report.results.last.findings, isEmpty);
    expect(report.results.last.status, OfficeProofingStatus.success);
    expect(report.complete, isTrue);
  });

  test('adjacent nonempty ranges remain independently reviewable', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding middle = _finding(request, 'rules', 2, 5);
    final OfficeProofingFinding left = _finding(request, 'model', 0, 2);
    final OfficeProofingFinding right = _finding(request, 'model', 5, 7);
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(request, 'rules', findings: <OfficeProofingFinding>[middle]),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'model',
          findings: <OfficeProofingFinding>[right, left],
        ),
      ]),
    );
    expect(report.findings, <OfficeProofingFinding>[left, middle, right]);
  });

  for (final int at in <int>[2, 3, 5]) {
    test('secondary insertion at $at conflicts with primary range 2..5', () {
      final OfficeProofingRequest request = _request();
      final OfficeProofingReport report = mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'rules',
            findings: <OfficeProofingFinding>[_finding(request, 'rules', 2, 5)],
          ),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'model',
            findings: <OfficeProofingFinding>[
              _finding(request, 'model', at, at),
            ],
          ),
        ]),
      );
      expect(report.results.last.findings, isEmpty);
    });
  }

  for (final (int, int) span in <(int, int)>[(1, 3), (3, 5), (3, 3)]) {
    test('primary insertion suppresses secondary span $span touching it', () {
      final OfficeProofingRequest request = _request();
      final OfficeProofingReport report = mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'rules',
            findings: <OfficeProofingFinding>[_finding(request, 'rules', 3, 3)],
          ),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'model',
            findings: <OfficeProofingFinding>[
              _finding(request, 'model', span.$1, span.$2),
            ],
          ),
        ]),
      );
      expect(report.results.last.findings, isEmpty);
    });
  }

  test('separate insertion points do not conflict', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding first = _finding(request, 'rules', 2, 2);
    final OfficeProofingFinding second = _finding(request, 'model', 3, 3);
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(request, 'rules', findings: <OfficeProofingFinding>[first]),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(request, 'model', findings: <OfficeProofingFinding>[second]),
      ]),
    );
    expect(report.findings, <OfficeProofingFinding>[first, second]);
  });

  test('secondary order resolves conflicts within and across providers', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding first = _finding(request, 'model-a', 4, 8);
    final OfficeProofingFinding last = _finding(request, 'model-b', 0, 2);
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(request, 'rules'),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'model-a',
          findings: <OfficeProofingFinding>[
            first,
            _finding(request, 'model-a', 0, 6),
          ],
        ),
        _result(
          request,
          'model-b',
          findings: <OfficeProofingFinding>[
            _finding(request, 'model-b', 7, 10),
            last,
          ],
        ),
      ]),
    );
    expect(report.findings, <OfficeProofingFinding>[last, first]);
    expect(report.results[1].findings, <OfficeProofingFinding>[first]);
    expect(report.results[2].findings, <OfficeProofingFinding>[last]);
  });

  test('primary alternatives and advisory overlaps remain intact', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingFinding spelling = _finding(
      request,
      'spelling',
      2,
      5,
      replacements: const <String>['first choice', 'second choice'],
    );
    final OfficeProofingFinding advisory = _finding(
      request,
      'rules',
      3,
      6,
      replacements: const <String>[],
    );
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'spelling',
          findings: <OfficeProofingFinding>[spelling],
        ),
        _result(request, 'rules', findings: <OfficeProofingFinding>[advisory]),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(
          request,
          'model',
          findings: <OfficeProofingFinding>[_finding(request, 'model', 5, 7)],
        ),
      ]),
    );
    expect(report.findings, <OfficeProofingFinding>[spelling, advisory]);
    expect(report.findings.first.replacements, <String>[
      'first choice',
      'second choice',
    ]);
    expect(report.results.last.findings, isEmpty);
  });

  for (final OfficeProofingStatus status in <OfficeProofingStatus>[
    OfficeProofingStatus.unsupported,
    OfficeProofingStatus.unavailable,
    OfficeProofingStatus.failed,
  ]) {
    test('secondary ${status.name} remains explicit in merged coverage', () {
      final OfficeProofingRequest request = _request();
      final OfficeProofingReport report = mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(request, 'rules'),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'model',
            status: status,
            message: 'Provider status.',
          ),
        ]),
      );
      expect(report.results.last.status, status);
      expect(report.results.last.message, 'Provider status.');
      expect(report.complete, status == OfficeProofingStatus.unsupported);
      expect(report.isClean, status == OfficeProofingStatus.unsupported);
    });
  }

  test('failure in primary is not hidden by a successful secondary', () {
    final OfficeProofingRequest request = _request();
    final OfficeProofingReport report = mergeOfficeProofingReports(
      primary: _report(request, <OfficeProofingResult>[
        _result(request, 'rules', status: OfficeProofingStatus.failed),
      ]),
      secondary: _report(request, <OfficeProofingResult>[
        _result(request, 'model'),
      ]),
    );
    expect(report.complete, isFalse);
    expect(report.isClean, isFalse);
  });

  test('equal request values do not permit joining different snapshots', () {
    final OfficeProofingRequest first = _request();
    final OfficeProofingRequest second = _request();
    expect(
      () => mergeOfficeProofingReports(
        primary: _report(first, <OfficeProofingResult>[
          _result(first, 'rules'),
        ]),
        secondary: _report(second, <OfficeProofingResult>[
          _result(second, 'model'),
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('misbound provider result is rejected even when reports agree', () {
    final OfficeProofingRequest request = _request();
    expect(
      () => mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(request, 'rules'),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(_request(), 'model'),
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('duplicate provider ownership cannot be merged', () {
    final OfficeProofingRequest request = _request();
    expect(
      () => mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(request, 'same-provider'),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(request, 'same-provider'),
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('failed provider cannot contribute hidden conflicting proposals', () {
    final OfficeProofingRequest request = _request();
    expect(
      () => mergeOfficeProofingReports(
        primary: _report(request, <OfficeProofingResult>[
          _result(request, 'rules'),
        ]),
        secondary: _report(request, <OfficeProofingResult>[
          _result(
            request,
            'model',
            status: OfficeProofingStatus.failed,
            findings: <OfficeProofingFinding>[_finding(request, 'model', 2, 5)],
          ),
        ]),
      ),
      throwsArgumentError,
    );
  });
}
