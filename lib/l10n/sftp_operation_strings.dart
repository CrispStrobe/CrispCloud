import 'package:flutter/widgets.dart';
import 'remote_transport_strings.dart';
import '../services/sftp_operation_failure.dart';

/// Localize app-authored SFTP text and retain the server's error detail.
String localizedSftpOperationError(BuildContext context, Object error) {
  if (error is! SftpOperationFailure) return error.toString();
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final template = (_messages[language] ?? _messages['en']!)[error.code.name];
  if (template == null) return error.toString();
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : localizedRemoteTransportError(context, value) ?? value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {"notLoggedIn": "Not logged in", "incompleteCredentials": "Incomplete credentials", "invalidAddress": "Invalid SFTP server address", "invalidIdentity": "Format must be user@host (e.g. u12345@u123.your-storagebox.de)", "listFailed": "Failed to list path {path}: {error}", "chmodFailed": "chmod failed: {output}", "chownFailed": "chown failed: {output}", "invalidPayload": "Invalid payload from WebSocket: {type}"},
  "de": {"notLoggedIn": "Nicht angemeldet", "incompleteCredentials": "Unvollständige Zugangsdaten", "invalidAddress": "Ungültige SFTP-Serveradresse", "invalidIdentity": "Format muss benutzer@host sein (z. B. u12345@u123.your-storagebox.de)", "listFailed": "Pfad {path} konnte nicht aufgelistet werden: {error}", "chmodFailed": "chmod fehlgeschlagen: {output}", "chownFailed": "chown fehlgeschlagen: {output}", "invalidPayload": "Ungültige WebSocket-Nutzdaten: {type}"},
  "fr": {"notLoggedIn": "Non connecté", "incompleteCredentials": "Identifiants incomplets", "invalidAddress": "Adresse du serveur SFTP invalide", "invalidIdentity": "Le format doit être utilisateur@hôte (ex. u12345@u123.your-storagebox.de)", "listFailed": "Impossible de lister le chemin {path} : {error}", "chmodFailed": "Échec de chmod : {output}", "chownFailed": "Échec de chown : {output}", "invalidPayload": "Données WebSocket invalides : {type}"},
  "es": {"notLoggedIn": "No has iniciado sesión", "incompleteCredentials": "Credenciales incompletas", "invalidAddress": "Dirección de servidor SFTP no válida", "invalidIdentity": "El formato debe ser usuario@host (p. ej. u12345@u123.your-storagebox.de)", "listFailed": "No se pudo listar la ruta {path}: {error}", "chmodFailed": "Error de chmod: {output}", "chownFailed": "Error de chown: {output}", "invalidPayload": "Datos WebSocket no válidos: {type}"},
  "pt": {"notLoggedIn": "Sessão não iniciada", "incompleteCredentials": "Credenciais incompletas", "invalidAddress": "Endereço do servidor SFTP inválido", "invalidIdentity": "O formato tem de ser utilizador@host (ex.: u12345@u123.your-storagebox.de)", "listFailed": "Não foi possível listar o caminho {path}: {error}", "chmodFailed": "Falha de chmod: {output}", "chownFailed": "Falha de chown: {output}", "invalidPayload": "Dados WebSocket inválidos: {type}"},
  "zh": {"notLoggedIn": "尚未登录", "incompleteCredentials": "凭据不完整", "invalidAddress": "SFTP 服务器地址无效", "invalidIdentity": "格式必须为 用户@主机（如 u12345@u123.your-storagebox.de）", "listFailed": "无法列出路径 {path}：{error}", "chmodFailed": "chmod 失败：{output}", "chownFailed": "chown 失败：{output}", "invalidPayload": "WebSocket 数据无效：{type}"},
  "ja": {"notLoggedIn": "ログインしていません", "incompleteCredentials": "認証情報が不足しています", "invalidAddress": "SFTP サーバーアドレスが無効です", "invalidIdentity": "形式は user@host です（例: u12345@u123.your-storagebox.de）", "listFailed": "パス {path} を一覧表示できませんでした: {error}", "chmodFailed": "chmod に失敗しました: {output}", "chownFailed": "chown に失敗しました: {output}", "invalidPayload": "WebSocket のデータが無効です: {type}"},
  "ko": {"notLoggedIn": "로그인되지 않았습니다", "incompleteCredentials": "자격 증명이 불완전합니다", "invalidAddress": "잘못된 SFTP 서버 주소입니다", "invalidIdentity": "형식은 사용자@호스트입니다 (예: u12345@u123.your-storagebox.de)", "listFailed": "경로 {path}의 목록을 가져올 수 없습니다: {error}", "chmodFailed": "chmod 실패: {output}", "chownFailed": "chown 실패: {output}", "invalidPayload": "잘못된 WebSocket 데이터: {type}"},
  "ar": {"notLoggedIn": "لم يتم تسجيل الدخول", "incompleteCredentials": "بيانات الاعتماد غير مكتملة", "invalidAddress": "عنوان خادم SFTP غير صالح", "invalidIdentity": "يجب أن يكون التنسيق مستخدم@مضيف (مثل u12345@u123.your-storagebox.de)", "listFailed": "تعذر عرض محتويات المسار {path}: {error}", "chmodFailed": "فشل chmod: {output}", "chownFailed": "فشل chown: {output}", "invalidPayload": "بيانات WebSocket غير صالحة: {type}"},
};
