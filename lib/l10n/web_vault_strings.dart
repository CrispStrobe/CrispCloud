import 'package:flutter/widgets.dart';

/// Strings for the browser credential vault. The locale follows the app.
class WebVaultStrings {
  WebVaultStrings(BuildContext context)
    : _values =
          _translations[Localizations.localeOf(context).languageCode] ??
          _translations['en']!;

  final List<String> _values;
  String get title => _values[0];
  String get createDescription => _values[1];
  String get unlockDescription => _values[2];
  String get password => _values[3];
  String get confirmation => _values[4];
  String get create => _values[5];
  String get unlock => _values[6];
  String get mismatch => _values[7];
  String get incorrect => _values[8];
  // Never interpolate a storage exception before the vault is unlocked.
  String get failure => _values[9];

  static const _translations = <String, List<String>>{
    'en': [
      'CrispCloud — Credential Vault',
      'Create a master password to encrypt credentials stored on this device. You will need it each time you open CrispCloud.',
      'Enter your master password to unlock encrypted credential storage.',
      'Master Password',
      'Confirm master password',
      'Create vault',
      'Unlock',
      'Passwords do not match',
      'Incorrect master password',
      'Failed to initialize',
    ],
    'de': [
      'CrispCloud — Zugangsdaten-Tresor',
      'Erstellen Sie ein Master-Passwort, um die auf diesem Gerät gespeicherten Zugangsdaten zu verschlüsseln. Sie benötigen es bei jedem Öffnen von CrispCloud.',
      'Geben Sie Ihr Master-Passwort ein, um die verschlüsselten Zugangsdaten zu entsperren.',
      'Master-Passwort',
      'Master-Passwort bestätigen',
      'Tresor erstellen',
      'Entsperren',
      'Die Passwörter stimmen nicht überein',
      'Falsches Master-Passwort',
      'Initialisierung fehlgeschlagen',
    ],
    'fr': [
      'CrispCloud — Coffre d’identifiants',
      'Créez un mot de passe principal pour chiffrer les identifiants enregistrés sur cet appareil. Il sera nécessaire à chaque ouverture de CrispCloud.',
      'Saisissez votre mot de passe principal pour déverrouiller les identifiants chiffrés.',
      'Mot de passe principal',
      'Confirmer le mot de passe principal',
      'Créer le coffre',
      'Déverrouiller',
      'Les mots de passe ne correspondent pas',
      'Mot de passe principal incorrect',
      'Échec de l’initialisation',
    ],
    'es': [
      'CrispCloud — Bóveda de credenciales',
      'Crea una contraseña maestra para cifrar las credenciales guardadas en este dispositivo. La necesitarás cada vez que abras CrispCloud.',
      'Introduce tu contraseña maestra para desbloquear las credenciales cifradas.',
      'Contraseña maestra',
      'Confirmar contraseña maestra',
      'Crear bóveda',
      'Desbloquear',
      'Las contraseñas no coinciden',
      'Contraseña maestra incorrecta',
      'Error al inicializar',
    ],
    'pt': [
      'CrispCloud — Cofre de credenciais',
      'Crie uma senha mestra para criptografar as credenciais armazenadas neste dispositivo. Você precisará dela sempre que abrir o CrispCloud.',
      'Digite sua senha mestra para desbloquear as credenciais criptografadas.',
      'Senha mestra',
      'Confirmar senha mestra',
      'Criar cofre',
      'Desbloquear',
      'As senhas não coincidem',
      'Senha mestra incorreta',
      'Falha ao inicializar',
    ],
    'ar': [
      'CrispCloud — خزنة بيانات الاعتماد',
      'أنشئ كلمة مرور رئيسية لتشفير بيانات الاعتماد المحفوظة على هذا الجهاز. ستحتاج إليها في كل مرة تفتح فيها CrispCloud.',
      'أدخل كلمة المرور الرئيسية لفتح بيانات الاعتماد المشفرة.',
      'كلمة المرور الرئيسية',
      'تأكيد كلمة المرور الرئيسية',
      'إنشاء الخزنة',
      'فتح',
      'كلمتا المرور غير متطابقتين',
      'كلمة المرور الرئيسية غير صحيحة',
      'فشل التهيئة',
    ],
    'ja': [
      'CrispCloud — 認証情報保管庫',
      'このデバイスに保存する認証情報を暗号化するマスターパスワードを作成してください。CrispCloudを開くたびに必要です。',
      '暗号化された認証情報を解除するには、マスターパスワードを入力してください。',
      'マスターパスワード',
      'マスターパスワードの確認',
      '保管庫を作成',
      'ロック解除',
      'パスワードが一致しません',
      'マスターパスワードが正しくありません',
      '初期化に失敗しました',
    ],
    'ko': [
      'CrispCloud — 자격 증명 보관함',
      '이 기기에 저장된 자격 증명을 암호화할 마스터 비밀번호를 만드세요. CrispCloud를 열 때마다 필요합니다.',
      '암호화된 자격 증명의 잠금을 해제하려면 마스터 비밀번호를 입력하세요.',
      '마스터 비밀번호',
      '마스터 비밀번호 확인',
      '보관함 만들기',
      '잠금 해제',
      '비밀번호가 일치하지 않습니다',
      '마스터 비밀번호가 올바르지 않습니다',
      '초기화 실패',
    ],
    'zh': [
      'CrispCloud — 凭据保险库',
      '创建主密码以加密存储在此设备上的凭据。每次打开 CrispCloud 时都需要输入该密码。',
      '输入主密码以解锁加密的凭据。',
      '主密码',
      '确认主密码',
      '创建保险库',
      '解锁',
      '两次输入的密码不一致',
      '主密码不正确',
      '初始化失败',
    ],
  };
}
