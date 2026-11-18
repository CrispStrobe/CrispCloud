import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Optional Android/iOS system spelling, with host-declared installed locales.
/// Flutter does not expose a reliable installed-dictionary enumeration. The host
/// must supply only languages it has established are usable on this device.
final class OfficePlatformSpellingProvider extends OfficeProofingProvider {
  OfficePlatformSpellingProvider({
    required Iterable<String> supportedLanguages,
    SpellCheckService? service,
    bool Function()? isAvailable,
    this.timeout = const Duration(seconds: 10),
  }) : _languages = supportedLanguages.map(normalizeProofingLanguage).toSet(),
       _service = service ?? DefaultSpellCheckService(),
       _isAvailable = isAvailable ?? _nativeAvailable,
       _scheduler = _schedulerFor(service) {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  }

  final Set<String> _languages;
  final SpellCheckService _service;
  final bool Function() _isAvailable;
  final _SpellingScheduler _scheduler;
  final Duration timeout;
  bool _disposed = false;

  // Every default service uses the same native channel, including services
  // owned by different documents. A custom service has its own lane unless the
  // host explicitly shares that same instance between providers.
  static final _systemScheduler = _SpellingScheduler();
  static final _customSchedulers = Expando<_SpellingScheduler>();
  static _SpellingScheduler _schedulerFor(SpellCheckService? service) =>
      service == null || service is DefaultSpellCheckService
      ? _systemScheduler
      : (_customSchedulers[service] ??= _SpellingScheduler());

  static final _language = RegExp(r'^[a-z]{2,8}$');
  static final _script = RegExp(r'^[a-z]{4}$');
  static final _region = RegExp(r'^(?:[A-Z]{2}|[0-9]{3})$');
  static final _identifierLeading = RegExp(r'[\p{N}\p{Pc}]', unicode: true);
  static final _visibleSuggestionText = RegExp(
    r'[^\p{M}\p{Cf}\p{Z}]',
    unicode: true,
  );

  /// Preserve backend order while keeping the review list useful and bounded.
  /// A spelling suggestion must not become an empty Delete action or insert
  /// malformed text/control characters. Internal spaces and script joiners are
  /// legitimate in spelling corrections and are kept verbatim.
  static List<String> _suggestionsFor(
    String original,
    List<String> suggestions,
  ) {
    final accepted = <String>{};
    for (final suggestion in suggestions.take(64)) {
      if (suggestion.isEmpty ||
          suggestion.length > 256 ||
          suggestion == original ||
          suggestion.trim().isEmpty ||
          !_visibleSuggestionText.hasMatch(suggestion) ||
          accepted.contains(suggestion) ||
          !_isPlainText(suggestion)) {
        continue;
      }
      accepted.add(suggestion);
      if (accepted.length == 8) break;
    }
    return accepted.toList(growable: false);
  }

