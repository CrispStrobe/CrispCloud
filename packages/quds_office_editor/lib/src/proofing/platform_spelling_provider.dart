import 'dart:async';
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
       _isAvailable = isAvailable ?? _nativeAvailable;

  final Set<String> _languages;
  final SpellCheckService _service;
  final bool Function() _isAvailable;
  final Duration timeout;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  static bool _nativeAvailable() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      PlatformDispatcher.instance.nativeSpellCheckServiceDefined;

  @override
  String get id => 'platform-spelling';

  @override
  bool supportsLanguage(String language) =>
      _languages.contains(normalizeProofingLanguage(language));

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) {
    // Flutter's spell-check channel allows one outstanding request. Queue even
    // independent paragraphs so a busy channel never looks like a clean result.
    final result = _queue.then((_) => _check(request));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<OfficeProofingResult> _check(OfficeProofingRequest request) async {
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
        'The host has not declared an installed dictionary for this language.',
      );
    }
    try {
      final parts = normalizeProofingLanguage(request.language).split('-');
      final locale = Locale.fromSubtags(
        languageCode: parts.first,
        countryCode: parts.length > 1 && parts.last.length == 2
            ? parts.last
            : null,
        scriptCode: parts.length > 1 && parts[1].length == 4 ? parts[1] : null,
      );
      final service = _service;
      // The framework cache is text-based and does not include locale. Never
      // carry one paragraph/language's cached results into another request.
      if (service is DefaultSpellCheckService) service.lastSavedResults = null;
      final spans = await service
          .fetchSpellCheckSuggestions(locale, request.text)
          .timeout(timeout);
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
      if (!request.ignoredRuleIds.contains('platform.spelling')) {
        for (final span in spans) {
          if (span.range.start < 0 ||
              span.range.end > request.text.length ||
              span.range.end <= span.range.start) {
            throw const FormatException('Invalid platform spelling range.');
          }
          findings.add(
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: span.range.start,
              end: span.range.end,
              ruleId: 'platform.spelling',
              message: 'The system dictionary does not recognize this word.',
              category: OfficeProofingCategory.spelling,
              replacements: span.suggestions.take(8).toList(),
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
      return result(
        OfficeProofingStatus.failed,
        'System spelling timed out; configure a new provider to retry.',
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
  }
}
