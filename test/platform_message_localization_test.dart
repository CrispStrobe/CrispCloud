import 'package:crisp_cloud/l10n/platform_message_strings.dart';
import 'package:crisp_cloud/services/siri_shortcuts_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification interpolation and shortcut identifiers survive translation', () {
    for (final language in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = PlatformMessageStrings(Locale(language));
      expect(strings.value('transferBody', 'report.pdf'), contains('report.pdf'));
      expect(strings.value('syncBody', 'Nextcloud'), contains('Nextcloud'));
      final shortcuts = shortcutsForLocale(Locale(language));
      expect(shortcuts.map((s) => s.identifier).toSet(), {
        SiriShortcutId.uploadToCloud, SiriShortcutId.showRecentFiles, SiriShortcutId.syncNow,
      });
      expect(shortcuts.every((s) => s.title.isNotEmpty && s.subtitle.isNotEmpty && s.suggestedInvocationPhrase.isNotEmpty), isTrue);
    }
    expect(shortcutsForLocale(const Locale('es')).last.title, 'Sincronizar ahora');
  });
}
