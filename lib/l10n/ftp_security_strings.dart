import 'package:flutter/widgets.dart';

import '../services/ftp_security_mode.dart';

class FtpSecurityStrings {
  FtpSecurityStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

  final String language;

  String text(String key) =>
      (_messages[language] ?? _messages['en']!)[key] ?? _messages['en']![key]!;

  String label(FtpSecurityMode mode) => text(mode.name);

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _messages;

  static const _messages = {
    'en': {
      'security': 'Connection security',
      'plain': 'FTP · unencrypted',
      'explicitTls': 'Explicit TLS (FTPES)',
      'implicitTls': 'Implicit TLS (FTPS)',
      'help': 'Explicit TLS usually uses port 21; implicit TLS uses 990. TLS verifies certificates and protects both commands and file data.',
      'invalidProfile': 'This profile has an invalid FTP security mode. Choose a mode or another profile before connecting.',
    },
    'de': {
      'security': 'Verbindungssicherheit',
      'plain': 'FTP · unverschlüsselt',
      'explicitTls': 'Explizites TLS (FTPES)',
      'implicitTls': 'Implizites TLS (FTPS)',
      'help': 'Explizites TLS nutzt meist Port 21, implizites TLS Port 990. TLS prüft Zertifikate und schützt Befehle und Dateidaten.',
      'invalidProfile': 'Dieses Profil hat einen ungültigen FTP-Sicherheitsmodus. Wählen Sie vor dem Verbinden einen Modus oder ein anderes Profil.',
    },
    'fr': {
      'security': 'Sécurité de la connexion',
      'plain': 'FTP · non chiffré',
      'explicitTls': 'TLS explicite (FTPES)',
      'implicitTls': 'TLS implicite (FTPS)',
      'help': 'TLS explicite utilise généralement le port 21, TLS implicite le port 990. TLS vérifie les certificats et protège les commandes et les données.',
      'invalidProfile': 'Ce profil contient un mode de sécurité FTP invalide. Choisissez un mode ou un autre profil avant la connexion.',
    },
    'es': {
      'security': 'Seguridad de la conexión',
      'plain': 'FTP · sin cifrar',
      'explicitTls': 'TLS explícito (FTPES)',
      'implicitTls': 'TLS implícito (FTPS)',
      'help': 'TLS explícito suele usar el puerto 21; TLS implícito, el 990. TLS verifica certificados y protege comandos y datos de archivos.',
      'invalidProfile': 'Este perfil tiene un modo de seguridad FTP inválido. Elija un modo u otro perfil antes de conectar.',
    },
    'pt': {
      'security': 'Segurança da conexão',
      'plain': 'FTP · sem criptografia',
      'explicitTls': 'TLS explícito (FTPES)',
      'implicitTls': 'TLS implícito (FTPS)',
      'help': 'TLS explícito costuma usar a porta 21; TLS implícito, a 990. TLS verifica certificados e protege comandos e dados de arquivos.',
      'invalidProfile': 'Este perfil tem um modo de segurança FTP inválido. Escolha um modo ou outro perfil antes de conectar.',
    },
    'ar': {
      'security': 'أمان الاتصال',
      'plain': 'FTP · غير مشفر',
      'explicitTls': 'TLS صريح (FTPES)',
      'implicitTls': 'TLS ضمني (FTPS)',
      'help': 'يستخدم TLS الصريح عادة المنفذ 21 والضمني المنفذ 990. يتحقق TLS من الشهادات ويحمي الأوامر وبيانات الملفات.',
      'invalidProfile': 'وضع أمان FTP في هذا الملف التعريفي غير صالح. اختر وضعًا أو ملفًا تعريفيًا آخر قبل الاتصال.',
    },
    'ja': {
      'security': '接続のセキュリティ',
      'plain': 'FTP · 暗号化なし',
      'explicitTls': '明示的 TLS (FTPES)',
      'implicitTls': '暗黙的 TLS (FTPS)',
      'help': '明示的 TLS は通常ポート 21、暗黙的 TLS は 990 を使用します。TLS は証明書を検証し、コマンドとファイルデータを保護します。',
      'invalidProfile':
          'このプロファイルの FTP セキュリティモードは無効です。接続する前にモードまたは別のプロファイルを選択してください。',
    },
    'ko': {
      'security': '연결 보안',
      'plain': 'FTP · 암호화 없음',
      'explicitTls': '명시적 TLS (FTPES)',
      'implicitTls': '암시적 TLS (FTPS)',
      'help': '명시적 TLS는 보통 포트 21, 암시적 TLS는 포트 990을 사용합니다. TLS는 인증서를 검증하고 명령과 파일 데이터를 보호합니다.',
      'invalidProfile': '이 프로필의 FTP 보안 모드가 잘못되었습니다. 연결 전에 모드나 다른 프로필을 선택하세요.',
    },
    'zh': {
      'security': '连接安全',
      'plain': 'FTP · 未加密',
      'explicitTls': '显式 TLS (FTPES)',
      'implicitTls': '隐式 TLS (FTPS)',
      'help': '显式 TLS 通常使用端口 21，隐式 TLS 使用端口 990。TLS 会验证证书并保护命令和文件数据。',
      'invalidProfile': '此配置的 FTP 安全模式无效。连接前请选择一种模式或其他配置。',
    },
  };
}
