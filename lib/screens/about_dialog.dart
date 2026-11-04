// lib/screens/about_dialog.dart
//
// About / Legal dialog widget.
// Extracted from file_browser_screen.dart.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../l10n/misc_ui_strings.dart';

class AboutAppDialog extends StatefulWidget {
  const AboutAppDialog({super.key});

  @override
  State<AboutAppDialog> createState() => _AboutAppDialogState();
}

class _AboutAppDialogState extends State<AboutAppDialog> {
  static const _fallbackVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const _gitHash = String.fromEnvironment('GIT_HASH', defaultValue: '');

  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageInfo = info);
    } catch (_) {
      // Fall back to the compile-time version.
    }
  }

  String get _versionLabel {
    final version = _packageInfo?.version ?? _fallbackVersion;
    final build = _packageInfo?.buildNumber ?? '';
    final suffix = _gitHash.isNotEmpty
        ? _gitHash
        : (build.isNotEmpty && build != '0' ? '${MiscUiStrings(context).text('build')} $build' : '');
    return suffix.isEmpty ? '${MiscUiStrings(context).text('version')} $version' : '${MiscUiStrings(context).text('version')} $version ($suffix)';
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SimpleDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(l.aboutLegal,
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ],
      ),
      contentPadding: const EdgeInsets.all(24.0),
      children: [
        SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud_circle,
                          size: 64, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(
                        l.appTitle,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SelectableText(
                        _versionLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.appDescription,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 32),

                _buildSectionTitle(context, l.serviceProvider),
                _buildSectionText(context,
                    'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany'),

                const SizedBox(height: 16),
                _buildSectionTitle(context, l.contact),
                _buildSectionText(context,
                    'Email: postmaster@crispstro.be\nPhone: +49 176 6421 8601'),

                const SizedBox(height: 16),
                _buildSectionTitle(context, l.disclaimer),
                _buildSectionText(context, l.disclaimerText),

                const SizedBox(height: 24),

                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.code),
                      label: Text(l.sourceCode),
                      onPressed: () => _launchURL(
                          'https://github.com/CrispStrobe/dart-cloud'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.web),
                      label: Text(l.website),
                      onPressed: () =>
                          _launchURL('https://www.crispstro.be'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Center(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.description),
                    label: Text(l.viewLicenses),
                    onPressed: () {
                      showLicensePage(
                        context: context,
                        applicationName: l.appTitle,
                        applicationVersion: _versionLabel,
                        applicationIcon:
                            const Icon(Icons.cloud, size: 48),
                        applicationLegalese: '© 2025 CrispStrobe',
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }

  Widget _buildSectionText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
