// lib/config/cli_config.dart
//
// Config file management for the crisp CLI.
// Credentials are stored at ~/.config/crispcloud/config.yaml
// (or $XDG_CONFIG_HOME/crispcloud/config.yaml on Linux).
//
// Format:
// ---
// default_provider: my-s3
// providers:
//   my-s3:
//     type: s3
//     access_key: AKIAIOSFODNN7EXAMPLE
//     secret_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
//     endpoint: https://s3.amazonaws.com
//     bucket: mybucket
//     region: us-east-1
//   my-sftp:
//     type: sftp
//     username: user
//     password: secret
//     host: example.com
//     port: 22
//   my-dav:
//     type: webdav
//     username: user
//     password: secret
//     host: https://dav.example.com

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Manages reading and writing the CLI config file.
class CliConfig {
  late final String configPath;

  CliConfig({String? path}) {
    configPath = path ?? _defaultConfigPath();
  }

  // ---------------------------------------------------------------------------
  // Path resolution
  // ---------------------------------------------------------------------------

  static String _defaultConfigPath() {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      return p.join(xdg, 'crispcloud', 'config.yaml');
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.config', 'crispcloud', 'config.yaml');
  }

  // ---------------------------------------------------------------------------
  // Raw YAML read/write
  // ---------------------------------------------------------------------------

  /// Read and parse the config file. Returns an empty map if the file does not
  /// exist or cannot be parsed.
  Map<String, dynamic> read() {
    final file = File(configPath);
    if (!file.existsSync()) return {};
    try {
      final content = file.readAsStringSync();
      if (content.trim().isEmpty) return {};
      final doc = loadYaml(content);
      if (doc == null) return {};
      return _yamlToMap(doc as YamlMap);
    } catch (e) {
      stderr.writeln('Warning: could not parse config at $configPath: $e');
      return {};
    }
  }

  /// Write the config map back to disk as YAML.
  void write(Map<String, dynamic> config) {
    final file = File(configPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_toYaml(config));
  }

  // ---------------------------------------------------------------------------
  // Providers
  // ---------------------------------------------------------------------------

  /// Return all configured provider names.
  List<String> providerNames() {
    final config = read();
    final providers = config['providers'] as Map<String, dynamic>? ?? {};
    return providers.keys.toList()..sort();
  }

  /// Return the config map for a named provider, or null if not found.
  Map<String, dynamic>? providerConfig(String name) {
    final config = read();
    final providers = config['providers'] as Map<String, dynamic>? ?? {};
    final raw = providers[name];
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  /// Save or overwrite a provider config entry.
  void saveProvider(String name, Map<String, dynamic> providerData) {
    final config = read();
    final providers =
        Map<String, dynamic>.from(config['providers'] as Map? ?? {});
    providers[name] = providerData;
    config['providers'] = providers;
    write(config);
  }

  /// Remove a provider entry.
  void removeProvider(String name) {
    final config = read();
    final providers =
        Map<String, dynamic>.from(config['providers'] as Map? ?? {});
    providers.remove(name);
    config['providers'] = providers;
    // If removed provider was the default, clear default
    if (config['default_provider'] == name) {
      config.remove('default_provider');
    }
    write(config);
  }

  /// Get the default provider name (null if not set).
  String? get defaultProvider {
    final config = read();
    return config['default_provider'] as String?;
  }

  /// Set the default provider name.
  set defaultProvider(String? name) {
    final config = read();
    if (name == null) {
      config.remove('default_provider');
    } else {
      config['default_provider'] = name;
    }
    write(config);
  }

  /// Resolve a provider name: returns [name] if given, else [defaultProvider],
  /// throws a [CliConfigException] if neither is set.
  String resolveProviderName(String? name) {
    final resolved = name ?? defaultProvider;
    if (resolved == null) {
      throw CliConfigException(
        'No provider specified and no default provider configured.\n'
        'Run: crisp connect <type> <identity> --name <name> --default',
      );
    }
    return resolved;
  }

  // ---------------------------------------------------------------------------
  // YAML serialisation helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _yamlToMap(YamlMap yaml) {
    final result = <String, dynamic>{};
    for (final key in yaml.keys) {
      final value = yaml[key];
      if (value is YamlMap) {
        result[key.toString()] = _yamlToMap(value);
      } else if (value is YamlList) {
        result[key.toString()] = _yamlToList(value);
      } else {
        result[key.toString()] = value;
      }
    }
    return result;
  }

  List<dynamic> _yamlToList(YamlList yaml) {
    return yaml.map((item) {
      if (item is YamlMap) return _yamlToMap(item);
      if (item is YamlList) return _yamlToList(item);
      return item;
    }).toList();
  }

  /// Naive YAML emitter (avoids a yaml_writer dependency).
  /// Handles only the simple structures we need (maps/lists/scalars).
  String _toYaml(Map<String, dynamic> map, {int indent = 0}) {
    final sb = StringBuffer();
    final pad = '  ' * indent;
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        sb.writeln('$pad${_yamlKey(entry.key)}:');
        sb.write(_toYaml(value, indent: indent + 1));
      } else if (value is List) {
        sb.writeln('$pad${_yamlKey(entry.key)}:');
        for (final item in value) {
          sb.writeln('$pad  - ${_yamlScalar(item)}');
        }
      } else if (value == null) {
        sb.writeln('$pad${_yamlKey(entry.key)}: ~');
      } else {
        sb.writeln('$pad${_yamlKey(entry.key)}: ${_yamlScalar(value)}');
      }
    }
    return sb.toString();
  }

  String _yamlKey(String key) {
    // Quote keys containing special chars
    if (RegExp(r'[:#{}[\],&*?|<>=!%@`]').hasMatch(key)) {
      return jsonEncode(key);
    }
    return key;
  }

  String _yamlScalar(dynamic value) {
    if (value is String) {
      // Quote if needed
      if (value.contains(':') ||
          value.contains('#') ||
          value.startsWith(' ') ||
          value.endsWith(' ') ||
          value.isEmpty) {
        return jsonEncode(value);
      }
      return value;
    }
    return '$value';
  }
}

class CliConfigException implements Exception {
  final String message;
  CliConfigException(this.message);

  @override
  String toString() => message;
}
