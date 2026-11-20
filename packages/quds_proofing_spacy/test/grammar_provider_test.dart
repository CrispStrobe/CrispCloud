// Controlled transport replies exercise provider ownership and configuration
// behavior. All linguistic annotations are synthetic; no native model executes.
import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';
import 'package:test/test.dart';

const _identity = SpacyBackendIdentity(librarySha256: spacyGrammarNativeSha256);
const _otherIdentity = SpacyBackendIdentity(
  librarySha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);

OfficeProofingRequest _request({
  String document = 'provider-document',
  String block = 'body:2',
  int revision = 4,
  String language = 'de-DE',
  int origin = 11,
  Set<String> ignored = const {},
}) => OfficeProofingRequest(
  documentId: document,
  blockId: block,
  revision: revision,
  language: language,
  startOffset: origin,
  text: 'Die Katzen im Garten schläft.',
  ignoredRuleIds: ignored,
);

LinguisticAnalysisRequest _copy(
  LinguisticAnalysisRequest original, {
  String? document,
  String? block,
  int? revision,
  String? text,
  String? locale,
  int? origin,
  int? generation,
  String? configuration,
}) => LinguisticAnalysisRequest(
  documentId: document ?? original.documentId,
  blockId: block ?? original.blockId,
  revision: revision ?? original.revision,
  text: text ?? original.text,
  locale: locale ?? original.locale,
  startOffset: origin ?? original.startOffset,
  generation: generation ?? original.generation,
  configurationId: configuration ?? original.configurationId,
);

LinguisticAnalysisResult _syntheticAnalysis(
  LinguisticAnalysisRequest request, {
  SpacyBackendIdentity identity = _identity,
}) {
  final words = request.text.substring(0, request.text.length - 1).split(' ');
  expect(words, hasLength(5));
  final texts = [...words, '.'];
  const heads = [1, 4, 1, 2, 4, 4];
  const dependencies = ['nk', 'sb', 'mnr', 'nk', 'ROOT', 'punct'];
  const tags = ['ART', 'NN', 'APPRART', 'NN', 'VVFIN', r'$.'];
  const positions = ['DET', 'NOUN', 'ADP', 'NOUN', 'VERB', 'PUNCT'];
  const morphologies = [
    '',
    'Case=Nom|Gender=Fem|Number=Plur',
    '',
    'Case=Dat|Gender=Masc|Number=Sing',
    'Mood=Ind|Number=Sing|Person=3|Tense=Pres|VerbForm=Fin',
    '',
  ];
  final tokens = <LinguisticToken>[];
  var utf16At = 0;
  var byteAt = 0;
  var scalarAt = 0;
  for (var index = 0; index < texts.length; index++) {
    final text = texts[index];
    final space = index < 4;
    final byteEnd = byteAt + utf8.encode(text).length;
    final scalarEnd = scalarAt + text.runes.length;
    tokens.add(
      LinguisticToken(
        index: index,
        text: text,
        byteStart: byteAt,
        byteEnd: byteEnd,
        scalarStart: scalarAt,
        scalarEnd: scalarEnd,
        start: utf16At,
        end: utf16At + text.length,
        lemma: index == 4 ? 'schlafen' : text.toLowerCase(),
        tag: tags[index],
        pos: positions[index],
        morphology: morphologies[index],
        dependency: dependencies[index],
        head: heads[index],
        sentenceStart: index == 0,
        sentenceEnd: index == texts.length - 1,
        spaceAfter: space,
      ),
    );
    utf16At += text.length + (space ? 1 : 0);
    byteAt = byteEnd + (space ? 1 : 0);
    scalarAt = scalarEnd + (space ? 1 : 0);
  }
  return LinguisticAnalysisResult.success(
    request: request,
    identity: identity,
    tokens: tokens,
  );
}

final class _Call {
  _Call(this.request);
  final LinguisticAnalysisRequest request;
  final completion = Completer<LinguisticAnalysisResult>();

  void succeed({
    LinguisticAnalysisRequest? responseRequest,
    SpacyBackendIdentity identity = _identity,
  }) => completion.complete(
    _syntheticAnalysis(responseRequest ?? request, identity: identity),
  );

  void fail(LinguisticAnalysisStatus status) => completion.complete(
    LinguisticAnalysisResult.failure(
      request: request,
      status: status,
      message: 'Controlled ${status.name} response.',
      identity: _identity,
    ),
  );
}

/// It intentionally permits late replies after cancel/dispose so provider
/// ownership is checked independently of the real worker's own safeguards.
final class _ControlledTransport implements SpacyTransport {
  _ControlledTransport({this.identity = _identity, this.holdClose = false});