  static bool _isPlainText(String value) {
    for (var at = 0; at < value.length; at++) {
      final unit = value.codeUnitAt(at);
      if (unit <= 0x1f ||
          unit >= 0x7f && unit <= 0x9f ||
          unit == 0x2028 ||
          unit == 0x2029 ||
          unit >= 0x202a && unit <= 0x202e ||
          unit >= 0x2066 && unit <= 0x2069) {
        return false;
      }
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++at == value.length) return false;
        final low = value.codeUnitAt(at);
        if (low < 0xdc00 || low > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  /// Flutter Locale can represent language, script and region, not variants or
  /// arbitrary extensions. Never silently discard an unrepresentable part and
  /// ask a different dictionary. Reviewed English/German aliases have already
  /// been resolved by normalizeProofingLanguage.
  static Locale? _localeFor(String language) {
    final parts = normalizeProofingLanguage(language).split('-');
    if (!_language.hasMatch(parts.first)) return null;
    var at = 1;
    String? script;
    String? region;
    if (at < parts.length && _script.hasMatch(parts[at])) {
      final value = parts[at++];
      script = '${value[0].toUpperCase()}${value.substring(1)}';
    }
    if (at < parts.length && _region.hasMatch(parts[at])) {
      region = parts[at++];
    }
    if (at != parts.length) return null;
    return Locale.fromSubtags(
      languageCode: parts.first,
      scriptCode: script,
      countryCode: region,
    );
  }

  static bool _nativeAvailable() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      PlatformDispatcher.instance.nativeSpellCheckServiceDefined;

  @override
  String get id => 'platform-spelling';

  @override
  bool supportsLanguage(String language) =>
      _languages.contains(normalizeProofingLanguage(language)) &&
      _localeFor(language) != null;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    OfficeProofingResult result(OfficeProofingStatus status, String message) =>
        OfficeProofingResult(
          request: request,
          providerId: id,
          status: status,
          message: message,
        );
    if (_disposed || !_isAvailable()) {
      return result(
        OfficeProofingStatus.unavailable,
        'System spelling is unavailable on this device.',
      );
    }
    if (!supportsLanguage(request.language)) {
      return result(
        OfficeProofingStatus.unsupported,
        'No installed dictionary is configured for this exact language.',
      );
    }
    try {
      final locale = _localeFor(request.language)!;
      final spans = await _scheduler.run(
        owner: this,
        timeout: timeout,
        onTimeout: () {
          // Retire before another timer at the same deadline can run. Sibling
          // requests become unavailable, rather than independently failing.
          _disposed = true;
          _scheduler.cancel(this);
        },
        action: () {
          final service = _service;
          // Clear this only once the previous native request has completed;
          // that request can still update the framework's text-only cache.
          if (service is DefaultSpellCheckService) {
            service.lastSavedResults = null;
          }
          return service.fetchSpellCheckSuggestions(locale, request.text);
        },
      );
      if (_disposed) {
        return result(
          OfficeProofingStatus.unavailable,
          'System spelling has been disposed.',
        );
      }
      if (spans == null) {
        return result(
          OfficeProofingStatus.failed,
          'The system spell checker could not complete this request.',
        );
      }
      final findings = <OfficeProofingFinding>[];
      final protected = OfficeProofingTextRanges(request.text);
      final boundaries = <int>{0};
      final identifierStarts = <int>{};
      final identifierEnds = <int>{};
      for (final cluster in GraphemeClusters.segment(request.text)) {
        boundaries.add(cluster.end);
        // A digit/connector and its combining marks form one identifier edge.
        // Reuse grapheme segmentation so an arbitrarily long marked edge does
        // not require copying or rescanning a prefix for each native finding.
        if (_identifierLeading.matchAsPrefix(request.text, cluster.start) !=
            null) {
          identifierStarts.add(cluster.start);
          identifierEnds.add(cluster.end);
        }
      }
      if (!request.ignoredRuleIds.contains('platform.spelling')) {
        for (final span in spans) {
          if (span.range.start < 0 ||
              span.range.end > request.text.length ||
              span.range.end <= span.range.start ||
              !boundaries.contains(span.range.start) ||
              !boundaries.contains(span.range.end)) {
            throw const FormatException('Invalid platform spelling range.');
          }
          // An OS dictionary may report only the letter portion of foo42 or
          // snake_case. Do not turn that into a partial identifier edit. Letter
          // adjacency is deliberately allowed: CJK dictionaries can return a
          // valid word from a continuous passage, and hyphen parts are words.
          if (protected.overlaps(span.range.start, span.range.end) ||
              identifierEnds.contains(span.range.start) ||
              identifierStarts.contains(span.range.end)) {
            continue;
          }
          final original = request.text.substring(
            span.range.start,
            span.range.end,
          );
          findings.add(
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: span.range.start,
              end: span.range.end,
              ruleId: 'platform.spelling',
              message: 'The system dictionary does not recognize this word.',
              category: OfficeProofingCategory.spelling,
              replacements: _suggestionsFor(original, span.suggestions),
            ),
          );
        }
      }
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: findings,
      );
    } on TimeoutException {
      _disposed = true;
      _scheduler.cancel(this);
      return result(
        OfficeProofingStatus.failed,
        'System spelling timed out. An unfinished system check must complete '
        'before retrying with a new provider.',
      );
    } on _SpellingDisposed {
      return result(
        OfficeProofingStatus.unavailable,
        'System spelling has been disposed.',
      );
    } on Object catch (error) {
      return result(
        OfficeProofingStatus.failed,
        'System spelling failed: $error',
      );
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _scheduler.cancel(this);
  }
}

final class _SpellingDisposed implements Exception {
  const _SpellingDisposed();
}

/// Owns physical channel occupancy separately from each caller's deadline.
/// Flutter exposes no cancellation for native spell checks. A timeout/disposal
/// settles the caller but cannot free the native slot. Queued callers have
/// their own timers, so even a permanently stuck OS call cannot hang them.
final class _SpellingScheduler {
  final _queue = ListQueue<_SpellingCall>();
  _SpellingCall? _active;

  Future<List<SuggestionSpan>?> run({
    required Object owner,
    required Duration timeout,
    required void Function() onTimeout,
    required Future<List<SuggestionSpan>?> Function() action,
  }) {
    final call = _SpellingCall(owner, action);
    call.timer = Timer(timeout, () {
      _queue.remove(call);
      call.fail(
        TimeoutException('System spelling deadline exceeded.', timeout),
      );
      onTimeout();
    });
    _queue.add(call);
    _pump();
    return call.result.future;
  }

  void cancel(Object owner) {
    for (final call in _queue.toList(growable: false)) {
      if (!identical(call.owner, owner)) continue;
      _queue.remove(call);
      call.fail(const _SpellingDisposed());
    }
    final active = _active;
    if (active != null && identical(active.owner, owner)) {
      active.fail(const _SpellingDisposed());
    }
  }

  void _pump() {
    if (_active != null || _queue.isEmpty) return;
    final call = _active = _queue.removeFirst();
    Future<List<SuggestionSpan>?>.sync(call.action).then(
      (spans) {
        call.timer.cancel();
        if (!call.result.isCompleted) call.result.complete(spans);
        _active = null;
        _pump();
      },
      onError: (Object error, StackTrace stack) {
        call.timer.cancel();
        if (!call.result.isCompleted) call.result.completeError(error, stack);
        _active = null;
        _pump();
      },
    );
  }
}

final class _SpellingCall {
  _SpellingCall(this.owner, this.action);

  final Object owner;
  final Future<List<SuggestionSpan>?> Function() action;
  final result = Completer<List<SuggestionSpan>?>();
  late final Timer timer;

  void fail(Object error) {
    timer.cancel();
    if (!result.isCompleted) result.completeError(error);
  }
}
