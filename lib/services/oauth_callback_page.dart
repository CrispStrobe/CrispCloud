import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'locale_preference.dart';

/// Localized content for the local OAuth callback server.
class OAuthCallbackPage {
  OAuthCallbackPage(Locale locale)
      : _text = _translations[locale.languageCode] ?? _translations['en']!;

  final List<String> _text;
  static const _escape = HtmlEscape(HtmlEscapeMode.element);

  static Future<OAuthCallbackPage> effective() async {
    final override = await LocalePreference.read(refresh: true);
    return OAuthCallbackPage(override ?? PlatformDispatcher.instance.locale);
  }

  String get notFound => _text[4];

  String successHtml() => _html(_text[0], _text[1]);

  String deniedHtml(String error) => _html('${_text[2]}: $error', _text[3]);

  String _html(String heading, String body) =>
      '<html><body><h2>${_escape.convert(heading)}</h2>'
      '<p>${_escape.convert(body)}</p></body></html>';

  // Success heading, success instruction, denied heading, denied instruction,
  // and the plain text response to other requests (such as favicon requests).
  static const Map<String, List<String>> _translations = {
    'en': ['Authorization successful!', 'You can close this window and return to CrispCloud.', 'Authorization denied', 'You can close this window.', 'Not found'],
    'de': ['Autorisierung erfolgreich!', 'Sie können dieses Fenster schließen und zu CrispCloud zurückkehren.', 'Autorisierung abgelehnt', 'Sie können dieses Fenster schließen.', 'Nicht gefunden'],
    'fr': ['Autorisation réussie !', 'Vous pouvez fermer cette fenêtre et revenir à CrispCloud.', 'Autorisation refusée', 'Vous pouvez fermer cette fenêtre.', 'Introuvable'],
    'es': ['¡Autorización completada!', 'Puede cerrar esta ventana y volver a CrispCloud.', 'Autorización denegada', 'Puede cerrar esta ventana.', 'No encontrado'],
    'pt': ['Autorização concluída!', 'Pode fechar esta janela e voltar ao CrispCloud.', 'Autorização negada', 'Pode fechar esta janela.', 'Não encontrado'],
    'zh': ['授权成功！', '您可以关闭此窗口并返回 CrispCloud。', '授权被拒绝', '您可以关闭此窗口。', '未找到'],
    'ja': ['認証が完了しました！', 'このウィンドウを閉じて CrispCloud に戻ることができます。', '認証が拒否されました', 'このウィンドウを閉じることができます。', '見つかりません'],
    'ko': ['인증이 완료되었습니다!', '이 창을 닫고 CrispCloud로 돌아가세요.', '인증이 거부되었습니다', '이 창을 닫아도 됩니다.', '찾을 수 없음'],
    'ar': ['تم التفويض بنجاح!', 'يمكنك إغلاق هذه النافذة والعودة إلى CrispCloud.', 'رُفض التفويض', 'يمكنك إغلاق هذه النافذة.', 'غير موجود'],
  };
}
