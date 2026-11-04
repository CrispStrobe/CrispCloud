import 'package:flutter/widgets.dart';

/// Text for SFTP file permissions.
class PermissionsStrings {
  PermissionsStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  PermissionsStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String format(String template, Map<String, Object?> values) =>
      text(template).replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
        final name = match.group(1)!;
        return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
      });
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Permissions — {name}": "Berechtigungen — {name}",
    "Permissions are only available for SFTP connections":
        "Berechtigungen sind nur für SFTP-Verbindungen verfügbar",
    "Failed to load permissions: {error}":
        "Berechtigungen konnten nicht geladen werden: {error}",
    "Owner": "Besitzer",
    "Group": "Gruppe",
    "Other": "Andere",
    "Cancel": "Abbrechen",
    "Apply": "Anwenden",
    "Read": "Lesen",
    "Write": "Schreiben",
    "Execute": "Ausführen",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "Berechtigungen für {name} auf {octal} ({symbolic}) gesetzt",
    "Failed to set permissions: {error}":
        "Berechtigungen konnten nicht gesetzt werden: {error}",
  },
  "fr": {
    "Permissions — {name}": "Autorisations — {name}",
    "Permissions are only available for SFTP connections":
        "Les autorisations ne sont disponibles que pour les connexions SFTP",
    "Failed to load permissions: {error}":
        "Impossible de charger les autorisations : {error}",
    "Owner": "Propriétaire",
    "Group": "Groupe",
    "Other": "Autres",
    "Cancel": "Annuler",
    "Apply": "Appliquer",
    "Read": "Lecture",
    "Write": "Écriture",
    "Execute": "Exécution",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "Autorisations de {name} définies sur {octal} ({symbolic})",
    "Failed to set permissions: {error}":
        "Impossible de définir les autorisations : {error}",
  },
  "es": {
    "Permissions — {name}": "Permisos — {name}",
    "Permissions are only available for SFTP connections":
        "Los permisos solo están disponibles para conexiones SFTP",
    "Failed to load permissions: {error}":
        "No se pudieron cargar los permisos: {error}",
    "Owner": "Propietario",
    "Group": "Grupo",
    "Other": "Otros",
    "Cancel": "Cancelar",
    "Apply": "Aplicar",
    "Read": "Lectura",
    "Write": "Escritura",
    "Execute": "Ejecución",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "Permisos de {name} establecidos en {octal} ({symbolic})",
    "Failed to set permissions: {error}":
        "No se pudieron establecer los permisos: {error}",
  },
  "pt": {
    "Permissions — {name}": "Permissões — {name}",
    "Permissions are only available for SFTP connections":
        "As permissões estão disponíveis apenas para ligações SFTP",
    "Failed to load permissions: {error}":
        "Não foi possível carregar as permissões: {error}",
    "Owner": "Proprietário",
    "Group": "Grupo",
    "Other": "Outros",
    "Cancel": "Cancelar",
    "Apply": "Aplicar",
    "Read": "Leitura",
    "Write": "Escrita",
    "Execute": "Execução",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "Permissões de {name} definidas como {octal} ({symbolic})",
    "Failed to set permissions: {error}":
        "Não foi possível definir as permissões: {error}",
  },
  "zh": {
    "Permissions — {name}": "权限 — {name}",
    "Permissions are only available for SFTP connections": "权限仅适用于 SFTP 连接",
    "Failed to load permissions: {error}": "无法加载权限：{error}",
    "Owner": "所有者",
    "Group": "群组",
    "Other": "其他",
    "Cancel": "取消",
    "Apply": "应用",
    "Read": "读取",
    "Write": "写入",
    "Execute": "执行",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "已将 {name} 的权限设为 {octal}（{symbolic}）",
    "Failed to set permissions: {error}": "无法设置权限：{error}",
  },
  "ja": {
    "Permissions — {name}": "アクセス権 — {name}",
    "Permissions are only available for SFTP connections":
        "アクセス権は SFTP 接続でのみ利用できます",
    "Failed to load permissions: {error}": "アクセス権を読み込めませんでした：{error}",
    "Owner": "所有者",
    "Group": "グループ",
    "Other": "その他",
    "Cancel": "キャンセル",
    "Apply": "適用",
    "Read": "読み取り",
    "Write": "書き込み",
    "Execute": "実行",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "{name} のアクセス権を {octal}（{symbolic}）に設定しました",
    "Failed to set permissions: {error}": "アクセス権を設定できませんでした：{error}",
  },
  "ko": {
    "Permissions — {name}": "권한 — {name}",
    "Permissions are only available for SFTP connections":
        "권한은 SFTP 연결에서만 사용할 수 있습니다",
    "Failed to load permissions: {error}": "권한을 불러오지 못했습니다: {error}",
    "Owner": "소유자",
    "Group": "그룹",
    "Other": "기타",
    "Cancel": "취소",
    "Apply": "적용",
    "Read": "읽기",
    "Write": "쓰기",
    "Execute": "실행",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "{name}의 권한을 {octal} ({symbolic})로 설정했습니다",
    "Failed to set permissions: {error}": "권한을 설정하지 못했습니다: {error}",
  },
  "ar": {
    "Permissions — {name}": "الأذونات — {name}",
    "Permissions are only available for SFTP connections":
        "الأذونات متاحة لاتصالات SFTP فقط",
    "Failed to load permissions: {error}": "تعذّر تحميل الأذونات: {error}",
    "Owner": "المالك",
    "Group": "المجموعة",
    "Other": "الآخرون",
    "Cancel": "إلغاء",
    "Apply": "تطبيق",
    "Read": "قراءة",
    "Write": "كتابة",
    "Execute": "تنفيذ",
    "Permissions set to {octal} ({symbolic}) for {name}":
        "تم تعيين أذونات {name} إلى {octal} ({symbolic})",
    "Failed to set permissions: {error}": "تعذّر تعيين الأذونات: {error}",
  },
};
