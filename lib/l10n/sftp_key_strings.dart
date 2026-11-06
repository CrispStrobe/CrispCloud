import 'package:flutter/widgets.dart';

class SftpKeyStrings {
  SftpKeyStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  SftpKeyStrings.forLanguage(this.language);
  final String language;
  List<String> get _values => _strings[language] ?? _strings['en']!;
  String get authentication => _values[0];
  String get password => _values[1];
  String get privateKey => _values[2];
  String get chooseKey => _values[3];
  String get keySelected => _values[4];
  String get passphrase => _values[5];
  String get storageHelp => _values[6];
  String get keyRequired => _values[7];
  String get invalidKey => _values[8];
  String get readFailed => _values[9];

  static const _strings = <String, List<String>>{
    'en': ['Authentication', 'Password', 'SSH private key', 'Choose private key', 'Selected key', 'Key passphrase (if encrypted)', 'The key and passphrase are saved in secure storage for reconnection.', 'Choose an SSH private key.', 'Invalid SSH private key or passphrase.', 'Could not read the key file, or it exceeds 1 MiB.'],
    'de': ['Anmeldung', 'Passwort', 'Privater SSH-Schlüssel', 'Privaten Schlüssel auswählen', 'Ausgewählter Schlüssel', 'Schlüsselpassphrase (falls verschlüsselt)', 'Schlüssel und Passphrase werden für die erneute Verbindung sicher gespeichert.', 'Wählen Sie einen privaten SSH-Schlüssel aus.', 'Ungültiger privater SSH-Schlüssel oder ungültige Passphrase.', 'Die Schlüsseldatei konnte nicht gelesen werden oder ist größer als 1 MiB.'],
    'fr': ['Authentification', 'Mot de passe', 'Clé privée SSH', 'Choisir une clé privée', 'Clé sélectionnée', 'Phrase secrète de la clé (si chiffrée)', 'La clé et sa phrase secrète sont enregistrées en sécurité pour la reconnexion.', 'Choisissez une clé privée SSH.', 'Clé privée SSH ou phrase secrète invalide.', 'Impossible de lire la clé ou sa taille dépasse 1 Mio.'],
    'es': ['Autenticación', 'Contraseña', 'Clave privada SSH', 'Elegir clave privada', 'Clave seleccionada', 'Frase de la clave (si está cifrada)', 'La clave y su frase se guardan de forma segura para reconectar.', 'Elige una clave privada SSH.', 'Clave privada SSH o frase no válida.', 'No se pudo leer la clave o supera 1 MiB.'],
    'pt': ['Autenticação', 'Palavra-passe', 'Chave privada SSH', 'Escolher chave privada', 'Chave selecionada', 'Frase da chave (se cifrada)', 'A chave e a frase são guardadas com segurança para reconexão.', 'Escolha uma chave privada SSH.', 'Chave privada SSH ou frase inválida.', 'Não foi possível ler a chave ou excede 1 MiB.'],
    'zh': ['身份验证', '密码', 'SSH 私钥', '选择私钥', '已选密钥', '密钥口令（如已加密）', '密钥和口令将安全保存以供重新连接。', '请选择 SSH 私钥。', 'SSH 私钥或口令无效。', '无法读取密钥文件，或文件超过 1 MiB。'],
    'ja': ['認証', 'パスワード', 'SSH 秘密鍵', '秘密鍵を選択', '選択した鍵', '鍵のパスフレーズ（暗号化されている場合）', '再接続のため、鍵とパスフレーズは安全に保存されます。', 'SSH 秘密鍵を選択してください。', 'SSH 秘密鍵またはパスフレーズが無効です。', '鍵ファイルを読み取れないか、1 MiB を超えています。'],
    'ko': ['인증', '비밀번호', 'SSH 개인 키', '개인 키 선택', '선택한 키', '키 암호문구(암호화된 경우)', '재연결을 위해 키와 암호문구를 안전하게 저장합니다.', 'SSH 개인 키를 선택하세요.', 'SSH 개인 키 또는 암호문구가 올바르지 않습니다.', '키 파일을 읽을 수 없거나 1 MiB를 초과합니다.'],
    'ar': ['المصادقة', 'كلمة المرور', 'مفتاح SSH الخاص', 'اختيار المفتاح الخاص', 'المفتاح المحدد', 'عبارة مرور المفتاح (إن كان مشفرًا)', 'يُحفظ المفتاح وعبارة مروره بأمان لإعادة الاتصال.', 'اختر مفتاح SSH خاصًا.', 'مفتاح SSH الخاص أو عبارة مروره غير صالحين.', 'تعذرت قراءة ملف المفتاح أو يتجاوز حجمه 1 ميبيبايت.'],
  };
}
