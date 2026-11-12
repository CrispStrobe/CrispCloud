import 'package:flutter/widgets.dart';

/// Localized proxy and TLS configuration text.
class ProxySettingsStrings {
  ProxySettingsStrings(BuildContext context)
    : _language = Localizations.localeOf(context).languageCode;
  @visibleForTesting
  ProxySettingsStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String proxy(String type, String host, int port) =>
      text('Proxy: {type} {host}:{port}')
          .replaceAll('{type}', type)
          .replaceAll('{host}', host)
          .replaceAll('{port}', '$port');
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "SOCKS4 Proxy (local DNS)": "SOCKS4-Proxy (lokales DNS)",
    "SOCKS4a Proxy (remote DNS)": "SOCKS4a-Proxy (DNS am Proxy)",
    "User ID (optional)": "Benutzer-ID (optional)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.": "SOCKS4 löst Zielnamen lokal in IPv4-Adressen auf. Die optionale Benutzer-ID ist kein Passwort.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.": "SOCKS4a löst Zielnamen am Proxy auf. IPv6-Ziele und Passwortauthentifizierung werden nicht unterstützt.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.": "SOCKS4-Benutzer-IDs dürfen bis zu 255 druckbare ASCII-Zeichen enthalten; Passwörter werden nicht unterstützt.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.": "Die gespeicherten Proxy-Einstellungen sind ungültig. Korrigieren Sie sie oder wählen Sie „Kein Proxy“, um die Verbindung wiederherzustellen.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "Gilt für native HTTP-/HTTPS-Verbindungen. FTP, SFTP, SMB und Browser-Verbindungen verwenden eigene Netzwerkeinstellungen.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.": "SOCKS5 löst Zielnamen am Proxy auf. Geben Sie für die Passwortauthentifizierung sowohl einen Benutzernamen als auch ein Passwort ein.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).": "SOCKS5 benötigt einen Benutzernamen und ein Passwort (jeweils bis zu 255 UTF-8-Bytes).",
    "Proxy Type": "Proxy-Typ",
    "No Proxy (Direct)": "Kein Proxy (direkt)",
    "HTTP / HTTPS Proxy": "HTTP-/HTTPS-Proxy",
    "SOCKS5 Proxy": "SOCKS5-Proxy",
    "Proxy Host": "Proxy-Host",
    "Port": "Port",
    "Username (optional)": "Benutzername (optional)",
    "Password (optional)": "Passwort (optional)",
    "No Proxy (bypass list)": "Kein Proxy (Ausnahmeliste)",
    "Comma-separated hostnames to bypass proxy":
        "Kommagetrennte Hostnamen, die den Proxy umgehen",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.": "Umgebungsvariablen (HTTP_PROXY, HTTPS_PROXY) werden automatisch erkannt.",
    "Manual settings override environment variables.":
        "Manuelle Einstellungen haben Vorrang vor Umgebungsvariablen.",
    "Certificate Pinning": "Zertifikat-Pinning",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "TLS-Zertifikate für Google, Microsoft, Dropbox und Amazon prüfen",
    "Minimum TLS Version": "Minimale TLS-Version",
    "TLS 1.2 (recommended)": "TLS 1.2 (empfohlen)",
    "TLS 1.3 (strict)": "TLS 1.3 (streng)",
    "Any (legacy override)": "Beliebig (Kompatibilität)",
    "Allowing any TLS version may expose connections to downgrade attacks.": "Beliebige TLS-Versionen können Verbindungen Downgrade-Angriffen aussetzen.",
    "Custom CA Certificates": "Eigene CA-Zertifikate",
    "No custom CA certificates imported.":
        "Keine eigenen CA-Zertifikate importiert.",
    "Remove certificate": "Zertifikat entfernen",
    "Import Certificate": "Zertifikat importieren",
    "Host and valid port are required":
        "Host und gültiger Port sind erforderlich",
    "Proxy: {type} {host}:{port}": "Proxy: {type} {host}:{port}",
    "Cert pinning: on": "Zertifikat-Pinning: an",
    "Proxy disabled": "Proxy deaktiviert",
    "Clear": "Zurücksetzen",
  },
  "fr": {
    "SOCKS4 Proxy (local DNS)": "Proxy SOCKS4 (DNS local)",
    "SOCKS4a Proxy (remote DNS)": "Proxy SOCKS4a (DNS distant)",
    "User ID (optional)": "Identifiant (facultatif)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.": "SOCKS4 résout les noms de destination localement en IPv4. L’identifiant facultatif n’est pas un mot de passe.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.": "SOCKS4a résout les noms de destination sur le proxy. Les destinations IPv6 et l’authentification par mot de passe ne sont pas prises en charge.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.": "Les identifiants SOCKS4 acceptent jusqu’à 255 caractères ASCII imprimables ; les mots de passe ne sont pas pris en charge.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.": "Les paramètres de proxy enregistrés sont invalides. Corrigez-les ou choisissez Aucun proxy pour vous reconnecter.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "S’applique aux connexions HTTP/HTTPS natives. Les connexions FTP, SFTP, SMB et du navigateur utilisent leurs propres paramètres réseau.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.": "SOCKS5 résout les noms de destination sur le proxy. Pour l’authentification par mot de passe, renseignez un nom d’utilisateur et un mot de passe.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).": "SOCKS5 exige un nom d’utilisateur et un mot de passe (255 octets UTF-8 maximum chacun).",
    "Proxy Type": "Type de proxy",
    "No Proxy (Direct)": "Aucun proxy (direct)",
    "HTTP / HTTPS Proxy": "Proxy HTTP / HTTPS",
    "SOCKS5 Proxy": "Proxy SOCKS5",
    "Proxy Host": "Hôte du proxy",
    "Port": "Port",
    "Username (optional)": "Nom d’utilisateur (facultatif)",
    "Password (optional)": "Mot de passe (facultatif)",
    "No Proxy (bypass list)": "Sans proxy (exceptions)",
    "Comma-separated hostnames to bypass proxy":
        "Noms d’hôtes séparés par des virgules qui ignorent le proxy",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.": "Les variables d’environnement (HTTP_PROXY, HTTPS_PROXY) sont détectées automatiquement.",
    "Manual settings override environment variables.":
        "Les paramètres manuels remplacent les variables d’environnement.",
    "Certificate Pinning": "Épinglage des certificats",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "Vérifier les certificats TLS de Google, Microsoft, Dropbox et Amazon",
    "Minimum TLS Version": "Version minimale de TLS",
    "TLS 1.2 (recommended)": "TLS 1.2 (recommandé)",
    "TLS 1.3 (strict)": "TLS 1.3 (strict)",
    "Any (legacy override)": "Toutes (compatibilité)",
    "Allowing any TLS version may expose connections to downgrade attacks.": "Autoriser toutes les versions TLS peut exposer les connexions à des attaques de rétrogradation.",
    "Custom CA Certificates": "Certificats CA personnalisés",
    "No custom CA certificates imported.":
        "Aucun certificat CA personnalisé importé.",
    "Remove certificate": "Supprimer le certificat",
    "Import Certificate": "Importer un certificat",
    "Host and valid port are required": "Un hôte et un port valide sont requis",
    "Proxy: {type} {host}:{port}": "Proxy : {type} {host}:{port}",
    "Cert pinning: on": "Épinglage des certificats : activé",
    "Proxy disabled": "Proxy désactivé",
    "Clear": "Réinitialiser",
  },
  "es": {
    "SOCKS4 Proxy (local DNS)": "Proxy SOCKS4 (DNS local)",
    "SOCKS4a Proxy (remote DNS)": "Proxy SOCKS4a (DNS remoto)",
    "User ID (optional)": "ID de usuario (opcional)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.": "SOCKS4 resuelve los nombres de destino localmente a IPv4. El ID de usuario opcional no es una contraseña.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.": "SOCKS4a resuelve los nombres de destino en el proxy. No admite destinos IPv6 ni autenticación con contraseña.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.": "Los ID de usuario de SOCKS4 admiten hasta 255 caracteres ASCII imprimibles; no se admiten contraseñas.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.": "Los ajustes de proxy guardados no son válidos. Corríjalos o elija Sin proxy para volver a conectarse.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "Se aplica a las conexiones HTTP/HTTPS nativas. Las conexiones FTP, SFTP, SMB y del navegador usan sus propios ajustes de red.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.": "SOCKS5 resuelve los nombres de destino en el proxy. Para autenticarse con contraseña, introduzca un usuario y una contraseña.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).": "SOCKS5 requiere un usuario y una contraseña (hasta 255 bytes UTF-8 cada uno).",
    "Proxy Type": "Tipo de proxy",
    "No Proxy (Direct)": "Sin proxy (directo)",
    "HTTP / HTTPS Proxy": "Proxy HTTP / HTTPS",
    "SOCKS5 Proxy": "Proxy SOCKS5",
    "Proxy Host": "Servidor proxy",
    "Port": "Puerto",
    "Username (optional)": "Usuario (opcional)",
    "Password (optional)": "Contraseña (opcional)",
    "No Proxy (bypass list)": "Sin proxy (excepciones)",
    "Comma-separated hostnames to bypass proxy":
        "Nombres de host separados por comas que omiten el proxy",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.": "Las variables de entorno (HTTP_PROXY, HTTPS_PROXY) se detectan automáticamente.",
    "Manual settings override environment variables.":
        "Los ajustes manuales prevalecen sobre las variables de entorno.",
    "Certificate Pinning": "Fijación de certificados",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "Verificar certificados TLS de Google, Microsoft, Dropbox y Amazon",
    "Minimum TLS Version": "Versión mínima de TLS",
    "TLS 1.2 (recommended)": "TLS 1.2 (recomendada)",
    "TLS 1.3 (strict)": "TLS 1.3 (estricta)",
    "Any (legacy override)": "Cualquiera (compatibilidad)",
    "Allowing any TLS version may expose connections to downgrade attacks.": "Permitir cualquier versión de TLS puede exponer las conexiones a ataques de degradación.",
    "Custom CA Certificates": "Certificados CA personalizados",
    "No custom CA certificates imported.":
        "No hay certificados CA personalizados importados.",
    "Remove certificate": "Eliminar certificado",
    "Import Certificate": "Importar certificado",
    "Host and valid port are required":
        "Se requieren un servidor y un puerto válido",
    "Proxy: {type} {host}:{port}": "Proxy: {type} {host}:{port}",
    "Cert pinning: on": "Fijación de certificados: activada",
    "Proxy disabled": "Proxy desactivado",
    "Clear": "Restablecer",
  },
  "pt": {
    "SOCKS4 Proxy (local DNS)": "Proxy SOCKS4 (DNS local)",
    "SOCKS4a Proxy (remote DNS)": "Proxy SOCKS4a (DNS remoto)",
    "User ID (optional)": "ID de utilizador (opcional)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.": "O SOCKS4 resolve os nomes de destino localmente para IPv4. O ID de utilizador opcional não é uma palavra-passe.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.": "O SOCKS4a resolve os nomes de destino no proxy. Não suporta destinos IPv6 nem autenticação por palavra-passe.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.": "Os IDs de utilizador SOCKS4 aceitam até 255 caracteres ASCII imprimíveis; as palavras-passe não são suportadas.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.": "As definições de proxy guardadas são inválidas. Corrija-as ou escolha Sem proxy para voltar a ligar.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "Aplica-se a ligações HTTP/HTTPS nativas. As ligações FTP, SFTP, SMB e do navegador utilizam as suas próprias definições de rede.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.": "O SOCKS5 resolve os nomes de destino no proxy. Para autenticação por palavra-passe, introduza um nome de utilizador e uma palavra-passe.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).": "O SOCKS5 exige um nome de utilizador e uma palavra-passe (até 255 bytes UTF-8 cada).",
    "Proxy Type": "Tipo de proxy",
    "No Proxy (Direct)": "Sem proxy (direto)",
    "HTTP / HTTPS Proxy": "Proxy HTTP / HTTPS",
    "SOCKS5 Proxy": "Proxy SOCKS5",
    "Proxy Host": "Servidor proxy",
    "Port": "Porta",
    "Username (optional)": "Nome de utilizador (opcional)",
    "Password (optional)": "Palavra-passe (opcional)",
    "No Proxy (bypass list)": "Sem proxy (exceções)",
    "Comma-separated hostnames to bypass proxy":
        "Nomes de anfitriões separados por vírgulas que ignoram o proxy",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.": "As variáveis de ambiente (HTTP_PROXY, HTTPS_PROXY) são detetadas automaticamente.",
    "Manual settings override environment variables.":
        "As definições manuais prevalecem sobre as variáveis de ambiente.",
    "Certificate Pinning": "Fixação de certificados",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "Verificar certificados TLS da Google, Microsoft, Dropbox e Amazon",
    "Minimum TLS Version": "Versão mínima de TLS",
    "TLS 1.2 (recommended)": "TLS 1.2 (recomendada)",
    "TLS 1.3 (strict)": "TLS 1.3 (restrita)",
    "Any (legacy override)": "Qualquer (compatibilidade)",
    "Allowing any TLS version may expose connections to downgrade attacks.": "Permitir qualquer versão TLS pode expor as ligações a ataques de downgrade.",
    "Custom CA Certificates": "Certificados CA personalizados",
    "No custom CA certificates imported.":
        "Nenhum certificado CA personalizado importado.",
    "Remove certificate": "Remover certificado",
    "Import Certificate": "Importar certificado",
    "Host and valid port are required":
        "São necessários um anfitrião e uma porta válida",
    "Proxy: {type} {host}:{port}": "Proxy: {type} {host}:{port}",
    "Cert pinning: on": "Fixação de certificados: ativa",
    "Proxy disabled": "Proxy desativado",
    "Clear": "Repor",
  },
  "zh": {
    "SOCKS4 Proxy (local DNS)": "SOCKS4 代理（本地 DNS）",
    "SOCKS4a Proxy (remote DNS)": "SOCKS4a 代理（远程 DNS）",
    "User ID (optional)": "用户 ID（可选）",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.":
        "SOCKS4 在本地将目标名称解析为 IPv4 地址。可选用户 ID 不是密码。",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.":
        "SOCKS4a 在代理端解析目标名称。不支持 IPv6 目标和密码认证。",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.":
        "SOCKS4 用户 ID 最多可包含 255 个可打印 ASCII 字符；不支持密码。",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.":
        "保存的代理设置无效。请更正设置或选择“无代理”以重新连接。",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.":
        "适用于原生 HTTP/HTTPS 连接。FTP、SFTP、SMB 和浏览器连接使用各自的网络设置。",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.":
        "SOCKS5 在代理端解析目标名称。如需密码认证，请同时输入用户名和密码。",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).":
        "SOCKS5 需要用户名和密码（各不超过 255 个 UTF-8 字节）。",
    "Proxy Type": "代理类型",
    "No Proxy (Direct)": "无代理（直接连接）",
    "HTTP / HTTPS Proxy": "HTTP / HTTPS 代理",
    "SOCKS5 Proxy": "SOCKS5 代理",
    "Proxy Host": "代理主机",
    "Port": "端口",
    "Username (optional)": "用户名（可选）",
    "Password (optional)": "密码（可选）",
    "No Proxy (bypass list)": "不使用代理（绕过列表）",
    "Comma-separated hostnames to bypass proxy": "用逗号分隔不使用代理的主机名",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.":
        "自动检测环境变量（HTTP_PROXY、HTTPS_PROXY）。",
    "Manual settings override environment variables.": "手动设置优先于环境变量。",
    "Certificate Pinning": "证书固定",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "验证 Google、Microsoft、Dropbox 和 Amazon 的 TLS 证书",
    "Minimum TLS Version": "最低 TLS 版本",
    "TLS 1.2 (recommended)": "TLS 1.2（推荐）",
    "TLS 1.3 (strict)": "TLS 1.3（严格）",
    "Any (legacy override)": "任意版本（兼容旧版）",
    "Allowing any TLS version may expose connections to downgrade attacks.":
        "允许任意 TLS 版本可能使连接面临降级攻击。",
    "Custom CA Certificates": "自定义 CA 证书",
    "No custom CA certificates imported.": "未导入自定义 CA 证书。",
    "Remove certificate": "移除证书",
    "Import Certificate": "导入证书",
    "Host and valid port are required": "必须提供主机和有效端口",
    "Proxy: {type} {host}:{port}": "代理：{type} {host}:{port}",
    "Cert pinning: on": "证书固定：开启",
    "Proxy disabled": "代理已禁用",
    "Clear": "清除",
  },
  "ja": {
    "SOCKS4 Proxy (local DNS)": "SOCKS4 プロキシ（ローカル DNS）",
    "SOCKS4a Proxy (remote DNS)": "SOCKS4a プロキシ（リモート DNS）",
    "User ID (optional)": "ユーザー ID（任意）",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.":
        "SOCKS4 は接続先の名前をローカルで IPv4 に解決します。任意のユーザー ID はパスワードではありません。",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.":
        "SOCKS4a はプロキシ側で接続先の名前を解決します。IPv6 の接続先とパスワード認証はサポートされていません。",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.":
        "SOCKS4 のユーザー ID は最大 255 文字の印刷可能な ASCII 文字に対応します。パスワードは使用できません。",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.":
        "保存されたプロキシ設定は無効です。設定を修正するか「プロキシなし」を選択して再接続してください。",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "ネイティブの HTTP/HTTPS 接続に適用されます。FTP、SFTP、SMB、ブラウザーの接続は、それぞれのネットワーク設定を使用します。",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.":
        "SOCKS5 はプロキシ側で接続先の名前を解決します。パスワード認証には、ユーザー名とパスワードの両方を入力してください。",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).":
        "SOCKS5 にはユーザー名とパスワードの両方が必要です（それぞれ最大 255 UTF-8 バイト）。",
    "Proxy Type": "プロキシの種類",
    "No Proxy (Direct)": "プロキシなし（直接接続）",
    "HTTP / HTTPS Proxy": "HTTP / HTTPS プロキシ",
    "SOCKS5 Proxy": "SOCKS5 プロキシ",
    "Proxy Host": "プロキシホスト",
    "Port": "ポート",
    "Username (optional)": "ユーザー名（任意）",
    "Password (optional)": "パスワード（任意）",
    "No Proxy (bypass list)": "プロキシ除外リスト",
    "Comma-separated hostnames to bypass proxy": "プロキシを使用しないホスト名をカンマ区切りで指定",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.":
        "環境変数（HTTP_PROXY、HTTPS_PROXY）を自動検出します。",
    "Manual settings override environment variables.": "手動設定は環境変数より優先されます。",
    "Certificate Pinning": "証明書のピン留め",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "Google、Microsoft、Dropbox、Amazon の TLS 証明書を検証",
    "Minimum TLS Version": "最低 TLS バージョン",
    "TLS 1.2 (recommended)": "TLS 1.2（推奨）",
    "TLS 1.3 (strict)": "TLS 1.3（厳格）",
    "Any (legacy override)": "すべて（旧方式の許可）",
    "Allowing any TLS version may expose connections to downgrade attacks.":
        "すべての TLS バージョンを許可すると、ダウングレード攻撃にさらされる可能性があります。",
    "Custom CA Certificates": "カスタム CA 証明書",
    "No custom CA certificates imported.": "カスタム CA 証明書はインポートされていません。",
    "Remove certificate": "証明書を削除",
    "Import Certificate": "証明書をインポート",
    "Host and valid port are required": "ホストと有効なポートが必要です",
    "Proxy: {type} {host}:{port}": "プロキシ：{type} {host}:{port}",
    "Cert pinning: on": "証明書のピン留め：オン",
    "Proxy disabled": "プロキシは無効です",
    "Clear": "クリア",
  },
  "ko": {
    "SOCKS4 Proxy (local DNS)": "SOCKS4 프록시 (로컬 DNS)",
    "SOCKS4a Proxy (remote DNS)": "SOCKS4a 프록시 (원격 DNS)",
    "User ID (optional)": "사용자 ID (선택 사항)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.":
        "SOCKS4는 대상 이름을 로컬에서 IPv4로 확인합니다. 선택 사항인 사용자 ID는 비밀번호가 아닙니다.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.":
        "SOCKS4a는 프록시에서 대상 이름을 확인합니다. IPv6 대상 및 비밀번호 인증은 지원하지 않습니다.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.":
        "SOCKS4 사용자 ID는 인쇄 가능한 ASCII 문자 최대 255자까지 허용합니다. 비밀번호는 지원하지 않습니다.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.":
        "저장된 프록시 설정이 잘못되었습니다. 설정을 수정하거나 프록시 없음을 선택하여 다시 연결하세요.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.":
        "기본 HTTP/HTTPS 연결에 적용됩니다. FTP, SFTP, SMB 및 브라우저 연결은 자체 네트워크 설정을 사용합니다.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.":
        "SOCKS5는 프록시에서 대상 이름을 확인합니다. 비밀번호 인증을 사용하려면 사용자 이름과 비밀번호를 모두 입력하세요.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).":
        "SOCKS5에는 사용자 이름과 비밀번호가 모두 필요합니다(각각 최대 255 UTF-8 바이트).",
    "Proxy Type": "프록시 유형",
    "No Proxy (Direct)": "프록시 없음 (직접 연결)",
    "HTTP / HTTPS Proxy": "HTTP / HTTPS 프록시",
    "SOCKS5 Proxy": "SOCKS5 프록시",
    "Proxy Host": "프록시 호스트",
    "Port": "포트",
    "Username (optional)": "사용자 이름 (선택 사항)",
    "Password (optional)": "비밀번호 (선택 사항)",
    "No Proxy (bypass list)": "프록시 제외 목록",
    "Comma-separated hostnames to bypass proxy": "프록시를 사용하지 않을 호스트 이름을 쉼표로 구분",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.":
        "환경 변수(HTTP_PROXY, HTTPS_PROXY)가 자동 감지됩니다.",
    "Manual settings override environment variables.": "수동 설정이 환경 변수보다 우선합니다.",
    "Certificate Pinning": "인증서 고정",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "Google, Microsoft, Dropbox, Amazon의 TLS 인증서 확인",
    "Minimum TLS Version": "최소 TLS 버전",
    "TLS 1.2 (recommended)": "TLS 1.2 (권장)",
    "TLS 1.3 (strict)": "TLS 1.3 (엄격)",
    "Any (legacy override)": "모두 허용 (레거시 설정)",
    "Allowing any TLS version may expose connections to downgrade attacks.":
        "모든 TLS 버전을 허용하면 연결이 다운그레이드 공격에 노출될 수 있습니다.",
    "Custom CA Certificates": "사용자 지정 CA 인증서",
    "No custom CA certificates imported.": "가져온 사용자 지정 CA 인증서가 없습니다.",
    "Remove certificate": "인증서 제거",
    "Import Certificate": "인증서 가져오기",
    "Host and valid port are required": "호스트와 유효한 포트가 필요합니다",
    "Proxy: {type} {host}:{port}": "프록시: {type} {host}:{port}",
    "Cert pinning: on": "인증서 고정: 켜짐",
    "Proxy disabled": "프록시 비활성화됨",
    "Clear": "초기화",
  },
  "ar": {
    "SOCKS4 Proxy (local DNS)": "وكيل SOCKS4 (DNS محلي)",
    "SOCKS4a Proxy (remote DNS)": "وكيل SOCKS4a (DNS بعيد)",
    "User ID (optional)": "معرّف المستخدم (اختياري)",
    "SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.": "يحل SOCKS4 أسماء الوجهات محليًا إلى IPv4. معرّف المستخدم الاختياري ليس كلمة مرور.",
    "SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.": "يحل SOCKS4a أسماء الوجهات عبر الوكيل. وجهات IPv6 والمصادقة بكلمة مرور غير مدعومتين.",
    "SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.": "تقبل معرّفات مستخدمي SOCKS4 حتى 255 حرف ASCII قابلًا للطباعة؛ كلمات المرور غير مدعومة.",
    "Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.": "إعدادات الوكيل المحفوظة غير صالحة. صححها أو اختر بدون وكيل لإعادة الاتصال.",
    "Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.": "ينطبق على اتصالات HTTP/HTTPS الأصلية. تستخدم اتصالات FTP وSFTP وSMB والمتصفح إعدادات الشبكة الخاصة بها.",
    "SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.": "يحل SOCKS5 أسماء الوجهات عبر الوكيل. للمصادقة بكلمة مرور، أدخل اسم المستخدم وكلمة المرور معًا.",
    "SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).":
        "يتطلب SOCKS5 اسم مستخدم وكلمة مرور (حتى 255 بايت UTF-8 لكل منهما).",
    "Proxy Type": "نوع الوكيل",
    "No Proxy (Direct)": "بدون وكيل (اتصال مباشر)",
    "HTTP / HTTPS Proxy": "وكيل HTTP / HTTPS",
    "SOCKS5 Proxy": "وكيل SOCKS5",
    "Proxy Host": "مضيف الوكيل",
    "Port": "المنفذ",
    "Username (optional)": "اسم المستخدم (اختياري)",
    "Password (optional)": "كلمة المرور (اختياري)",
    "No Proxy (bypass list)": "بدون وكيل (قائمة الاستثناءات)",
    "Comma-separated hostnames to bypass proxy":
        "أسماء المضيفين التي تتجاوز الوكيل مفصولة بفواصل",
    "Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.":
        "يتم اكتشاف متغيرات البيئة (HTTP_PROXY وHTTPS_PROXY) تلقائيًا.",
    "Manual settings override environment variables.":
        "تتجاوز الإعدادات اليدوية متغيرات البيئة.",
    "Certificate Pinning": "تثبيت الشهادات",
    "Verify TLS certificates for Google, Microsoft, Dropbox, Amazon":
        "التحقق من شهادات TLS لـ Google وMicrosoft وDropbox وAmazon",
    "Minimum TLS Version": "الحد الأدنى لإصدار TLS",
    "TLS 1.2 (recommended)": "TLS 1.2 (موصى به)",
    "TLS 1.3 (strict)": "TLS 1.3 (صارم)",
    "Any (legacy override)": "أي إصدار (توافق قديم)",
    "Allowing any TLS version may expose connections to downgrade attacks.":
        "قد يؤدي السماح بأي إصدار TLS إلى تعريض الاتصالات لهجمات خفض الإصدار.",
    "Custom CA Certificates": "شهادات CA مخصصة",
    "No custom CA certificates imported.": "لم تُستورد شهادات CA مخصصة.",
    "Remove certificate": "إزالة الشهادة",
    "Import Certificate": "استيراد شهادة",
    "Host and valid port are required": "المضيف والمنفذ الصحيح مطلوبان",
    "Proxy: {type} {host}:{port}": "الوكيل: {type} {host}:{port}",
    "Cert pinning: on": "تثبيت الشهادات: مفعّل",
    "Proxy disabled": "الوكيل معطّل",
    "Clear": "مسح",
  },
};
