import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final _request = OfficeProofingRequest(
  documentId: 'd',
  blockId: 'b',
  revision: 1,
  text: 'ذهب الى البيت',
  language: 'ar',
);

OfficeProofingResult _result(
  String provider,
  List<(int, int, String, OfficeProofingCategory, List<String>)> findings,
) => OfficeProofingResult(
  request: _request,
  providerId: provider,
  status: OfficeProofingStatus.success,
  findings: [
    for (final (start, end, rule, category, replacements) in findings)
      OfficeProofingFinding.forRequest(
        _request,
        providerId: provider,
        start: start,
        end: end,
        ruleId: rule,
        message: '$provider message',
        category: category,
        replacements: replacements,
      ),
  ],
);

void main() {
  const spelling = OfficeProofingCategory.spelling;

  test('agreeing findings for one range become one review item', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('arabic-writing', [
          (4, 7, 'ar.hamza.initial', spelling, ['إلى']),
        ]),
        _result('hunspell-ayaspell-ar', [
          (4, 7, 'hunspell.spelling', spelling, ['إلى', 'ألي', 'إلي']),
        ]),
      ],
    );
    expect(report.findings, hasLength(1));
    final finding = report.findings.single;
    expect(finding.providerId, 'arabic-writing');
    expect(finding.ruleId, 'ar.hamza.initial');
    expect(finding.message, 'arabic-writing message');
    expect(finding.originalText, 'الى');
    expect(finding.replacements, ['إلى', 'ألي', 'إلي']);
  });

  test('provider order decides between equal categories', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('hunspell-ayaspell-ar', [
          (4, 7, 'hunspell.spelling', spelling, ['ألي', 'إلى']),
        ]),
        _result('arabic-writing', [
          (4, 7, 'ar.hamza.initial', spelling, ['إلى']),
        ]),
      ],
    );
    expect(report.findings.single.ruleId, 'hunspell.spelling');
    expect(report.findings.single.replacements, ['ألي', 'إلى']);
  });

  test('disagreeing or differently ranged findings stay separate', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('a', [
          (4, 7, 'rule', OfficeProofingCategory.grammar, ['X']),
          (8, 13, 'rule2', spelling, ['Y']),
        ]),
        _result('b', [
          (4, 7, 'spell', spelling, ['Z']),
          (8, 12, 'spell2', spelling, ['Y']),
          (8, 13, 'none', spelling, []),
        ]),
      ],
    );
    expect(report.findings.map((f) => f.ruleId).toList(), [
      'rule',
      'spell',
      'spell2',
      'rule2',
      'none',
    ]);
  });

  test('findings of one provider are never merged with each other', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('a', [
          (4, 7, 'one', spelling, ['إلى']),
          (4, 7, 'two', spelling, ['إلى']),
        ]),
      ],
    );
    expect(report.findings, hasLength(2));
  });

  test('another provider cannot bridge two findings of the same provider', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('a', [
          (4, 7, 'first-provider', spelling, ['إلى']),
        ]),
        _result('b', [
          (4, 7, 'one', spelling, ['إلى', 'إلي']),
          (4, 7, 'two', spelling, ['إلى', 'ألي']),
        ]),
      ],
    );
    expect(report.findings.map((finding) => finding.ruleId), [
      'first-provider',
      'two',
    ]);
    expect(report.findings.first.providerId, 'a');
    expect(report.findings.first.message, 'a message');
    expect(report.findings.first.replacements, ['إلى', 'إلي']);
    expect(report.findings.last.providerId, 'b');
    expect(report.findings.last.message, 'b message');
    expect(report.findings.last.replacements, ['إلى', 'ألي']);
    expect(report.results.last.findings, hasLength(2));
  });

  test('agreeing findings of different categories stay separate', () {
    final report = OfficeProofingReport(
      request: _request,
      results: [
        _result('spell', [
          (4, 7, 'spell', spelling, ['إلى']),
        ]),
        _result('grammar', [
          (4, 7, 'grammar', OfficeProofingCategory.grammar, ['إلى']),
        ]),
      ],
    );
    expect(report.findings.map((f) => f.ruleId).toList(), ['grammar', 'spell']);
  });
}
