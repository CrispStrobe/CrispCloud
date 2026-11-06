import 'package:flutter/widgets.dart';
import '../services/ftp_operation_failure.dart';

/// Translates FTP-owned errors and retains external error details.
String localizedFtpError(BuildContext context, Object error) =>
    localizedFtpErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String localizedFtpErrorForLanguage(String language, Object error) {
  if (error is! FtpOperationFailure) return error.toString();
  final template = (_messages[language] ?? _messages['en']!)[error.code.name] ??
      error.message;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    if (value is FtpOperationFailure) return localizedFtpErrorForLanguage(language, value);
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "notLoggedIn": "Not logged in",
    "incompleteCredentials": "Incomplete credentials",
    "connectionFailed": "FTP connection failed",
    "connectionError": "Connection failed: {error}",
    "webUnsupported": "FTP is not supported on Web",
    "invalidFormat":
        "Format must be user@host[:port] (e.g. user@ftp.example.com:21)",
    "list": "Failed to list path {path}: {error}",
    "upload": "FTP upload failed for {path}",
    "download": "FTP download failed for {path}",
  },
  'de': {
    "notLoggedIn": "Nicht angemeldet",
    "incompleteCredentials": "Unvollständige Zugangsdaten",
    "connectionFailed": "FTP-Verbindung fehlgeschlagen",
    "connectionError": "Verbindung fehlgeschlagen: {error}",
    "webUnsupported": "FTP wird im Web nicht unterstützt",
    "invalidFormat":
        "Format: benutzer@host[:port] (z. B. user@ftp.example.com:21)",
    "list": "Pfad {path} konnte nicht aufgelistet werden: {error}",
    "upload": "FTP-Upload für {path} fehlgeschlagen",
    "download": "FTP-Download für {path} fehlgeschlagen",
  },
  'fr': {
    "notLoggedIn": "Non connecté",
    "incompleteCredentials": "Identifiants incomplets",
    "connectionFailed": "Échec de la connexion FTP",
    "connectionError": "Échec de la connexion : {error}",
    "webUnsupported": "FTP n’est pas pris en charge sur le Web",
    "invalidFormat":
        "Format attendu : utilisateur@hôte[:port] (ex. user@ftp.example.com:21)",
    "list": "Impossible de lister le chemin {path} : {error}",
    "upload": "Échec de l’envoi FTP de {path}",
    "download": "Échec du téléchargement FTP de {path}",
  },
  'es': {
    "notLoggedIn": "Sesión no iniciada",
    "incompleteCredentials": "Credenciales incompletas",
    "connectionFailed": "Error de conexión FTP",
    "connectionError": "Error de conexión: {error}",
    "webUnsupported": "FTP no es compatible con la web",
    "invalidFormat":
        "Formato requerido: usuario@host[:puerto] (p. ej. user@ftp.example.com:21)",
    "list": "No se pudo listar la ruta {path}: {error}",
    "upload": "Error de subida FTP de {path}",
    "download": "Error de descarga FTP de {path}",
  },
  'pt': {
    "notLoggedIn": "Não conectado",
    "incompleteCredentials": "Credenciais incompletas",
    "connectionFailed": "Falha na conexão FTP",
    "connectionError": "Falha na conexão: {error}",
    "webUnsupported": "FTP não é compatível com a Web",
    "invalidFormat":
        "Formato exigido: usuário@host[:porta] (ex.: user@ftp.example.com:21)",
    "list": "Falha ao listar o caminho {path}: {error}",
    "upload": "Falha no envio FTP de {path}",
    "download": "Falha no download FTP de {path}",
  },
  'ar': {
    "notLoggedIn": "لم يتم تسجيل الدخول",
    "incompleteCredentials": "بيانات الاعتماد غير مكتملة",
    "connectionFailed": "فشل اتصال FTP",
    "connectionError": "فشل الاتصال: {error}",
    "webUnsupported": "FTP غير مدعوم على الويب",
    "invalidFormat":
        "يجب أن يكون التنسيق user@host[:port] (مثال user@ftp.example.com:21)",
    "list": "تعذر عرض المسار {path}: {error}",
    "upload": "فشل رفع FTP للملف {path}",
    "download": "فشل تنزيل FTP للملف {path}",
  },
  'ja': {
    "notLoggedIn": "ログインしていません",
    "incompleteCredentials": "認証情報が不完全です",
    "connectionFailed": "FTP 接続に失敗しました",
    "connectionError": "接続に失敗しました: {error}",
    "webUnsupported": "Web では FTP を利用できません",
    "invalidFormat": "形式は user@host[:port] です（例: user@ftp.example.com:21）",
    "list": "パス {path} の一覧取得に失敗しました: {error}",
    "upload": "{path} の FTP アップロードに失敗しました",
    "download": "{path} の FTP ダウンロードに失敗しました",
  },
  'ko': {
    "notLoggedIn": "로그인하지 않았습니다",
    "incompleteCredentials": "인증 정보가 불완전합니다",
    "connectionFailed": "FTP 연결에 실패했습니다",
    "connectionError": "연결에 실패했습니다: {error}",
    "webUnsupported": "웹에서는 FTP를 지원하지 않습니다",
    "invalidFormat": "형식은 user@host[:port]여야 합니다 (예: user@ftp.example.com:21)",
    "list": "경로 {path}의 목록을 가져오지 못했습니다: {error}",
    "upload": "{path} FTP 업로드에 실패했습니다",
    "download": "{path} FTP 다운로드에 실패했습니다",
  },
  'zh': {
    "notLoggedIn": "未登录",
    "incompleteCredentials": "凭据不完整",
    "connectionFailed": "FTP 连接失败",
    "connectionError": "连接失败：{error}",
    "webUnsupported": "Web 端不支持 FTP",
    "invalidFormat": "格式必须为 user@host[:port]（例如 user@ftp.example.com:21）",
    "list": "无法列出路径 {path}：{error}",
    "upload": "FTP 上传 {path} 失败",
    "download": "FTP 下载 {path} 失败",
  },
};
