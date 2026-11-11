import 'package:flutter/widgets.dart';

/// A small independent fallback so startup errors remain readable even when
/// the normal application state and providers could not be initialized.
class StartupFailureStrings {
  StartupFailureStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String get title => _titles[language] ?? _titles['en']!;
  List<String> get _credentialValues =>
      _credentialMessages[language] ?? _credentialMessages['en']!;
  String get credentialStorageUnavailable => _credentialValues[0];
  String get restoreKeychainAccess => _credentialValues[1];
  String get restoreOriginalKeychain => _credentialValues[2];
  String get credentialSelectionChanged => _credentialValues[3];
  String get chooseAnotherStore => _credentialValues[4];
  String get chooseAnotherStoreWarning => _credentialValues[5];
  String get chooseAnotherStoreConfirm => _credentialValues[6];

  static const _credentialMessages = <String, List<String>>{
    'en': [
      'The selected credential store is unavailable. Restore access or unlock it, then retry.',
      'Restore keychain access',
      'Select the original keychain file to grant access again. Restore a missing file to its original location first. Your storage choice and App Lock remain unchanged.',
      'Credential storage changed while access was being restored. Retry to open the current selection.',
      'Choose another credential store…',
      'CrispCloud will start with a different credential store. Saved sign-ins and the App Lock in the unavailable store are neither used nor deleted: reconnect your accounts and enable App Lock again. You can switch back in Settings once the original store is available.',
      'Choose store',
    ],
    'de': [
      'Der ausgewählte Speicher für Zugangsdaten ist nicht verfügbar. Stellen Sie den Zugriff wieder her oder entsperren Sie ihn und versuchen Sie es erneut.',
      'Schlüsselbundzugriff wiederherstellen',
      'Wählen Sie die ursprüngliche Schlüsselbunddatei, um den Zugriff erneut zu erlauben. Stellen Sie eine fehlende Datei zuerst an ihrem ursprünglichen Speicherort wieder her. Ihre Speicherauswahl und die App-Sperre bleiben unverändert.',
      'Der Speicher für Zugangsdaten wurde während der Wiederherstellung des Zugriffs geändert. Versuchen Sie es erneut, um die aktuelle Auswahl zu öffnen.',
      'Anderen Speicher für Zugangsdaten wählen…',
      'CrispCloud startet mit einem anderen Speicher für Zugangsdaten. Gespeicherte Anmeldungen und die App-Sperre im nicht verfügbaren Speicher werden weder verwendet noch gelöscht: Verbinden Sie Ihre Konten erneut und aktivieren Sie die App-Sperre wieder. Sobald der ursprüngliche Speicher verfügbar ist, können Sie in den Einstellungen zurückwechseln.',
      'Speicher wählen',
    ],
    'fr': [
      'Le stockage d’identifiants sélectionné est indisponible. Rétablissez l’accès ou déverrouillez-le, puis réessayez.',
      'Rétablir l’accès au trousseau',
      'Sélectionnez le fichier de trousseau d’origine pour autoriser à nouveau l’accès. Restaurez d’abord tout fichier manquant à son emplacement d’origine. Votre choix de stockage et le verrouillage de l’application restent inchangés.',
      'Le stockage d’identifiants a changé pendant le rétablissement de l’accès. Réessayez pour ouvrir la sélection actuelle.',
      'Choisir un autre stockage d’identifiants…',
      'CrispCloud démarrera avec un autre stockage d’identifiants. Les connexions enregistrées et le verrouillage de l’application du stockage indisponible ne sont ni utilisés ni supprimés : reconnectez vos comptes et réactivez le verrouillage. Vous pourrez revenir en arrière dans les Réglages lorsque le stockage d’origine sera de nouveau disponible.',
      'Choisir le stockage',
    ],
    'es': [
      'El almacén de credenciales seleccionado no está disponible. Restablece el acceso o desbloquéalo y vuelve a intentarlo.',
      'Restablecer acceso al llavero',
      'Selecciona el archivo de llavero original para volver a permitir el acceso. Si falta, restáuralo primero en su ubicación original. La selección de almacenamiento y el bloqueo de la aplicación no cambian.',
      'El almacenamiento de credenciales cambió mientras se restablecía el acceso. Vuelve a intentarlo para abrir la selección actual.',
      'Elegir otro almacén de credenciales…',
      'CrispCloud se iniciará con otro almacén de credenciales. Los inicios de sesión guardados y el bloqueo de la aplicación del almacén no disponible no se usan ni se eliminan: vuelve a conectar tus cuentas y activa de nuevo el bloqueo. Podrás volver al almacén original desde Ajustes cuando esté disponible.',
      'Elegir almacén',
    ],
    'pt': [
      'O armazenamento de credenciais selecionado está indisponível. Restaure o acesso ou desbloqueie-o e tente novamente.',
      'Restaurar acesso ao chaveiro',
      'Selecione o arquivo de chaveiro original para permitir o acesso novamente. Se o arquivo estiver ausente, restaure-o primeiro no local original. A escolha de armazenamento e o bloqueio do aplicativo permanecem inalterados.',
      'O armazenamento de credenciais mudou durante a restauração do acesso. Tente novamente para abrir a seleção atual.',
      'Escolher outro armazenamento de credenciais…',
      'O CrispCloud será iniciado com outro armazenamento de credenciais. Os logins salvos e o bloqueio do aplicativo do armazenamento indisponível não são usados nem excluídos: conecte suas contas novamente e reative o bloqueio. Você pode voltar ao original nas Configurações quando ele estiver disponível.',
      'Escolher armazenamento',
    ],
    'zh': [
      '所选凭据存储不可用。请恢复访问权限或解锁后重试。',
      '恢复钥匙串访问权限',
      '请选择原来的钥匙串文件以重新授予访问权限。如果文件丢失，请先将其恢复到原来的位置。您的存储选择和应用锁保持不变。',
      '恢复访问权限期间，凭据存储已更改。请重试以打开当前选择。',
      '选择其他凭据存储…',
      'CrispCloud 将使用其他凭据存储启动。不可用存储中保存的登录信息和应用锁既不会被使用，也不会被删除：请重新连接您的帐户并再次启用应用锁。原始存储恢复可用后，您可以在设置中切换回去。',
      '选择存储',
    ],
    'ja': [
      '選択した認証情報ストレージを利用できません。アクセスを復元するかロックを解除してから再試行してください。',
      'キーチェーンへのアクセスを復元',
      '元のキーチェーンファイルを選択して、アクセスを再度許可してください。ファイルが見つからない場合は、先に元の場所に復元してください。ストレージの選択とアプリロックは変更されません。',
      'アクセスの復元中に認証情報ストレージが変更されました。再試行して現在の選択を開いてください。',
      '別の認証情報ストレージを選択…',
      'CrispCloud は別の認証情報ストレージで起動します。利用できないストレージに保存されたサインイン情報とアプリロックは使用も削除もされません。アカウントを再接続し、アプリロックを再度有効にしてください。元のストレージが利用可能になったら、設定で元に戻せます。',
      'ストレージを選択',
    ],
    'ko': [
      '선택한 자격 증명 저장소를 사용할 수 없습니다. 접근 권한을 복원하거나 잠금을 해제한 후 다시 시도하세요.',
      '키체인 접근 권한 복원',
      '원래 키체인 파일을 선택하여 접근을 다시 허용하세요. 파일이 없다면 먼저 원래 위치에 복원하세요. 저장소 선택과 앱 잠금은 변경되지 않습니다.',
      '접근 권한을 복원하는 동안 자격 증명 저장소가 변경되었습니다. 다시 시도하여 현재 선택한 저장소를 여세요.',
      '다른 자격 증명 저장소 선택…',
      'CrispCloud가 다른 자격 증명 저장소로 시작됩니다. 사용할 수 없는 저장소에 저장된 로그인 정보와 앱 잠금은 사용되거나 삭제되지 않습니다. 계정을 다시 연결하고 앱 잠금을 다시 활성화하세요. 원래 저장소를 다시 사용할 수 있게 되면 설정에서 되돌릴 수 있습니다.',
      '저장소 선택',
    ],
    'ar': [
      'مخزن بيانات الاعتماد المحدد غير متاح. استعد إمكانية الوصول إليه أو افتح قفله، ثم أعد المحاولة.',
      'استعادة الوصول إلى سلسلة المفاتيح',
      'حدد ملف سلسلة المفاتيح الأصلي للسماح بالوصول مجددًا. إذا كان الملف مفقودًا، فاستعده إلى موقعه الأصلي أولًا. سيبقى اختيار التخزين وقفل التطبيق دون تغيير.',
      'تغير مخزن بيانات الاعتماد أثناء استعادة الوصول. أعد المحاولة لفتح الاختيار الحالي.',
      'اختيار مخزن آخر لبيانات الاعتماد…',
      'سيبدأ CrispCloud باستخدام مخزن آخر لبيانات الاعتماد. لن تُستخدم عمليات تسجيل الدخول المحفوظة وقفل التطبيق في المخزن غير المتاح ولن تُحذف: أعد ربط حساباتك وفعّل قفل التطبيق مجددًا. يمكنك العودة إلى المخزن الأصلي من الإعدادات عندما يصبح متاحًا.',
      'اختيار المخزن',
    ],
  };

  static const Map<String, String> _titles = {
    'en': 'Failed to start CrispCloud:',
    'de': 'CrispCloud konnte nicht gestartet werden:',
    'fr': 'Impossible de démarrer CrispCloud :',
    'es': 'No se pudo iniciar CrispCloud:',
    'pt': 'Não foi possível iniciar o CrispCloud:',
    'zh': '无法启动 CrispCloud：',
    'ja': 'CrispCloud を起動できませんでした:',
    'ko': 'CrispCloud를 시작할 수 없습니다:',
    'ar': 'تعذر بدء CrispCloud:',
  };
}
