/// Localized shared connection validation and platform errors.
const Map<String, Map<String, String>> remoteValidationStrings = {
  "de": {
    "invalidCredentials":
        "Geben Sie einen Verbindungsnamen und gültige Zugangsdaten ein.",
    "invalidUrl":
        "Verwenden Sie smb://host/freigabe/ für SMB, sftp:// für SFTP oder HTTPS für Plex/WebDAV. Lokales HTTP erfordert eine ausdrückliche Freigabe.",
    "invalidShare": "Geben Sie eine SMB-Freigabe ein: smb://host/freigabe/.",
    "invalidFingerprint": "Ungültiger SSH-SHA256-Fingerabdruck.",
    "smbWebUnsupported": "SMB erfordert die installierte App.",
    "sftpOffsetRequired":
        "Verwenden Sie für diese Quelle den SFTP-Download mit Offset."
  },
  "fr": {
    "invalidCredentials":
        "Saisissez un nom de connexion et des identifiants valides.",
    "invalidUrl":
        "Utilisez smb://hôte/partage/ pour SMB, sftp:// pour SFTP ou HTTPS pour Plex/WebDAV. Le HTTP local exige une autorisation explicite.",
    "invalidShare": "Saisissez un partage SMB : smb://hôte/partage/.",
    "invalidFingerprint": "Empreinte SSH SHA256 invalide.",
    "smbWebUnsupported": "SMB nécessite l’application installée.",
    "sftpOffsetRequired":
        "Utilisez le téléchargement SFTP avec décalage pour cette source."
  },
  "es": {
    "invalidCredentials":
        "Introduce un nombre de conexión y credenciales válidas.",
    "invalidUrl":
        "Usa smb://host/recurso/ para SMB, sftp:// para SFTP o HTTPS para Plex/WebDAV. HTTP local requiere autorización explícita.",
    "invalidShare": "Introduce un recurso SMB: smb://host/recurso/.",
    "invalidFingerprint": "Huella SSH SHA256 no válida.",
    "smbWebUnsupported": "SMB requiere la aplicación instalada.",
    "sftpOffsetRequired":
        "Usa la descarga SFTP con desplazamiento para esta fuente."
  },
  "pt": {
    "invalidCredentials": "Introduza um nome de ligação e credenciais válidas.",
    "invalidUrl":
        "Use smb://host/partilha/ para SMB, sftp:// para SFTP ou HTTPS para Plex/WebDAV. HTTP local exige autorização explícita.",
    "invalidShare": "Introduza uma partilha SMB: smb://host/partilha/.",
    "invalidFingerprint": "Impressão digital SSH SHA256 inválida.",
    "smbWebUnsupported": "SMB requer a aplicação instalada.",
    "sftpOffsetRequired":
        "Use a transferência SFTP com deslocamento para esta origem."
  },
  "zh": {
    "invalidCredentials": "请输入连接名称和有效凭据。",
    "invalidUrl":
        "SMB 使用 smb://host/share/，SFTP 使用 sftp://，Plex/WebDAV 使用 HTTPS。本地 HTTP 需要明确启用。",
    "invalidShare": "请输入 SMB 共享：smb://host/share/。",
    "invalidFingerprint": "SSH SHA256 指纹无效。",
    "smbWebUnsupported": "SMB 需要安装的应用。",
    "sftpOffsetRequired": "对此来源请使用 SFTP 偏移下载。"
  },
  "ja": {
    "invalidCredentials": "接続名と有効な認証情報を入力してください。",
    "invalidUrl":
        "SMB には smb://host/share/、SFTP には sftp://、Plex/WebDAV には HTTPS を使用してください。ローカル HTTP は明示的な許可が必要です。",
    "invalidShare": "SMB 共有を入力してください: smb://host/share/。",
    "invalidFingerprint": "SSH SHA256 フィンガープリントが無効です。",
    "smbWebUnsupported": "SMB にはインストール版アプリが必要です。",
    "sftpOffsetRequired": "このソースには SFTP オフセットダウンロードを使用してください。"
  },
  "ko": {
    "invalidCredentials": "연결 이름과 유효한 자격 증명을 입력하세요.",
    "invalidUrl":
        "SMB에는 smb://host/share/, SFTP에는 sftp://, Plex/WebDAV에는 HTTPS를 사용하세요. 로컬 HTTP는 명시적 허용이 필요합니다.",
    "invalidShare": "SMB 공유를 입력하세요: smb://host/share/.",
    "invalidFingerprint": "잘못된 SSH SHA256 지문입니다.",
    "smbWebUnsupported": "SMB에는 설치된 앱이 필요합니다.",
    "sftpOffsetRequired": "이 소스에는 SFTP 오프셋 다운로드를 사용하세요."
  },
  "ar": {
    "invalidCredentials": "أدخل اسم الاتصال وبيانات اعتماد صالحة.",
    "invalidUrl":
        "استخدم smb://host/share/ لـ SMB وsftp:// لـ SFTP أو HTTPS لـ Plex/WebDAV. يتطلب HTTP المحلي موافقة صريحة.",
    "invalidShare": "أدخل مشاركة SMB: smb://host/share/.",
    "invalidFingerprint": "بصمة SSH SHA256 غير صالحة.",
    "smbWebUnsupported": "يتطلب SMB التطبيق المثبت.",
    "sftpOffsetRequired": "استخدم تنزيل SFTP بالإزاحة لهذا المصدر."
  }
};
