import 'package:flutter/widgets.dart';

/// Text for Nextcloud connection guidance and authentication errors.
class ConnectionStrings {
  const ConnectionStrings._(this._values);

  static ConnectionStrings of(BuildContext context) => forLanguage(
        Localizations.localeOf(context).languageCode,
      );

  @visibleForTesting
  static ConnectionStrings forLanguage(String language) =>
      ConnectionStrings._(_translations[language] ?? _english);

  final List<String> _values;
  String get serverAddress => _values[0];
  String get passwordOrAppPassword => _values[1];
  String get appPasswordHelp => _values[2];
  String get authenticationFailed => _values[3];

  static const _english = [
    'Server address, including any installation subfolder',
    'Password or app password',
    'For two-factor authentication, create an app password in Nextcloud security settings.',
    'Authentication failed. Check your username and password. If your account uses two-factor authentication, create an app password in Nextcloud security settings.',
  ];
  static const _translations = <String, List<String>>{
    'de': [
      'Serveradresse einschließlich eines Installationsunterordners',
      'Passwort oder App-Passwort',
      'Erstellen Sie bei Zwei-Faktor-Authentifizierung ein App-Passwort in den Nextcloud-Sicherheitseinstellungen.',
      'Anmeldung fehlgeschlagen. Prüfen Sie Benutzername und Passwort. Erstellen Sie bei Zwei-Faktor-Authentifizierung ein App-Passwort in den Nextcloud-Sicherheitseinstellungen.',
    ],
    'fr': [
      'Adresse du serveur, y compris le sous-dossier d’installation éventuel',
      'Mot de passe ou mot de passe d’application',
      'Pour l’authentification à deux facteurs, créez un mot de passe d’application dans les paramètres de sécurité Nextcloud.',
      'Échec de l’authentification. Vérifiez votre nom d’utilisateur et votre mot de passe. Avec l’authentification à deux facteurs, créez un mot de passe d’application dans les paramètres de sécurité Nextcloud.',
    ],
    'es': [
      'Dirección del servidor, incluida la subcarpeta de instalación',
      'Contraseña o contraseña de aplicación',
      'Para la autenticación en dos pasos, cree una contraseña de aplicación en los ajustes de seguridad de Nextcloud.',
      'Error de autenticación. Compruebe su usuario y contraseña. Si usa autenticación en dos pasos, cree una contraseña de aplicación en los ajustes de seguridad de Nextcloud.',
    ],
    'pt': [
      'Endereço do servidor, incluindo a subpasta de instalação',
      'Palavra-passe ou palavra-passe de aplicação',
      'Para autenticação de dois fatores, crie uma palavra-passe de aplicação nas definições de segurança do Nextcloud.',
      'Falha na autenticação. Verifique o nome de utilizador e a palavra-passe. Se usar autenticação de dois fatores, crie uma palavra-passe de aplicação nas definições de segurança do Nextcloud.',
    ],
    'ja': [
      'インストール先のサブフォルダーを含むサーバーアドレス',
      'パスワードまたはアプリパスワード',
      '二要素認証を使用する場合は、Nextcloudのセキュリティ設定でアプリパスワードを作成してください。',
      '認証に失敗しました。ユーザー名とパスワードを確認してください。二要素認証を使用する場合は、Nextcloudのセキュリティ設定でアプリパスワードを作成してください。',
    ],
    'ko': [
      '설치된 하위 폴더를 포함한 서버 주소',
      '비밀번호 또는 앱 비밀번호',
      '2단계 인증을 사용하는 경우 Nextcloud 보안 설정에서 앱 비밀번호를 만드세요.',
      '인증에 실패했습니다. 사용자 이름과 비밀번호를 확인하세요. 2단계 인증을 사용하는 경우 Nextcloud 보안 설정에서 앱 비밀번호를 만드세요.',
    ],
    'zh': [
      '服务器地址，包括安装所在的子文件夹',
      '密码或应用密码',
      '如果使用双重身份验证，请在 Nextcloud 安全设置中创建应用密码。',
      '身份验证失败。请检查用户名和密码。如果使用双重身份验证，请在 Nextcloud 安全设置中创建应用密码。',
    ],
    'ar': [
      'عنوان الخادم، بما في ذلك مجلد التثبيت الفرعي إن وجد',
      'كلمة المرور أو كلمة مرور التطبيق',
      'عند استخدام المصادقة الثنائية، أنشئ كلمة مرور للتطبيق في إعدادات أمان Nextcloud.',
      'فشلت المصادقة. تحقق من اسم المستخدم وكلمة المرور. عند استخدام المصادقة الثنائية، أنشئ كلمة مرور للتطبيق في إعدادات أمان Nextcloud.',
    ],
  };
}
