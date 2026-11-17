import 'dart:async';

import 'package:characters/characters.dart';

/// Provider outcomes. An empty successful result is different from no checker.
enum OfficeProofingStatus { success, unavailable, unsupported, failed }

/// A spelling error, a narrowly scoped grammar error, or an advisory style rule.
enum OfficeProofingCategory { spelling, grammar, style }

final RegExp _proofingRegion = RegExp(r'^[A-Z]{2}$');
final RegExp _unicodeLocalePart = RegExp(
  r'^[a-z0-9]{3,8}$',
  caseSensitive: false,
);
final RegExp _unicodeLocaleKey = RegExp(
  r'^[a-z0-9][a-z]$',
  caseSensitive: false,
);

bool _hasUnicodeLocalePreferences(List<String> parts, int at) {
  if (at >= parts.length || parts[at] != 'u' || at + 1 >= parts.length) {
    return false;
  }
  final Set<String> attributes = <String>{};
  final Set<String> keys = <String>{};
  for (final String part in parts.skip(at + 1)) {
    if (_unicodeLocaleKey.hasMatch(part)) {
      if (!keys.add(part)) return false;
    } else if (_unicodeLocalePart.hasMatch(part)) {
      if (keys.isEmpty && !attributes.add(part)) return false;
    } else {
      return false;
    }
  }
  return true;
}

/// Canonical supported language tags; unknown tags remain visible to providers.
String normalizeProofingLanguage(String language) {
  // Layout asks for a language at every source position. Canonical host tags
  // take this allocation-free path; parsing is only needed for an alias.
  if (const <String>{
    'de-DE',
    'de-AT',
    'de-CH',
    'en-US',
    'en-GB',
    'en-CA',
    'en-AU',
    'en-IN',
  }.contains(language)) {
    return language;
  }
  final List<String> parts = language.trim().replaceAll('_', '-').split('-');
  final String base = parts.first.toLowerCase();
  final List<String> canonical = <String>[
    base,
    for (final String part in parts.skip(1))
      part.length == 2 ? part.toUpperCase() : part.toLowerCase(),
  ];
  if (base == 'de' || base == 'en') {
    // A Latin-script tag, the reformed German variant and Unicode locale
    // preferences do not select a different spelling dictionary. Recognize
    // only these aliases: historical orthography, other scripts and unknown
    // variants must remain unsupported, rather than silently becoming modern
    // German or American English.
    int at = 1;
    if (at < canonical.length && canonical[at] == 'latn') at++;
    String region = base == 'de' ? 'DE' : 'US';
    if (at < canonical.length && _proofingRegion.hasMatch(canonical[at])) {
      region = canonical[at++];
    }
    if (base == 'de' && at < canonical.length && canonical[at] == '1996') {
      at++;
    }
    if (_hasUnicodeLocalePreferences(canonical, at)) {
      at = canonical.length;
    }
    if (at == canonical.length) return '$base-$region';
  }
  return canonical.join('-');
}

/// Converts a backend's Unicode-scalar offset to Dart's UTF-16 coordinate.
/// Throws instead of clamping an invalid backend offset to unrelated text.
int scalarOffsetToUtf16(String text, int scalarOffset) {
  if (scalarOffset < 0) throw RangeError.value(scalarOffset, 'scalarOffset');
  int scalars = 0;
  int units = 0;
  for (final int rune in text.runes) {
    if (scalars == scalarOffset) return units;
    units += rune > 0xffff ? 2 : 1;
    scalars++;
  }
  if (scalars == scalarOffset) return units;
  throw RangeError.range(scalarOffset, 0, scalars, 'scalarOffset');
}

/// Immutable input snapshot. [text] may be a language-specific segment of a
/// block; [startOffset] is its UTF-16 origin within the whole logical block.
class OfficeProofingRequest {
  OfficeProofingRequest({
    required this.documentId,
    required this.blockId,
    required this.revision,
    required this.text,
    String language = 'de-DE',
    this.startOffset = 0,
    Set<String> ignoredRuleIds = const <String>{},
  }) : language = normalizeProofingLanguage(language),
       ignoredRuleIds = Set<String>.unmodifiable(ignoredRuleIds) {
    if (startOffset < 0) throw RangeError.value(startOffset, 'startOffset');
  }

