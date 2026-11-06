import 'package:flutter/widgets.dart';

/// Text for Hetzner Storage Box setup.
class HetznerSetupStrings {
  HetznerSetupStrings(BuildContext context)
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
      "connectTitle": "Connect to Hetzner Storage Box",
      "info":
          "connect via SFTP (port 23) or WebDAV (HTTPS). Your username is shown in the Robot & Storage Box panel in the Hetzner Cloud Console.",
      "usernameRequired": "Username is required (e.g. u123456)",
      "usernameFormat": "Username should be in uNNNNNN format (e.g. u123456)",
      "passwordRequired": "Password is required",
      "usernameHelp": "Format: uNNNNNN (shown in Hetzner console)",
      "protocol": "Protocol",
      "sftp": "SFTP  (port 23)",
      "subAccount": "Sub-account (optional)",
      "subHelp":
          "Leave blank to use the main account. Effective login: uNNNNNN-subN",
      "success": "Connection successful ({latency}ms)",
      "healthTimeout": "Connected but health check timed out",
    },
    'de': {
      "connectTitle": "Mit Hetzner Storage Box verbinden",
      "info":
          "Verbinden Sie sich über SFTP (Port 23) oder WebDAV (HTTPS). Ihren Benutzernamen finden Sie im Bereich Robot & Storage Box der Hetzner Cloud Console.",
      "usernameRequired": "Benutzername ist erforderlich (z. B. u123456)",
      "usernameFormat":
          "Der Benutzername sollte das Format uNNNNNN haben (z. B. u123456)",
      "passwordRequired": "Passwort ist erforderlich",
      "usernameHelp": "Format: uNNNNNN (in der Hetzner-Konsole angezeigt)",
      "protocol": "Protokoll",
      "sftp": "SFTP  (Port 23)",
      "subAccount": "Unterkonto (optional)",
      "subHelp":
          "Leer lassen, um das Hauptkonto zu verwenden. Effektive Anmeldung: uNNNNNN-subN",
      "success": "Verbindung erfolgreich ({latency} ms)",
      "healthTimeout":
          "Verbunden, aber die Zustandsprüfung hat das Zeitlimit überschritten",
    },
    'fr': {
      "connectTitle": "Se connecter à Hetzner Storage Box",
      "info":
          "Connectez-vous via SFTP (port 23) ou WebDAV (HTTPS). Votre nom d’utilisateur figure dans le panneau Robot & Storage Box de la console Hetzner Cloud.",
      "usernameRequired": "Le nom d’utilisateur est requis (ex. u123456)",
      "usernameFormat":
          "Le nom d’utilisateur doit respecter le format uNNNNNN (ex. u123456)",
      "passwordRequired": "Le mot de passe est requis",
      "usernameHelp": "Format : uNNNNNN (affiché dans la console Hetzner)",
      "protocol": "Protocole",
      "sftp": "SFTP  (port 23)",
      "subAccount": "Sous-compte (facultatif)",
      "subHelp":
          "Laissez vide pour utiliser le compte principal. Identifiant utilisé : uNNNNNN-subN",
      "success": "Connexion réussie ({latency} ms)",
      "healthTimeout": "Connecté, mais le contrôle d’état a expiré",
    },
    'es': {
      "connectTitle": "Conectar a Hetzner Storage Box",
      "info":
          "Conéctate mediante SFTP (puerto 23) o WebDAV (HTTPS). Tu usuario aparece en el panel Robot & Storage Box de Hetzner Cloud Console.",
      "usernameRequired": "El usuario es obligatorio (p. ej., u123456)",
      "usernameFormat":
          "El usuario debe tener el formato uNNNNNN (p. ej., u123456)",
      "passwordRequired": "La contraseña es obligatoria",
      "usernameHelp": "Formato: uNNNNNN (mostrado en la consola de Hetzner)",
      "protocol": "Protocolo",
      "sftp": "SFTP  (puerto 23)",
      "subAccount": "Subcuenta (opcional)",
      "subHelp":
          "Déjalo vacío para usar la cuenta principal. Usuario efectivo: uNNNNNN-subN",
      "success": "Conexión correcta ({latency} ms)",
      "healthTimeout":
          "Conectado, pero la comprobación de estado agotó el tiempo",
    },
    'pt': {
      "connectTitle": "Conectar ao Hetzner Storage Box",
      "info":
          "Conecte-se via SFTP (porta 23) ou WebDAV (HTTPS). Seu usuário aparece no painel Robot & Storage Box do Hetzner Cloud Console.",
      "usernameRequired": "O nome de usuário é obrigatório (ex.: u123456)",
      "usernameFormat":
          "O nome de usuário deve estar no formato uNNNNNN (ex.: u123456)",
      "passwordRequired": "A senha é obrigatória",
      "usernameHelp": "Formato: uNNNNNN (exibido no console Hetzner)",
      "protocol": "Protocolo",
      "sftp": "SFTP  (porta 23)",
      "subAccount": "Subconta (opcional)",
      "subHelp":
          "Deixe em branco para usar a conta principal. Login efetivo: uNNNNNN-subN",
      "success": "Conexão bem-sucedida ({latency} ms)",
      "healthTimeout": "Conectado, mas a verificação de integridade expirou",
    },
    'zh': {
      "connectTitle": "连接 Hetzner Storage Box",
      "info":
          "通过 SFTP（端口 23）或 WebDAV（HTTPS）连接。用户名显示在 Hetzner Cloud Console 的 Robot & Storage Box 面板中。",
      "usernameRequired": "必须填写用户名（例如 u123456）",
      "usernameFormat": "用户名应采用 uNNNNNN 格式（例如 u123456）",
      "passwordRequired": "必须填写密码",
      "usernameHelp": "格式：uNNNNNN（显示在 Hetzner 控制台中）",
      "protocol": "协议",
      "sftp": "SFTP（端口 23）",
      "subAccount": "子账户（可选）",
      "subHelp": "留空使用主账户。实际登录名：uNNNNNN-subN",
      "success": "连接成功（{latency} 毫秒）",
      "healthTimeout": "已连接，但健康检查超时",
    },
    'ja': {
      "connectTitle": "Hetzner Storage Box に接続",
      "info":
          "SFTP（ポート 23）または WebDAV（HTTPS）で接続します。ユーザー名は Hetzner Cloud Console の Robot & Storage Box パネルに表示されます。",
      "usernameRequired": "ユーザー名は必須です（例: u123456）",
      "usernameFormat": "ユーザー名は uNNNNNN 形式で入力してください（例: u123456）",
      "passwordRequired": "パスワードは必須です",
      "usernameHelp": "形式: uNNNNNN（Hetzner コンソールに表示）",
      "protocol": "プロトコル",
      "sftp": "SFTP（ポート 23）",
      "subAccount": "サブアカウント（任意）",
      "subHelp": "メインアカウントを使用するには空欄にします。ログイン名: uNNNNNN-subN",
      "success": "接続に成功しました（{latency} ミリ秒）",
      "healthTimeout": "接続しましたが、ヘルスチェックがタイムアウトしました",
    },
    'ko': {
      "connectTitle": "Hetzner Storage Box에 연결",
      "info":
          "SFTP (포트 23) 또는 WebDAV (HTTPS)로 연결합니다. 사용자 이름은 Hetzner Cloud Console의 Robot & Storage Box 패널에 표시됩니다.",
      "usernameRequired": "사용자 이름은 필수입니다 (예: u123456)",
      "usernameFormat": "사용자 이름은 uNNNNNN 형식이어야 합니다 (예: u123456)",
      "passwordRequired": "비밀번호는 필수입니다",
      "usernameHelp": "형식: uNNNNNN (Hetzner 콘솔에 표시)",
      "protocol": "프로토콜",
      "sftp": "SFTP (포트 23)",
      "subAccount": "하위 계정 (선택 사항)",
      "subHelp": "기본 계정을 사용하려면 비워 두세요. 실제 로그인: uNNNNNN-subN",
      "success": "연결 성공 ({latency}ms)",
      "healthTimeout": "연결되었지만 상태 확인 시간이 초과되었습니다",
    },
    'ar': {
      "connectTitle": "الاتصال بـ Hetzner Storage Box",
      "info":
          "اتصل عبر SFTP (المنفذ 23) أو WebDAV ‏(HTTPS). يظهر اسم المستخدم في لوحة Robot & Storage Box ضمن Hetzner Cloud Console.",
      "usernameRequired": "اسم المستخدم مطلوب (مثل u123456)",
      "usernameFormat":
          "يجب أن يكون اسم المستخدم بالتنسيق uNNNNNN (مثل u123456)",
      "passwordRequired": "كلمة المرور مطلوبة",
      "usernameHelp": "التنسيق: uNNNNNN (يظهر في لوحة Hetzner)",
      "protocol": "البروتوكول",
      "sftp": "SFTP (المنفذ 23)",
      "subAccount": "حساب فرعي (اختياري)",
      "subHelp":
          "اتركه فارغًا لاستخدام الحساب الرئيسي. اسم الدخول الفعلي: uNNNNNN-subN",
      "success": "نجح الاتصال ({latency} مللي ثانية)",
      "healthTimeout": "تم الاتصال لكن انتهت مهلة فحص الحالة",
    },
  };
}
