import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'multi_rename_service.dart';

/// Versioned, portable rule pipelines. Source paths and manual row names stay
/// in the batch journal, never in a reusable preset.
class RenamePresetStore {
  static const key = 'commander.multiRenamePresets.v1';
  Future<Map<String, MultiRenameOptions>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return {};
    return _options(jsonDecode(raw));
  }

  Future<void> save(Map<String, MultiRenameOptions> presets) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(
        presets.map((name, options) => MapEntry(name, options.toJson())),
      ),
    )) {
      throw StateError('Rename presets could not be saved.');
    }
  }

  String export(Map<String, MultiRenameOptions> presets) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'CrispCloud rename presets',
        'version': 2,
        'presets': presets.map(
          (name, options) => MapEntry(name, options.toJson()),
        ),
      });
  Map<String, MultiRenameOptions> import(String text) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Preset import is limited to 2 MiB.');
    }
    final value = jsonDecode(text);
    if (value is! Map ||
        value['format'] != 'CrispCloud rename presets' ||
        ![1, 2].contains(value['version'])) {
      throw const FormatException(
        'Choose a supported CrispCloud rename preset export.',
      );
    }
    return _options(value['presets']);
  }

  Map<String, MultiRenameOptions> _options(Object? value) {
    if (value is! Map || value.length > 1000) {
      throw const FormatException('Invalid rename preset collection.');
    }
    final result = <String, MultiRenameOptions>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).length > 80 ||
          entry.value is! Map) {
        throw const FormatException(
          'A preset needs a name and transformation settings.',
        );
      }
      final options = Map<String, dynamic>.from(entry.value as Map);
      final steps = options['additionalSteps'];
      if (steps is List &&
          (steps.length > 100 ||
              steps.any(
                (step) =>
                    step is! Map ||
                    (step['additionalSteps'] is List &&
                        (step['additionalSteps'] as List).isNotEmpty),
              ))) {
        throw const FormatException(
          'Preset pipelines support up to 100 flat additional steps.',
        );
      }
      result[entry.key as String] = MultiRenameOptions.fromJson(options);
    }
    return result;
  }
}