  final String documentId;
  final String blockId;
  final int revision;
  final String text;
  final String language;
  final int startOffset;
  final Set<String> ignoredRuleIds;
}

/// A source-bound finding. Ranges are UTF-16 offsets in the WHOLE block.
/// Replacements are literal text for the indicated range, never automatic edits.
class OfficeProofingFinding {
  OfficeProofingFinding({
    required this.documentId,
    required this.blockId,
    required this.revision,
    required this.providerId,
    required this.start,
    required this.end,
    required this.originalText,
    required this.ruleId,
    required this.message,
    required this.category,
    List<String> replacements = const <String>[],
  }) : replacements = List<String>.unmodifiable(replacements);

  /// [start] and [end] here are RELATIVE to [request.text]. The stored finding
  /// adds [OfficeProofingRequest.startOffset] exactly once.
  factory OfficeProofingFinding.forRequest(
    OfficeProofingRequest request, {
    required String providerId,
    required int start,
    required int end,
    required String ruleId,
    required String message,
    required OfficeProofingCategory category,
    List<String> replacements = const <String>[],
  }) => OfficeProofingFinding(
    documentId: request.documentId,
    blockId: request.blockId,
    revision: request.revision,
    providerId: providerId,
    start: start + request.startOffset,
    end: end + request.startOffset,
    originalText: request.text.substring(start, end),
    ruleId: ruleId,
    message: message,
    category: category,
    replacements: replacements,
  );

  final String documentId;
  final String blockId;
  final int revision;
  final String providerId;
  final int start;
  final int end;
  final String originalText;
  final String ruleId;
  final String message;
  final OfficeProofingCategory category;
  final List<String> replacements;
}

/// One provider's result, including operational failure and unsupported locale.
class OfficeProofingResult {
  OfficeProofingResult({
    required this.request,
    required this.providerId,
    required this.status,
    List<OfficeProofingFinding> findings = const <OfficeProofingFinding>[],
    this.message,
  }) : findings = List<OfficeProofingFinding>.unmodifiable(findings);

  final OfficeProofingRequest request;
  final String providerId;
  final OfficeProofingStatus status;
  final List<OfficeProofingFinding> findings;
  final String? message;
}

/// Providers own their transport resources. Dispose terminates outstanding work
/// where the backend supports cancellation. Checkers must never modify text.
abstract class OfficeProofingProvider {
  String get id;
  int get configurationRevision => 0;
  bool supportsLanguage(String language);
  Future<OfficeProofingResult> check(OfficeProofingRequest request);
  Future<void> dispose() async {}
}

/// Checked provider results for a single immutable input snapshot.
class OfficeProofingReport {
  OfficeProofingReport({
    required this.request,
    required List<OfficeProofingResult> results,
  }) : results = List<OfficeProofingResult>.unmodifiable(results),
       findings = List<OfficeProofingFinding>.unmodifiable(
         <OfficeProofingFinding>[
           for (final OfficeProofingResult result in results)
             if (result.status == OfficeProofingStatus.success)
               ...result.findings,
         ]..sort((OfficeProofingFinding a, OfficeProofingFinding b) {
           final int byStart = a.start.compareTo(b.start);
           if (byStart != 0) return byStart;
           final int byEnd = a.end.compareTo(b.end);
           if (byEnd != 0) return byEnd;
           int priority(OfficeProofingCategory category) => switch (category) {
             OfficeProofingCategory.grammar => 0,
             OfficeProofingCategory.spelling => 1,
             OfficeProofingCategory.style => 2,
           };
           // Keep both review items; put contextual grammar before an edit-
           // distance spelling guess for the identical source word/range.
           return priority(a.category).compareTo(priority(b.category));
         }),
       );

  final OfficeProofingRequest request;
  final List<OfficeProofingResult> results;
  final List<OfficeProofingFinding> findings;

