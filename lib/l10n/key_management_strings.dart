import 'package:flutter/widgets.dart';

/// Text for encryption key export and recovery.
class KeyManagementStrings {
  KeyManagementStrings(BuildContext context)
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
      "fileRecoveryTitle": "Back up your file encryption key",
      "fileRecoveryWarning":
          "This key is kept only for this session. Your passphrase alone cannot recover files encrypted with it after a restart. Save these 24 words somewhere safe before uploading encrypted files. Anyone with the words can decrypt those files.",
      "fileRecoveryConfirm": "Re-enter the 24 saved words",
      "fileRecoveryConfirmHelp":
          "Enter all 24 words in order to confirm your backup.",
      "fileRecoveryMismatch":
          "The words do not match. Re-enter the saved phrase in the same order.",
      "fileRecoveryContinue": "Confirm backup and connect",
      "fileRecoveryCopyFailed":
          "Could not copy the recovery phrase. Write down the words before continuing.",
      "passphraseRequired":
          "Enter a passphrase before enabling file encryption.",
      "encryptionAlreadyEnabled":
          "Disable file encryption before importing a different key. Keep a backup of your current key.",
      "keyManagement": "Key Management",
      "inactive":
          "Encryption is not active. Enable it in the connection dialog, or import an existing key below.",
      "exportTab": "Export / Backup",
      "importTab": "Import / Recover",
      "noKey": "No encryption key to export",
      "phrase": "Recovery Phrase (BIP39)",
      "phraseHelp":
          "Write down these 24 words in order. They can recover your key.",
      "raw": "Raw Key (Hex)",
      "rawHelp": "32-byte encryption key as hexadecimal.",
      "bundle": "Full Backup Bundle",
      "bundleHelp":
          "JSON with mnemonic, salt, and verification. Best for full recovery.",
      "mnemonic": "Mnemonic",
      "key": "Key",
      "bundleLabel": "Backup bundle",
      "copy": "Copy {label}",
      "copied": "{label} copied to clipboard (auto-clears in 30s)",
      "restoreTitle": "Restore from Backup Bundle (recommended)",
      "bundleHint": "Paste backup bundle JSON...",
      "restore": "Restore from Bundle",
      "recoverTitle": "Recover from Mnemonic (24 words)",
      "recover": "Recover from Mnemonic",
      "importRaw": "Import Raw Key (Hex)",
      "hexHint": "64 hex characters (32 bytes)",
      "importHex": "Import Hex Key",
      "mnemonicSuccess":
          "Key recovered from mnemonic. Note: a new salt was generated. Previously encrypted files will still decrypt correctly (salt is only for key derivation).",
      "hexSuccess": "Key imported successfully.",
      "bundleSuccess": "Key and salt restored from backup bundle.",
      "dataTooShort": "Data too short for AES-GCM",
      "keyLength": "Key must be 64 hex characters (32 bytes), got {count}",
      "invalidHex": "Key contains invalid hex characters",
      "invalidMnemonic": "Invalid BIP39 mnemonic phrase",
      "verificationFailed": "Key verification failed",
      "verificationMnemonic":
          "Key verification failed — mnemonic may be incorrect",
      "hexLength": "Hex string must have even length, got {count}",
    },
    'de': {
      "fileRecoveryTitle": "Dateiverschlüsselungsschlüssel sichern",
      "fileRecoveryWarning":
          "Dieser Schlüssel wird nur für diese Sitzung gespeichert. Ihre Passphrase allein kann damit verschlüsselte Dateien nach einem Neustart nicht wiederherstellen. Bewahren Sie diese 24 Wörter sicher auf, bevor Sie verschlüsselte Dateien hochladen. Wer die Wörter kennt, kann diese Dateien entschlüsseln.",
      "fileRecoveryConfirm": "Die 24 gesicherten Wörter erneut eingeben",
      "fileRecoveryConfirmHelp":
          "Geben Sie alle 24 Wörter in der richtigen Reihenfolge ein, um die Sicherung zu bestätigen.",
      "fileRecoveryMismatch":
          "Die Wörter stimmen nicht überein. Geben Sie die gesicherte Phrase in derselben Reihenfolge erneut ein.",
      "fileRecoveryContinue": "Sicherung bestätigen und verbinden",
      "fileRecoveryCopyFailed":
          "Die Wiederherstellungsphrase konnte nicht kopiert werden. Schreiben Sie die Wörter auf, bevor Sie fortfahren.",
      "passphraseRequired":
          "Geben Sie eine Passphrase ein, bevor Sie die Dateiverschlüsselung aktivieren.",
      "encryptionAlreadyEnabled":
          "Deaktivieren Sie die Dateiverschlüsselung, bevor Sie einen anderen Schlüssel importieren. Bewahren Sie eine Sicherung Ihres aktuellen Schlüssels auf.",
      "keyManagement": "Schlüsselverwaltung",
      "inactive":
          "Verschlüsselung ist nicht aktiv. Aktivieren Sie sie im Verbindungsdialog oder importieren Sie unten einen Schlüssel.",
      "exportTab": "Export / Sicherung",
      "importTab": "Import / Wiederherstellen",
      "noKey": "Kein Verschlüsselungsschlüssel zum Exportieren",
      "phrase": "Wiederherstellungsphrase (BIP39)",
      "phraseHelp":
          "Notieren Sie diese 24 Wörter in der richtigen Reihenfolge. Damit können Sie Ihren Schlüssel wiederherstellen.",
      "raw": "Rohschlüssel (Hex)",
      "rawHelp": "32-Byte-Verschlüsselungsschlüssel als Hexadezimalwert.",
      "bundle": "Vollständiges Sicherungspaket",
      "bundleHelp":
          "JSON mit Wiederherstellungsphrase, Salt und Prüfung. Empfohlen für die vollständige Wiederherstellung.",
      "mnemonic": "Wiederherstellungsphrase",
      "key": "Schlüssel",
      "bundleLabel": "Sicherungspaket",
      "copy": "{label} kopieren",
      "copied":
          "{label} in die Zwischenablage kopiert (wird nach 30 s automatisch gelöscht)",
      "restoreTitle": "Aus Sicherungspaket wiederherstellen (empfohlen)",
      "bundleHint": "Sicherungspaket-JSON einfügen...",
      "restore": "Aus Paket wiederherstellen",
      "recoverTitle":
          "Aus Wiederherstellungsphrase wiederherstellen (24 Wörter)",
      "recover": "Aus Wiederherstellungsphrase wiederherstellen",
      "importRaw": "Rohschlüssel importieren (Hex)",
      "hexHint": "64 Hexadezimalzeichen (32 Byte)",
      "importHex": "Hex-Schlüssel importieren",
      "mnemonicSuccess":
          "Schlüssel aus Wiederherstellungsphrase wiederhergestellt. Hinweis: Ein neues Salt wurde erzeugt. Zuvor verschlüsselte Dateien können weiterhin entschlüsselt werden (das Salt dient nur der Schlüsselableitung).",
      "hexSuccess": "Schlüssel erfolgreich importiert.",
      "bundleSuccess":
          "Schlüssel und Salt aus Sicherungspaket wiederhergestellt.",
      "dataTooShort": "Daten für AES-GCM zu kurz",
      "keyLength":
          "Der Schlüssel muss 64 Hexadezimalzeichen (32 Byte) haben, erhalten: {count}",
      "invalidHex": "Der Schlüssel enthält ungültige Hexadezimalzeichen",
      "invalidMnemonic": "Ungültige BIP39-Wiederherstellungsphrase",
      "verificationFailed": "Schlüsselprüfung fehlgeschlagen",
      "verificationMnemonic":
          "Schlüsselprüfung fehlgeschlagen – Wiederherstellungsphrase möglicherweise falsch",
      "hexLength":
          "Die Hexadezimalzeichenfolge muss eine gerade Länge haben, erhalten: {count}",
    },
    'fr': {
      "fileRecoveryTitle": "Sauvegardez votre clé de chiffrement de fichiers",
      "fileRecoveryWarning":
          "Cette clé est conservée uniquement pour cette session. Après un redémarrage, votre phrase secrète seule ne permet pas de récupérer les fichiers chiffrés avec cette clé. Conservez ces 24 mots en lieu sûr avant de téléverser des fichiers chiffrés. Toute personne connaissant ces mots peut déchiffrer ces fichiers.",
      "fileRecoveryConfirm": "Saisissez à nouveau les 24 mots sauvegardés",
      "fileRecoveryConfirmHelp":
          "Saisissez les 24 mots dans l’ordre pour confirmer votre sauvegarde.",
      "fileRecoveryMismatch":
          "Les mots ne correspondent pas. Saisissez à nouveau la phrase sauvegardée dans le même ordre.",
      "fileRecoveryContinue": "Confirmer la sauvegarde et se connecter",
      "fileRecoveryCopyFailed":
          "Impossible de copier la phrase de récupération. Notez les mots avant de continuer.",
      "passphraseRequired":
          "Saisissez une phrase secrète avant d’activer le chiffrement des fichiers.",
      "encryptionAlreadyEnabled":
          "Désactivez le chiffrement des fichiers avant d’importer une autre clé. Conservez une sauvegarde de votre clé actuelle.",
      "keyManagement": "Gestion des clés",
      "inactive":
          "Le chiffrement n’est pas actif. Activez-le dans la connexion ou importez une clé ci-dessous.",
      "exportTab": "Exporter / Sauvegarder",
      "importTab": "Importer / Restaurer",
      "noKey": "Aucune clé de chiffrement à exporter",
      "phrase": "Phrase de récupération (BIP39)",
      "phraseHelp":
          "Notez ces 24 mots dans l’ordre. Ils permettent de récupérer votre clé.",
      "raw": "Clé brute (hexadécimal)",
      "rawHelp": "Clé de chiffrement de 32 octets en hexadécimal.",
      "bundle": "Sauvegarde complète",
      "bundleHelp":
          "JSON contenant la phrase, le sel et la vérification. Recommandé pour une restauration complète.",
      "mnemonic": "Phrase de récupération",
      "key": "Clé",
      "bundleLabel": "Sauvegarde",
      "copy": "Copier : {label}",
      "copied": "{label} copié dans le presse-papiers (effacé après 30 s)",
      "restoreTitle": "Restaurer depuis une sauvegarde (recommandé)",
      "bundleHint": "Collez le JSON de sauvegarde…",
      "restore": "Restaurer depuis la sauvegarde",
      "recoverTitle": "Récupérer avec la phrase (24 mots)",
      "recover": "Récupérer avec la phrase",
      "importRaw": "Importer une clé brute (hexadécimal)",
      "hexHint": "64 caractères hexadécimaux (32 octets)",
      "importHex": "Importer la clé hexadécimale",
      "mnemonicSuccess":
          "Clé récupérée. Un nouveau sel a été généré. Les fichiers déjà chiffrés restent déchiffrables (le sel sert uniquement à dériver la clé).",
      "hexSuccess": "Clé importée avec succès.",
      "bundleSuccess": "Clé et sel restaurés depuis la sauvegarde.",
      "dataTooShort": "Données trop courtes pour AES-GCM",
      "keyLength":
          "La clé doit comporter 64 caractères hexadécimaux (32 octets) ; reçu : {count}",
      "invalidHex": "La clé contient des caractères hexadécimaux invalides",
      "invalidMnemonic": "Phrase de récupération BIP39 invalide",
      "verificationFailed": "Échec de la vérification de la clé",
      "verificationMnemonic":
          "Échec de la vérification — la phrase est peut-être incorrecte",
      "hexLength":
          "La chaîne hexadécimale doit avoir une longueur paire ; reçu : {count}",
    },
    'es': {
      "fileRecoveryTitle": "Guarda tu clave de cifrado de archivos",
      "fileRecoveryWarning":
          "Esta clave se conserva solo durante esta sesión. Tras reiniciar, tu frase de contraseña por sí sola no puede recuperar los archivos cifrados con ella. Guarda estas 24 palabras en un lugar seguro antes de subir archivos cifrados. Cualquiera que conozca las palabras puede descifrar esos archivos.",
      "fileRecoveryConfirm": "Vuelve a introducir las 24 palabras guardadas",
      "fileRecoveryConfirmHelp":
          "Introduce las 24 palabras en orden para confirmar la copia.",
      "fileRecoveryMismatch":
          "Las palabras no coinciden. Vuelve a introducir la frase guardada en el mismo orden.",
      "fileRecoveryContinue": "Confirmar copia y conectar",
      "fileRecoveryCopyFailed":
          "No se pudo copiar la frase de recuperación. Anota las palabras antes de continuar.",
      "passphraseRequired":
          "Introduce una frase de contraseña antes de activar el cifrado de archivos.",
      "encryptionAlreadyEnabled":
          "Desactiva el cifrado de archivos antes de importar una clave diferente. Guarda una copia de tu clave actual.",
      "keyManagement": "Gestión de claves",
      "inactive":
          "El cifrado no está activo. Actívalo en el diálogo de conexión o importa una clave abajo.",
      "exportTab": "Exportar / Copia",
      "importTab": "Importar / Recuperar",
      "noKey": "No hay clave de cifrado para exportar",
      "phrase": "Frase de recuperación (BIP39)",
      "phraseHelp":
          "Anota estas 24 palabras en orden. Permiten recuperar tu clave.",
      "raw": "Clave sin procesar (hexadecimal)",
      "rawHelp": "Clave de cifrado de 32 bytes en hexadecimal.",
      "bundle": "Paquete de copia completo",
      "bundleHelp":
          "JSON con frase, sal y verificación. Recomendado para una recuperación completa.",
      "mnemonic": "Frase de recuperación",
      "key": "Clave",
      "bundleLabel": "Paquete de copia",
      "copy": "Copiar {label}",
      "copied": "{label} copiado al portapapeles (se borra tras 30 s)",
      "restoreTitle": "Restaurar desde copia (recomendado)",
      "bundleHint": "Pega el JSON de la copia...",
      "restore": "Restaurar desde copia",
      "recoverTitle": "Recuperar desde frase (24 palabras)",
      "recover": "Recuperar desde frase",
      "importRaw": "Importar clave sin procesar (hexadecimal)",
      "hexHint": "64 caracteres hexadecimales (32 bytes)",
      "importHex": "Importar clave hexadecimal",
      "mnemonicSuccess":
          "Clave recuperada. Se generó una nueva sal. Los archivos cifrados anteriormente se podrán descifrar (la sal solo deriva la clave).",
      "hexSuccess": "Clave importada correctamente.",
      "bundleSuccess": "Clave y sal restauradas desde la copia.",
      "dataTooShort": "Datos demasiado cortos para AES-GCM",
      "keyLength":
          "La clave debe tener 64 caracteres hexadecimales (32 bytes); recibidos: {count}",
      "invalidHex": "La clave contiene caracteres hexadecimales no válidos",
      "invalidMnemonic": "Frase de recuperación BIP39 no válida",
      "verificationFailed": "Error al verificar la clave",
      "verificationMnemonic":
          "Error al verificar la clave; la frase puede ser incorrecta",
      "hexLength":
          "La cadena hexadecimal debe tener longitud par; recibida: {count}",
    },
    'pt': {
      "fileRecoveryTitle": "Faça backup da sua chave de criptografia de arquivos",
      "fileRecoveryWarning":
          "Esta chave é mantida apenas durante esta sessão. Após reiniciar, sua frase de senha sozinha não pode recuperar os arquivos criptografados com ela. Guarde estas 24 palavras em um lugar seguro antes de enviar arquivos criptografados. Quem tiver as palavras poderá descriptografar esses arquivos.",
      "fileRecoveryConfirm": "Digite novamente as 24 palavras salvas",
      "fileRecoveryConfirmHelp":
          "Digite todas as 24 palavras na ordem para confirmar o backup.",
      "fileRecoveryMismatch":
          "As palavras não correspondem. Digite novamente a frase salva na mesma ordem.",
      "fileRecoveryContinue": "Confirmar backup e conectar",
      "fileRecoveryCopyFailed":
          "Não foi possível copiar a frase de recuperação. Anote as palavras antes de continuar.",
      "passphraseRequired":
          "Digite uma frase de senha antes de ativar a criptografia de arquivos.",
      "encryptionAlreadyEnabled":
          "Desative a criptografia de arquivos antes de importar uma chave diferente. Mantenha um backup da chave atual.",
      "keyManagement": "Gerenciamento de chaves",
      "inactive":
          "A criptografia não está ativa. Ative-a na conexão ou importe uma chave abaixo.",
      "exportTab": "Exportar / Backup",
      "importTab": "Importar / Recuperar",
      "noKey": "Nenhuma chave de criptografia para exportar",
      "phrase": "Frase de recuperação (BIP39)",
      "phraseHelp":
          "Anote estas 24 palavras na ordem. Elas recuperam sua chave.",
      "raw": "Chave bruta (hexadecimal)",
      "rawHelp": "Chave de criptografia de 32 bytes em hexadecimal.",
      "bundle": "Pacote de backup completo",
      "bundleHelp":
          "JSON com frase, salt e verificação. Recomendado para recuperação completa.",
      "mnemonic": "Frase de recuperação",
      "key": "Chave",
      "bundleLabel": "Pacote de backup",
      "copy": "Copiar {label}",
      "copied":
          "{label} copiado para a área de transferência (limpeza automática em 30 s)",
      "restoreTitle": "Restaurar do backup (recomendado)",
      "bundleHint": "Cole o JSON do backup...",
      "restore": "Restaurar do pacote",
      "recoverTitle": "Recuperar com frase (24 palavras)",
      "recover": "Recuperar com frase",
      "importRaw": "Importar chave bruta (hexadecimal)",
      "hexHint": "64 caracteres hexadecimais (32 bytes)",
      "importHex": "Importar chave hexadecimal",
      "mnemonicSuccess":
          "Chave recuperada. Um novo salt foi gerado. Arquivos já criptografados continuam sendo descriptografados (o salt serve apenas para derivar a chave).",
      "hexSuccess": "Chave importada com sucesso.",
      "bundleSuccess": "Chave e salt restaurados do backup.",
      "dataTooShort": "Dados curtos demais para AES-GCM",
      "keyLength":
          "A chave deve ter 64 caracteres hexadecimais (32 bytes); recebidos: {count}",
      "invalidHex": "A chave contém caracteres hexadecimais inválidos",
      "invalidMnemonic": "Frase de recuperação BIP39 inválida",
      "verificationFailed": "Falha na verificação da chave",
      "verificationMnemonic":
          "Falha na verificação — a frase pode estar incorreta",
      "hexLength":
          "A sequência hexadecimal deve ter tamanho par; recebido: {count}",
    },
    'zh': {
      "fileRecoveryTitle": "备份文件加密密钥",
      "fileRecoveryWarning":
          "此密钥仅保留在当前会话中。重启后，仅凭密码短语无法恢复用此密钥加密的文件。上传加密文件前，请将这 24 个单词妥善保存。任何获得这些单词的人都能解密这些文件。",
      "fileRecoveryConfirm": "重新输入已保存的 24 个单词",
      "fileRecoveryConfirmHelp": "按顺序输入全部 24 个单词以确认备份。",
      "fileRecoveryMismatch": "单词不匹配。请按相同顺序重新输入已保存的恢复短语。",
      "fileRecoveryContinue": "确认备份并连接",
      "fileRecoveryCopyFailed": "无法复制恢复短语。请先记下这些单词再继续。",
      "passphraseRequired": "启用文件加密前，请输入密码短语。",
      "encryptionAlreadyEnabled": "导入其他密钥前，请先禁用文件加密，并保留当前密钥的备份。",
      "keyManagement": "密钥管理",
      "inactive": "加密未启用。请在连接对话框中启用，或在下方导入现有密钥。",
      "exportTab": "导出 / 备份",
      "importTab": "导入 / 恢复",
      "noKey": "没有可导出的加密密钥",
      "phrase": "恢复短语（BIP39）",
      "phraseHelp": "按顺序记录这 24 个单词，它们可用于恢复密钥。",
      "raw": "原始密钥（十六进制）",
      "rawHelp": "32 字节加密密钥的十六进制表示。",
      "bundle": "完整备份包",
      "bundleHelp": "包含助记词、盐和验证信息的 JSON，最适合完整恢复。",
      "mnemonic": "助记词",
      "key": "密钥",
      "bundleLabel": "备份包",
      "copy": "复制{label}",
      "copied": "{label}已复制到剪贴板（30 秒后自动清除）",
      "restoreTitle": "从备份包恢复（推荐）",
      "bundleHint": "粘贴备份包 JSON…",
      "restore": "从备份包恢复",
      "recoverTitle": "从助记词恢复（24 个单词）",
      "recover": "从助记词恢复",
      "importRaw": "导入原始密钥（十六进制）",
      "hexHint": "64 个十六进制字符（32 字节）",
      "importHex": "导入十六进制密钥",
      "mnemonicSuccess": "已从助记词恢复密钥。已生成新的盐；以前加密的文件仍可正常解密（盐仅用于密钥派生）。",
      "hexSuccess": "密钥导入成功。",
      "bundleSuccess": "已从备份包恢复密钥和盐。",
      "dataTooShort": "数据过短，无法使用 AES-GCM",
      "keyLength": "密钥必须为 64 个十六进制字符（32 字节），实际为 {count} 个",
      "invalidHex": "密钥包含无效的十六进制字符",
      "invalidMnemonic": "BIP39 助记词无效",
      "verificationFailed": "密钥验证失败",
      "verificationMnemonic": "密钥验证失败，助记词可能有误",
      "hexLength": "十六进制字符串的长度必须为偶数，实际为 {count}",
    },
    'ja': {
      "fileRecoveryTitle": "ファイル暗号化キーをバックアップ",
      "fileRecoveryWarning":
          "このキーは現在のセッション中のみ保持されます。再起動後は、パスフレーズだけではこのキーで暗号化したファイルを復元できません。暗号化したファイルをアップロードする前に、この 24 語を安全な場所に保存してください。この単語を知っている人は、それらのファイルを復号できます。",
      "fileRecoveryConfirm": "保存した 24 語を再入力",
      "fileRecoveryConfirmHelp": "バックアップを確認するため、24 語すべてを順番に入力してください。",
      "fileRecoveryMismatch": "単語が一致しません。保存したフレーズを同じ順序で再入力してください。",
      "fileRecoveryContinue": "バックアップを確認して接続",
      "fileRecoveryCopyFailed": "復元フレーズをコピーできませんでした。続行する前に単語を書き留めてください。",
      "passphraseRequired": "ファイル暗号化を有効にする前にパスフレーズを入力してください。",
      "encryptionAlreadyEnabled": "別のキーをインポートする前にファイル暗号化を無効にし、現在のキーのバックアップを保管してください。",
      "keyManagement": "キー管理",
      "inactive": "暗号化は有効ではありません。接続画面で有効にするか、以下から既存のキーをインポートしてください。",
      "exportTab": "エクスポート / バックアップ",
      "importTab": "インポート / 復元",
      "noKey": "エクスポートする暗号化キーがありません",
      "phrase": "復元フレーズ（BIP39）",
      "phraseHelp": "この 24 語を順番に書き留めてください。キーの復元に使用できます。",
      "raw": "生キー（16 進数）",
      "rawHelp": "32 バイトの暗号化キーを 16 進数で表示します。",
      "bundle": "完全バックアップバンドル",
      "bundleHelp": "復元フレーズ、ソルト、検証情報を含む JSON。完全な復元に適しています。",
      "mnemonic": "復元フレーズ",
      "key": "キー",
      "bundleLabel": "バックアップバンドル",
      "copy": "{label}をコピー",
      "copied": "{label}をクリップボードにコピーしました（30 秒後に自動消去）",
      "restoreTitle": "バックアップバンドルから復元（推奨）",
      "bundleHint": "バックアップバンドルの JSON を貼り付け…",
      "restore": "バンドルから復元",
      "recoverTitle": "復元フレーズから復元（24 語）",
      "recover": "復元フレーズから復元",
      "importRaw": "生キーをインポート（16 進数）",
      "hexHint": "16 進数 64 文字（32 バイト）",
      "importHex": "16 進数キーをインポート",
      "mnemonicSuccess":
          "復元フレーズからキーを復元しました。新しいソルトが生成されましたが、以前のファイルは引き続き復号できます（ソルトはキー導出専用です）。",
      "hexSuccess": "キーをインポートしました。",
      "bundleSuccess": "バックアップバンドルからキーとソルトを復元しました。",
      "dataTooShort": "AES-GCM のデータが短すぎます",
      "keyLength": "キーは 16 進数 64 文字（32 バイト）である必要があります。入力: {count} 文字",
      "invalidHex": "キーに無効な 16 進文字が含まれています",
      "invalidMnemonic": "BIP39 復元フレーズが無効です",
      "verificationFailed": "キーの検証に失敗しました",
      "verificationMnemonic": "キーの検証に失敗しました。復元フレーズが間違っている可能性があります。",
      "hexLength": "16 進文字列の長さは偶数である必要があります。入力: {count}",
    },
    'ko': {
      "fileRecoveryTitle": "파일 암호화 키 백업",
      "fileRecoveryWarning":
          "이 키는 현재 세션에만 보관됩니다. 재시작 후에는 암호문구만으로 이 키로 암호화한 파일을 복구할 수 없습니다. 암호화된 파일을 업로드하기 전에 이 24개 단어를 안전한 곳에 보관하세요. 이 단어를 아는 사람은 누구나 해당 파일을 복호화할 수 있습니다.",
      "fileRecoveryConfirm": "저장한 24개 단어 다시 입력",
      "fileRecoveryConfirmHelp": "백업을 확인하려면 24개 단어를 모두 순서대로 입력하세요.",
      "fileRecoveryMismatch": "단어가 일치하지 않습니다. 저장한 문구를 같은 순서로 다시 입력하세요.",
      "fileRecoveryContinue": "백업 확인 후 연결",
      "fileRecoveryCopyFailed": "복구 문구를 복사할 수 없습니다. 계속하기 전에 단어를 적어 두세요.",
      "passphraseRequired": "파일 암호화를 활성화하기 전에 암호문구를 입력하세요.",
      "encryptionAlreadyEnabled": "다른 키를 가져오기 전에 파일 암호화를 비활성화하세요. 현재 키의 백업을 보관하세요.",
      "keyManagement": "키 관리",
      "inactive": "암호화가 활성화되어 있지 않습니다. 연결 대화상자에서 활성화하거나 아래에서 기존 키를 가져오세요.",
      "exportTab": "내보내기 / 백업",
      "importTab": "가져오기 / 복구",
      "noKey": "내보낼 암호화 키가 없습니다",
      "phrase": "복구 문구 (BIP39)",
      "phraseHelp": "이 24개 단어를 순서대로 적어 두세요. 키를 복구할 수 있습니다.",
      "raw": "원시 키 (16진수)",
      "rawHelp": "32바이트 암호화 키의 16진수 표현입니다.",
      "bundle": "전체 백업 번들",
      "bundleHelp": "복구 문구, 솔트 및 검증 정보가 포함된 JSON입니다. 전체 복구에 적합합니다.",
      "mnemonic": "복구 문구",
      "key": "키",
      "bundleLabel": "백업 번들",
      "copy": "{label} 복사",
      "copied": "{label}을(를) 클립보드에 복사했습니다 (30초 후 자동 삭제)",
      "restoreTitle": "백업 번들에서 복원 (권장)",
      "bundleHint": "백업 번들 JSON 붙여넣기...",
      "restore": "번들에서 복원",
      "recoverTitle": "복구 문구로 복구 (24단어)",
      "recover": "복구 문구로 복구",
      "importRaw": "원시 키 가져오기 (16진수)",
      "hexHint": "16진수 64자 (32바이트)",
      "importHex": "16진수 키 가져오기",
      "mnemonicSuccess":
          "복구 문구로 키를 복구했습니다. 새 솔트가 생성되었지만 이전 파일은 계속 복호화할 수 있습니다 (솔트는 키 파생에만 사용).",
      "hexSuccess": "키를 가져왔습니다.",
      "bundleSuccess": "백업 번들에서 키와 솔트를 복원했습니다.",
      "dataTooShort": "AES-GCM 데이터가 너무 짧습니다",
      "keyLength": "키는 16진수 64자 (32바이트)여야 합니다. 입력: {count}자",
      "invalidHex": "키에 잘못된 16진수 문자가 있습니다",
      "invalidMnemonic": "BIP39 복구 문구가 올바르지 않습니다",
      "verificationFailed": "키 확인 실패",
      "verificationMnemonic": "키 확인 실패 — 복구 문구가 올바르지 않을 수 있습니다",
      "hexLength": "16진수 문자열 길이는 짝수여야 합니다. 입력: {count}",
    },
    'ar': {
      "fileRecoveryTitle": "احتفظ بنسخة احتياطية من مفتاح تشفير الملفات",
      "fileRecoveryWarning":
          "يُحتفظ بهذا المفتاح خلال هذه الجلسة فقط. بعد إعادة التشغيل، لا تكفي عبارة المرور وحدها لاستعادة الملفات المشفّرة به. احفظ هذه الكلمات الأربع والعشرين في مكان آمن قبل رفع الملفات المشفّرة. يمكن لأي شخص لديه هذه الكلمات فك تشفير تلك الملفات.",
      "fileRecoveryConfirm": "أعد إدخال الكلمات الأربع والعشرين المحفوظة",
      "fileRecoveryConfirmHelp":
          "أدخل الكلمات الأربع والعشرين كلها بالترتيب لتأكيد النسخة الاحتياطية.",
      "fileRecoveryMismatch":
          "الكلمات غير متطابقة. أعد إدخال العبارة المحفوظة بالترتيب نفسه.",
      "fileRecoveryContinue": "تأكيد النسخة الاحتياطية والاتصال",
      "fileRecoveryCopyFailed":
          "تعذّر نسخ عبارة الاستعادة. دوّن الكلمات قبل المتابعة.",
      "passphraseRequired": "أدخل عبارة مرور قبل تفعيل تشفير الملفات.",
      "encryptionAlreadyEnabled":
          "عطّل تشفير الملفات قبل استيراد مفتاح مختلف. احتفظ بنسخة احتياطية من مفتاحك الحالي.",
      "keyManagement": "إدارة المفاتيح",
      "inactive":
          "التشفير غير نشط. فعّله في نافذة الاتصال أو استورد مفتاحًا موجودًا أدناه.",
      "exportTab": "تصدير / نسخ احتياطي",
      "importTab": "استيراد / استعادة",
      "noKey": "لا يوجد مفتاح تشفير لتصديره",
      "phrase": "عبارة الاستعادة (BIP39)",
      "phraseHelp":
          "اكتب هذه الكلمات الأربع والعشرين بالترتيب. يمكنها استعادة مفتاحك.",
      "raw": "المفتاح الخام (سداسي عشري)",
      "rawHelp": "مفتاح تشفير بطول 32 بايت بصيغة سداسية عشرية.",
      "bundle": "حزمة نسخ احتياطي كاملة",
      "bundleHelp":
          "ملف JSON يتضمن العبارة والملح والتحقق. الأنسب للاستعادة الكاملة.",
      "mnemonic": "عبارة الاستعادة",
      "key": "المفتاح",
      "bundleLabel": "حزمة النسخ الاحتياطي",
      "copy": "نسخ {label}",
      "copied": "نُسخ {label} إلى الحافظة (يُمسح تلقائيًا بعد 30 ثانية)",
      "restoreTitle": "الاستعادة من حزمة النسخ الاحتياطي (موصى به)",
      "bundleHint": "الصق JSON لحزمة النسخ الاحتياطي...",
      "restore": "الاستعادة من الحزمة",
      "recoverTitle": "الاستعادة من العبارة (24 كلمة)",
      "recover": "الاستعادة من العبارة",
      "importRaw": "استيراد المفتاح الخام (سداسي عشري)",
      "hexHint": "64 حرفًا سداسيًا عشريًا (32 بايت)",
      "importHex": "استيراد المفتاح السداسي",
      "mnemonicSuccess":
          "تمت استعادة المفتاح من العبارة وإنشاء ملح جديد. سيظل فك تشفير الملفات السابقة ممكنًا (يُستخدم الملح لاشتقاق المفتاح فقط).",
      "hexSuccess": "تم استيراد المفتاح بنجاح.",
      "bundleSuccess": "تمت استعادة المفتاح والملح من حزمة النسخ الاحتياطي.",
      "dataTooShort": "البيانات قصيرة جدًا لـ AES-GCM",
      "keyLength":
          "يجب أن يتكون المفتاح من 64 حرفًا سداسيًا عشريًا (32 بايت)، المدخل: {count}",
      "invalidHex": "يحتوي المفتاح على أحرف سداسية عشرية غير صالحة",
      "invalidMnemonic": "عبارة استعادة BIP39 غير صالحة",
      "verificationFailed": "فشل التحقق من المفتاح",
      "verificationMnemonic":
          "فشل التحقق من المفتاح — قد تكون عبارة الاستعادة غير صحيحة",
      "hexLength": "يجب أن يكون طول السلسلة السداسية زوجيًا، المدخل: {count}",
    },
  };
}
