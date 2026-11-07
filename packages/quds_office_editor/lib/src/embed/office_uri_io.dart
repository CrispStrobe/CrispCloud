import 'package:url_launcher/url_launcher.dart';

/// Hands [uri] to the OS so a click on a PDF link opens the browser.
Future<void> openExternalUri(String uri) async {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return;
  await launchUrl(parsed, mode: LaunchMode.externalApplication);
}
