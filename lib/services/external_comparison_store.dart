import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/external_comparison.dart';
import '../utils/async_lock.dart';

/// Preferences contain tool definitions only. Private session manifests live
/// with their staged files and never restore source-write authority.
class ExternalComparisonStore {
  ExternalComparisonStore(this.platform);
  final String platform;
  final _lock = AsyncLock();
  String get key => 'external_comparison_v1_$platform';

  Future<Map<ExternalComparisonKind, ExternalComparisonConfiguration>> load() =>
      _lock.synchronized(_load);

  Future<Map<ExternalComparisonKind, ExternalComparisonConfiguration>>
  _load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return {};
    try {
      if (raw.length > 128 * 1024) throw const FormatException();
      final json = jsonDecode(raw);
      if (json is! Map ||
          json['version'] != 1 ||
          json['tools'] is! List ||
          (json['tools'] as List).length > 2) {
        throw const FormatException();
      }
      final result =
          <ExternalComparisonKind, ExternalComparisonConfiguration>{};
      for (final value in json['tools'] as List) {
        final tool = ExternalComparisonConfiguration.fromJson(value);
        if (tool.platform != platform || result.containsKey(tool.kind)) {
          throw const FormatException();
        }
        result[tool.kind] = tool;
      }
      return result;
    } catch (_) {
      throw const ExternalComparisonException(
        ExternalComparisonFailure.storageFailed,
      );
    }
  }

  Future<void> save(ExternalComparisonConfiguration configuration) =>
      _lock.synchronized(() async {
        configuration.validate();
        if (configuration.platform != platform) {
          throw const ExternalComparisonException(
            ExternalComparisonFailure.invalidConfiguration,
          );
        }
        final current = await _load();
        current[configuration.kind] = configuration;
        if (!await (await SharedPreferences.getInstance()).setString(
          key,
          jsonEncode({
            'version': 1,
            'tools': current.values.map((tool) => tool.toJson()).toList(),
          }),
        )) {
          throw const ExternalComparisonException(
            ExternalComparisonFailure.storageFailed,
          );
        }
      });
}
