import 'package:flutter/widgets.dart';

/// Strings for unlocking the encrypted credential vault with Touch ID.
/// The locale follows the app; every language matches the app's locales.
class BiometricVaultStrings {
  BiometricVaultStrings(BuildContext context)
    : this.forLanguage(Localizations.localeOf(context).languageCode);

  BiometricVaultStrings.forLanguage(String languageCode)
    : _values = translations[languageCode] ?? translations['en']!;

  final List<String> _values;
  String get offerTitle => _values[0];
  String get offerBody => _values[1];
  String get notNow => _values[2];
  String get enable => _values[3];

  /// macOS shows this as "CrispCloud is trying to <reason>."
  String get reason => _values[4];
  String get unlockButton => _values[5];
  String get invalidated => _values[6];
  String get settingsTitle => _values[7];
  String get settingsSubtitle => _values[8];
  String get notEnrolled => _values[9];
  String get missingEntitlement => _values[10];
  String get unavailable => _values[11];
  String get enableFailed => _values[12];

  @visibleForTesting
  static const translations = <String, List<String>>{
    'en': [
      'Unlock with Touch ID next time?',
      'CrispCloud can keep the vault key in the macOS keychain, protected by Touch ID. Your master password keeps working, and you can turn this off in Settings.',
      'Not now',
      'Use Touch ID',
      'unlock your credential vault',
      'Unlock with Touch ID',
      'Your Touch ID fingerprints changed. Enter your master password to unlock, then you can turn Touch ID on again.',
      'Unlock with Touch ID',
      'Use Touch ID instead of typing the master password.',
      'Set up Touch ID in System Settings to use this.',
      'Not available in this build: it must be signed by the developer to use the protected keychain.',
      'Touch ID is not available on this Mac right now.',
      'Could not turn on Touch ID unlock. Your master password still works.',
    ],
    'de': [
      'Nächstes Mal mit Touch ID entsperren?',
      'CrispCloud kann den Tresorschlüssel im macOS-Schlüsselbund ablegen, geschützt durch Touch ID. Ihr Master-Passwort funktioniert weiterhin, und Sie können dies in den Einstellungen ausschalten.',
      'Nicht jetzt',
      'Touch ID verwenden',
      'Ihren Zugangsdaten-Tresor entsperren',
      'Mit Touch ID entsperren',
      'Ihre Touch-ID-Fingerabdrücke haben sich geändert. Entsperren Sie mit Ihrem Master-Passwort; danach können Sie Touch ID wieder einschalten.',
      'Mit Touch ID entsperren',
      'Touch ID statt Eingabe des Master-Passworts verwenden.',
      'Richten Sie Touch ID in den Systemeinstellungen ein, um dies zu nutzen.',
      'In diesem Build nicht verfügbar: Für den geschützten Schlüsselbund muss die App vom Entwickler signiert sein.',
      'Touch ID ist auf diesem Mac derzeit nicht verfügbar.',
      'Entsperren mit Touch ID konnte nicht eingeschaltet werden. Ihr Master-Passwort funktioniert weiterhin.',
    ],
    'fr': [
      'Déverrouiller avec Touch ID la prochaine fois ?',
      'CrispCloud peut conserver la clé du coffre dans le trousseau macOS, protégée par Touch ID. Votre mot de passe principal reste valable et vous pouvez désactiver cette option dans les Réglages.',
      'Pas maintenant',
      'Utiliser Touch ID',
      'déverrouiller votre coffre d’identifiants',
      'Déverrouiller avec Touch ID',
      'Vos empreintes Touch ID ont changé. Saisissez votre mot de passe principal pour déverrouiller, puis vous pourrez réactiver Touch ID.',
      'Déverrouiller avec Touch ID',
      'Utiliser Touch ID au lieu de saisir le mot de passe principal.',
      'Configurez Touch ID dans les Réglages Système pour utiliser cette option.',
      'Indisponible dans cette version : l’app doit être signée par le développeur pour utiliser le trousseau protégé.',
      'Touch ID n’est pas disponible sur ce Mac pour le moment.',
      'Impossible d’activer le déverrouillage Touch ID. Votre mot de passe principal reste valable.',
    ],
    'es': [
      '¿Desbloquear con Touch ID la próxima vez?',
      'CrispCloud puede guardar la clave de la bóveda en el llavero de macOS, protegida con Touch ID. Tu contraseña maestra sigue funcionando y puedes desactivarlo en Ajustes.',
      'Ahora no',
      'Usar Touch ID',
      'desbloquear tu bóveda de credenciales',
      'Desbloquear con Touch ID',
      'Tus huellas de Touch ID han cambiado. Introduce tu contraseña maestra para desbloquear y después podrás volver a activar Touch ID.',
      'Desbloquear con Touch ID',
      'Usa Touch ID en lugar de escribir la contraseña maestra.',
      'Configura Touch ID en Ajustes del Sistema para usar esta opción.',
      'No disponible en esta compilación: la app debe estar firmada por el desarrollador para usar el llavero protegido.',
      'Touch ID no está disponible en este Mac en este momento.',
      'No se pudo activar el desbloqueo con Touch ID. Tu contraseña maestra sigue funcionando.',
    ],
    'pt': [
      'Desbloquear com Touch ID da próxima vez?',
      'O CrispCloud pode guardar a chave do cofre nas Chaves do macOS, protegida pelo Touch ID. Sua senha mestra continua funcionando e você pode desativar isso nos Ajustes.',
      'Agora não',
      'Usar Touch ID',
      'desbloquear seu cofre de credenciais',
      'Desbloquear com Touch ID',
      'Suas digitais do Touch ID mudaram. Digite sua senha mestra para desbloquear e depois você poderá ativar o Touch ID novamente.',
      'Desbloquear com Touch ID',
      'Use o Touch ID em vez de digitar a senha mestra.',
      'Configure o Touch ID nos Ajustes do Sistema para usar isto.',
      'Indisponível nesta versão: o app precisa ser assinado pelo desenvolvedor para usar as chaves protegidas.',
      'O Touch ID não está disponível neste Mac no momento.',
      'Não foi possível ativar o desbloqueio com Touch ID. Sua senha mestra continua funcionando.',
    ],
    'zh': [
      '下次使用触控 ID 解锁？',
      'CrispCloud 可以将保险库密钥保存在 macOS 钥匙串中，并由触控 ID 保护。主密码仍然可用，你也可以在设置中关闭此功能。',
      '暂不',
      '使用触控 ID',
      '解锁你的凭据保险库',
      '使用触控 ID 解锁',
      '你的触控 ID 指纹已更改。请输入主密码解锁，之后可以重新开启触控 ID。',
      '使用触控 ID 解锁',
      '使用触控 ID 代替输入主密码。',
      '请先在系统设置中设置触控 ID。',
      '此版本不可用：应用必须由开发者签名才能使用受保护的钥匙串。',
      '此 Mac 当前无法使用触控 ID。',
      '无法开启触控 ID 解锁。主密码仍然可用。',
    ],
    'ja': [
      '次回から Touch ID でロック解除しますか？',
      'CrispCloud は保管庫の鍵を Touch ID で保護された macOS キーチェーンに保存できます。マスターパスワードも引き続き使用でき、設定でいつでもオフにできます。',
      '後で',
      'Touch ID を使用',
      '認証情報保管庫のロックを解除',
      'Touch ID でロック解除',
      'Touch ID の指紋が変更されました。マスターパスワードでロックを解除してから、Touch ID を再度オンにできます。',
      'Touch ID でロック解除',
      'マスターパスワードを入力する代わりに Touch ID を使用します。',
      'これを使用するには、システム設定で Touch ID を設定してください。',
      'このビルドでは使用できません：保護されたキーチェーンを使うには開発者による署名が必要です。',
      'この Mac では現在 Touch ID を使用できません。',
      'Touch ID によるロック解除をオンにできませんでした。マスターパスワードは引き続き使用できます。',
    ],
    'ko': [
      '다음부터 Touch ID로 잠금 해제할까요?',
      'CrispCloud는 보관함 키를 Touch ID로 보호되는 macOS 키체인에 보관할 수 있습니다. 마스터 비밀번호도 계속 사용할 수 있으며 설정에서 끌 수 있습니다.',
      '나중에',
      'Touch ID 사용',
      '자격 증명 보관함 잠금 해제',
      'Touch ID로 잠금 해제',
      'Touch ID 지문이 변경되었습니다. 마스터 비밀번호로 잠금 해제한 후 Touch ID를 다시 켤 수 있습니다.',
      'Touch ID로 잠금 해제',
      '마스터 비밀번호를 입력하는 대신 Touch ID를 사용합니다.',
      '이 기능을 사용하려면 시스템 설정에서 Touch ID를 설정하세요.',
      '이 빌드에서는 사용할 수 없습니다: 보호된 키체인을 사용하려면 개발자가 서명한 앱이어야 합니다.',
      '현재 이 Mac에서 Touch ID를 사용할 수 없습니다.',
      'Touch ID 잠금 해제를 켤 수 없습니다. 마스터 비밀번호는 계속 사용할 수 있습니다.',
    ],
    'ar': [
      'هل تريد الفتح باستخدام Touch ID في المرة القادمة؟',
      'يمكن لـ CrispCloud الاحتفاظ بمفتاح الخزنة في سلسلة مفاتيح macOS محميًا بـ Touch ID. ستظل كلمة المرور الرئيسية تعمل، ويمكنك إيقاف ذلك من الإعدادات.',
      'ليس الآن',
      'استخدام Touch ID',
      'فتح خزنة بيانات الاعتماد',
      'الفتح باستخدام Touch ID',
      'تغيرت بصمات Touch ID. أدخل كلمة المرور الرئيسية للفتح، ثم يمكنك تشغيل Touch ID مرة أخرى.',
      'الفتح باستخدام Touch ID',
      'استخدم Touch ID بدلًا من كتابة كلمة المرور الرئيسية.',
      'أعدّ Touch ID في إعدادات النظام لاستخدام هذه الميزة.',
      'غير متاح في هذا الإصدار: يجب أن يوقّع المطوّر التطبيق لاستخدام سلسلة المفاتيح المحمية.',
      'Touch ID غير متاح على هذا الـ Mac حاليًا.',
      'تعذّر تشغيل الفتح باستخدام Touch ID. ستظل كلمة المرور الرئيسية تعمل.',
    ],
  };
}
