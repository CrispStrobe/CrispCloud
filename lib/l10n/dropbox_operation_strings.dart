import 'package:flutter/widgets.dart';
import '../services/dropbox_operation_failure.dart';

/// Localize app-owned Dropbox errors while retaining server detail.
String localizedDropboxError(BuildContext context, Object error) {
  if (error is! DropboxOperationFailure) return error.toString();
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final map = _messages[language] ?? _messages['en']!;
  final code = error.code.name;
  final args = <String, Object>{...error.arguments};
  final String template;
  if (args.containsKey('status')) {
    template = map['http']!;
    args['operation'] = map[code] ?? code;
  } else {
    template = map[code] ?? error.message;
  }
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = args[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {"http": "Dropbox {operation} failed (HTTP {status}): {body}", "appKey": "App Key is required", "unauthenticated": "Not authenticated", "missingRefresh": "Cannot refresh: missing refresh token or app key", "upload": "upload", "download": "download", "tokenRefresh": "token refresh", "tokenExchange": "token exchange", "api": "API request", "paperExport": "Paper export"},
  "de": {"http": "Dropbox: {operation} fehlgeschlagen (HTTP {status}): {body}", "appKey": "App-Schlüssel ist erforderlich", "unauthenticated": "Nicht angemeldet", "missingRefresh": "Aktualisierung nicht möglich: Refresh-Token oder App-Schlüssel fehlt", "upload": "Upload", "download": "Download", "tokenRefresh": "Token-Aktualisierung", "tokenExchange": "Token-Austausch", "api": "API-Anfrage", "paperExport": "Paper-Export"},
  "fr": {"http": "Dropbox : échec de {operation} (HTTP {status}) : {body}", "appKey": "La clé d’application est requise", "unauthenticated": "Non authentifié", "missingRefresh": "Actualisation impossible : jeton ou clé d’application manquant", "upload": "l’envoi", "download": "le téléchargement", "tokenRefresh": "l’actualisation du jeton", "tokenExchange": "l’échange de jeton", "api": "la requête API", "paperExport": "l’exportation Paper"},
  "es": {"http": "Dropbox: error en {operation} (HTTP {status}): {body}", "appKey": "Se requiere la clave de aplicación", "unauthenticated": "No autenticado", "missingRefresh": "No se puede renovar: falta el token de renovación o la clave de aplicación", "upload": "la subida", "download": "la descarga", "tokenRefresh": "la renovación del token", "tokenExchange": "el intercambio del token", "api": "la solicitud API", "paperExport": "la exportación de Paper"},
  "pt": {"http": "Dropbox: falha em {operation} (HTTP {status}): {body}", "appKey": "A chave da aplicação é obrigatória", "unauthenticated": "Não autenticado", "missingRefresh": "Não é possível renovar: falta o token de renovação ou a chave da aplicação", "upload": "carregamento", "download": "transferência", "tokenRefresh": "renovação do token", "tokenExchange": "troca do token", "api": "pedido API", "paperExport": "exportação do Paper"},
  "zh": {"http": "Dropbox {operation}失败（HTTP {status}）：{body}", "appKey": "必须提供应用密钥", "unauthenticated": "尚未验证身份", "missingRefresh": "无法刷新：缺少刷新令牌或应用密钥", "upload": "上传", "download": "下载", "tokenRefresh": "刷新令牌", "tokenExchange": "交换令牌", "api": "API 请求", "paperExport": "导出 Paper"},
  "ja": {"http": "Dropbox の{operation}に失敗しました（HTTP {status}）: {body}", "appKey": "アプリキーが必要です", "unauthenticated": "認証されていません", "missingRefresh": "更新できません: 更新トークンまたはアプリキーがありません", "upload": "アップロード", "download": "ダウンロード", "tokenRefresh": "トークン更新", "tokenExchange": "トークン交換", "api": "API リクエスト", "paperExport": "Paper のエクスポート"},
  "ko": {"http": "Dropbox {operation} 실패 (HTTP {status}): {body}", "appKey": "앱 키가 필요합니다", "unauthenticated": "인증되지 않았습니다", "missingRefresh": "갱신할 수 없음: 갱신 토큰 또는 앱 키가 없습니다", "upload": "업로드", "download": "다운로드", "tokenRefresh": "토큰 갱신", "tokenExchange": "토큰 교환", "api": "API 요청", "paperExport": "Paper 내보내기"},
  "ar": {"http": "فشل {operation} في Dropbox ‏(HTTP {status}): {body}", "appKey": "مفتاح التطبيق مطلوب", "unauthenticated": "لم تتم المصادقة", "missingRefresh": "تعذر التجديد: رمز التجديد أو مفتاح التطبيق مفقود", "upload": "الرفع", "download": "التنزيل", "tokenRefresh": "تجديد الرمز", "tokenExchange": "تبادل الرمز", "api": "طلب API", "paperExport": "تصدير Paper"},
};
