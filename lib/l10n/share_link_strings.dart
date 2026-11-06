import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Localized text for creating share links.
class ShareLinkStrings {
  ShareLinkStrings(BuildContext context)
      : _language = Localizations.localeOf(context).languageCode;
  @visibleForTesting
  ShareLinkStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String name(String template, String name) =>
      text(template).replaceAll('{name}', name);
  String provider(String template, String provider) =>
      text(template).replaceAll('{provider}', provider);
  String failure(String provider, int status, String details) =>
      text('Sharing failed for {provider} (HTTP {status}): {details}')
          .replaceAll('{provider}', provider)
          .replaceAll('{status}', '$status')
          .replaceAll('{details}', details);
  String duration(int count) {
    if (_language == 'ar') {
      if (count == 1) return 'يوم واحد';
      if (count == 2) return 'يومان';
      if (count % 100 >= 3 && count % 100 <= 10) return '$count أيام';
      return '$count يومًا';
    }
    return Intl.plural(count,
            locale: _language,
            one: text('{count} day'),
            other: text('{count} days'))
        .replaceAll('{count}', '$count');
  }

  String expires(int count) =>
      text('Expires in {duration}').replaceAll('{duration}', duration(count));
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Share — {name}": "Teilen — {name}",
    "Generate Link": "Link erstellen",
    "Copy Link": "Link kopieren",
    "Link copied to clipboard": "Link in die Zwischenablage kopiert",
    "Share Options": "Freigabeoptionen",
    "Password Protection": "Passwortschutz",
    "Require password to access": "Passwort für den Zugriff erforderlich",
    "Link Password": "Link-Passwort",
    "Expiration": "Ablauf",
    "Expires in {duration}": "Läuft in {duration} ab",
    "Link never expires": "Link läuft nie ab",
    "Expires in:": "Läuft ab in:",
    "{count} day": "{count} Tag",
    "{count} days": "{count} Tagen",
    "This provider does not support password or expiration options.":
        "Dieser Anbieter unterstützt weder Passwortschutz noch Ablauf.",
    "Share URL": "Freigabe-URL",
    "Copy to clipboard": "In Zwischenablage kopieren",
    "Password protected": "Passwortgeschützt",
    "Anyone with this link can access the file.":
        "Jeder mit diesem Link kann auf die Datei zugreifen.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "Freigabe bei {provider} fehlgeschlagen (HTTP {status}): {details}",
    "Share links are not yet implemented for {provider}.":
        "Freigabelinks für {provider} sind noch nicht implementiert.",
    "{provider} does not support sharing.":
        "{provider} unterstützt keine Freigabe.",
    "The provider did not return a share link.":
        "Der Anbieter hat keinen Freigabelink zurückgegeben.",
  },
  "fr": {
    "Share — {name}": "Partager — {name}",
    "Generate Link": "Créer le lien",
    "Copy Link": "Copier le lien",
    "Link copied to clipboard": "Lien copié dans le presse-papiers",
    "Share Options": "Options de partage",
    "Password Protection": "Protection par mot de passe",
    "Require password to access": "Exiger un mot de passe",
    "Link Password": "Mot de passe du lien",
    "Expiration": "Expiration",
    "Expires in {duration}": "Expire dans {duration}",
    "Link never expires": "Le lien n’expire jamais",
    "Expires in:": "Expire dans :",
    "{count} day": "{count} jour",
    "{count} days": "{count} jours",
    "This provider does not support password or expiration options.":
        "Ce fournisseur ne prend pas en charge le mot de passe ou l’expiration.",
    "Share URL": "URL de partage",
    "Copy to clipboard": "Copier dans le presse-papiers",
    "Password protected": "Protégé par mot de passe",
    "Anyone with this link can access the file.":
        "Toute personne disposant de ce lien peut accéder au fichier.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "Échec du partage pour {provider} (HTTP {status}) : {details}",
    "Share links are not yet implemented for {provider}.":
        "Les liens de partage ne sont pas encore disponibles pour {provider}.",
    "{provider} does not support sharing.":
        "{provider} ne prend pas en charge le partage.",
    "The provider did not return a share link.":
        "Le fournisseur n’a pas renvoyé de lien de partage.",
  },
  "es": {
    "Share — {name}": "Compartir — {name}",
    "Generate Link": "Generar enlace",
    "Copy Link": "Copiar enlace",
    "Link copied to clipboard": "Enlace copiado al portapapeles",
    "Share Options": "Opciones de uso compartido",
    "Password Protection": "Protección con contraseña",
    "Require password to access": "Exigir contraseña para acceder",
    "Link Password": "Contraseña del enlace",
    "Expiration": "Caducidad",
    "Expires in {duration}": "Caduca en {duration}",
    "Link never expires": "El enlace no caduca",
    "Expires in:": "Caduca en:",
    "{count} day": "{count} día",
    "{count} days": "{count} días",
    "This provider does not support password or expiration options.":
        "Este proveedor no admite contraseña ni caducidad.",
    "Share URL": "URL compartida",
    "Copy to clipboard": "Copiar al portapapeles",
    "Password protected": "Protegido con contraseña",
    "Anyone with this link can access the file.":
        "Cualquiera que tenga este enlace puede acceder al archivo.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "Error al compartir con {provider} (HTTP {status}): {details}",
    "Share links are not yet implemented for {provider}.":
        "Los enlaces compartidos aún no están disponibles para {provider}.",
    "{provider} does not support sharing.": "{provider} no admite compartir.",
    "The provider did not return a share link.":
        "El proveedor no devolvió un enlace para compartir.",
  },
  "pt": {
    "Share — {name}": "Partilhar — {name}",
    "Generate Link": "Gerar ligação",
    "Copy Link": "Copiar ligação",
    "Link copied to clipboard": "Ligação copiada para a área de transferência",
    "Share Options": "Opções de partilha",
    "Password Protection": "Proteção por palavra-passe",
    "Require password to access": "Exigir palavra-passe para aceder",
    "Link Password": "Palavra-passe da ligação",
    "Expiration": "Validade",
    "Expires in {duration}": "Expira em {duration}",
    "Link never expires": "A ligação nunca expira",
    "Expires in:": "Expira em:",
    "{count} day": "{count} dia",
    "{count} days": "{count} dias",
    "This provider does not support password or expiration options.":
        "Este fornecedor não suporta palavra-passe nem validade.",
    "Share URL": "URL de partilha",
    "Copy to clipboard": "Copiar para a área de transferência",
    "Password protected": "Protegido por palavra-passe",
    "Anyone with this link can access the file.":
        "Qualquer pessoa com esta ligação pode aceder ao ficheiro.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "Falha na partilha com {provider} (HTTP {status}): {details}",
    "Share links are not yet implemented for {provider}.":
        "As ligações de partilha ainda não estão disponíveis para {provider}.",
    "{provider} does not support sharing.": "{provider} não suporta partilha.",
    "The provider did not return a share link.":
        "O fornecedor não devolveu uma ligação de partilha.",
  },
  "zh": {
    "Share — {name}": "分享 — {name}",
    "Generate Link": "生成链接",
    "Copy Link": "复制链接",
    "Link copied to clipboard": "链接已复制到剪贴板",
    "Share Options": "分享选项",
    "Password Protection": "密码保护",
    "Require password to access": "访问时需要密码",
    "Link Password": "链接密码",
    "Expiration": "有效期",
    "Expires in {duration}": "{duration}后过期",
    "Link never expires": "链接永不过期",
    "Expires in:": "过期时间：",
    "{count} day": "{count} 天",
    "{count} days": "{count} 天",
    "This provider does not support password or expiration options.":
        "此服务不支持密码或有效期选项。",
    "Share URL": "分享网址",
    "Copy to clipboard": "复制到剪贴板",
    "Password protected": "受密码保护",
    "Anyone with this link can access the file.": "任何拥有此链接的人都可以访问该文件。",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "通过 {provider} 分享失败（HTTP {status}）：{details}",
    "Share links are not yet implemented for {provider}.":
        "尚未实现 {provider} 的分享链接。",
    "{provider} does not support sharing.": "{provider} 不支持分享。",
    "The provider did not return a share link.": "服务提供商未返回分享链接。",
  },
  "ja": {
    "Share — {name}": "共有 — {name}",
    "Generate Link": "リンクを生成",
    "Copy Link": "リンクをコピー",
    "Link copied to clipboard": "リンクをクリップボードにコピーしました",
    "Share Options": "共有オプション",
    "Password Protection": "パスワード保護",
    "Require password to access": "アクセスにパスワードを要求",
    "Link Password": "リンクのパスワード",
    "Expiration": "有効期限",
    "Expires in {duration}": "{duration}後に期限切れ",
    "Link never expires": "リンクの期限なし",
    "Expires in:": "期限まで：",
    "{count} day": "{count} 日",
    "{count} days": "{count} 日",
    "This provider does not support password or expiration options.":
        "このプロバイダーはパスワードまたは有効期限をサポートしていません。",
    "Share URL": "共有 URL",
    "Copy to clipboard": "クリップボードにコピー",
    "Password protected": "パスワード保護あり",
    "Anyone with this link can access the file.":
        "このリンクを知っている人は誰でもファイルにアクセスできます。",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "{provider} での共有に失敗しました（HTTP {status}）：{details}",
    "Share links are not yet implemented for {provider}.":
        "{provider} の共有リンクはまだ実装されていません。",
    "{provider} does not support sharing.": "{provider} は共有に対応していません。",
    "The provider did not return a share link.": "プロバイダーから共有リンクが返されませんでした。",
  },
  "ko": {
    "Share — {name}": "공유 — {name}",
    "Generate Link": "링크 생성",
    "Copy Link": "링크 복사",
    "Link copied to clipboard": "링크가 클립보드에 복사됨",
    "Share Options": "공유 옵션",
    "Password Protection": "비밀번호 보호",
    "Require password to access": "액세스하려면 비밀번호 필요",
    "Link Password": "링크 비밀번호",
    "Expiration": "만료",
    "Expires in {duration}": "{duration} 후 만료",
    "Link never expires": "링크가 만료되지 않음",
    "Expires in:": "만료까지:",
    "{count} day": "{count}일",
    "{count} days": "{count}일",
    "This provider does not support password or expiration options.":
        "이 제공업체는 비밀번호 또는 만료 옵션을 지원하지 않습니다.",
    "Share URL": "공유 URL",
    "Copy to clipboard": "클립보드에 복사",
    "Password protected": "비밀번호로 보호됨",
    "Anyone with this link can access the file.":
        "이 링크가 있는 사람은 누구나 파일에 액세스할 수 있습니다.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "{provider} 공유 실패 (HTTP {status}): {details}",
    "Share links are not yet implemented for {provider}.":
        "{provider}의 공유 링크는 아직 구현되지 않았습니다.",
    "{provider} does not support sharing.": "{provider}은(는) 공유를 지원하지 않습니다.",
    "The provider did not return a share link.": "제공업체가 공유 링크를 반환하지 않았습니다.",
  },
  "ar": {
    "Share — {name}": "مشاركة — {name}",
    "Generate Link": "إنشاء رابط",
    "Copy Link": "نسخ الرابط",
    "Link copied to clipboard": "تم نسخ الرابط إلى الحافظة",
    "Share Options": "خيارات المشاركة",
    "Password Protection": "الحماية بكلمة مرور",
    "Require password to access": "طلب كلمة مرور للوصول",
    "Link Password": "كلمة مرور الرابط",
    "Expiration": "انتهاء الصلاحية",
    "Expires in {duration}": "تنتهي الصلاحية بعد {duration}",
    "Link never expires": "الرابط لا تنتهي صلاحيته",
    "Expires in:": "تنتهي الصلاحية بعد:",
    "{count} day": "{count} يوم",
    "{count} days": "{count} يومًا",
    "This provider does not support password or expiration options.":
        "لا يدعم هذا المزود خيارات كلمة المرور أو انتهاء الصلاحية.",
    "Share URL": "عنوان رابط المشاركة",
    "Copy to clipboard": "نسخ إلى الحافظة",
    "Password protected": "محمي بكلمة مرور",
    "Anyone with this link can access the file.":
        "يمكن لأي شخص لديه هذا الرابط الوصول إلى الملف.",
    "Sharing failed for {provider} (HTTP {status}): {details}":
        "فشلت المشاركة عبر {provider} (HTTP {status}): {details}",
    "Share links are not yet implemented for {provider}.":
        "لم تُنفذ روابط المشاركة لـ {provider} بعد.",
    "{provider} does not support sharing.": "لا يدعم {provider} المشاركة.",
    "The provider did not return a share link.": "لم يُرجع المزود رابط مشاركة.",
  },
};
