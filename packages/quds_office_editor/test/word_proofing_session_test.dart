import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _ProbeProvider extends OfficeProofingProvider {
  _ProbeProvider({
    this.id = 'session-test',
    this.status = OfficeProofingStatus.success,
    this.languages,
    this.gate,
  });

  OfficeProofingStatus status;
  final Set<String>? languages;
  Completer<void>? gate;
  final Completer<void> started = Completer<void>();
  final List<OfficeProofingRequest> requests = <OfficeProofingRequest>[];
  int version = 0;
  bool disposed = false;

  @override
  final String id;

  @override
  int get configurationRevision => version;

  @override
  bool supportsLanguage(String language) =>
      languages?.contains(language) ?? true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    if (gate != null) await gate!.future;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: status,
      message: status == OfficeProofingStatus.success
          ? null
          : 'Checker ${status.name}.',
      findings: <OfficeProofingFinding>[
        if (status == OfficeProofingStatus.success)
          for (final RegExpMatch match in RegExp(
            'Feler',
          ).allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'test-spelling',
              message: 'Check spelling.',
              category: OfficeProofingCategory.spelling,
              replacements: const <String>['Fehler'],
            ),
      ],
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Harness {
  _Harness({
    WmlDocument? document,
    _ProbeProvider? provider,
    List<OfficeProofingProvider>? providers,
    OfficeProofingVocabulary? vocabulary,
  }) : document = document ?? WmlDocument.empty(text: 'Ein Feler.'),
       provider = provider ?? _ProbeProvider() {
    session = WordProofingSession(
      document: () => this.document,
      revision: () => revision,
      service: OfficeProofingService(
        providers: providers ?? <OfficeProofingProvider>[this.provider],
      ),
      vocabulary: vocabulary,
    );
    addTearDown(session.dispose);
  }

  WmlDocument document;
  final _ProbeProvider provider;
  int revision = 0;
  late final WordProofingSession session;

  void changed() {
    revision++;
    session.observeDocument();
  }
}

WmlParagraph _paragraph(String text, {WmlParagraphProps? properties}) =>
    WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: text)],
      properties: properties,
    );

WmlTable _table(WmlParagraph paragraph) => WmlTable(
  grid: <double>[200],
  rows: <WmlTableRow>[
    WmlTableRow(
      cells: <WmlTableCell>[
        WmlTableCell(blocks: <WmlBlock>[paragraph]),
      ],
    ),
  ],
);

