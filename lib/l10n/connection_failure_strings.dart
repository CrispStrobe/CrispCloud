import 'package:flutter/widgets.dart';

import '../services/connection_failure.dart';

/// Renders recognized app-authored connection errors without altering others.
String? localizedConnectionFailure(BuildContext context, Object error) {
  final String key;
  final Map<String, Object> arguments;
  if (error is ConnectionFailure) {
    key = error.code.name;
    arguments = error.arguments;
  } else if (error is SftpConnectionFailure) {
    key = 'sftpFailed';
    arguments = const {};
  } else {
    return null;
  }
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  var message = (_messages[language] ?? _messages['en']!)[key]!;
  for (final entry in arguments.entries) {
    message = message.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return message;
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "oauthWebUnsupported":
        "{provider} OAuth2 on web requires a different redirect flow.",
    "oauthWebUnsupportedDesktopMobile":
        "{provider} OAuth2 on web requires a different redirect flow. Use desktop or mobile.",
    "oauthCancelled": "{provider} authorization was cancelled or failed",
    "oauthBrowserUnavailable":
        "Could not open browser for {provider} authorization",
    "nextcloudHttp": "Connection test failed (HTTP {status})",
    "sftpFailed":
        "SFTP connection failed. Check server access and credentials.",
  },
  'de': {
    "oauthWebUnsupported":
        "Für {provider}-OAuth2 im Web ist ein anderer Weiterleitungsablauf erforderlich.",
    "oauthWebUnsupportedDesktopMobile":
        "Für {provider}-OAuth2 im Web ist ein anderer Weiterleitungsablauf erforderlich. Verwenden Sie Desktop oder Mobilgerät.",
    "oauthCancelled":
        "Die Autorisierung für {provider} wurde abgebrochen oder ist fehlgeschlagen",
    "oauthBrowserUnavailable":
        "Browser für {provider}-Autorisierung konnte nicht geöffnet werden",
    "nextcloudHttp": "Verbindungstest fehlgeschlagen (HTTP {status})",
    "sftpFailed":
        "SFTP-Verbindung fehlgeschlagen. Prüfen Sie den Serverzugriff und die Zugangsdaten.",
  },
  'fr': {
    "oauthWebUnsupported":
        "OAuth2 {provider} sur le web nécessite un autre flux de redirection.",
    "oauthWebUnsupportedDesktopMobile":
        "OAuth2 {provider} sur le web nécessite un autre flux de redirection. Utilisez l’application de bureau ou mobile.",
    "oauthCancelled": "L’autorisation {provider} a été annulée ou a échoué",
    "oauthBrowserUnavailable":
        "Impossible d’ouvrir le navigateur pour autoriser {provider}",
    "nextcloudHttp": "Échec du test de connexion (HTTP {status})",
    "sftpFailed":
        "Échec de la connexion SFTP. Vérifiez l’accès au serveur et les identifiants.",
  },
  'es': {
    "oauthWebUnsupported":
        "OAuth2 de {provider} en la web requiere otro flujo de redirección.",
    "oauthWebUnsupportedDesktopMobile":
        "OAuth2 de {provider} en la web requiere otro flujo de redirección. Usa la aplicación de escritorio o móvil.",
    "oauthCancelled": "La autorización de {provider} se canceló o falló",
    "oauthBrowserUnavailable":
        "No se pudo abrir el navegador para autorizar {provider}",
    "nextcloudHttp": "Error en la prueba de conexión (HTTP {status})",
    "sftpFailed":
        "Falló la conexión SFTP. Comprueba el acceso al servidor y las credenciales.",
  },
  'pt': {
    "oauthWebUnsupported":
        "O OAuth2 do {provider} na web requer outro fluxo de redirecionamento.",
    "oauthWebUnsupportedDesktopMobile":
        "O OAuth2 do {provider} na web requer outro fluxo de redirecionamento. Use o aplicativo para computador ou celular.",
    "oauthCancelled": "A autorização do {provider} foi cancelada ou falhou",
    "oauthBrowserUnavailable":
        "Não foi possível abrir o navegador para autorizar {provider}",
    "nextcloudHttp": "Falha no teste de conexão (HTTP {status})",
    "sftpFailed":
        "Falha na conexão SFTP. Verifique o acesso ao servidor e as credenciais.",
  },
  'zh': {
    "oauthWebUnsupported": "网页版 {provider} OAuth2 需要不同的重定向流程。",
    "oauthWebUnsupportedDesktopMobile":
        "网页版 {provider} OAuth2 需要不同的重定向流程。请使用桌面版或移动版。",
    "oauthCancelled": "{provider} 授权已取消或失败",
    "oauthBrowserUnavailable": "无法打开浏览器以授权 {provider}",
    "nextcloudHttp": "连接测试失败（HTTP {status}）",
    "sftpFailed": "SFTP 连接失败。请检查服务器访问权限和凭据。",
  },
  'ja': {
    "oauthWebUnsupported": "ウェブ版の {provider} OAuth2 には別のリダイレクトフローが必要です。",
    "oauthWebUnsupportedDesktopMobile":
        "ウェブ版の {provider} OAuth2 には別のリダイレクトフローが必要です。デスクトップ版またはモバイル版を使用してください。",
    "oauthCancelled": "{provider} の認可がキャンセルされたか失敗しました",
    "oauthBrowserUnavailable": "{provider} の認可用ブラウザーを開けませんでした",
    "nextcloudHttp": "接続テストに失敗しました（HTTP {status}）",
    "sftpFailed": "SFTP 接続に失敗しました。サーバーへのアクセスと認証情報を確認してください。",
  },
  'ko': {
    "oauthWebUnsupported": "웹에서 {provider} OAuth2를 사용하려면 다른 리디렉션 흐름이 필요합니다.",
    "oauthWebUnsupportedDesktopMobile":
        "웹에서 {provider} OAuth2를 사용하려면 다른 리디렉션 흐름이 필요합니다. 데스크톱 또는 모바일 앱을 사용하세요.",
    "oauthCancelled": "{provider} 인증이 취소되었거나 실패했습니다",
    "oauthBrowserUnavailable": "{provider} 인증을 위한 브라우저를 열 수 없습니다",
    "nextcloudHttp": "연결 테스트 실패 (HTTP {status})",
    "sftpFailed": "SFTP 연결 실패. 서버 접근 및 자격 증명을 확인하세요.",
  },
  'ar': {
    "oauthWebUnsupported":
        "تتطلب مصادقة OAuth2 لـ {provider} على الويب مسار إعادة توجيه مختلفًا.",
    "oauthWebUnsupportedDesktopMobile":
        "تتطلب مصادقة OAuth2 لـ {provider} على الويب مسار إعادة توجيه مختلفًا. استخدم تطبيق سطح المكتب أو الهاتف.",
    "oauthCancelled": "أُلغي تفويض {provider} أو فشل",
    "oauthBrowserUnavailable": "تعذّر فتح المتصفح لتفويض {provider}",
    "nextcloudHttp": "فشل اختبار الاتصال (HTTP {status})",
    "sftpFailed": "فشل اتصال SFTP. تحقق من الوصول إلى الخادم وبيانات الاعتماد.",
  },
};
