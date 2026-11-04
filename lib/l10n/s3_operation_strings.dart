import 'package:flutter/widgets.dart';
import '../services/s3_operation_failure.dart';

/// Localize S3 operation errors, preserving provider responses verbatim.
String localizedS3Error(BuildContext context, S3OperationFailure error) {
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final messages = _messages[language] ?? _messages['en']!;
  final bodyCodes = {
    S3OperationCode.connection,
    S3OperationCode.list,
    S3OperationCode.upload,
    S3OperationCode.multipartInitiate,
    S3OperationCode.multipartComplete,
    S3OperationCode.listParts,
    S3OperationCode.download,
    S3OperationCode.createFolder,
    S3OperationCode.delete,
    S3OperationCode.copy
  };
  final values = <String, Object>{...error.arguments};
  String template;
  if (bodyCodes.contains(error.code)) {
    template = messages['httpBody']!;
    values['operation'] = messages[error.code.name]!;
  } else if (error.code == S3OperationCode.rangeDownload) {
    template = messages['httpStatus']!;
    values['operation'] = messages[error.code.name]!;
  } else {
    template = messages[error.code.name] ?? error.message;
  }
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = values[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "httpBody": "{operation} failed (HTTP {status}): {body}",
    "httpStatus": "{operation} failed (HTTP {status})",
    "connection": "S3 connection test",
    "list": "S3 list",
    "upload": "S3 upload",
    "multipartInitiate": "S3 initiate multipart",
    "multipartComplete": "S3 complete multipart",
    "listParts": "S3 ListParts",
    "download": "S3 download",
    "createFolder": "S3 create folder",
    "delete": "S3 delete",
    "copy": "S3 copy",
    "rangeDownload": "S3 range download",
    "invalidCredentials":
        "Invalid S3 credentials format. Use: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "S3 initiate multipart: no UploadId in response",
    "partUpload": "S3 upload part {part} failed (HTTP {status})",
    "missingEtag": "S3 upload part {part}: no ETag in response",
    "missingInterruptedUpload": "No interrupted upload found for {path}",
    "notAuthenticated": "Not authenticated. Call login() first.",
  },
  'de': {
    "httpBody": "{operation} fehlgeschlagen (HTTP {status}): {body}",
    "httpStatus": "{operation} fehlgeschlagen (HTTP {status})",
    "connection": "S3-Verbindungstest",
    "list": "S3-Auflistung",
    "upload": "S3-Upload",
    "multipartInitiate": "S3-Start des mehrteiligen Uploads",
    "multipartComplete": "S3-Abschluss des mehrteiligen Uploads",
    "listParts": "S3 ListParts",
    "download": "S3-Download",
    "createFolder": "S3-Ordnererstellung",
    "delete": "S3-Löschen",
    "copy": "S3-Kopieren",
    "rangeDownload": "S3-Bereichsdownload",
    "invalidCredentials":
        "Ungültiges S3-Zugangsdatenformat. Verwenden Sie: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId":
        "S3-Start des mehrteiligen Uploads: keine UploadId in der Antwort",
    "partUpload": "S3-Upload von Teil {part} fehlgeschlagen (HTTP {status})",
    "missingEtag": "S3-Upload von Teil {part}: kein ETag in der Antwort",
    "missingInterruptedUpload":
        "Kein unterbrochener Upload für {path} gefunden",
    "notAuthenticated": "Nicht angemeldet. Rufen Sie zuerst login() auf.",
  },
  'fr': {
    "httpBody": "Échec de {operation} (HTTP {status}) : {body}",
    "httpStatus": "Échec de {operation} (HTTP {status})",
    "connection": "test de connexion S3",
    "list": "liste S3",
    "upload": "envoi S3",
    "multipartInitiate": "démarrage de l’envoi S3 en plusieurs parties",
    "multipartComplete": "finalisation de l’envoi S3 en plusieurs parties",
    "listParts": "ListParts S3",
    "download": "téléchargement S3",
    "createFolder": "création du dossier S3",
    "delete": "suppression S3",
    "copy": "copie S3",
    "rangeDownload": "téléchargement partiel S3",
    "invalidCredentials":
        "Format des identifiants S3 invalide. Utilisez : accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId":
        "Démarrage S3 en plusieurs parties : aucun UploadId dans la réponse",
    "partUpload": "Échec de l’envoi S3 de la partie {part} (HTTP {status})",
    "missingEtag": "Envoi S3 de la partie {part} : aucun ETag dans la réponse",
    "missingInterruptedUpload": "Aucun envoi interrompu trouvé pour {path}",
    "notAuthenticated": "Non authentifié. Appelez d’abord login().",
  },
  'es': {
    "httpBody": "Error de {operation} (HTTP {status}): {body}",
    "httpStatus": "Error de {operation} (HTTP {status})",
    "connection": "prueba de conexión S3",
    "list": "listado S3",
    "upload": "subida a S3",
    "multipartInitiate": "inicio de subida S3 por partes",
    "multipartComplete": "finalización de subida S3 por partes",
    "listParts": "ListParts de S3",
    "download": "descarga de S3",
    "createFolder": "creación de carpeta S3",
    "delete": "eliminación en S3",
    "copy": "copia en S3",
    "rangeDownload": "descarga parcial S3",
    "invalidCredentials":
        "Formato de credenciales S3 no válido. Usa: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId":
        "Inicio de subida S3 por partes: la respuesta no contiene UploadId",
    "partUpload": "Error al subir la parte {part} a S3 (HTTP {status})",
    "missingEtag":
        "Subida S3 de la parte {part}: la respuesta no contiene ETag",
    "missingInterruptedUpload":
        "No se encontró una subida interrumpida para {path}",
    "notAuthenticated": "No autenticado. Llama primero a login().",
  },
  'pt': {
    "httpBody": "Falha de {operation} (HTTP {status}): {body}",
    "httpStatus": "Falha de {operation} (HTTP {status})",
    "connection": "teste de conexão S3",
    "list": "listagem S3",
    "upload": "envio S3",
    "multipartInitiate": "início de envio S3 em partes",
    "multipartComplete": "conclusão de envio S3 em partes",
    "listParts": "ListParts do S3",
    "download": "download S3",
    "createFolder": "criação de pasta S3",
    "delete": "exclusão S3",
    "copy": "cópia S3",
    "rangeDownload": "download parcial S3",
    "invalidCredentials":
        "Formato de credenciais S3 inválido. Use: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "Início de envio S3 em partes: resposta sem UploadId",
    "partUpload": "Falha ao enviar a parte {part} ao S3 (HTTP {status})",
    "missingEtag": "Envio S3 da parte {part}: resposta sem ETag",
    "missingInterruptedUpload":
        "Nenhum envio interrompido encontrado para {path}",
    "notAuthenticated": "Não autenticado. Chame login() primeiro.",
  },
  'zh': {
    "httpBody": "{operation}失败（HTTP {status}）：{body}",
    "httpStatus": "{operation}失败（HTTP {status}）",
    "connection": "S3 连接测试",
    "list": "S3 列表获取",
    "upload": "S3 上传",
    "multipartInitiate": "S3 分段上传初始化",
    "multipartComplete": "S3 分段上传完成",
    "listParts": "S3 ListParts",
    "download": "S3 下载",
    "createFolder": "S3 创建文件夹",
    "delete": "S3 删除",
    "copy": "S3 复制",
    "rangeDownload": "S3 范围下载",
    "invalidCredentials":
        "S3 凭据格式无效。请使用：accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "S3 分段上传初始化：响应中没有 UploadId",
    "partUpload": "S3 上传第 {part} 部分失败（HTTP {status}）",
    "missingEtag": "S3 上传第 {part} 部分：响应中没有 ETag",
    "missingInterruptedUpload": "未找到 {path} 的中断上传",
    "notAuthenticated": "未通过身份验证。请先调用 login()。",
  },
  'ja': {
    "httpBody": "{operation}に失敗しました（HTTP {status}）: {body}",
    "httpStatus": "{operation}に失敗しました（HTTP {status}）",
    "connection": "S3 接続テスト",
    "list": "S3 一覧取得",
    "upload": "S3 アップロード",
    "multipartInitiate": "S3 マルチパート開始",
    "multipartComplete": "S3 マルチパート完了処理",
    "listParts": "S3 ListParts",
    "download": "S3 ダウンロード",
    "createFolder": "S3 フォルダー作成",
    "delete": "S3 削除",
    "copy": "S3 コピー",
    "rangeDownload": "S3 範囲ダウンロード",
    "invalidCredentials":
        "S3 認証情報の形式が無効です。形式: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "S3 マルチパート開始: 応答に UploadId がありません",
    "partUpload": "S3 パート {part} のアップロードに失敗しました（HTTP {status}）",
    "missingEtag": "S3 パート {part}: 応答に ETag がありません",
    "missingInterruptedUpload": "{path} の中断されたアップロードが見つかりません",
    "notAuthenticated": "認証されていません。先に login() を呼び出してください。",
  },
  'ko': {
    "httpBody": "{operation} 실패 (HTTP {status}): {body}",
    "httpStatus": "{operation} 실패 (HTTP {status})",
    "connection": "S3 연결 테스트",
    "list": "S3 목록 조회",
    "upload": "S3 업로드",
    "multipartInitiate": "S3 멀티파트 시작",
    "multipartComplete": "S3 멀티파트 완료",
    "listParts": "S3 ListParts",
    "download": "S3 다운로드",
    "createFolder": "S3 폴더 만들기",
    "delete": "S3 삭제",
    "copy": "S3 복사",
    "rangeDownload": "S3 범위 다운로드",
    "invalidCredentials":
        "S3 자격 증명 형식이 올바르지 않습니다. 형식: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "S3 멀티파트 시작: 응답에 UploadId가 없습니다",
    "partUpload": "S3 파트 {part} 업로드 실패 (HTTP {status})",
    "missingEtag": "S3 파트 {part}: 응답에 ETag가 없습니다",
    "missingInterruptedUpload": "{path}의 중단된 업로드가 없습니다",
    "notAuthenticated": "인증되지 않았습니다. 먼저 login()을 호출하세요.",
  },
  'ar': {
    "httpBody": "فشل {operation} ‏(HTTP {status}): {body}",
    "httpStatus": "فشل {operation} ‏(HTTP {status})",
    "connection": "اختبار اتصال S3",
    "list": "عرض قائمة S3",
    "upload": "الرفع إلى S3",
    "multipartInitiate": "بدء رفع S3 متعدد الأجزاء",
    "multipartComplete": "إكمال رفع S3 متعدد الأجزاء",
    "listParts": "ListParts في S3",
    "download": "التنزيل من S3",
    "createFolder": "إنشاء مجلد S3",
    "delete": "الحذف في S3",
    "copy": "النسخ في S3",
    "rangeDownload": "تنزيل نطاق S3",
    "invalidCredentials":
        "تنسيق بيانات اعتماد S3 غير صالح. استخدم: accessKey@endpoint/bucket?region=us-east-1",
    "missingUploadId": "بدء رفع S3 متعدد الأجزاء: لا يحتوي الرد على UploadId",
    "partUpload": "فشل رفع الجزء {part} إلى S3 ‏(HTTP {status})",
    "missingEtag": "رفع الجزء {part} إلى S3: لا يحتوي الرد على ETag",
    "missingInterruptedUpload": "لم يُعثر على رفع متقطع لـ {path}",
    "notAuthenticated": "لم تتم المصادقة. استدعِ login() أولًا.",
  },
};
