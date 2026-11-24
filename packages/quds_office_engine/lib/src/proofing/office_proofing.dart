import 'dart:async';

import '../bidi/grapheme_clusters.dart';

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

  /// The finding categories this provider can report. Editors use it to
  /// schedule work: a provider that reports only
  /// [OfficeProofingCategory.spelling] can run when a word is completed,
  /// others when a sentence is completed or typing pauses. The default
  /// claims every category.
  Set<OfficeProofingCategory> get categories =>
      OfficeProofingCategory.values.toSet();
  bool supportsLanguage(String language);

  /// Loads shared, one-time resources (dictionaries, models) without checking
  /// text. [OfficeProofingService] awaits it before starting a request's
  /// deadline, so a cold start is not charged to whichever request happens to
  /// come first. Implementations must make repeated calls cheap.
  Future<void> warmUp() async {}

  Future<OfficeProofingResult> check(OfficeProofingRequest request);
  Future<void> dispose() async {}
}

int _categoryPriority(OfficeProofingCategory category) => switch (category) {
  OfficeProofingCategory.grammar => 0,
  OfficeProofingCategory.spelling => 1,
  OfficeProofingCategory.style => 2,
};

// One ordered provider list needs no sorting or cross-provider merge when
// each finding has a distinct start. Equal starts still need range and
// category ordering, including zero-width punctuation suggestions.
List<OfficeProofingFinding>? _orderedFindingsFromOneResult(
  List<OfficeProofingResult> results,
) {
  List<OfficeProofingFinding>? findings;
  for (final result in results) {
    if (result.status != OfficeProofingStatus.success) continue;
    final reported = result.findings;
    if (reported.isEmpty) continue;
    if (findings != null) return null;
    findings = reported;
  }
  if (findings == null) return const [];
  for (var index = 1; index < findings.length; index++) {
    if (findings[index - 1].start >= findings[index].start) return null;
  }
  return findings;
}

/// Successful findings in source order. Findings of different providers with
/// the same category for the identical range and text that agree on at least
/// one replacement are one review item: the first in provider order in
/// [results] keeps its rule and message, and the other findings' extra
/// replacements follow its own (e.g. an Arabic hamza rule and a dictionary
/// both correcting `الى` to `إلى`). Findings of different categories stay
/// separate, contextual grammar before an edit-distance spelling guess for
/// the identical source word, as do disagreeing findings.
List<OfficeProofingFinding> _mergeAgreeingFindings(
  List<OfficeProofingResult> results,
) {
  final ordered = _orderedFindingsFromOneResult(results);
  if (ordered != null) return ordered;

  final providerOrder = <String, int>{};
  final all = <OfficeProofingFinding>[];
  Map<OfficeProofingFinding, int>? findingOrder;
  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    if (result.status != OfficeProofingStatus.success) continue;
    final findings = result.findings;
    if (findings.isEmpty) continue;
    if (findingOrder == null) {
      final provider = result.providerId;
      // Direct report callers can repeat providers or supply custom findings.
      // Use the earlier provider indices to recover their per-finding order.
      if (providerOrder.containsKey(provider) ||
          findings.any(
            (finding) =>
                finding.runtimeType != OfficeProofingFinding ||
                finding.providerId != provider,
          )) {
        findingOrder = {
          for (final finding in all)
            finding: providerOrder[finding.providerId]!,
        };
      } else {
        providerOrder[provider] = index;
      }
    }
    if (findingOrder != null) {
      for (final finding in findings) {
        findingOrder[finding] = index;
      }
    }
    all.addAll(findings);
  }

  final orderByFinding = findingOrder;
  int compare(OfficeProofingFinding a, OfficeProofingFinding b) {
    final int byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    final int byEnd = a.end.compareTo(b.end);
    if (byEnd != 0) return byEnd;
    final int byCategory = _categoryPriority(
      a.category,
    ).compareTo(_categoryPriority(b.category));
    if (byCategory != 0) return byCategory;
    return orderByFinding == null
        ? providerOrder[a.providerId]!.compareTo(providerOrder[b.providerId]!)
        : orderByFinding[a]!.compareTo(orderByFinding[b]!);
  }

  all.sort(compare);
  // Compact the sorted scratch list. Only actual merges need bookkeeping.
  var writeAt = 0;
  Set<OfficeProofingFinding>? absorbed;
  for (var i = 0; i < all.length; i++) {
    final kept = all[i];
    if (absorbed?.contains(kept) ?? false) continue;
    var replacements = kept.replacements;
    if (replacements.isEmpty) {
      all[writeAt++] = kept;
      continue;
    }
    Set<String>? providers;
    for (var j = i + 1; j < all.length; j++) {
      final other = all[j];
      if (other.start != kept.start || other.end != kept.end) break;
      if ((absorbed?.contains(other) ?? false) ||
          other.providerId == kept.providerId ||
          (providers?.contains(other.providerId) ?? false) ||
          other.category != kept.category ||
          other.originalText != kept.originalText ||
          !other.replacements.any(replacements.contains)) {
        continue;
      }
      (absorbed ??= {}).add(other);
      (providers ??= {}).add(other.providerId);
      replacements = [
        ...replacements,
        for (final value in other.replacements)
          if (!replacements.contains(value)) value,
      ];
    }
    all[writeAt++] = identical(replacements, kept.replacements)
        ? kept
        : OfficeProofingFinding(
            documentId: kept.documentId,
            blockId: kept.blockId,
            revision: kept.revision,
            providerId: kept.providerId,
            start: kept.start,
            end: kept.end,
            originalText: kept.originalText,
            ruleId: kept.ruleId,
            message: kept.message,
            category: kept.category,
            replacements: replacements,
          );
  }
  all.length = writeAt;
  return all;
}

