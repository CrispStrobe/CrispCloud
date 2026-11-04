import 'package:flutter/widgets.dart';

/// Text for Azure and Backblaze connection setup.
class CloudSetupStrings {
  CloudSetupStrings(BuildContext context)
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
      "azure": "Connect to Azure Blob Storage",
      "b2": "Connect to Backblaze B2",
      "mode": "Authentication Mode",
      "accountName": "Account Name",
      "accountKey": "Account Key",
      "container": "Container",
      "sasToken": "SAS Token",
      "connectionString": "Connection String",
      "accountNameRequired": "Account Name is required",
      "accountKeyRequired": "Account Key is required",
      "containerRequired": "Container name is required",
      "sasUrlRequired": "SAS URL is required",
      "sasInvalid": "SAS URL does not appear to contain a valid query string",
      "sasTokenRequired": "SAS Token is required",
      "connectionRequired": "Connection String is required",
      "connectionInvalid":
          "Connection string is not valid. Expected format: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected":
          "Fields checked; connection not tested. Endpoint: {endpoint}",
      "testFailed": "Test failed: {error}",
      "test": "Test Connection",
      "accountHelp":
          "The storage account name (without .blob.core.windows.net)",
      "azureKeyHelp": "Found in Azure Portal → Storage account → Access keys",
      "fullUrl": "Full SAS URL",
      "tokenAccount": "Token + Account",
      "sasUrlHelp":
          "Full SAS URL from Azure Portal or az storage … generate-sas",
      "tokenHelp": "Token query string only (without the leading ?)",
      "appKeyId": "Application Key ID",
      "appKey": "Application Key",
      "optionalBucket": "Bucket Name (optional)",
      "appKeyIdRequired": "Application Key ID is required",
      "appKeyRequired": "Application Key is required",
      "keyShort":
          "Key ID appears too short. B2 Application Key IDs are typically 25+ characters.",
      "credentialsBucket":
          "Key ID length checked; credentials not verified (bucket: {bucket})",
      "credentialsAll":
          "Key ID length checked; credentials not verified (all buckets)",
      "b2Help":
          "Create an Application Key in Backblaze B2 Console → App Keys. Use a key with read/write access to the desired bucket.",
      "keyIdHelp": "The \"keyID\" shown when you create a B2 Application Key",
      "appKeyHelp":
          "The secret key shown once at creation time. Store it safely.",
      "bucketHelp": "Leave blank to browse all buckets accessible to this key",
      "checkFormat": "Check Format",
      "formatFailed": "Format check failed: {error}",
    },
    'de': {
      "azure": "Mit Azure Blob Storage verbinden",
      "b2": "Mit Backblaze B2 verbinden",
      "mode": "Authentifizierungsmethode",
      "accountName": "Kontoname",
      "accountKey": "Kontoschlüssel",
      "container": "Container",
      "sasToken": "SAS-Token",
      "connectionString": "Verbindungszeichenfolge",
      "accountNameRequired": "Kontoname ist erforderlich",
      "accountKeyRequired": "Kontoschlüssel ist erforderlich",
      "containerRequired": "Containername ist erforderlich",
      "sasUrlRequired": "SAS-URL ist erforderlich",
      "sasInvalid":
          "Die SAS-URL enthält offenbar keine gültige Abfragezeichenfolge",
      "sasTokenRequired": "SAS-Token ist erforderlich",
      "connectionRequired": "Verbindungszeichenfolge ist erforderlich",
      "connectionInvalid":
          "Ungültige Verbindungszeichenfolge. Erwartetes Format: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected":
          "Felder geprüft; Verbindung nicht getestet. Endpunkt: {endpoint}",
      "testFailed": "Test fehlgeschlagen: {error}",
      "test": "Verbindung testen",
      "accountHelp": "Der Speicherkontoname (ohne .blob.core.windows.net)",
      "azureKeyHelp":
          "Zu finden unter Azure Portal → Storage account → Access keys",
      "fullUrl": "Vollständige SAS-URL",
      "tokenAccount": "Token + Konto",
      "sasUrlHelp":
          "Vollständige SAS-URL aus Azure Portal oder az storage … generate-sas",
      "tokenHelp": "Nur Token-Abfragezeichenfolge (ohne führendes ?)",
      "appKeyId": "Anwendungsschlüssel-ID",
      "appKey": "Anwendungsschlüssel",
      "optionalBucket": "Bucketname (optional)",
      "appKeyIdRequired": "Anwendungsschlüssel-ID ist erforderlich",
      "appKeyRequired": "Anwendungsschlüssel ist erforderlich",
      "keyShort":
          "Die Schlüssel-ID ist zu kurz. B2-Anwendungsschlüssel-IDs haben normalerweise mindestens 25 Zeichen.",
      "credentialsBucket":
          "Länge der Schlüssel-ID geprüft; Zugangsdaten nicht überprüft (Bucket: {bucket})",
      "credentialsAll":
          "Länge der Schlüssel-ID geprüft; Zugangsdaten nicht überprüft (alle Buckets)",
      "b2Help":
          "Erstellen Sie einen Anwendungsschlüssel unter Backblaze B2 Console → App Keys. Verwenden Sie einen Schlüssel mit Lese- und Schreibzugriff auf den gewünschten Bucket.",
      "keyIdHelp":
          "Die beim Erstellen eines B2-Anwendungsschlüssels angezeigte „keyID“",
      "appKeyHelp":
          "Der geheime Schlüssel wird beim Erstellen einmal angezeigt. Bewahren Sie ihn sicher auf.",
      "bucketHelp":
          "Leer lassen, um alle für diesen Schlüssel zugänglichen Buckets anzuzeigen",
      "checkFormat": "Format prüfen",
      "formatFailed": "Formatprüfung fehlgeschlagen: {error}",
    },
    'fr': {
      "azure": "Se connecter à Azure Blob Storage",
      "b2": "Se connecter à Backblaze B2",
      "mode": "Mode d’authentification",
      "accountName": "Nom du compte",
      "accountKey": "Clé du compte",
      "container": "Conteneur",
      "sasToken": "Jeton SAS",
      "connectionString": "Chaîne de connexion",
      "accountNameRequired": "Le nom du compte est requis",
      "accountKeyRequired": "La clé du compte est requise",
      "containerRequired": "Le nom du conteneur est requis",
      "sasUrlRequired": "L’URL SAS est requise",
      "sasInvalid":
          "L’URL SAS ne semble pas contenir de chaîne de requête valide",
      "sasTokenRequired": "Le jeton SAS est requis",
      "connectionRequired": "La chaîne de connexion est requise",
      "connectionInvalid":
          "Chaîne de connexion invalide. Format attendu : DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected":
          "Champs vérifiés ; connexion non testée. Point de terminaison : {endpoint}",
      "testFailed": "Échec du test : {error}",
      "test": "Tester la connexion",
      "accountHelp": "Nom du compte de stockage (sans .blob.core.windows.net)",
      "azureKeyHelp": "Dans Azure Portal → Storage account → Access keys",
      "fullUrl": "URL SAS complète",
      "tokenAccount": "Jeton + compte",
      "sasUrlHelp":
          "URL SAS complète depuis Azure Portal ou az storage … generate-sas",
      "tokenHelp": "Chaîne de requête du jeton uniquement (sans le ? initial)",
      "appKeyId": "Identifiant de clé d’application",
      "appKey": "Clé d’application",
      "optionalBucket": "Nom du compartiment (facultatif)",
      "appKeyIdRequired": "L’identifiant de clé d’application est requis",
      "appKeyRequired": "La clé d’application est requise",
      "keyShort":
          "L’identifiant semble trop court. Les identifiants B2 comportent généralement au moins 25 caractères.",
      "credentialsBucket":
          "Longueur de l’identifiant vérifiée ; identifiants non vérifiés (compartiment : {bucket})",
      "credentialsAll":
          "Longueur de l’identifiant vérifiée ; identifiants non vérifiés (tous les compartiments)",
      "b2Help":
          "Créez une clé dans Backblaze B2 Console → App Keys avec accès en lecture et écriture au compartiment souhaité.",
      "keyIdHelp": "Le « keyID » affiché lors de la création d’une clé B2",
      "appKeyHelp":
          "La clé secrète n’est affichée qu’une fois à la création. Conservez-la en sécurité.",
      "bucketHelp":
          "Laissez vide pour parcourir tous les compartiments accessibles avec cette clé",
      "checkFormat": "Vérifier le format",
      "formatFailed": "Échec de la vérification du format : {error}",
    },
    'es': {
      "azure": "Conectar a Azure Blob Storage",
      "b2": "Conectar a Backblaze B2",
      "mode": "Modo de autenticación",
      "accountName": "Nombre de cuenta",
      "accountKey": "Clave de cuenta",
      "container": "Contenedor",
      "sasToken": "Token SAS",
      "connectionString": "Cadena de conexión",
      "accountNameRequired": "El nombre de cuenta es obligatorio",
      "accountKeyRequired": "La clave de cuenta es obligatoria",
      "containerRequired": "El nombre del contenedor es obligatorio",
      "sasUrlRequired": "La URL SAS es obligatoria",
      "sasInvalid": "La URL SAS no parece contener una consulta válida",
      "sasTokenRequired": "El token SAS es obligatorio",
      "connectionRequired": "La cadena de conexión es obligatoria",
      "connectionInvalid":
          "Cadena de conexión no válida. Formato esperado: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected":
          "Campos comprobados; conexión no probada. Endpoint: {endpoint}",
      "testFailed": "Error en la prueba: {error}",
      "test": "Probar conexión",
      "accountHelp":
          "Nombre de la cuenta de almacenamiento (sin .blob.core.windows.net)",
      "azureKeyHelp": "En Azure Portal → Storage account → Access keys",
      "fullUrl": "URL SAS completa",
      "tokenAccount": "Token + cuenta",
      "sasUrlHelp":
          "URL SAS completa de Azure Portal o az storage … generate-sas",
      "tokenHelp": "Solo la consulta del token (sin el ? inicial)",
      "appKeyId": "ID de clave de aplicación",
      "appKey": "Clave de aplicación",
      "optionalBucket": "Nombre del bucket (opcional)",
      "appKeyIdRequired": "El ID de clave de aplicación es obligatorio",
      "appKeyRequired": "La clave de aplicación es obligatoria",
      "keyShort":
          "El ID de clave parece demasiado corto. Los ID de B2 suelen tener 25 caracteres o más.",
      "credentialsBucket":
          "Longitud del ID comprobada; credenciales sin verificar (bucket: {bucket})",
      "credentialsAll":
          "Longitud del ID comprobada; credenciales sin verificar (todos los buckets)",
      "b2Help":
          "Crea una clave en Backblaze B2 Console → App Keys con acceso de lectura y escritura al bucket deseado.",
      "keyIdHelp": "El «keyID» mostrado al crear una clave de B2",
      "appKeyHelp":
          "La clave secreta se muestra una sola vez al crearla. Guárdala de forma segura.",
      "bucketHelp":
          "Déjalo vacío para ver todos los buckets accesibles con esta clave",
      "checkFormat": "Comprobar formato",
      "formatFailed": "Error al comprobar el formato: {error}",
    },
    'pt': {
      "azure": "Conectar ao Azure Blob Storage",
      "b2": "Conectar ao Backblaze B2",
      "mode": "Modo de autenticação",
      "accountName": "Nome da conta",
      "accountKey": "Chave da conta",
      "container": "Contêiner",
      "sasToken": "Token SAS",
      "connectionString": "Cadeia de conexão",
      "accountNameRequired": "O nome da conta é obrigatório",
      "accountKeyRequired": "A chave da conta é obrigatória",
      "containerRequired": "O nome do contêiner é obrigatório",
      "sasUrlRequired": "A URL SAS é obrigatória",
      "sasInvalid": "A URL SAS não parece conter uma consulta válida",
      "sasTokenRequired": "O token SAS é obrigatório",
      "connectionRequired": "A cadeia de conexão é obrigatória",
      "connectionInvalid":
          "Cadeia de conexão inválida. Formato esperado: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected":
          "Campos verificados; conexão não testada. Endpoint: {endpoint}",
      "testFailed": "Falha no teste: {error}",
      "test": "Testar conexão",
      "accountHelp":
          "Nome da conta de armazenamento (sem .blob.core.windows.net)",
      "azureKeyHelp": "Em Azure Portal → Storage account → Access keys",
      "fullUrl": "URL SAS completa",
      "tokenAccount": "Token + conta",
      "sasUrlHelp":
          "URL SAS completa do Azure Portal ou az storage … generate-sas",
      "tokenHelp": "Somente a consulta do token (sem o ? inicial)",
      "appKeyId": "ID da chave de aplicativo",
      "appKey": "Chave de aplicativo",
      "optionalBucket": "Nome do bucket (opcional)",
      "appKeyIdRequired": "O ID da chave de aplicativo é obrigatório",
      "appKeyRequired": "A chave de aplicativo é obrigatória",
      "keyShort":
          "O ID da chave parece curto demais. IDs B2 geralmente têm 25 caracteres ou mais.",
      "credentialsBucket":
          "Comprimento do ID verificado; credenciais não verificadas (bucket: {bucket})",
      "credentialsAll":
          "Comprimento do ID verificado; credenciais não verificadas (todos os buckets)",
      "b2Help":
          "Crie uma chave em Backblaze B2 Console → App Keys com acesso de leitura e gravação ao bucket desejado.",
      "keyIdHelp": "O “keyID” exibido ao criar uma chave B2",
      "appKeyHelp":
          "A chave secreta é exibida uma vez na criação. Guarde-a em segurança.",
      "bucketHelp":
          "Deixe em branco para navegar por todos os buckets acessíveis por esta chave",
      "checkFormat": "Verificar formato",
      "formatFailed": "Falha na verificação do formato: {error}",
    },
    'zh': {
      "azure": "连接 Azure Blob Storage",
      "b2": "连接 Backblaze B2",
      "mode": "身份验证方式",
      "accountName": "账户名",
      "accountKey": "账户密钥",
      "container": "容器",
      "sasToken": "SAS 令牌",
      "connectionString": "连接字符串",
      "accountNameRequired": "必须填写账户名",
      "accountKeyRequired": "必须填写账户密钥",
      "containerRequired": "必须填写容器名",
      "sasUrlRequired": "必须填写 SAS 地址",
      "sasInvalid": "SAS 地址似乎不包含有效的查询字符串",
      "sasTokenRequired": "必须填写 SAS 令牌",
      "connectionRequired": "必须填写连接字符串",
      "connectionInvalid":
          "连接字符串无效。预期格式：DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected": "字段已检查；未测试连接。端点：{endpoint}",
      "testFailed": "测试失败：{error}",
      "test": "测试连接",
      "accountHelp": "存储账户名（不含 .blob.core.windows.net）",
      "azureKeyHelp": "位于 Azure Portal → Storage account → Access keys",
      "fullUrl": "完整 SAS 地址",
      "tokenAccount": "令牌 + 账户",
      "sasUrlHelp": "来自 Azure Portal 或 az storage … generate-sas 的完整 SAS 地址",
      "tokenHelp": "仅输入令牌查询字符串（不含开头的 ?）",
      "appKeyId": "应用密钥 ID",
      "appKey": "应用密钥",
      "optionalBucket": "存储桶名称（可选）",
      "appKeyIdRequired": "必须填写应用密钥 ID",
      "appKeyRequired": "必须填写应用密钥",
      "keyShort": "密钥 ID 似乎过短。B2 应用密钥 ID 通常至少有 25 个字符。",
      "credentialsBucket": "已检查密钥 ID 长度；凭据未验证（存储桶：{bucket}）",
      "credentialsAll": "已检查密钥 ID 长度；凭据未验证（所有存储桶）",
      "b2Help": "在 Backblaze B2 Console → App Keys 中创建应用密钥，并授予目标存储桶的读写权限。",
      "keyIdHelp": "创建 B2 应用密钥时显示的“keyID”",
      "appKeyHelp": "私密密钥仅在创建时显示一次，请妥善保存。",
      "bucketHelp": "留空可浏览此密钥可访问的所有存储桶",
      "checkFormat": "检查格式",
      "formatFailed": "格式检查失败：{error}",
    },
    'ja': {
      "azure": "Azure Blob Storage に接続",
      "b2": "Backblaze B2 に接続",
      "mode": "認証方式",
      "accountName": "アカウント名",
      "accountKey": "アカウントキー",
      "container": "コンテナー",
      "sasToken": "SAS トークン",
      "connectionString": "接続文字列",
      "accountNameRequired": "アカウント名は必須です",
      "accountKeyRequired": "アカウントキーは必須です",
      "containerRequired": "コンテナー名は必須です",
      "sasUrlRequired": "SAS URL は必須です",
      "sasInvalid": "SAS URL に有効なクエリ文字列が含まれていないようです",
      "sasTokenRequired": "SAS トークンは必須です",
      "connectionRequired": "接続文字列は必須です",
      "connectionInvalid":
          "接続文字列が無効です。形式: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected": "入力欄を確認しました。接続はテストされていません。エンドポイント: {endpoint}",
      "testFailed": "テスト失敗: {error}",
      "test": "接続テスト",
      "accountHelp": "ストレージアカウント名（.blob.core.windows.net を除く）",
      "azureKeyHelp": "Azure Portal → Storage account → Access keys にあります",
      "fullUrl": "完全な SAS URL",
      "tokenAccount": "トークン＋アカウント",
      "sasUrlHelp":
          "Azure Portal または az storage … generate-sas から取得した完全な SAS URL",
      "tokenHelp": "トークンのクエリ文字列のみ（先頭の ? を除く）",
      "appKeyId": "アプリケーションキー ID",
      "appKey": "アプリケーションキー",
      "optionalBucket": "バケット名（任意）",
      "appKeyIdRequired": "アプリケーションキー ID は必須です",
      "appKeyRequired": "アプリケーションキーは必須です",
      "keyShort": "キー ID が短すぎます。B2 のアプリケーションキー ID は通常 25 文字以上です。",
      "credentialsBucket": "キー ID の長さを確認しました。認証情報は未検証です（バケット: {bucket}）",
      "credentialsAll": "キー ID の長さを確認しました。認証情報は未検証です（すべてのバケット）",
      "b2Help": "Backblaze B2 Console → App Keys で対象バケットへの読み書き権限を持つキーを作成します。",
      "keyIdHelp": "B2 アプリケーションキー作成時に表示される「keyID」",
      "appKeyHelp": "秘密キーは作成時に一度だけ表示されます。安全に保管してください。",
      "bucketHelp": "空欄にすると、このキーでアクセスできるすべてのバケットを参照できます",
      "checkFormat": "形式を確認",
      "formatFailed": "形式の確認に失敗しました: {error}",
    },
    'ko': {
      "azure": "Azure Blob Storage에 연결",
      "b2": "Backblaze B2에 연결",
      "mode": "인증 방식",
      "accountName": "계정 이름",
      "accountKey": "계정 키",
      "container": "컨테이너",
      "sasToken": "SAS 토큰",
      "connectionString": "연결 문자열",
      "accountNameRequired": "계정 이름은 필수입니다",
      "accountKeyRequired": "계정 키는 필수입니다",
      "containerRequired": "컨테이너 이름은 필수입니다",
      "sasUrlRequired": "SAS URL은 필수입니다",
      "sasInvalid": "SAS URL에 유효한 쿼리 문자열이 없는 것 같습니다",
      "sasTokenRequired": "SAS 토큰은 필수입니다",
      "connectionRequired": "연결 문자열은 필수입니다",
      "connectionInvalid":
          "연결 문자열이 올바르지 않습니다. 형식: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected": "필드를 확인했습니다. 연결은 테스트하지 않았습니다. 엔드포인트: {endpoint}",
      "testFailed": "테스트 실패: {error}",
      "test": "연결 테스트",
      "accountHelp": "저장소 계정 이름 (.blob.core.windows.net 제외)",
      "azureKeyHelp": "Azure Portal → Storage account → Access keys에서 확인",
      "fullUrl": "전체 SAS URL",
      "tokenAccount": "토큰 + 계정",
      "sasUrlHelp":
          "Azure Portal 또는 az storage … generate-sas에서 생성한 전체 SAS URL",
      "tokenHelp": "토큰 쿼리 문자열만 입력 (앞의 ? 제외)",
      "appKeyId": "애플리케이션 키 ID",
      "appKey": "애플리케이션 키",
      "optionalBucket": "버킷 이름 (선택 사항)",
      "appKeyIdRequired": "애플리케이션 키 ID는 필수입니다",
      "appKeyRequired": "애플리케이션 키는 필수입니다",
      "keyShort": "키 ID가 너무 짧습니다. B2 애플리케이션 키 ID는 보통 25자 이상입니다.",
      "credentialsBucket": "키 ID 길이를 확인했습니다. 자격 증명은 확인되지 않았습니다 (버킷: {bucket})",
      "credentialsAll": "키 ID 길이를 확인했습니다. 자격 증명은 확인되지 않았습니다 (모든 버킷)",
      "b2Help":
          "Backblaze B2 Console → App Keys에서 원하는 버킷에 대한 읽기/쓰기 권한이 있는 키를 만드세요.",
      "keyIdHelp": "B2 애플리케이션 키를 만들 때 표시되는 \"keyID\"",
      "appKeyHelp": "비밀 키는 생성 시 한 번만 표시됩니다. 안전하게 보관하세요.",
      "bucketHelp": "비워 두면 이 키로 접근할 수 있는 모든 버킷을 탐색합니다",
      "checkFormat": "형식 확인",
      "formatFailed": "형식 확인 실패: {error}",
    },
    'ar': {
      "azure": "الاتصال بـ Azure Blob Storage",
      "b2": "الاتصال بـ Backblaze B2",
      "mode": "طريقة المصادقة",
      "accountName": "اسم الحساب",
      "accountKey": "مفتاح الحساب",
      "container": "الحاوية",
      "sasToken": "رمز SAS",
      "connectionString": "سلسلة الاتصال",
      "accountNameRequired": "اسم الحساب مطلوب",
      "accountKeyRequired": "مفتاح الحساب مطلوب",
      "containerRequired": "اسم الحاوية مطلوب",
      "sasUrlRequired": "عنوان SAS مطلوب",
      "sasInvalid": "لا يبدو أن عنوان SAS يحتوي على سلسلة استعلام صالحة",
      "sasTokenRequired": "رمز SAS مطلوب",
      "connectionRequired": "سلسلة الاتصال مطلوبة",
      "connectionInvalid":
          "سلسلة الاتصال غير صالحة. التنسيق المتوقع: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…",
      "connected": "تم فحص الحقول؛ لم يُختبر الاتصال. نقطة النهاية: {endpoint}",
      "testFailed": "فشل الاختبار: {error}",
      "test": "اختبار الاتصال",
      "accountHelp": "اسم حساب التخزين (دون ‎.blob.core.windows.net)",
      "azureKeyHelp": "في Azure Portal ← Storage account ← Access keys",
      "fullUrl": "عنوان SAS كامل",
      "tokenAccount": "الرمز + الحساب",
      "sasUrlHelp":
          "عنوان SAS كامل من Azure Portal أو az storage … generate-sas",
      "tokenHelp": "سلسلة استعلام الرمز فقط (دون علامة ? الأولى)",
      "appKeyId": "معرّف مفتاح التطبيق",
      "appKey": "مفتاح التطبيق",
      "optionalBucket": "اسم الحاوية (اختياري)",
      "appKeyIdRequired": "معرّف مفتاح التطبيق مطلوب",
      "appKeyRequired": "مفتاح التطبيق مطلوب",
      "keyShort":
          "يبدو معرّف المفتاح قصيرًا جدًا. تتكون معرّفات B2 عادةً من 25 حرفًا أو أكثر.",
      "credentialsBucket":
          "تم فحص طول معرّف المفتاح؛ لم تُتحقق بيانات الاعتماد (الحاوية: {bucket})",
      "credentialsAll":
          "تم فحص طول معرّف المفتاح؛ لم تُتحقق بيانات الاعتماد (كل الحاويات)",
      "b2Help":
          "أنشئ مفتاح تطبيق في Backblaze B2 Console ← App Keys بصلاحية القراءة والكتابة للحاوية المطلوبة.",
      "keyIdHelp": "قيمة «keyID» المعروضة عند إنشاء مفتاح B2",
      "appKeyHelp": "يظهر المفتاح السري مرة واحدة عند إنشائه. احتفظ به بأمان.",
      "bucketHelp": "اتركه فارغًا لاستعراض كل الحاويات المتاحة لهذا المفتاح",
      "checkFormat": "التحقق من التنسيق",
      "formatFailed": "فشل التحقق من التنسيق: {error}",
    },
  };
}