  /// Every applicable configured provider completed. Unsupported providers do
  /// not invalidate another language's checker, but at least one must succeed.
  bool get complete =>
      results.any(
        (OfficeProofingResult r) => r.status == OfficeProofingStatus.success,
      ) &&
      results.every(
        (OfficeProofingResult r) =>
            r.status == OfficeProofingStatus.success ||
            r.status == OfficeProofingStatus.unsupported,
      );
  bool get isClean => complete && findings.isEmpty;
}

/// Combines service-validated reports for the same immutable request.
///
/// Every [primary] finding keeps precedence. Secondary findings are accepted
/// in provider/result order only when they do not overlap a primary finding or
/// an earlier accepted secondary finding. An insertion conflicts with a range
/// at either endpoint, including another insertion at the same position.
/// Existing overlaps within [primary] are retained for individual review.
///
/// Each provider's status and message remain visible even when all of its
/// proposals are suppressed. This is the shared policy for the editor's manual
/// grammar lane and combined-provider qualification; it never applies edits.
/// The reports must share the identical request object and distinct provider
/// IDs. Source ranges must already have been checked by [OfficeProofingService].
OfficeProofingReport mergeOfficeProofingReports({
  required OfficeProofingReport primary,
  required OfficeProofingReport secondary,
}) {
  if (!identical(primary.request, secondary.request)) {
    throw ArgumentError('Proofing reports belong to different requests.');
  }
  final Set<String> providerIds = <String>{};
  for (final OfficeProofingResult result in <OfficeProofingResult>[
    ...primary.results,
    ...secondary.results,
  ]) {
    if (!identical(result.request, primary.request)) {
      throw ArgumentError('A provider result belongs to a different request.');
    }
    if (!providerIds.add(result.providerId)) {
      throw ArgumentError(
        'Duplicate proofing provider id: ${result.providerId}',
      );
    }
    if (result.status != OfficeProofingStatus.success &&
        result.findings.isNotEmpty) {
      throw ArgumentError('An incomplete provider result contains findings.');
    }
  }
  final List<OfficeProofingFinding> accepted = <OfficeProofingFinding>[
    ...primary.findings,
  ];
  final List<OfficeProofingResult> results = <OfficeProofingResult>[
    ...primary.results,
  ];
  for (final OfficeProofingResult result in secondary.results) {
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    for (final OfficeProofingFinding finding in result.findings) {
      if (accepted.any(
        (OfficeProofingFinding previous) =>
            _proofingFindingsConflict(previous, finding),
      )) {
        continue;
      }
      findings.add(finding);
      accepted.add(finding);
    }
    results.add(
      OfficeProofingResult(
        request: primary.request,
        providerId: result.providerId,
        status: result.status,
        findings: findings,
        message: result.message,
      ),
    );
  }
  return OfficeProofingReport(request: primary.request, results: results);
}

bool _proofingFindingsConflict(
  OfficeProofingFinding a,
  OfficeProofingFinding b,
) {
  if (a.start == a.end) return a.start >= b.start && a.start <= b.end;
  if (b.start == b.end) return b.start >= a.start && b.start <= a.end;
  return a.start < b.end && b.start < a.end;
}

