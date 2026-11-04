import 'package:flutter/widgets.dart';
import 'remote_transport_strings.dart';
import '../services/webdav_operation_failure.dart';

/// Localize app-owned WebDAV messages while preserving remote error detail.
String localizedWebDavError(BuildContext context, Object error) =>
    localizedWebDavErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String localizedWebDavErrorForLanguage(String language, Object error) {
  if (error is! WebDavOperationFailure) return error.toString();
  final template = (_messages[language] ?? _messages['en']!)[error.code.name];
  if (template == null) return error.toString();
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : localizedRemoteTransportErrorForLanguage(language, value) ?? value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {"invalidIdentity": "Format must be user@ServerURL", "connectionFailed": "Connection failed: {error}", "notLoggedIn": "Not logged in", "listFailed": "Failed to list path {path}: {error}", "webDownload": "Use the browser download stream on web"},
  "de": {"invalidIdentity": "Format muss benutzer@ServerURL sein", "connectionFailed": "Verbindung fehlgeschlagen: {error}", "notLoggedIn": "Nicht angemeldet", "listFailed": "Pfad {path} konnte nicht aufgelistet werden: {error}", "webDownload": "Im Web den Download-Stream des Browsers verwenden"},
  "fr": {"invalidIdentity": "Le format doit être utilisateur@URLServeur", "connectionFailed": "Échec de connexion : {error}", "notLoggedIn": "Non connecté", "listFailed": "Impossible de lister le chemin {path} : {error}", "webDownload": "Utilisez le flux de téléchargement du navigateur sur le Web"},
  "es": {"invalidIdentity": "El formato debe ser usuario@URLServidor", "connectionFailed": "Error de conexión: {error}", "notLoggedIn": "No has iniciado sesión", "listFailed": "No se pudo listar la ruta {path}: {error}", "webDownload": "Usa el flujo de descarga del navegador en la web"},
  "pt": {"invalidIdentity": "O formato tem de ser utilizador@URLServidor", "connectionFailed": "Falha na ligação: {error}", "notLoggedIn": "Sessão não iniciada", "listFailed": "Não foi possível listar o caminho {path}: {error}", "webDownload": "Use o fluxo de transferência do navegador na Web"},
  "zh": {"invalidIdentity": "格式必须为 用户@服务器URL", "connectionFailed": "连接失败：{error}", "notLoggedIn": "尚未登录", "listFailed": "无法列出路径 {path}：{error}", "webDownload": "在网页端请使用浏览器下载流"},
  "ja": {"invalidIdentity": "形式は user@サーバーURL で指定してください", "connectionFailed": "接続に失敗しました: {error}", "notLoggedIn": "ログインしていません", "listFailed": "パス {path} を一覧表示できませんでした: {error}", "webDownload": "Web ではブラウザーのダウンロードストリームを使用してください"},
  "ko": {"invalidIdentity": "형식은 사용자@서버URL이어야 합니다", "connectionFailed": "연결 실패: {error}", "notLoggedIn": "로그인되지 않았습니다", "listFailed": "경로 {path}의 목록을 가져올 수 없습니다: {error}", "webDownload": "웹에서는 브라우저 다운로드 스트림을 사용하세요"},
  "ar": {"invalidIdentity": "يجب أن يكون التنسيق المستخدم@عنوان_الخادم", "connectionFailed": "فشل الاتصال: {error}", "notLoggedIn": "لم يتم تسجيل الدخول", "listFailed": "تعذر عرض محتويات المسار {path}: {error}", "webDownload": "استخدم تدفق التنزيل في المتصفح على الويب"},
};
