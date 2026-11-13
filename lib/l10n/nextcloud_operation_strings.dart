import 'package:flutter/widgets.dart';

import '../services/nextcloud_operation_failure.dart';

/// Localize recognized Nextcloud messages, leaving remote details intact.
String localizedNextcloudError(BuildContext context, Object error) =>
    localizedNextcloudErrorForLanguage(
      Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
      error,
    );

String localizedNextcloudErrorForLanguage(String language, Object error) {
  if (error is! NextcloudOperationFailure) return error.toString();
  final template =
      (_messages[language] ?? _messages['en']!)[error.code.name] ??
      error.message;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "browserConnectionFailed": "The browser could not access Nextcloud at {uri} from {origin}. No HTTP response was available. Check the browser Network/Console for CORS preflight, TLS certificate, mixed-content or network failures. The server must allow this app origin, PROPFIND, and Authorization, Depth and Content-Type headers. An HTTPS app requires an HTTPS server. Use the desktop/mobile app if cross-origin WebDAV cannot be enabled. Details: {error}",
    "invalidIdentity": "Format must be username@https://nextcloud.example.com",
    "connectionFailed": "Connection failed: {error}",
    "list": "Failed to list path \"{path}\" (HTTP {status})",
    "upload": "Nextcloud upload failed (HTTP {status}): {body}",
    "download": "Nextcloud download failed (HTTP {status}): {body}",
    "createFolder": "Failed to create folder \"{path}\" (HTTP {status})",
    "delete": "Nextcloud delete failed (HTTP {status}): {body}",
    "move": "Nextcloud move failed (HTTP {status}): {body}",
    "share": "OCS share creation failed (HTTP {status}): {body}",
    "shareParse": "Failed to parse share URL from OCS response",
    "listVersions": "Failed to list versions (HTTP {status})",
    "restoreVersion": "Restore version failed (HTTP {status}): {body}",
    "notAuthenticated": "Not authenticated. Please connect to Nextcloud first.",
    "propfind": "PROPFIND failed for {uri}: {error}",
    "rangeDownload": "Nextcloud range download failed (HTTP {status})",
    "chunkCreate": "Chunked MKCOL failed ({status})",
    "chunkUpload": "Chunked PUT failed at offset {offset} ({status})",
    "chunkFinish": "Chunked MOVE failed ({status})",
    "deltaUpload": "Delta block upload failed at offset {offset} ({status})",
  },
  'de': {
    "browserConnectionFailed": "Der Browser konnte Nextcloud unter {uri} von {origin} nicht erreichen. Keine HTTP-Antwort verfügbar. Prüfen Sie Netzwerk/Konsole auf CORS-Preflight, TLS-Zertifikat, gemischte Inhalte oder Netzwerkfehler. Der Server muss diesen App-Ursprung, PROPFIND sowie Authorization, Depth und Content-Type erlauben. Eine HTTPS-App benötigt einen HTTPS-Server. Verwenden Sie andernfalls die Desktop-/Mobil-App. Details: {error}",
    "invalidIdentity": "Format: benutzername@https://nextcloud.example.com",
    "connectionFailed": "Verbindung fehlgeschlagen: {error}",
    "list": "Pfad „{path}“ konnte nicht aufgelistet werden (HTTP {status})",
    "upload": "Nextcloud-Upload fehlgeschlagen (HTTP {status}): {body}",
    "download": "Nextcloud-Download fehlgeschlagen (HTTP {status}): {body}",
    "createFolder":
        "Ordner „{path}“ konnte nicht erstellt werden (HTTP {status})",
    "delete": "Nextcloud-Löschen fehlgeschlagen (HTTP {status}): {body}",
    "move": "Nextcloud-Verschieben fehlgeschlagen (HTTP {status}): {body}",
    "share":
        "OCS-Freigabe konnte nicht erstellt werden (HTTP {status}): {body}",
    "shareParse":
        "Freigabe-URL konnte nicht aus der OCS-Antwort gelesen werden",
    "listVersions":
        "Versionen konnten nicht aufgelistet werden (HTTP {status})",
    "restoreVersion":
        "Version konnte nicht wiederhergestellt werden (HTTP {status}): {body}",
    "notAuthenticated":
        "Nicht angemeldet. Bitte verbinden Sie sich zuerst mit Nextcloud.",
    "propfind": "PROPFIND für {uri} fehlgeschlagen: {error}",
    "rangeDownload":
        "Nextcloud-Bereichsdownload fehlgeschlagen (HTTP {status})",
    "chunkCreate": "MKCOL für Block-Upload fehlgeschlagen ({status})",
    "chunkUpload":
        "PUT für Block bei Offset {offset} fehlgeschlagen ({status})",
    "chunkFinish": "MOVE für Block-Upload fehlgeschlagen ({status})",
    "deltaUpload":
        "Delta-Block-Upload bei Offset {offset} fehlgeschlagen ({status})",
  },
  'fr': {
    "browserConnectionFailed": "Le navigateur ne peut pas accéder à Nextcloud à {uri} depuis {origin}. Aucune réponse HTTP disponible. Vérifiez Réseau/Console : prérequête CORS, certificat TLS, contenu mixte ou réseau. Le serveur doit autoriser cette origine, PROPFIND et les en-têtes Authorization, Depth et Content-Type. Une application HTTPS nécessite un serveur HTTPS. Sinon, utilisez l’application bureau/mobile. Détails : {error}",
    "invalidIdentity":
        "Format attendu : utilisateur@https://nextcloud.example.com",
    "connectionFailed": "Échec de la connexion : {error}",
    "list": "Impossible de lister « {path} » (HTTP {status})",
    "upload": "Échec de l’envoi Nextcloud (HTTP {status}) : {body}",
    "download": "Échec du téléchargement Nextcloud (HTTP {status}) : {body}",
    "createFolder": "Impossible de créer le dossier « {path} » (HTTP {status})",
    "delete": "Échec de la suppression Nextcloud (HTTP {status}) : {body}",
    "move": "Échec du déplacement Nextcloud (HTTP {status}) : {body}",
    "share": "Échec de création du partage OCS (HTTP {status}) : {body}",
    "shareParse": "Impossible d’extraire l’URL de partage de la réponse OCS",
    "listVersions": "Impossible de lister les versions (HTTP {status})",
    "restoreVersion":
        "Échec de restauration de la version (HTTP {status}) : {body}",
    "notAuthenticated": "Non authentifié. Connectez-vous d’abord à Nextcloud.",
    "propfind": "Échec de PROPFIND pour {uri} : {error}",
    "rangeDownload":
        "Échec du téléchargement partiel Nextcloud (HTTP {status})",
    "chunkCreate": "Échec de MKCOL pour l’envoi par blocs ({status})",
    "chunkUpload": "Échec de PUT par blocs à la position {offset} ({status})",
    "chunkFinish": "Échec de MOVE pour l’envoi par blocs ({status})",
    "deltaUpload":
        "Échec de l’envoi du bloc delta à la position {offset} ({status})",
  },
  'es': {
    "browserConnectionFailed": "El navegador no pudo acceder a Nextcloud en {uri} desde {origin}. Sin respuesta HTTP. Revise Red/Consola: solicitud previa CORS, certificado TLS, contenido mixto o red. El servidor debe permitir este origen, PROPFIND y las cabeceras Authorization, Depth y Content-Type. Una aplicación HTTPS requiere un servidor HTTPS. De lo contrario, use la aplicación de escritorio/móvil. Detalles: {error}",
    "invalidIdentity":
        "Formato requerido: usuario@https://nextcloud.example.com",
    "connectionFailed": "Error de conexión: {error}",
    "list": "No se pudo listar «{path}» (HTTP {status})",
    "upload": "Error al subir a Nextcloud (HTTP {status}): {body}",
    "download": "Error al descargar de Nextcloud (HTTP {status}): {body}",
    "createFolder": "No se pudo crear la carpeta «{path}» (HTTP {status})",
    "delete": "Error al eliminar en Nextcloud (HTTP {status}): {body}",
    "move": "Error al mover en Nextcloud (HTTP {status}): {body}",
    "share": "Error al crear el enlace OCS (HTTP {status}): {body}",
    "shareParse": "No se pudo obtener la URL compartida de la respuesta OCS",
    "listVersions": "No se pudieron listar las versiones (HTTP {status})",
    "restoreVersion": "Error al restaurar la versión (HTTP {status}): {body}",
    "notAuthenticated": "No autenticado. Conéctate primero a Nextcloud.",
    "propfind": "Error PROPFIND en {uri}: {error}",
    "rangeDownload": "Error de descarga parcial de Nextcloud (HTTP {status})",
    "chunkCreate": "Error MKCOL en la subida por bloques ({status})",
    "chunkUpload":
        "Error de PUT por bloques en el desplazamiento {offset} ({status})",
    "chunkFinish": "Error MOVE en la subida por bloques ({status})",
    "deltaUpload": "Error al subir el bloque delta en el desplazamiento {offset} ({status})",
  },
  'pt': {
    "browserConnectionFailed": "O navegador não conseguiu acessar Nextcloud em {uri} a partir de {origin}. Sem resposta HTTP. Verifique Rede/Console: preflight CORS, certificado TLS, conteúdo misto ou rede. O servidor deve permitir esta origem, PROPFIND e os cabeçalhos Authorization, Depth e Content-Type. Uma aplicação HTTPS exige um servidor HTTPS. Caso contrário, use a aplicação desktop/móvel. Detalhes: {error}",
    "invalidIdentity": "Formato exigido: usuario@https://nextcloud.example.com",
    "connectionFailed": "Falha na conexão: {error}",
    "list": "Não foi possível listar “{path}” (HTTP {status})",
    "upload": "Falha no envio ao Nextcloud (HTTP {status}): {body}",
    "download": "Falha no download do Nextcloud (HTTP {status}): {body}",
    "createFolder": "Não foi possível criar a pasta “{path}” (HTTP {status})",
    "delete": "Falha ao excluir no Nextcloud (HTTP {status}): {body}",
    "move": "Falha ao mover no Nextcloud (HTTP {status}): {body}",
    "share": "Falha ao criar compartilhamento OCS (HTTP {status}): {body}",
    "shareParse":
        "Não foi possível obter a URL de compartilhamento da resposta OCS",
    "listVersions": "Não foi possível listar as versões (HTTP {status})",
    "restoreVersion": "Falha ao restaurar versão (HTTP {status}): {body}",
    "notAuthenticated": "Não autenticado. Conecte-se primeiro ao Nextcloud.",
    "propfind": "Falha no PROPFIND de {uri}: {error}",
    "rangeDownload": "Falha no download parcial do Nextcloud (HTTP {status})",
    "chunkCreate": "Falha de MKCOL no envio em blocos ({status})",
    "chunkUpload": "Falha de PUT em blocos no deslocamento {offset} ({status})",
    "chunkFinish": "Falha de MOVE no envio em blocos ({status})",
    "deltaUpload":
        "Falha ao enviar bloco delta no deslocamento {offset} ({status})",
  },
  'zh': {
    "browserConnectionFailed": "浏览器无法从 {origin} 访问 {uri} 的 Nextcloud，未获得 HTTP 响应。请在网络/控制台检查 CORS 预检、TLS 证书、混合内容或网络故障。服务器必须允许此应用来源、PROPFIND 和 Authorization、Depth、Content-Type 请求头。HTTPS 应用需要 HTTPS 服务器。如果无法启用跨域 WebDAV，请使用桌面/移动应用。详情：{error}",
    "invalidIdentity": "格式必须为 username@https://nextcloud.example.com",
    "connectionFailed": "连接失败：{error}",
    "list": "无法列出路径“{path}”（HTTP {status}）",
    "upload": "Nextcloud 上传失败（HTTP {status}）：{body}",
    "download": "Nextcloud 下载失败（HTTP {status}）：{body}",
    "createFolder": "无法创建文件夹“{path}”（HTTP {status}）",
    "delete": "Nextcloud 删除失败（HTTP {status}）：{body}",
    "move": "Nextcloud 移动失败（HTTP {status}）：{body}",
    "share": "创建 OCS 共享失败（HTTP {status}）：{body}",
    "shareParse": "无法从 OCS 响应中解析共享链接",
    "listVersions": "无法列出版本（HTTP {status}）",
    "restoreVersion": "恢复版本失败（HTTP {status}）：{body}",
    "notAuthenticated": "未通过身份验证。请先连接 Nextcloud。",
    "propfind": "对 {uri} 的 PROPFIND 请求失败：{error}",
    "rangeDownload": "Nextcloud 范围下载失败（HTTP {status}）",
    "chunkCreate": "分块 MKCOL 失败（{status}）",
    "chunkUpload": "偏移量 {offset} 处的分块 PUT 失败（{status}）",
    "chunkFinish": "分块 MOVE 失败（{status}）",
    "deltaUpload": "偏移量 {offset} 处的增量块上传失败（{status}）",
  },
  'ja': {
    "browserConnectionFailed": "ブラウザーは {origin} から {uri} の Nextcloud にアクセスできませんでした。HTTP 応答がありません。ネットワーク/コンソールで CORS プリフライト、TLS 証明書、混在コンテンツ、接続障害を確認してください。サーバーでこのオリジン、PROPFIND、Authorization・Depth・Content-Type ヘッダーを許可する必要があります。HTTPS アプリには HTTPS サーバーが必要です。設定できない場合はデスクトップ/モバイル版を使用してください。詳細: {error}",
    "invalidIdentity": "形式: username@https://nextcloud.example.com",
    "connectionFailed": "接続に失敗しました: {error}",
    "list": "パス「{path}」を一覧表示できません（HTTP {status}）",
    "upload": "Nextcloud へのアップロードに失敗しました（HTTP {status}）: {body}",
    "download": "Nextcloud からのダウンロードに失敗しました（HTTP {status}）: {body}",
    "createFolder": "フォルダー「{path}」を作成できません（HTTP {status}）",
    "delete": "Nextcloud の削除に失敗しました（HTTP {status}）: {body}",
    "move": "Nextcloud の移動に失敗しました（HTTP {status}）: {body}",
    "share": "OCS 共有の作成に失敗しました（HTTP {status}）: {body}",
    "shareParse": "OCS 応答から共有 URL を取得できませんでした",
    "listVersions": "バージョンを一覧表示できません（HTTP {status}）",
    "restoreVersion": "バージョンの復元に失敗しました（HTTP {status}）: {body}",
    "notAuthenticated": "認証されていません。先に Nextcloud に接続してください。",
    "propfind": "{uri} の PROPFIND に失敗しました: {error}",
    "rangeDownload": "Nextcloud の範囲ダウンロードに失敗しました（HTTP {status}）",
    "chunkCreate": "分割アップロードの MKCOL に失敗しました（{status}）",
    "chunkUpload": "オフセット {offset} の分割 PUT に失敗しました（{status}）",
    "chunkFinish": "分割アップロードの MOVE に失敗しました（{status}）",
    "deltaUpload": "オフセット {offset} の差分ブロックをアップロードできません（{status}）",
  },
  'ko': {
    "browserConnectionFailed": "브라우저가 {origin}에서 {uri}의 Nextcloud에 접근하지 못했습니다. HTTP 응답이 없습니다. 네트워크/콘솔에서 CORS 사전 요청, TLS 인증서, 혼합 콘텐츠 또는 네트워크 오류를 확인하세요. 서버는 이 출처, PROPFIND 및 Authorization, Depth, Content-Type 헤더를 허용해야 합니다. HTTPS 앱에는 HTTPS 서버가 필요합니다. 설정할 수 없으면 데스크톱/모바일 앱을 사용하세요. 세부 정보: {error}",
    "invalidIdentity": "형식: username@https://nextcloud.example.com",
    "connectionFailed": "연결 실패: {error}",
    "list": "경로 \"{path}\" 목록을 불러올 수 없습니다 (HTTP {status})",
    "upload": "Nextcloud 업로드 실패 (HTTP {status}): {body}",
    "download": "Nextcloud 다운로드 실패 (HTTP {status}): {body}",
    "createFolder": "폴더 \"{path}\"을(를) 만들 수 없습니다 (HTTP {status})",
    "delete": "Nextcloud 삭제 실패 (HTTP {status}): {body}",
    "move": "Nextcloud 이동 실패 (HTTP {status}): {body}",
    "share": "OCS 공유 생성 실패 (HTTP {status}): {body}",
    "shareParse": "OCS 응답에서 공유 URL을 읽을 수 없습니다",
    "listVersions": "버전 목록을 불러올 수 없습니다 (HTTP {status})",
    "restoreVersion": "버전 복원 실패 (HTTP {status}): {body}",
    "notAuthenticated": "인증되지 않았습니다. 먼저 Nextcloud에 연결하세요.",
    "propfind": "{uri} PROPFIND 실패: {error}",
    "rangeDownload": "Nextcloud 범위 다운로드 실패 (HTTP {status})",
    "chunkCreate": "분할 업로드 MKCOL 실패 ({status})",
    "chunkUpload": "오프셋 {offset}에서 분할 PUT 실패 ({status})",
    "chunkFinish": "분할 업로드 MOVE 실패 ({status})",
    "deltaUpload": "오프셋 {offset}에서 델타 블록 업로드 실패 ({status})",
  },
  'ar': {
    "browserConnectionFailed": "تعذر على المتصفح الوصول إلى Nextcloud في {uri} من {origin}. لا توجد استجابة HTTP. افحص الشبكة/وحدة التحكم للتحقق من طلب CORS التمهيدي أو شهادة TLS أو المحتوى المختلط أو فشل الشبكة. يجب أن يسمح الخادم بهذا المصدر وPROPFIND ورؤوس Authorization وDepth وContent-Type. يتطلب تطبيق HTTPS خادم HTTPS. وإلا فاستخدم تطبيق سطح المكتب/الهاتف. التفاصيل: {error}",
    "invalidIdentity":
        "التنسيق المطلوب: username@https://nextcloud.example.com",
    "connectionFailed": "فشل الاتصال: {error}",
    "list": "تعذّر عرض المسار «{path}» (HTTP {status})",
    "upload": "فشل الرفع إلى Nextcloud ‏(HTTP {status}): {body}",
    "download": "فشل التنزيل من Nextcloud ‏(HTTP {status}): {body}",
    "createFolder": "تعذّر إنشاء المجلد «{path}» (HTTP {status})",
    "delete": "فشل الحذف في Nextcloud ‏(HTTP {status}): {body}",
    "move": "فشل النقل في Nextcloud ‏(HTTP {status}): {body}",
    "share": "فشل إنشاء مشاركة OCS ‏(HTTP {status}): {body}",
    "shareParse": "تعذّر استخراج رابط المشاركة من استجابة OCS",
    "listVersions": "تعذّر عرض الإصدارات (HTTP {status})",
    "restoreVersion": "فشلت استعادة الإصدار (HTTP {status}): {body}",
    "notAuthenticated": "لم تتم المصادقة. اتصل بـ Nextcloud أولًا.",
    "propfind": "فشل PROPFIND لـ {uri}: {error}",
    "rangeDownload": "فشل تنزيل النطاق من Nextcloud ‏(HTTP {status})",
    "chunkCreate": "فشل MKCOL للرفع المجزأ ({status})",
    "chunkUpload": "فشل PUT المجزأ عند الموضع {offset} ‏({status})",
    "chunkFinish": "فشل MOVE للرفع المجزأ ({status})",
    "deltaUpload": "فشل رفع كتلة التغييرات عند الموضع {offset} ‏({status})",
  },
};
