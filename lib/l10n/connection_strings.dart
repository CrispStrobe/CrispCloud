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
  String get browserLogin => _values[4];
  String get browserLoginHelp => _values[5];
  String get waitingForBrowser => _values[6];
  String get browserLoginExpired => _values[7];

  static const _english = [
    'Server address, including any installation subfolder',
    'Password or app password',
    'For two-factor authentication, create an app password in Nextcloud security settings.',
    'Authentication failed. Check your username and password. If your account uses two-factor authentication, create an app password in Nextcloud security settings.',
    'Log in with browser',
    'Recommended for single sign-on, two-factor and email logins: sign in on your server’s page and approve CrispCloud. An app password is created for you.',
    'Waiting for approval in the browser…',
    'The browser login was not completed. Try again.',
  ];
  static const _translations = <String, List<String>>{
    'de': [
      'Serveradresse einschließlich eines Installationsunterordners',
      'Passwort oder App-Passwort',
      'Erstellen Sie bei Zwei-Faktor-Authentifizierung ein App-Passwort in den Nextcloud-Sicherheitseinstellungen.',
      'Anmeldung fehlgeschlagen. Prüfen Sie Benutzername und Passwort. Erstellen Sie bei Zwei-Faktor-Authentifizierung ein App-Passwort in den Nextcloud-Sicherheitseinstellungen.',
      'Im Browser anmelden',
      'Empfohlen für Single Sign-on, Zwei-Faktor- und E-Mail-Anmeldungen: Melden Sie sich auf der Seite Ihres Servers an und erlauben Sie CrispCloud den Zugriff. Ein App-Passwort wird für Sie erstellt.',
      'Warte auf Freigabe im Browser …',
      'Die Anmeldung im Browser wurde nicht abgeschlossen. Versuchen Sie es erneut.',
    ],
    'fr': [
      'Adresse du serveur, y compris le sous-dossier d’installation éventuel',
      'Mot de passe ou mot de passe d’application',
      'Pour l’authentification à deux facteurs, créez un mot de passe d’application dans les paramètres de sécurité Nextcloud.',
      'Échec de l’authentification. Vérifiez votre nom d’utilisateur et votre mot de passe. Avec l’authentification à deux facteurs, créez un mot de passe d’application dans les paramètres de sécurité Nextcloud.',
      'Se connecter dans le navigateur',
      'Recommandé pour l’authentification unique, à deux facteurs ou par e-mail : connectez-vous sur la page de votre serveur et autorisez CrispCloud. Un mot de passe d’application est créé pour vous.',
      'En attente de l’autorisation dans le navigateur…',
      'La connexion dans le navigateur n’a pas abouti. Réessayez.',
    ],
    'es': [
      'Dirección del servidor, incluida la subcarpeta de instalación',
      'Contraseña o contraseña de aplicación',
      'Para la autenticación en dos pasos, cree una contraseña de aplicación en los ajustes de seguridad de Nextcloud.',
      'Error de autenticación. Compruebe su usuario y contraseña. Si usa autenticación en dos pasos, cree una contraseña de aplicación en los ajustes de seguridad de Nextcloud.',
      'Iniciar sesión en el navegador',
      'Recomendado para inicio de sesión único, en dos pasos o con correo: inicie sesión en la página de su servidor y autorice a CrispCloud. Se creará una contraseña de aplicación.',
      'Esperando la autorización en el navegador…',
      'No se completó el inicio de sesión en el navegador. Inténtelo de nuevo.',
    ],
    'pt': [
      'Endereço do servidor, incluindo a subpasta de instalação',
      'Palavra-passe ou palavra-passe de aplicação',
      'Para autenticação de dois fatores, crie uma palavra-passe de aplicação nas definições de segurança do Nextcloud.',
      'Falha na autenticação. Verifique o nome de utilizador e a palavra-passe. Se usar autenticação de dois fatores, crie uma palavra-passe de aplicação nas definições de segurança do Nextcloud.',
      'Iniciar sessão no navegador',
      'Recomendado para início de sessão único, de dois fatores ou por e-mail: inicie sessão na página do seu servidor e autorize o CrispCloud. É criada uma palavra-passe de aplicação.',
      'A aguardar autorização no navegador…',
      'O início de sessão no navegador não foi concluído. Tente novamente.',
    ],
    'ja': [
      'インストール先のサブフォルダーを含むサーバーアドレス',
      'パスワードまたはアプリパスワード',
      '二要素認証を使用する場合は、Nextcloudのセキュリティ設定でアプリパスワードを作成してください。',
      '認証に失敗しました。ユーザー名とパスワードを確認してください。二要素認証を使用する場合は、Nextcloudのセキュリティ設定でアプリパスワードを作成してください。',
      'ブラウザーでログイン',
      'シングルサインオン、二要素認証、メールアドレスでのログインに推奨：サーバーのページでサインインし、CrispCloudを承認してください。アプリパスワードが自動で作成されます。',
      'ブラウザーでの承認を待っています…',
      'ブラウザーでのログインが完了しませんでした。もう一度お試しください。',
    ],
    'ko': [
      '설치된 하위 폴더를 포함한 서버 주소',
      '비밀번호 또는 앱 비밀번호',
      '2단계 인증을 사용하는 경우 Nextcloud 보안 설정에서 앱 비밀번호를 만드세요.',
      '인증에 실패했습니다. 사용자 이름과 비밀번호를 확인하세요. 2단계 인증을 사용하는 경우 Nextcloud 보안 설정에서 앱 비밀번호를 만드세요.',
      '브라우저로 로그인',
      '싱글 사인온, 2단계 인증, 이메일 로그인에 권장: 서버 페이지에서 로그인하고 CrispCloud를 승인하세요. 앱 비밀번호가 자동으로 만들어집니다.',
      '브라우저에서 승인을 기다리는 중…',
      '브라우저 로그인이 완료되지 않았습니다. 다시 시도하세요.',
    ],
    'zh': [
      '服务器地址，包括安装所在的子文件夹',
      '密码或应用密码',
      '如果使用双重身份验证，请在 Nextcloud 安全设置中创建应用密码。',
      '身份验证失败。请检查用户名和密码。如果使用双重身份验证，请在 Nextcloud 安全设置中创建应用密码。',
      '在浏览器中登录',
      '推荐用于单点登录、双重身份验证和电子邮件登录：在服务器页面登录并批准 CrispCloud，系统会为您创建应用密码。',
      '正在等待浏览器中的批准…',
      '浏览器登录未完成。请重试。',
    ],
    'ar': [
      'عنوان الخادم، بما في ذلك مجلد التثبيت الفرعي إن وجد',
      'كلمة المرور أو كلمة مرور التطبيق',
      'عند استخدام المصادقة الثنائية، أنشئ كلمة مرور للتطبيق في إعدادات أمان Nextcloud.',
      'فشلت المصادقة. تحقق من اسم المستخدم وكلمة المرور. عند استخدام المصادقة الثنائية، أنشئ كلمة مرور للتطبيق في إعدادات أمان Nextcloud.',
      'تسجيل الدخول عبر المتصفح',
      'يُنصح به لتسجيل الدخول الموحد والمصادقة الثنائية وتسجيل الدخول بالبريد الإلكتروني: سجّل الدخول في صفحة خادمك ووافق على CrispCloud، وستُنشأ كلمة مرور للتطبيق تلقائيًا.',
      'في انتظار الموافقة في المتصفح…',
      'لم يكتمل تسجيل الدخول عبر المتصفح. حاول مرة أخرى.',
    ],
  };
}