/// Runs configured providers with a deadline, validates their output against
/// the original snapshot, and preserves each provider's operational status.
class OfficeProofingService {
  OfficeProofingService({
    required List<OfficeProofingProvider> providers,
    this.timeout = const Duration(seconds: 10),
  }) : providers = List<OfficeProofingProvider>.unmodifiable(providers) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    final Set<String> ids = <String>{};
    for (final OfficeProofingProvider provider in providers) {
      if (!ids.add(provider.id)) {
        throw ArgumentError('Duplicate proofing provider id: ${provider.id}');
      }
    }
  }

  final List<OfficeProofingProvider> providers;
  final Duration timeout;
  bool _disposed = false;
  final Set<OfficeProofingProvider> _timedOut = <OfficeProofingProvider>{};

  String get configurationKey => providers
      .map((OfficeProofingProvider p) => '${p.id}:${p.configurationRevision}')
      .join('|');

  Future<OfficeProofingReport> check(OfficeProofingRequest request) async {
    if (_disposed || providers.isEmpty) {
      return OfficeProofingReport(
        request: request,
        results: <OfficeProofingResult>[
          OfficeProofingResult(
            request: request,
            providerId: 'proofing',
            status: OfficeProofingStatus.unavailable,
            message: _disposed
                ? 'Proofing service is disposed.'
                : 'No proofing provider is configured.',
          ),
        ],
      );
    }
    final List<OfficeProofingResult> results = await Future.wait(
      providers.map(
        (OfficeProofingProvider provider) => _checkProvider(provider, request),
      ),
    );
    return OfficeProofingReport(request: request, results: results);
  }

  Future<OfficeProofingResult> _checkProvider(
    OfficeProofingProvider provider,
    OfficeProofingRequest request,
  ) async {
    OfficeProofingResult unavailable(String message) => OfficeProofingResult(
      request: request,
      providerId: provider.id,
      status: OfficeProofingStatus.unavailable,
      message: message,
    );
    if (_timedOut.contains(provider)) {
      return unavailable('Provider was disposed after exceeding its deadline.');
    }
    try {
      if (!provider.supportsLanguage(request.language)) {
        return OfficeProofingResult(
          request: request,
          providerId: provider.id,
          status: OfficeProofingStatus.unsupported,
          message: '${provider.id} does not support ${request.language}.',
        );
      }
      final OfficeProofingResult result = await provider
          .check(request)
          .timeout(timeout);
      if (_disposed) return unavailable('Proofing service is disposed.');
      final String? invalid = _invalidResult(provider, request, result);
      if (invalid != null) throw FormatException(invalid);
      return OfficeProofingResult(
        request: request,
        providerId: provider.id,
        status: result.status,
        findings: <OfficeProofingFinding>[
          for (final OfficeProofingFinding finding in result.findings)
            if (!request.ignoredRuleIds.contains(finding.ruleId)) finding,
        ],
        message: result.message,
      );
    } on TimeoutException {
      _timedOut.add(provider);
      // A failing disposal must not prevent the timeout result from returning.
      unawaited(Future<void>.sync(provider.dispose).catchError((Object _) {}));
      return OfficeProofingResult(
        request: request,
        providerId: provider.id,
        status: OfficeProofingStatus.failed,
        message: 'Provider exceeded the ${timeout.inMilliseconds} ms deadline.',
      );
    } catch (error) {
      return OfficeProofingResult(
        request: request,
        providerId: provider.id,
        status: OfficeProofingStatus.failed,
        message: 'Provider failed: $error',
      );
    }
  }

  static String? _invalidResult(
    OfficeProofingProvider provider,
    OfficeProofingRequest request,
    OfficeProofingResult result,
  ) {
    if (result.providerId != provider.id ||
        !identical(result.request, request)) {
      return 'Provider returned a result for a different request or provider.';
    }
    if (result.status != OfficeProofingStatus.success &&
        result.findings.isNotEmpty) {
      return 'An incomplete provider result must not contain findings.';
    }
    final Set<int> boundaries = <int>{0};
    int boundary = 0;
    for (final String cluster in request.text.characters) {
      boundary += cluster.length;
      boundaries.add(boundary);
    }
    for (final OfficeProofingFinding finding in result.findings) {
      final int start = finding.start - request.startOffset;
      final int end = finding.end - request.startOffset;
      if (finding.documentId != request.documentId ||
          finding.blockId != request.blockId ||
          finding.revision != request.revision ||
          finding.providerId != provider.id ||
          start < 0 ||
          end < start ||
          end > request.text.length ||
          !boundaries.contains(start) ||
          !boundaries.contains(end) ||
          request.text.substring(start, end) != finding.originalText) {
        return 'Provider returned an invalid or stale source range.';
      }
    }
    return null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(
      providers.map((OfficeProofingProvider provider) async {
        if (_timedOut.contains(provider)) return;
        try {
          await provider.dispose().timeout(timeout);
        } catch (_) {
          // Disposal is best effort; subsequent checks still report unavailable.
        }
      }),
    );
  }
}