  @override
  final SpacyBackendIdentity identity;
  final bool holdClose;
  final calls = <_Call>[];
  final cancellations = <String>[];
  final closing = Completer<void>();
  int disposeCalls = 0;

  @override
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request) {
    final call = _Call(request);
    calls.add(call);
    return call.completion.future;
  }

  @override
  void cancel(String key) => cancellations.add(key);

  @override
  Future<void> dispose() {
    disposeCalls++;
    return holdClose ? closing.future : Future<void>.value();
  }
}

final class _MustNotOpenFactory implements SpacyBackendFactory {
  int opens = 0;
  @override
  Future<SpacyBackend> open(SpacyBundle bundle) {
    opens++;
    throw StateError('Disabled grammar must not open a backend.');
  }
}

void main() {
  test('default disabled provider makes zero analysis calls', () async {
    final transport = _ControlledTransport();
    final provider = SpacyGrammarProvider.withTransport(transport: transport);
    final result = await provider.check(_request());
    expect(result.status, OfficeProofingStatus.unavailable);
    expect(result.message, contains('disabled'));
    expect(result.findings, isEmpty);
    expect(transport.calls, isEmpty);
    expect(transport.cancellations, isEmpty);
    await provider.dispose();
    expect(transport.disposeCalls, 1);
  });

  test('disabled load refuses before any backend can open', () async {
    final factory = _MustNotOpenFactory();
    await expectLater(
      SpacyGrammarProvider.load(backendFactory: factory),
      throwsA(
        isA<SpacyUnavailableException>().having(
          (error) => error.message,
          'message',
          'Optional manual German grammar is disabled.',
        ),
      ),
    );
    expect(factory.opens, 0);
  });

  test(
    'unsupported locales and ignored rules make zero analysis calls',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        families: const {SpacyGrammarFamily.nounVerb},
      );
      addTearDown(provider.dispose);
      for (final locale in ['de-AT', 'de-CH', 'de-DE-1901', 'en-US']) {
        final result = await provider.check(_request(language: locale));
        expect(result.status, OfficeProofingStatus.unsupported);
        expect(result.findings, isEmpty);
      }
      for (final ignored in [
        {spacyNounVerbRuleId},
        {'de.grammar.noun-verb'},
      ]) {
        final result = await provider.check(_request(ignored: ignored));
        expect(result.status, OfficeProofingStatus.success);
        expect(result.message, contains('ignored'));
        expect(result.findings, isEmpty);
      }
      expect(transport.calls, isEmpty);

      // With every qualified family enabled, ignoring one family still
      // analyzes; ignoring all of them (new or matching deterministic IDs)
      // makes no call.
      final all = _ControlledTransport();
      final multi = SpacyGrammarProvider.withTransport(
        transport: all,
        enabled: true,
      );
      addTearDown(multi.dispose);
      final everything = {
        for (final family in spacyGrammarQualifiedFamilies)
          family.legacyRuleIds.first,
      };
      final none = await multi.check(_request(ignored: everything));
      expect(none.status, OfficeProofingStatus.success);
      expect(none.message, contains('ignored'));
      expect(all.calls, isEmpty);
      unawaited(multi.check(_request(ignored: {spacyNounVerbRuleId})));
      expect(all.calls, hasLength(1));
    },
  );

  test(
    'admitted check preserves the exact request and nonzero source origin',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      addTearDown(provider.dispose);
      final request = _request(origin: 37);
      final pending = provider.check(request);
      final call = transport.calls.single;
      expect(call.request.documentId, request.documentId);
      expect(call.request.blockId, request.blockId);
      expect(call.request.revision, request.revision);
      expect(call.request.startOffset, 37);
      expect(call.request.text, request.text);
      call.succeed();
      final result = await pending;
      expect(identical(result.request, request), isTrue);
      expect(result.status, OfficeProofingStatus.success);
      final finding = result.findings.single;
      expect(finding.originalText, 'schläft');
      expect(finding.replacements, ['schlafen']);
      expect(finding.start, 37 + request.text.indexOf('schläft'));
    },
  );

  test('personal and ignored words are captured before inference', () async {
    for (final addWord in [true, false]) {
      final transport = _ControlledTransport();
      final vocabulary = OfficeProofingVocabulary();
      if (addWord) {
        vocabulary.addWord('Katzen');
      } else {
        vocabulary.ignoreWord('Katzen');
      }
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        vocabulary: vocabulary,
      );
      final pending = provider.check(_request());
      final call = transport.calls.single;
      expect(provider.configurationRevision, 1);
      expect((jsonDecode(call.request.configurationId) as List)[1], 1);
      call.succeed();
      final result = await pending;
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, isEmpty);
      await provider.dispose();
    }
  });

  test(
    'a vocabulary change during inference invalidates the returned snapshot',
    () async {
      final transport = _ControlledTransport();
      final vocabulary = OfficeProofingVocabulary();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        vocabulary: vocabulary,
      );
      addTearDown(provider.dispose);
      final pending = provider.check(_request());
      vocabulary.addWord('Garten');
      transport.calls.single.succeed();
      final result = await pending;
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.message, contains('personal vocabulary changed'));
      expect(result.findings, isEmpty);
      expect(provider.configurationRevision, 1);
    },
  );

  test(
    'a vocabulary change while lexical planning yields invalidates completion',
    () async {
      final transport = _ControlledTransport();
      final vocabulary = OfficeProofingVocabulary();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        vocabulary: vocabulary,
      );
      addTearDown(provider.dispose);
      final pending = provider.check(_request());
      transport.calls.single.succeed();
      // Completion resumes the provider first. The following microtask runs at
      // the planner's real asynchronous lexical-preparation boundary, even when
      // noun buckets are already warm. No planner injection or mock is used.
      scheduleMicrotask(() => vocabulary.addWord('Garten'));
      final result = await pending;
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.message, contains('before completion'));
      expect(result.findings, isEmpty);
    },
  );

  test(
    'all exact analysis snapshot fields are authenticated before planning',
    () async {
      final changes =
          <LinguisticAnalysisRequest Function(LinguisticAnalysisRequest)>[
            (request) => _copy(request, document: 'other-document'),
            (request) => _copy(request, block: 'other-block'),
            (request) => _copy(request, revision: request.revision + 1),
            (request) => _copy(request, origin: request.startOffset + 1),
            (request) => _copy(request, generation: request.generation + 1),
            (request) => _copy(request, configuration: 'other-configuration'),
            (request) => _copy(
              request,
              text: request.text.replaceFirst('Katzen', 'Hunde'),
            ),
          ];
      for (final change in changes) {
        final transport = _ControlledTransport();
        final provider = SpacyGrammarProvider.withTransport(
          transport: transport,
          enabled: true,
        );
        final pending = provider.check(_request());
        final call = transport.calls.single;
        call.succeed(responseRequest: change(call.request));
        final result = await pending;
        expect(result.status, OfficeProofingStatus.failed);
        expect(
          result.message,
          contains('different snapshot or native runtime'),
        );
        expect(result.findings, isEmpty);
        await provider.dispose();
      }
      // Successful analysis DTOs independently require de-DE. Authenticate
      // the locale on operational replies too, before propagating a backend
      // outcome that belongs to a different request.
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      final pending = provider.check(_request());
      final call = transport.calls.single;
      call.completion.complete(
        LinguisticAnalysisResult.failure(
          request: _copy(call.request, locale: 'de-AT'),
          status: LinguisticAnalysisStatus.unsupported,
          message: 'Controlled unsupported locale.',
          identity: _identity,
        ),
      );
      final result = await pending;
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.message, contains('different snapshot or native runtime'));
      expect(result.findings, isEmpty);
      await provider.dispose();
    },
  );

  test(
    'reply runtime and grammar-qualified runtime identities are both enforced',
    () async {
      for (final wrongTransport in [false, true]) {
        final transport = _ControlledTransport(
          identity: wrongTransport ? _otherIdentity : _identity,
        );
        final provider = SpacyGrammarProvider.withTransport(
          transport: transport,
          enabled: true,
        );
        final pending = provider.check(_request());
        transport.calls.single.succeed(identity: _otherIdentity);
        final result = await pending;
        expect(result.status, OfficeProofingStatus.failed);
        expect(result.findings, isEmpty);
        expect(
          result.message,
          wrongTransport
              ? 'runtime-mismatch'
              : contains('different snapshot or native runtime'),
        );
        await provider.dispose();
      }
    },
  );

  test(
    'obsolete request cancellation and completion cannot invalidate its successor',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      addTearDown(provider.dispose);
      final first = _request(revision: 4);
      final latest = _request(revision: 5);
      final oldPending = provider.check(first);
      final latestPending = provider.check(latest);
      expect(transport.calls, hasLength(2));
      expect(
        transport.calls[1].request.generation,
        greaterThan(transport.calls[0].request.generation),
      );
      provider.cancel(first);
      expect(transport.cancellations, isEmpty);
      transport.calls[0].succeed();
      final oldResult = await oldPending;
      expect(oldResult.status, OfficeProofingStatus.failed);
      expect(oldResult.findings, isEmpty);
      provider.cancel(first);
      expect(transport.cancellations, isEmpty);
      transport.calls[1].succeed();
      final currentResult = await latestPending;
      expect(currentResult.status, OfficeProofingStatus.success);
      expect(currentResult.findings, hasLength(1));
    },
  );

  test(
    'current cancellation invalidates even a late successful reply',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      addTearDown(provider.dispose);
      final request = _request();
      final pending = provider.check(request);
      provider.cancel(request);
      expect(transport.cancellations, [transport.calls.single.request.key]);
      transport.calls.single.succeed();
      final result = await pending;
      expect(result.status, OfficeProofingStatus.failed);
      expect(result.findings, isEmpty);
      provider.cancel(request);
      expect(transport.cancellations, hasLength(1));
    },
  );

  test(
    'a new ignored request cancels an older pending check without inference',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
        families: const {SpacyGrammarFamily.nounVerb},
      );
      addTearDown(provider.dispose);
      final pending = provider.check(_request());
      final ignored = await provider.check(
        _request(ignored: {spacyNounVerbRuleId}),
      );
      expect(ignored.status, OfficeProofingStatus.success);
      expect(ignored.findings, isEmpty);
      expect(transport.calls, hasLength(1));
      expect(transport.cancellations, [transport.calls.single.request.key]);
      transport.calls.single.succeed();
      final obsolete = await pending;
      expect(obsolete.status, OfficeProofingStatus.failed);
      expect(obsolete.findings, isEmpty);
    },
  );

  test(
    'independent blocks retain independent cancellation ownership',
    () async {
      final transport = _ControlledTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      addTearDown(provider.dispose);
      final first = _request(block: 'body:1');
      final other = _request(block: 'body:2');
      final cancelled = provider.check(first);
      final kept = provider.check(other);
      provider.cancel(first);
      transport.calls[1].succeed();
      expect((await kept).findings, hasLength(1));
      transport.calls[0].succeed();
      expect((await cancelled).status, OfficeProofingStatus.failed);
    },
  );

  test(
    'dispose invalidates pending work and joins transport cleanup once',
    () async {
      final transport = _ControlledTransport(holdClose: true);
      final provider = SpacyGrammarProvider.withTransport(
        transport: transport,
        enabled: true,
      );
      final pending = provider.check(_request());
      final firstClose = provider.dispose();
      final secondClose = provider.dispose();
      expect(identical(firstClose, secondClose), isTrue);
      expect(transport.disposeCalls, 1);
      var closed = false;
      unawaited(firstClose.then((_) => closed = true));
      transport.calls.single.succeed();
      final result = await pending;
      expect(result.status, OfficeProofingStatus.unavailable);
      expect(result.findings, isEmpty);
      expect(closed, isFalse);
      final rejected = await provider.check(_request(revision: 5));
      expect(rejected.status, OfficeProofingStatus.unavailable);
      expect(transport.calls, hasLength(1));
      transport.closing.complete();
      await Future.wait([firstClose, secondClose]);
      expect(closed, isTrue);
    },
  );

  test(
    'native failures and timeouts remain explicit operational outcomes',
    () async {
      for (final status in [
        LinguisticAnalysisStatus.failed,
        LinguisticAnalysisStatus.timeout,
        LinguisticAnalysisStatus.cancelled,
        LinguisticAnalysisStatus.stale,
        LinguisticAnalysisStatus.capacity,
        LinguisticAnalysisStatus.unavailable,
        LinguisticAnalysisStatus.unsupported,
      ]) {
        final transport = _ControlledTransport();
        final provider = SpacyGrammarProvider.withTransport(
          transport: transport,
          enabled: true,
        );
        final pending = provider.check(_request());
        transport.calls.single.fail(status);
        final result = await pending;
        expect(result.status, switch (status) {
          LinguisticAnalysisStatus.unavailable =>
            OfficeProofingStatus.unavailable,
          LinguisticAnalysisStatus.unsupported =>
            OfficeProofingStatus.unsupported,
          _ => OfficeProofingStatus.failed,
        });
        expect(result.message, 'analysis-${status.name}');
        expect(result.findings, isEmpty);
        await provider.dispose();
      }
    },
  );

  test(
    'transport exceptions stay failed or unavailable without findings',
    () async {
      for (final error in [
        StateError('Controlled transport fault.'),
        const SpacyUnavailableException('Controlled unavailable transport.'),
      ]) {
        final transport = _ControlledTransport();
        final provider = SpacyGrammarProvider.withTransport(
          transport: transport,
          enabled: true,
        );
        final pending = provider.check(_request());
        transport.calls.single.completion.completeError(error);
        final result = await pending;
        expect(
          result.status,
          error is SpacyUnavailableException
              ? OfficeProofingStatus.unavailable
              : OfficeProofingStatus.failed,
        );
        expect(result.findings, isEmpty);
        await provider.dispose();
      }
    },
  );
}