/// Checked provider results for a single immutable input snapshot.
class OfficeProofingReport {
  OfficeProofingReport({
    required this.request,
    required List<OfficeProofingResult> results,
  }) : results = List<OfficeProofingResult>.unmodifiable(results),
       findings = List<OfficeProofingFinding>.unmodifiable(
         _mergeAgreeingFindings(results),
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
    this.warmUpTimeout = const Duration(minutes: 2),
    this.disposeOnTimeout = true,
  }) : providers = List<OfficeProofingProvider>.unmodifiable(providers) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    if (warmUpTimeout <= Duration.zero) {
      throw ArgumentError.value(warmUpTimeout, 'warmUpTimeout');
    }
    final Set<String> ids = <String>{};
    for (final OfficeProofingProvider provider in providers) {
      if (!ids.add(provider.id)) {
        throw ArgumentError('Duplicate proofing provider id: ${provider.id}');
      }
    }
  }

  final List<OfficeProofingProvider> providers;

  /// Deadline of one provider's [OfficeProofingProvider.check].
  final Duration timeout;

  /// Separate bound for [OfficeProofingProvider.warmUp], which runs before
  /// [timeout] starts. A slow warm-up reports a failed result but does not
  /// dispose the provider; the next request awaits the same load.
  final Duration warmUpTimeout;

  /// Keep a bounded, isolated provider usable after an individual request
  /// misses its deadline, such as when a shared worker queue is temporarily
  /// busy. In-process providers are retired on timeout by default.
  final bool disposeOnTimeout;
  bool _disposed = false;
  final Set<OfficeProofingProvider> _timedOut = <OfficeProofingProvider>{};

  String get configurationKey => providers
      .map((OfficeProofingProvider p) => '${p.id}:${p.configurationRevision}')
      .join('|');

  /// Checks [request] with every provider, or only with the providers
  /// accepted by [only]. A filtered report omits the other providers'
  /// results; callers merge it with their results for the same text.
  Future<OfficeProofingReport> check(
    OfficeProofingRequest request, {
    bool Function(OfficeProofingProvider provider)? only,
  }) async {
    final List<OfficeProofingProvider> selected = only == null
        ? providers
        : providers.where(only).toList(growable: false);
    if (_disposed || selected.isEmpty) {
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
    final boundaries = GraphemeBoundaries(request.text);
    final List<OfficeProofingResult> results = await Future.wait(
      selected.map((provider) => _checkProvider(provider, request, boundaries)),
    );
    return OfficeProofingReport(request: request, results: results);
  }

  Future<OfficeProofingResult> _checkProvider(
    OfficeProofingProvider provider,
    OfficeProofingRequest request,
    GraphemeBoundaries boundaries,
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
      try {
        await provider.warmUp().timeout(warmUpTimeout);
      } on TimeoutException {
        return OfficeProofingResult(
          request: request,
          providerId: provider.id,
          status: OfficeProofingStatus.failed,
          message:
              'Provider did not finish loading within '
              '${warmUpTimeout.inMilliseconds} ms.',
        );
      }
      if (_disposed) return unavailable('Proofing service is disposed.');
      final OfficeProofingResult result = await provider
          .check(request)
          .timeout(timeout);
      if (_disposed) return unavailable('Proofing service is disposed.');
      final String? invalid = _invalidResult(
        provider,
        request,
        result,
        boundaries,
      );
      if (invalid != null) throw FormatException(invalid);
      // Reuse the built-in immutable result after validation when it needs no
      // filtering. Custom result implementations still get copied.
      if (result.runtimeType == OfficeProofingResult &&
          (result.findings.isEmpty || request.ignoredRuleIds.isEmpty)) {
        return result;
      }
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
      if (disposeOnTimeout) {
        _timedOut.add(provider);
        // A failing disposal must not prevent the timeout result from returning.
        unawaited(
          Future<void>.sync(provider.dispose).catchError((Object _) {}),
        );
      }
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
    GraphemeBoundaries boundaries,
  ) {
    if (result.providerId != provider.id ||
        !identical(result.request, request)) {
      return 'Provider returned a result for a different request or provider.';
    }
    if (result.status != OfficeProofingStatus.success &&
        result.findings.isNotEmpty) {
      return 'An incomplete provider result must not contain findings.';
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
          end - start != finding.originalText.length ||
          !request.text.startsWith(finding.originalText, start)) {
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
