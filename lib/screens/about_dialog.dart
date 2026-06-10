// lib/screens/about_dialog.dart
//
// About / Legal dialog widget.
// Extracted from file_browser_screen.dart.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutAppDialog extends StatelessWidget {
  const AboutAppDialog({super.key});

  static const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
  static const _gitHash = String.fromEnvironment('GIT_HASH', defaultValue: 'dev');

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SimpleDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text('About / Legal',
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
                        'Crisp Cloud',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SelectableText(
                        'Version $_appVersion ($_gitHash)',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'An unofficial, open-source client for Filen.io, SFTP & WebDAV.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 32),

                _buildSectionTitle(context, 'Service Provider'),
                _buildSectionText(context,
                    'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland/Germany'),

                const SizedBox(height: 16),
                _buildSectionTitle(context, 'Contact'),
                _buildSectionText(context,
                    'Email: postmaster@crispstro.be\nPhone: +49 176 6421 8601'),

                const SizedBox(height: 16),
                _buildSectionTitle(context, 'Disclaimer'),
                _buildSectionText(context,
                    'This software is provided "as is", without warranty of any kind. This app is not affiliated with Filen.io, or any other cloud provider.'),

                const SizedBox(height: 24),

                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.code),
                      label: const Text('Source Code (GitHub)'),
                      onPressed: () => _launchURL(
                          'https://github.com/CrispStrobe/dart-cloud'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.web),
                      label: const Text('Website'),
                      onPressed: () =>
                          _launchURL('https://www.crispstro.be'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Center(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.description),
                    label: const Text('View Open Source Licenses'),
                    onPressed: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'Crisp Cloud',
                        applicationVersion: '$_appVersion ($_gitHash)',
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
                    child: const Text('Close'),
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