void main() {
  test('closed empty complex fields never reach providers', () async {
    for (final includeEmptyRun in <bool>[false, true]) {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' QUDS_TEST_FIELD ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          if (includeEmptyRun) WmlRun(text: ''),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests, isEmpty);
      expect(summary.issues, isEmpty);
      expect(summary.paragraphCount, 1);
      expect(summary.checkedParagraphCount, 0);
      expect(summary.skippedContentCount, 1);
      expect(summary.complete, isFalse);
      expect(paragraph.text, isEmpty);
    }
  });

  test(
    'empty paragraphs inside and ending a spanning field are excluded while later authored paragraphs are checked',
    () async {
      final beginning = WmlParagraph(
        inlines: <WmlInline>[
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' QUDS_TEST_FIELD ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        ],
      );
      final ending = WmlParagraph(
        inlines: <WmlInline>[WmlFieldBoundary(kind: WmlFieldBoundaryKind.end)],
      );
      final authored = _paragraph('Feler');
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(
              blocks: <WmlBlock>[
                beginning,
                _paragraph(''),
                ending,
                _paragraph(''),
                authored,
              ],
            ),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests.map((request) => request.text), <String>[
        '',
        'Feler',
      ]);
      expect(summary.issues.single.paragraph, same(authored));
      expect(summary.paragraphCount, 5);
      expect(summary.checkedParagraphCount, 2);
      expect(summary.skippedContentCount, 3);
      expect(summary.complete, isFalse);
    },
  );

  test('generated page-number paragraphs never reach providers', () async {
    for (final text in <String>['Feler', '']) {
      final paragraph = _paragraph(
        text,
        properties: WmlParagraphProps(pageNumberField: true),
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests, isEmpty);
      expect(summary.issues, isEmpty);
      expect(summary.checkedParagraphCount, 0);
      expect(summary.skippedContentCount, 1);
      expect(summary.complete, isFalse);
    }
  });

  test(
    'page-number metadata invalidates findings without a text edit',
    () async {
      final h = _Harness();
      final issue = (await h.session.checkNow()).issues.single;
      issue.paragraph.properties.pageNumberField = true;
      expect(h.session.isCurrent(issue), isFalse);
      expect(h.session.canCorrect(issue), isFalse);
      expect((await h.session.checkNow()).issues, isEmpty);
      expect(h.provider.requests, hasLength(1));
      issue.paragraph.properties.pageNumberField = false;
      expect((await h.session.checkNow()).issues, hasLength(1));
      expect(h.provider.requests, hasLength(2));
    },
  );

  test(
    'pending page-number metadata changes discard provider results',
    () async {
      final gate = Completer<void>();
      final provider = _ProbeProvider(gate: gate);
      final h = _Harness(provider: provider);
      final pending = h.session.checkNow();
      await provider.started.future;
      h.document.paragraphs.first.properties.pageNumberField = true;
      gate.complete();
      await pending;
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.hasResults, isFalse);
      expect(h.session.findingsByParagraph, isEmpty);
    },
  );

  test('nonempty findings use half-open hit ranges', () async {
    final h = _Harness(document: WmlDocument.empty(text: 'Feler Feler'));
    final summary = await h.session.checkNow();
    final paragraph = summary.issues.first.paragraph;
    expect(h.session.issuesAt(paragraph, 0), <WordProofingIssue>[
      summary.issues.first,
    ]);
    expect(h.session.issuesAt(paragraph, 4), <WordProofingIssue>[
      summary.issues.first,
    ]);
    expect(h.session.issuesAt(paragraph, 5), isEmpty);
    expect(h.session.issuesAt(paragraph, 6), <WordProofingIssue>[
      summary.issues.last,
    ]);
    expect(h.session.issuesAt(paragraph, 11), isEmpty);
  });

  test(
    'a new document reusing the same paragraph gets fresh provider results and no inherited ignore-once state',
    () async {
      final h = _Harness();
      final first = (await h.session.checkNow()).issues.single;
      final paragraph = first.paragraph;
      final firstDocumentId = first.finding.documentId;
      h.session.ignoreOnce(first);
      expect((await h.session.checkNow()).issues, isEmpty);
      expect(h.provider.requests, hasLength(1));

      h.document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(blocks: <WmlBlock>[paragraph]),
        ],
      );
      final next = await h.session.checkNow();
      expect(h.provider.requests, hasLength(2));
      expect(next.issues.single.paragraph, same(paragraph));
      expect(next.issues.single.finding.documentId, isNot(firstDocumentId));
      expect(
        h.provider.requests.last.documentId,
        next.issues.single.finding.documentId,
      );
      expect(h.session.isCurrent(first), isFalse);
      expect(h.session.isCurrent(next.issues.single), isTrue);
    },
  );

  test(
    'language changes inside a combining cluster retain the full cluster and its first language',
    () async {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: 'a',
            properties: WmlRunProps(proofingLanguage: 'de-DE'),
          ),
          WmlRun(
            text: '\u0308',
            properties: WmlRunProps(proofingLanguage: 'en-US'),
          ),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, 'a\u0308');
      expect(h.provider.requests.single.language, 'de-DE');
      expect(summary.complete, isTrue);
    },
  );

  test(
    'a surrogate pair split across runs and languages remains one emoji in provider input',
    () async {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: '\uD83D',
            properties: WmlRunProps(proofingLanguage: 'de-DE'),
          ),
          WmlRun(
            text: '\uDE00',
            properties: WmlRunProps(proofingLanguage: 'en-US'),
          ),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, '😀');
      expect(h.provider.requests.single.language, 'de-DE');
      expect(summary.complete, isTrue);
    },
  );

  test(
    'noProof on part of a combining cluster excludes the entire cluster',
    () async {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'a'),
          WmlRun(text: '\u0308', properties: WmlRunProps(noProof: true)),
          WmlRun(text: ' tail'),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, ' tail');
      expect(h.provider.requests.single.startOffset, 2);
      expect(summary.complete, isFalse);
      expect(summary.skippedContentCount, greaterThan(0));
    },
  );

  test(
    'review traverses body, nested tables, frames, all headers/footers, notes and comments',
    () async {
      final paragraphs = <String, WmlParagraph>{
        for (final String name in <String>[
          'body',
          'table',
          'frame',
          'header',
          'footer',
          'first header',
          'first footer',
          'even header',
          'even footer',
          'footnote',
          'footnote table',
          'endnote',
          'comment',
          'second section',
        ])
          name: _paragraph('Feler $name'),
      };
      final document = WmlDocument(
        sections: <WmlSection>[
          WmlSection(
            blocks: <WmlBlock>[
              paragraphs['body']!,
              _table(paragraphs['table']!),
              WmlFrame(blocks: <WmlBlock>[paragraphs['frame']!]),
            ],
            header: <WmlParagraph>[paragraphs['header']!],
            footer: <WmlParagraph>[paragraphs['footer']!],
            firstHeader: <WmlParagraph>[paragraphs['first header']!],
            firstFooter: <WmlParagraph>[paragraphs['first footer']!],
            evenHeader: <WmlParagraph>[paragraphs['even header']!],
            evenFooter: <WmlParagraph>[paragraphs['even footer']!],
          ),
          WmlSection(blocks: <WmlBlock>[paragraphs['second section']!]),
        ],
        footnotes: <WmlNote>[
          WmlNote(
            id: 1,
            endnote: false,
            blocks: <WmlBlock>[
              paragraphs['footnote']!,
              _table(paragraphs['footnote table']!),
            ],
          ),
        ],
        endnotes: <WmlNote>[
          WmlNote(
            id: 2,
            endnote: true,
            paragraphs: <WmlParagraph>[paragraphs['endnote']!],
          ),
        ],
        comments: <WmlComment>[
          WmlComment(id: 3, paragraphs: <WmlParagraph>[paragraphs['comment']!]),
        ],
      );
      final h = _Harness(document: document);
      final summary = await h.session.checkNow();
      expect(summary.complete, isTrue);
      expect(summary.paragraphCount, paragraphs.length);
      expect(summary.checkedParagraphCount, paragraphs.length);
      expect(
        summary.issues.map((issue) => issue.paragraph),
        unorderedEquals(paragraphs.values),
      );
      expect(
        h.provider.requests.map((request) => request.text),
        unorderedEquals(paragraphs.values.map((paragraph) => paragraph.text)),
      );
      expect(
        summary.issues.map((issue) => issue.story).toSet(),
        containsAll(<String>[
          'Body',
          'Header · section 1',
          'Footer · section 1',
          'First-page header · section 1',
          'First-page footer · section 1',
          'Even-page header · section 1',
          'Even-page footer · section 1',
          'Footnote 1',
          'Endnote 2',
          'Comment 3',
        ]),
      );
      expect(summary.issues.every(h.session.isCurrent), isTrue);
    },
  );

  test(
    'formatting fragments join while language and noProof boundaries preserve UTF-16 offsets',
    () async {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: '😀 Fe', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'ler deutsch ', properties: WmlRunProps(italic: true)),
          WmlRun(
            text: 'Feler',
            properties: WmlRunProps(proofingLanguage: 'de-CH'),
          ),
          WmlRun(text: ' Feler', properties: WmlRunProps(noProof: true)),
          WmlRun(text: ' tail'),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(h.provider.requests.map((request) => request.text), <String>[
        '😀 Feler deutsch ',
        'Feler',
        ' tail',
      ]);
      expect(h.provider.requests.map((request) => request.language), <String>[
        'de-DE',
        'de-CH',
        'de-DE',
      ]);
      expect(summary.issues.map((issue) => issue.finding.start), <int>[
        3,
        '😀 Feler deutsch '.length,
      ]);
      expect(summary.issues.map((issue) => issue.language), <String>[
        'de-DE',
        'de-CH',
      ]);
      expect(summary.skippedContentCount, greaterThan(0));
      expect(summary.complete, isFalse);
      expect(paragraph.text, '😀 Feler deutsch Feler Feler tail');
    },
  );

  test(
    'run language overrides paragraph language, which overrides the document default',
    () async {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(proofingLanguage: 'de_CH'),
        inlines: <WmlInline>[
          WmlRun(text: 'Feler '),
          WmlRun(
            text: 'Feler',
            properties: WmlRunProps(proofingLanguage: 'en-GB'),
          ),
        ],
      );
      final h = _Harness(
        document: WmlDocument(
          proofingLanguage: 'de-AT',
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph, _paragraph('Feler')]),
          ],
        ),
      );
      await h.session.checkNow();
      expect(h.provider.requests.map((request) => request.language), <String>[
        'de-CH',
        'en-GB',
        'de-AT',
      ]);
    },
  );

  test(
    'late results after a revision change never become current findings',
    () async {
      final gate = Completer<void>();
      final provider = _ProbeProvider(gate: gate);
      final h = _Harness(provider: provider);
      final pending = h.session.checkNow();
      await provider.started.future;
      h.document.paragraphs.first.inlines = <WmlInline>[
        WmlRun(text: 'Correct now.'),
      ];
      h.changed();
      gate.complete();
      await pending;
      expect(h.session.summary.issues, isEmpty);
      expect(h.session.summary.hasResults, isFalse);
      final fresh = await h.session.checkNow();
      expect(fresh.complete, isTrue);
      expect(fresh.issues, isEmpty);
    },
  );

  test(
    'direct model edits during a pending check invalidate its snapshot even without revision notification',
    () async {
      final gate = Completer<void>();
      final provider = _ProbeProvider(gate: gate);
      final h = _Harness(provider: provider);
      final pending = h.session.checkNow();
      await provider.started.future;
      h.document.paragraphs.first.inlines = <WmlInline>[
        WmlRun(text: 'Changed directly.'),
      ];
      gate.complete();
      await pending;
      expect(h.session.summary.hasResults, isFalse);
      expect(h.session.summary.issues, isEmpty);
    },
  );

  test(
    'replacing a document with identical text and revision rejects the old document result',
    () async {
      final gate = Completer<void>();
      final provider = _ProbeProvider(gate: gate);
      final h = _Harness(provider: provider);
      final pending = h.session.checkNow();
      await provider.started.future;
      h.document = WmlDocument.empty(text: 'Ein Feler.');
      h.session.observeDocument();
      gate.complete();
      await pending;
      expect(h.session.summary.hasResults, isFalse);
      final fresh = await h.session.checkNow();
      expect(fresh.issues.single.paragraph, same(h.document.paragraphs.first));
      expect(
        provider.requests[0].documentId,
        isNot(provider.requests[1].documentId),
      );
    },
  );

  test(
    'provider reconfiguration cancels pending publication and disposes the previous provider',
    () async {
      final gate = Completer<void>();
      final previous = _ProbeProvider(gate: gate);
      final h = _Harness(provider: previous);
      final pending = h.session.checkNow();
      await previous.started.future;
      final next = _ProbeProvider(status: OfficeProofingStatus.unavailable);
      h.session.configure(
        OfficeProofingService(providers: <OfficeProofingProvider>[next]),
      );
      gate.complete();
      await pending;
      expect(previous.disposed, isTrue);
      final summary = await h.session.checkNow();
      expect(summary.complete, isFalse);
      expect(summary.issues, isEmpty);
      expect(summary.statusMessage, contains('unavailable'));
    },
  );

  test(
    'unchanged paragraphs reuse results while rebinding findings to the current revision',
    () async {
      final first = _paragraph('Feler one');
      final second = _paragraph('Correct two');
      final h = _Harness(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[first, second]),
          ],
        ),
      );
      final old = (await h.session.checkNow()).issues.single;
      expect(h.provider.requests, hasLength(2));
      h.changed();
      final rebound = (await h.session.checkNow()).issues.single;
      expect(h.provider.requests, hasLength(2));
      expect(rebound.finding.revision, h.revision);
      expect(h.session.isCurrent(rebound), isTrue);
      expect(h.session.isCurrent(old), isFalse);
      second.inlines = <WmlInline>[WmlRun(text: 'Feler two')];
      h.changed();
      final summary = await h.session.checkNow();
      expect(h.provider.requests, hasLength(3));
      expect(summary.issues, hasLength(2));
      expect(summary.issues.every(h.session.isCurrent), isTrue);
      expect(h.session.findingsByParagraph[first]!.single.revision, h.revision);
    },
  );

  test(
    'provider configuration revisions invalidate otherwise identical cached text',
    () async {
      final h = _Harness();
      await h.session.checkNow();
      h.provider.version++;
      await h.session.checkNow();
      expect(h.provider.requests, hasLength(2));
    },
  );

  test(
    'moving a paragraph between stories invalidates its old finding and cache',
    () async {
      final h = _Harness();
      final old = (await h.session.checkNow()).issues.single;
      final section = h.document.sections.first;
      section.blocks.remove(old.paragraph);
      section.header.add(old.paragraph);
      expect(h.session.isCurrent(old), isFalse);
      final current = (await h.session.checkNow()).issues.single;
      expect(current.story, 'Header · section 1');
      expect(h.provider.requests, hasLength(2));
    },
  );

  test(
    'a document with no checkable paragraphs never claims a clean completed check',
    () async {
      final h = _Harness(
        document: WmlDocument(sections: <WmlSection>[WmlSection()]),
      );
      final summary = await h.session.checkNow();
      expect(summary.hasResults, isTrue);
      expect(summary.complete, isFalse);
      expect(summary.statusMessage, contains('No checkable text'));
      expect(summary.statusMessage, isNot(contains('No issues found')));
    },
  );

  test('no configured provider is visibly unavailable', () async {
    final h = _Harness(providers: <OfficeProofingProvider>[]);
    final summary = await h.session.checkNow();
    expect(summary.complete, isFalse);
    expect(summary.issues, isEmpty);
    expect(
      summary.statusMessage,
      contains('No proofing provider is configured'),
    );
  });

  for (final status in <OfficeProofingStatus>[
    OfficeProofingStatus.unavailable,
    OfficeProofingStatus.unsupported,
    OfficeProofingStatus.failed,
  ]) {
    test(
      '${status.name} checks are incomplete and can be retried instead of cached as clean',
      () async {
        final provider = _ProbeProvider(status: status);
        final h = _Harness(provider: provider);
        final summary = await h.session.checkNow();
        expect(summary.complete, isFalse);
        expect(summary.checkedParagraphCount, 0);
        expect(summary.issues, isEmpty);
        expect(
          summary.statusMessage,
          status == OfficeProofingStatus.unsupported
              ? contains('No configured checker supports')
              : contains(status.name),
        );
        provider.status = OfficeProofingStatus.success;
        final retry = await h.session.checkNow();
        expect(provider.requests, hasLength(2));
        expect(retry.complete, isTrue);
        expect(retry.issues, hasLength(1));
      },
    );
  }

  test(
    'an unsupported document language reuses its incomplete report without rechecking',
    () async {
      final provider = _ProbeProvider(languages: <String>{'de-DE'});
      final h = _Harness(provider: provider);
      h.document.proofingLanguage = 'en-GB';
      final summary = await h.session.checkNow();
      expect(provider.requests, isEmpty);
      expect(summary.complete, isFalse);
      expect(
        summary.statusMessage,
        contains('No configured checker supports en-GB'),
      );
      expect(h.session.checkedParagraphCount, 1);

      for (var pass = 0; pass < 2; pass++) {
        final cached = await h.session.checkNow();
        expect(provider.requests, isEmpty);
        expect(h.session.checkedParagraphCount, 1);
        expect(cached.checkedParagraphCount, 0);
        expect(cached.complete, isFalse);
        expect(
          cached.statusMessage,
          contains('No configured checker supports en-GB'),
        );
      }
      expect(h.session.passCount, 3);
    },
  );

  test(
    'a provider revision can enable a previously unsupported cached language',
    () async {
      final languages = <String>{'de-DE'};
      final provider = _ProbeProvider(languages: languages);
      final h = _Harness(provider: provider);
      h.document.proofingLanguage = 'en-GB';
      await h.session.checkNow();
      await h.session.checkNow();
      expect(h.session.checkedParagraphCount, 1);
      expect(provider.requests, isEmpty);

      languages.add('en-GB');
      provider.version++;
      final supported = await h.session.checkNow();
      expect(provider.requests.single.language, 'en-GB');
      expect(h.session.checkedParagraphCount, 2);
      expect(supported.checkedParagraphCount, 1);
      expect(supported.complete, isTrue);
      expect(supported.issues, hasLength(1));

      await h.session.checkNow();
      expect(provider.requests, hasLength(1));
      expect(h.session.checkedParagraphCount, 2);
    },
  );

  test(
    'replacing providers rechecks a previously unsupported cached language',
    () async {
      final unsupported = _ProbeProvider(languages: <String>{'de-DE'});
      final h = _Harness(provider: unsupported);
      h.document.proofingLanguage = 'en-GB';
      await h.session.checkNow();
      await h.session.checkNow();
      expect(h.session.checkedParagraphCount, 1);

      final supported = _ProbeProvider(languages: <String>{'en-GB'});
      h.session.configure(OfficeProofingService(providers: [supported]));
      final summary = await h.session.checkNow();
      expect(unsupported.requests, isEmpty);
      expect(supported.requests.single.language, 'en-GB');
      expect(h.session.checkedParagraphCount, 2);
      expect(summary.checkedParagraphCount, 1);
      expect(summary.complete, isTrue);
      expect(summary.issues, hasLength(1));
    },
  );

  test(
    'a successful paragraph cannot cover another unsupported paragraph',
    () async {
      final provider = _ProbeProvider(languages: <String>{'de-DE'});
      final h = _Harness(
        provider: provider,
        document: WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                _paragraph(
                  'Guter Text.',
                  properties: WmlParagraphProps(proofingLanguage: 'de-DE'),
                ),
                _paragraph(
                  'A short text.',
                  properties: WmlParagraphProps(proofingLanguage: 'en-GB'),
                ),
              ],
            ),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(provider.requests.single.language, 'de-DE');
      expect(summary.reports, hasLength(2));
      expect(summary.checkedParagraphCount, 1);
      expect(summary.paragraphCount, 2);
      expect(summary.complete, isFalse);
      expect(summary.statusMessage, contains('1 of 2 paragraphs checked'));
      expect(summary.statusMessage, contains('coverage is incomplete'));
      expect(summary.statusMessage, isNot(contains('No issues found')));
      expect(summary.statusMessage, isNot(contains('does not support')));

      // Reports are the evidence of coverage even when a caller supplies a
      // count that says all paragraphs were checked.
      final recounted = WordProofingSummary(
        hasResults: true,
        paragraphCount: 2,
        checkedParagraphCount: 2,
        reports: summary.reports,
      );
      expect(recounted.complete, isFalse);
      expect(recounted.statusMessage, contains('coverage is incomplete'));
    },
  );

  test(
    'language-specific checkers complete every paragraph without unsupported warnings',
    () async {
      final german = _ProbeProvider(
        id: 'german-checker',
        languages: <String>{'de-DE'},
      );
      final english = _ProbeProvider(
        id: 'english-checker',
        languages: <String>{'en-GB'},
      );
      final h = _Harness(
        providers: [german, english],
        document: WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                _paragraph(
                  'Guter Text.',
                  properties: WmlParagraphProps(proofingLanguage: 'de-DE'),
                ),
                _paragraph(
                  'A short text.',
                  properties: WmlParagraphProps(proofingLanguage: 'en-GB'),
                ),
              ],
            ),
          ],
        ),
      );
      final summary = await h.session.checkNow();
      expect(german.requests.single.language, 'de-DE');
      expect(english.requests.single.language, 'en-GB');
      expect(summary.reports, hasLength(2));
      for (final report in summary.reports) {
        expect(
          report.results.map((result) => result.status),
          containsAll([
            OfficeProofingStatus.success,
            OfficeProofingStatus.unsupported,
          ]),
        );
      }
      expect(summary.checkedParagraphCount, 2);
      expect(summary.complete, isTrue);
      expect(summary.statusMessage, contains('No issues found'));
      expect(summary.statusMessage, isNot(contains('does not support')));
      expect(summary.statusMessage, isNot(contains('unsupported')));
    },
  );

  test(
    'opaque body blocks and preserved header stories are explicit coverage gaps',
    () async {
      final h = _Harness();
      final section = h.document.sections.first;
      section.blocks.add(
        WmlOpaqueBlock(
          xml: '<w:altChunk/>',
          sourcePartUri: '/word/document.xml',
          relationships: <WmlOpaqueRelationship>[],
        ),
      );
      section.preservedStories['header'] = WmlOpaqueBlock(
        xml: '<w:hdr/>',
        sourcePartUri: '/word/header1.xml',
        relationships: <WmlOpaqueRelationship>[],
      );
      final summary = await h.session.checkNow();
      expect(summary.paragraphCount, 1);
      expect(summary.checkedParagraphCount, 1);
      expect(summary.skippedContentCount, 2);
      expect(summary.complete, isFalse);
      expect(summary.statusMessage, contains('coverage is incomplete'));
    },
  );

  test(
    'personal words are language-scoped and host snapshots preserve owner identity',
    () async {
      final vocabulary = OfficeProofingVocabulary(ownerId: 'profile-a');
      final h = _Harness(vocabulary: vocabulary);
      final snapshots = <Map<String, Object?>>[];
      h.session.onVocabularyChanged = snapshots.add;
      final issue = (await h.session.checkNow()).issues.single;
      h.session.addWord(issue);
      expect(snapshots.single['ownerId'], 'profile-a');
      expect(vocabulary.wordsFor('de-DE'), contains('Feler'));
      expect((await h.session.checkNow()).issues, isEmpty);
      h.document.proofingLanguage = 'de-CH';
      h.changed();
      expect((await h.session.checkNow()).issues, hasLength(1));
      expect(h.document.paragraphs.first.text, 'Ein Feler.');
      final restored = OfficeProofingVocabulary(ownerId: 'profile-a')
        ..addWord('Custom', language: 'de-CH');
      h.session.restoreVocabulary(restored.toJson());
      expect(vocabulary.wordsFor('de-DE'), isEmpty);
      expect(vocabulary.wordsFor('de-CH'), <String>{'Custom'});
      expect(
        () => h.session.restoreVocabulary(
          OfficeProofingVocabulary(ownerId: 'profile-b').toJson(),
        ),
        throwsArgumentError,
      );
      expect(vocabulary.wordsFor('de-CH'), <String>{'Custom'});
      expect(snapshots, hasLength(1));
    },
  );

  test(
    'ignore once suppresses one occurrence and resets when its paragraph text changes',
    () async {
      final h = _Harness(document: WmlDocument.empty(text: 'Feler und Feler'));
      final before = await h.session.checkNow();
      h.session.ignoreOnce(before.issues.first);
      final ignored = await h.session.checkNow();
      expect(ignored.issues, hasLength(1));
      expect(ignored.issues.single.finding.start, 10);
      expect(h.session.vocabulary.toJson()['words'], isEmpty);
      h.document.paragraphs.first.inlines.add(WmlRun(text: '.'));
      h.changed();
      expect((await h.session.checkNow()).issues, hasLength(2));
    },
  );

  test(
    'ignored rules can be restored without changing source text or personal words',
    () async {
      final h = _Harness();
      await h.session.checkNow();
      h.session.ignoreRule('test-spelling');
      expect((await h.session.checkNow()).issues, isEmpty);
      expect(
        h.provider.requests.last.ignoredRuleIds,
        contains('test-spelling'),
      );
      h.session.restoreRule('test-spelling');
      expect((await h.session.checkNow()).issues, hasLength(1));
      expect(h.document.paragraphs.first.text, 'Ein Feler.');
    },
  );

  test(
    'restoring ignored occurrences preserves word and rule preferences',
    () async {
      final h = _Harness(document: WmlDocument.empty(text: 'Feler Feler'));
      h.session.vocabulary
        ..addWord('Quds', language: 'de-DE')
        ..ignoreWord('Custom', language: 'de-CH');
      h.session.ignoreRule('unrelated-rule');
      final before = await h.session.checkNow();
      h.session.ignoreOnce(before.issues.first);
      expect((await h.session.checkNow()).issues, hasLength(1));
      expect(h.session.hasIgnoredOccurrences, isTrue);
      h.session.clearIgnoredOnce();
      expect((await h.session.checkNow()).issues, hasLength(2));
      expect(h.session.hasIgnoredOccurrences, isFalse);
      expect(h.session.vocabulary.wordsFor('de-DE'), <String>{'Quds'});
      expect(h.session.vocabulary.ignoredWordsFor('de-CH'), <String>{'Custom'});
      expect(h.session.ignoredRuleIds, <String>{'unrelated-rule'});
      expect(h.provider.requests, hasLength(1));
      expect(h.document.paragraphs.first.text, 'Feler Feler');
    },
  );
}
