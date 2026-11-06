import 'package:flutter/widgets.dart';

/// Text for provider-specific settings.
class ProviderSettingsStrings {
  ProviderSettingsStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key, [Map<String, Object> values = const {}]) {
    var result =
        (_strings[language] ?? _strings['en']!)[key] ?? _strings['en']![key]!;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      "settings": "{provider} Settings",
      "timeout": "Request Timeout (seconds)",
      "default": "Default: 30 seconds",
      "headers": "Custom Headers",
      "headerHelp": "One per line: Header-Name: value",
      "redirects": "Follow Redirects",
      "verify": "Verify SSL Certificates",
      "verifyHelp": "Disable only for self-signed certs",
    },
    'de': {
      "settings": "{provider}-Einstellungen",
      "timeout": "Zeitlimit für Anfragen (Sekunden)",
      "default": "Standard: 30 Sekunden",
      "headers": "Benutzerdefinierte Header",
      "headerHelp": "Eine pro Zeile: Header-Name: Wert",
      "redirects": "Weiterleitungen folgen",
      "verify": "SSL-Zertifikate überprüfen",
      "verifyHelp": "Nur bei selbstsignierten Zertifikaten deaktivieren",
    },
    'fr': {
      "settings": "Paramètres {provider}",
      "timeout": "Délai des requêtes (secondes)",
      "default": "Par défaut : 30 secondes",
      "headers": "En-têtes personnalisés",
      "headerHelp": "Un par ligne : Nom-En-tête: valeur",
      "redirects": "Suivre les redirections",
      "verify": "Vérifier les certificats SSL",
      "verifyHelp": "Désactiver uniquement pour les certificats auto-signés",
    },
    'es': {
      "settings": "Configuración de {provider}",
      "timeout": "Tiempo de espera de solicitud (segundos)",
      "default": "Predeterminado: 30 segundos",
      "headers": "Encabezados personalizados",
      "headerHelp": "Uno por línea: Nombre-Encabezado: valor",
      "redirects": "Seguir redirecciones",
      "verify": "Verificar certificados SSL",
      "verifyHelp": "Desactivar solo para certificados autofirmados",
    },
    'pt': {
      "settings": "Configurações de {provider}",
      "timeout": "Tempo limite da solicitação (segundos)",
      "default": "Padrão: 30 segundos",
      "headers": "Cabeçalhos personalizados",
      "headerHelp": "Um por linha: Nome-Cabeçalho: valor",
      "redirects": "Seguir redirecionamentos",
      "verify": "Verificar certificados SSL",
      "verifyHelp": "Desative apenas para certificados autoassinados",
    },
    'zh': {
      "settings": "{provider} 设置",
      "timeout": "请求超时（秒）",
      "default": "默认：30 秒",
      "headers": "自定义请求头",
      "headerHelp": "每行一个：请求头名称: 值",
      "redirects": "跟随重定向",
      "verify": "验证 SSL 证书",
      "verifyHelp": "仅针对自签名证书关闭",
    },
    'ja': {
      "settings": "{provider} の設定",
      "timeout": "リクエストのタイムアウト（秒）",
      "default": "既定値: 30 秒",
      "headers": "カスタムヘッダー",
      "headerHelp": "1 行に 1 つ: ヘッダー名: 値",
      "redirects": "リダイレクトに従う",
      "verify": "SSL 証明書を検証",
      "verifyHelp": "自己署名証明書の場合のみ無効にしてください",
    },
    'ko': {
      "settings": "{provider} 설정",
      "timeout": "요청 제한 시간 (초)",
      "default": "기본값: 30초",
      "headers": "사용자 지정 헤더",
      "headerHelp": "한 줄에 하나씩: 헤더-이름: 값",
      "redirects": "리디렉션 따르기",
      "verify": "SSL 인증서 확인",
      "verifyHelp": "자체 서명 인증서에 대해서만 비활성화하세요",
    },
    'ar': {
      "settings": "إعدادات {provider}",
      "timeout": "مهلة الطلب (بالثواني)",
      "default": "الافتراضي: 30 ثانية",
      "headers": "الترويسات المخصصة",
      "headerHelp": "واحدة لكل سطر: اسم-الترويسة: القيمة",
      "redirects": "اتباع إعادة التوجيه",
      "verify": "التحقق من شهادات SSL",
      "verifyHelp": "عطّل هذا فقط للشهادات الموقعة ذاتيًا",
    },
  };
}
