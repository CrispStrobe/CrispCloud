import 'dart:convert';

import 'package:path/path.dart' as p;

import 'custom_toolbar_command.dart';
import '../services/plugin_workspace.dart' show validatePluginId;

enum CommandExtensionCapability { toolbar, contextMenu }

/// A declarative list of commands, never downloaded Dart/native plugin code.
class CommandExtensionManifest {
  CommandExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required List<CustomToolbarCommand> commands,
    Set<CommandExtensionCapability> capabilities = const {
      CommandExtensionCapability.toolbar,
      CommandExtensionCapability.contextMenu,
    },
  }) : commands = List.unmodifiable(
         commands.map(
           (command) => CustomToolbarCommand.fromJson(command.toJson()),
         ),
       ),
       capabilities = Set.unmodifiable(capabilities) {
    validate();
  }
  final String id, name, version, description;
  final List<CustomToolbarCommand> commands;
  final Set<CommandExtensionCapability> capabilities;
  static const maxBytes = 1024 * 1024;

  static void validateCommand(CustomToolbarCommand command) {
    validatePluginId(command.id);
    command.validate();
    if (command.command.isNotEmpty) {
      throw const FormatException(
        'Command extensions require executable and argument definitions; legacy shell strings are unsupported.',
      );
    }
    final executable = command.executable.trim();
    if ((executable.contains('/') || executable.contains(r'\')) &&
        !p.posix.isAbsolute(executable) &&
        !p.windows.isAbsolute(executable)) {
      throw const FormatException(
        'Use an absolute installed executable path or a program name from PATH.',
      );
    }
  }

  void validate() {
    validatePluginId(id);
    if (name.trim().isEmpty ||
        name.length > 160 ||
        name.contains('\u0000') ||
        description.length > 4096 ||
        description.contains('\u0000') ||
        !RegExp(r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$').hasMatch(version) ||
        version.length > 80) {
      throw const FormatException(
        'Extensions require a short name, description and semantic version such as 1.0.0.',
      );
    }
    if (commands.isEmpty ||
        commands.length > 32 ||
        commands.map((command) => command.id).toSet().length !=
            commands.length) {
      throw const FormatException(
        'An extension requires 1–32 commands with unique IDs.',
      );
    }
    if (capabilities.isEmpty) {
      throw const FormatException(
        'Choose toolbar, contextMenu or both capabilities.',
      );
    }
    for (final command in commands) {
      validateCommand(command);
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxBytes) {
      throw const FormatException('Command extension manifests exceed 1 MiB.');
    }
  }

  Map<String, dynamic> toJson() => {
    'format': 'crispcloud.command-extension',
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'capabilities': capabilities.map((capability) => capability.name).toList(),
    'commands': commands.map((command) => command.toJson()).toList(),
  };
  String exportText() => const JsonEncoder.withIndent('  ').convert(toJson());
  CommandExtensionManifest withCommands(List<CustomToolbarCommand> commands) =>
      CommandExtensionManifest(
        id: id,
        name: name,
        version: version,
        description: description,
        commands: commands,
        capabilities: capabilities,
      );

  factory CommandExtensionManifest.fromJson(Map<String, dynamic> value) {
    if (value['format'] != 'crispcloud.command-extension' ||
        value['schemaVersion'] != 1) {
      throw const FormatException(
        'Unsupported command extension manifest. Native and Dart binary plugins cannot be installed from a manifest.',
      );
    }
    if (value.keys.any(
      (key) => !const {
        'format',
        'schemaVersion',
        'id',
        'name',
        'version',
        'description',
        'capabilities',
        'commands',
      }.contains(key),
    )) {
      throw const FormatException(
        'Unsupported manifest field. Background hooks, binary libraries and automatic installation scripts are not accepted.',
      );
    }
    return CommandExtensionManifest(
      id: value['id'] as String,
      name: value['name'] as String,
      version: value['version'] as String,
      description: value['description'] as String? ?? '',
      capabilities: (value['capabilities'] as List)
          .map(
            (value) =>
                CommandExtensionCapability.values.byName(value as String),
          )
          .toSet(),
      commands: (value['commands'] as List)
          .map(
            (value) => CustomToolbarCommand.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(),
    );
  }
  factory CommandExtensionManifest.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException(
        'Command extension manifests must be no larger than 1 MiB.',
      );
    }
    return CommandExtensionManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(text) as Map),
    );
  }
}

class InstalledCommandExtension {
  InstalledCommandExtension({
    required this.manifest,
    this.enabled = false,
    Map<String, CustomToolbarCommand> overrides = const {},
  }) : overrides = Map.unmodifiable(
         overrides.map(
           (id, command) =>
               MapEntry(id, CustomToolbarCommand.fromJson(command.toJson())),
         ),
       ) {
    for (final entry in this.overrides.entries) {
      if (entry.key != entry.value.id ||
          !manifest.commands.any((command) => command.id == entry.key)) {
        throw const FormatException(
          'An extension setting refers to an unknown command.',
        );
      }
      CommandExtensionManifest.validateCommand(entry.value);
    }
  }
  final CommandExtensionManifest manifest;
  final bool enabled;
  final Map<String, CustomToolbarCommand> overrides;
  List<CustomToolbarCommand> get commands => List.unmodifiable(
    manifest.commands.map((command) => overrides[command.id] ?? command),
  );
  InstalledCommandExtension copyWith({
    bool? enabled,
    Map<String, CustomToolbarCommand>? overrides,
  }) => InstalledCommandExtension(
    manifest: manifest,
    enabled: enabled ?? this.enabled,
    overrides: overrides ?? this.overrides,
  );
  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'enabled': enabled,
    'overrides': overrides.map((id, command) => MapEntry(id, command.toJson())),
  };
  factory InstalledCommandExtension.fromJson(Map<String, dynamic> value) =>
      InstalledCommandExtension(
        manifest: CommandExtensionManifest.fromJson(
          Map<String, dynamic>.from(value['manifest'] as Map),
        ),
        enabled: value['enabled'] == true,
        overrides: (value['overrides'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key as String,
            CustomToolbarCommand.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          ),
        ),
      );
}

/// An immutable action captured while building a menu or opening its review.
class CommandExtensionAction {
  CommandExtensionAction({
    required this.extensionId,
    required this.extensionName,
    required this.command,
    required this.generation,
    required this.owner,
  });
  final String extensionId, extensionName;
  final CustomToolbarCommand command;
  final int generation;
  final Object owner;
}
