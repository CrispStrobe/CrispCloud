import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/extension_translations.dart';
import '../models/command_extension.dart';
import '../models/custom_toolbar_command.dart';
import '../models/panel_side.dart';
import '../providers/command_extension_provider.dart';
import '../providers/plugin_provider.dart';
import 'command_extension_actions.dart';
import 'custom_command_dialog.dart';
import 'rename_text_dialog.dart';

Future<void> showExtensionsDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) => showDialog<void>(
  context: context,
  builder: (_) => ExtensionsDialog(side: side),
);

class ExtensionsDialog extends ConsumerStatefulWidget {
  const ExtensionsDialog({super.key, required this.side});
  final PanelSide side;
  @override
  ConsumerState<ExtensionsDialog> createState() => _ExtensionsDialogState();
}

class _ExtensionsDialogState extends ConsumerState<ExtensionsDialog> {
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.microtask(
        () => _change(() async {
          await ref.read(commandExtensionStoreProvider).ready;
          await ref.read(pluginRegistryProvider).initializeAll();
        }),
      ),
    );
  }

  Future<void> _change(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => RenameTextDialog(
        title: context.extensionTr('Import manifest'),
        instructions: context.extensionTr(
          'Paste or load a command extension JSON manifest.',
        ),
        initialText: '',
        submitLabel: context.extensionTr('Review extension'),
        fileExtensions: const ['json'],
        filename: 'extension.json',
        validate: (value) {
          try {
            CommandExtensionManifest.decode(value);
            return null;
          } catch (error) {
            return '$error';
          }
        },
      ),
    );
    if (text == null || !mounted) return;
    try {
      final manifest = CommandExtensionManifest.decode(text);
      final store = ref.read(commandExtensionStoreProvider);
      final replacing = store.get(manifest.id) != null;
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            ExtensionReviewDialog(manifest: manifest, replacing: replacing),
      );
      if (approved == true && mounted) {
        await _change(() => store.install(manifest, replace: replacing));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _configure(String id, CustomToolbarCommand command) async {
    final edited = await showDialog<CustomToolbarCommand>(
      context: context,
      builder: (_) => CustomCommandEditor(command: command),
    );
    if (edited != null && mounted) {
      await _change(
        () => ref.read(commandExtensionStoreProvider).configure(id, edited),
      );
    }
  }

  Future<void> _export(String id) async {
    try {
      final text = ref.read(commandExtensionStoreProvider).exportManifest(id);
      await showDialog<String>(
        context: context,
        builder: (_) => RenameTextDialog(
          title: context.extensionTr('Export manifest'),
          instructions: context.extensionTr(
            'This manifest includes the current command settings.',
          ),
          initialText: text,
          submitLabel: context.extensionTr('Done'),
          fileExtensions: const ['json'],
          filename: '$id.json',
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _pluginSettings(CrispCloudPlugin plugin) async {
    final registry = ref.read(pluginRegistryProvider);
    final current = registry.getPluginSettings(plugin.id)?.settings ?? {};
    final text = await showDialog<String>(
      context: context,
      builder: (_) => RenameTextDialog(
        title: context.extensionTr('Plugin settings'),
        instructions: context.extensionTr(
          'Saving settings restarts an enabled plugin.',
        ),
        initialText: const JsonEncoder.withIndent('  ').convert(current),
        submitLabel: context.extensionTr('Save'),
        filename: '${plugin.id}-settings.json',
        fileExtensions: const ['json'],
        validate: (value) {
          try {
            if (utf8.encode(value).length > 1024 * 1024 ||
                jsonDecode(value) is! Map<String, dynamic>) {
              throw const FormatException(
                'Use a JSON object no larger than 1 MiB.',
              );
            }
            return null;
          } catch (error) {
            return '$error';
          }
        },
      ),
    );
    if (text != null && mounted) {
      await _change(
        () => registry.savePluginSettings(
          plugin.id,
          Map<String, dynamic>.from(jsonDecode(text) as Map),
        ),
      );
    }
  }

  Widget _commandCard(InstalledCommandExtension entry) {
    final manifest = entry.manifest;
    final store = ref.read(commandExtensionStoreProvider);
    final actions = {
      for (final action in manifest.capabilities.expand(store.actions))
        if (action.extensionId == manifest.id) action.command.id: action,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: ValueKey('extension-enabled-${manifest.id}'),
              contentPadding: EdgeInsets.zero,
              value: entry.enabled,
              onChanged: _busy
                  ? null
                  : (value) =>
                        _change(() => store.setEnabled(manifest.id, value)),
              title: Text(manifest.name),
              subtitle: Text('${manifest.id} · ${manifest.version}'),
            ),
            if (manifest.description.isNotEmpty) Text(manifest.description),
            Text(
              manifest.capabilities
                  .map(
                    (capability) => context.extensionTr(
                      capability == CommandExtensionCapability.toolbar
                          ? 'Toolbar'
                          : 'Context menu',
                    ),
                  )
                  .join(' · '),
            ),
            if (!entry.enabled)
              Text(
                context.extensionTr(
                  'Enable this extension to show its actions.',
                ),
              ),
            for (final command in entry.commands)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SelectableText(command.executable),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          key: ValueKey(
                            'extension-run-${manifest.id}-${command.id}',
                          ),
                          onPressed: _busy || !entry.enabled
                              ? null
                              : () {
                                  final action = actions[command.id];
                                  if (action == null) return;
                                  showCommandExtensionRunDialog(
                                    context,
                                    ref,
                                    widget.side,
                                    action,
                                  );
                                },
                          icon: const Icon(Icons.play_arrow),
                          label: Text(context.extensionTr('Run')),
                        ),
                        TextButton.icon(
                          key: ValueKey(
                            'extension-settings-${manifest.id}-${command.id}',
                          ),
                          onPressed: _busy
                              ? null
                              : () => _configure(manifest.id, command),
                          icon: const Icon(Icons.tune),
                          label: Text(context.extensionTr('Command settings')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _export(manifest.id),
                  child: Text(context.extensionTr('Export manifest')),
                ),
                TextButton(
                  onPressed: _busy || entry.overrides.isEmpty
                      ? null
                      : () => _change(() => store.resetSettings(manifest.id)),
                  child: Text(context.extensionTr('Reset settings')),
                ),
                TextButton(
                  key: ValueKey('extension-remove-${manifest.id}'),
                  onPressed: _busy
                      ? null
                      : () => _change(() => store.remove(manifest.id)),
                  child: Text(context.extensionTr('Remove')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pluginCard(CrispCloudPlugin plugin) {
    final notifier = ref.read(pluginRegistryProvider);
    final status = notifier.registry.statusOf(plugin.id);
    final enabled = notifier.getPluginSettings(plugin.id)?.enabled ?? false;
    final error = notifier.errors[plugin.id];
    final label = switch (status) {
      PluginRuntimeStatus.registered => 'Waiting for initialization',
      PluginRuntimeStatus.initializing => 'Initializing',
      PluginRuntimeStatus.ready => 'Ready',
      PluginRuntimeStatus.disabled => 'Disabled',
      PluginRuntimeStatus.failed => 'Failed',
      null => 'Unavailable',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: ValueKey('plugin-enabled-${plugin.id}'),
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: _busy
                  ? null
                  : (value) =>
                        _change(() => notifier.setEnabled(plugin.id, value)),
              title: Text(plugin.name),
              subtitle: Text(
                '${plugin.version} · ${context.extensionTr(label)}',
              ),
            ),
            Text(plugin.description),
            if (error != null)
              SelectableText(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (plugin.capabilities.contains(PluginCapability.settings))
                  TextButton(
                    onPressed: _busy ? null : () => _pluginSettings(plugin),
                    child: Text(context.extensionTr('Plugin settings')),
                  ),
                if (status == PluginRuntimeStatus.failed)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _change(() => notifier.retryPlugin(plugin.id)),
                    child: Text(context.extensionTr('Retry')),
                  ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            _change(() => notifier.unregisterPlugin(plugin.id)),
                  child: Text(context.extensionTr('Unload')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(commandExtensionStoreProvider);
    final plugins = ref.watch(pluginRegistryProvider).getAllPlugins();
    return AlertDialog(
      title: Text(context.extensionTr('Extensions')),
      content: SizedBox(
        width: 720,
        height: math.min(560, MediaQuery.sizeOf(context).height * .55),
        child: ListView(
          children: [
            Text(context.extensionTr('Command extensions')),
            Text(
              context.extensionTr(
                'Programs run only after you review and start an action.',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error ?? store.loadError case final error?)
              SelectableText(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (store.installed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  context.extensionTr('No command extensions installed.'),
                ),
              ),
            for (final entry in store.installed) _commandCard(entry),
            const Divider(),
            Text(context.extensionTr('First-party plugins')),
            Text(
              context.extensionTr(
                'Trusted compiled plugins use app privileges; they are not isolated by an OS sandbox.',
              ),
            ),
            if (plugins.isEmpty)
              Text(context.extensionTr('No first-party plugins registered.')),
            for (final plugin in plugins) _pluginCard(plugin),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _import,
          child: Text(context.extensionTr('Import manifest')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.extensionTr('Close')),
        ),
      ],
    );
  }
}

/// The complete executable/argv review appears before any installation write.
class ExtensionReviewDialog extends StatelessWidget {
  const ExtensionReviewDialog({
    super.key,
    required this.manifest,
    this.replacing = false,
  });
  final CommandExtensionManifest manifest;
  final bool replacing;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(context.extensionTr('Review extension')),
    content: SizedBox(
      width: 680,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(manifest.name, style: Theme.of(context).textTheme.titleLarge),
          SelectableText('${manifest.id} · ${manifest.version}'),
          Text(manifest.description),
          Text(
            manifest.capabilities
                .map(
                  (capability) => context.extensionTr(
                    capability == CommandExtensionCapability.toolbar
                        ? 'Toolbar'
                        : 'Context menu',
                  ),
                )
                .join(' · '),
          ),
          const SizedBox(height: 12),
          Text(
            context.extensionTr(
              'Installation runs nothing. Enable the extension separately.',
            ),
          ),
          if (replacing)
            Text(
              context.extensionTr(
                'Replacement resets saved command settings and disables the extension.',
              ),
            ),
          for (final command in manifest.commands) ...[
            const Divider(),
            Text(command.label, style: Theme.of(context).textTheme.titleSmall),
            SelectableText(command.executable),
            for (var index = 0; index < command.arguments.length; index++)
              SelectableText(
                '[$index] ${jsonEncode(command.arguments[index])}',
              ),
            Text(
              command.useCurrentPanelPath
                  ? context.extensionTr(
                      'Working directory: captured local folder',
                    )
                  : context.extensionTr('Working directory: {0}', [
                      command.workingDir ?? '',
                    ]),
            ),
            Text(
              context.extensionTr('Timeout: {0} seconds', [
                command.timeoutSeconds,
              ]),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(context.extensionTr('Cancel')),
      ),
      FilledButton(
        key: const ValueKey('extension-install-reviewed'),
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          context.extensionTr(
            replacing ? 'Replace disabled' : 'Install disabled',
          ),
        ),
      ),
    ],
  );
}
