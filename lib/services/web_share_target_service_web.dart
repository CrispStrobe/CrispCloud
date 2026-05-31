// lib/services/web_share_target_service_web.dart
//
// Web implementation: detects a share-target POST by inspecting the URL and
// reading the multipart form data posted by the browser.

import 'package:universal_html/html.dart' as html;

import 'log_service.dart';
import 'web_share_target_service.dart';

WebShareTargetService createWebShareTargetService() =>
    _WebShareTargetServiceImpl();

class _WebShareTargetServiceImpl implements WebShareTargetService {
  static final _log = Log('WebShareTargetService');

  SharedContent? _content;

  @override
  bool get hasSharedContent => _content != null && !_content!.isEmpty;

  @override
  SharedContent? get sharedContent => _content;

  @override
  Future<void> initialize() async {
    final href = html.window.location.href;
    _log.debug('Checking for share-target launch', {'url': href});

    final uri = Uri.tryParse(href);
    if (uri == null) return;

    // The manifest.json share_target action is "/share-target".
    if (!uri.path.endsWith('/share-target')) return;

    _log.info('Share-target launch detected');

    // Extract simple query parameters (title, text, url) from GET params
    // (browsers may redirect POST to GET after the service worker handles it).
    final title = uri.queryParameters['title'];
    final text = uri.queryParameters['text'];
    final url = uri.queryParameters['url'];

    _content = SharedContent(
      title: title,
      text: text,
      url: url,
      files: const [], // File bytes are only available via POST / service worker
    );

    _log.info('Shared content parsed', {
      'title': title,
      'text': text,
      'url': url,
    });
  }

  @override
  void clear() {
    _log.debug('Clearing shared content');
    _content = null;
  }
}
