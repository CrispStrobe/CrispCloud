import 'package:flutter/widgets.dart';

/// Text displayed in the audit log.
class AuditLogStrings {
  AuditLogStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  AuditLogStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Audit log copied to clipboard as JSON":
        "Audit-Protokoll als JSON in die Zwischenablage kopiert",
    "Clear Audit Log": "Audit-Protokoll löschen",
    "This will permanently delete all audit log entries. Continue?":
        "Alle Einträge des Audit-Protokolls werden dauerhaft gelöscht. Fortfahren?",
    "Cancel": "Abbrechen",
    "Clear": "Löschen",
    "Audit Log": "Audit-Protokoll",
    "Refresh": "Aktualisieren",
    "No audit entries yet": "Noch keine Audit-Einträge",
    "Export JSON": "JSON exportieren",
    "Close": "Schließen",
    "Upload": "Hochladen",
    "Download": "Herunterladen",
    "Delete": "Löschen",
    "Rename": "Umbenennen",
    "Move": "Verschieben",
    "Copy": "Kopieren",
    "Create folder": "Ordner erstellen",
    "Sync": "Synchronisieren",
  },
  "fr": {
    "Audit log copied to clipboard as JSON":
        "Journal d’audit copié en JSON dans le presse-papiers",
    "Clear Audit Log": "Effacer le journal d’audit",
    "This will permanently delete all audit log entries. Continue?":
        "Toutes les entrées du journal d’audit seront définitivement supprimées. Continuer ?",
    "Cancel": "Annuler",
    "Clear": "Effacer",
    "Audit Log": "Journal d’audit",
    "Refresh": "Actualiser",
    "No audit entries yet": "Aucune entrée d’audit pour le moment",
    "Export JSON": "Exporter en JSON",
    "Close": "Fermer",
    "Upload": "Envoyer",
    "Download": "Télécharger",
    "Delete": "Supprimer",
    "Rename": "Renommer",
    "Move": "Déplacer",
    "Copy": "Copier",
    "Create folder": "Créer un dossier",
    "Sync": "Synchroniser",
  },
  "es": {
    "Audit log copied to clipboard as JSON":
        "Registro de auditoría copiado al portapapeles como JSON",
    "Clear Audit Log": "Borrar registro de auditoría",
    "This will permanently delete all audit log entries. Continue?":
        "Se eliminarán permanentemente todas las entradas del registro de auditoría. ¿Continuar?",
    "Cancel": "Cancelar",
    "Clear": "Borrar",
    "Audit Log": "Registro de auditoría",
    "Refresh": "Actualizar",
    "No audit entries yet": "Todavía no hay entradas de auditoría",
    "Export JSON": "Exportar JSON",
    "Close": "Cerrar",
    "Upload": "Subir",
    "Download": "Descargar",
    "Delete": "Eliminar",
    "Rename": "Renombrar",
    "Move": "Mover",
    "Copy": "Copiar",
    "Create folder": "Crear carpeta",
    "Sync": "Sincronizar",
  },
  "pt": {
    "Audit log copied to clipboard as JSON":
        "Registo de auditoria copiado para a área de transferência como JSON",
    "Clear Audit Log": "Limpar registo de auditoria",
    "This will permanently delete all audit log entries. Continue?":
        "Todas as entradas do registo de auditoria serão eliminadas permanentemente. Continuar?",
    "Cancel": "Cancelar",
    "Clear": "Limpar",
    "Audit Log": "Registo de auditoria",
    "Refresh": "Atualizar",
    "No audit entries yet": "Ainda não existem entradas de auditoria",
    "Export JSON": "Exportar JSON",
    "Close": "Fechar",
    "Upload": "Enviar",
    "Download": "Transferir",
    "Delete": "Eliminar",
    "Rename": "Mudar nome",
    "Move": "Mover",
    "Copy": "Copiar",
    "Create folder": "Criar pasta",
    "Sync": "Sincronizar",
  },
  "zh": {
    "Audit log copied to clipboard as JSON": "审计日志已作为 JSON 复制到剪贴板",
    "Clear Audit Log": "清除审计日志",
    "This will permanently delete all audit log entries. Continue?":
        "这将永久删除所有审计日志条目。是否继续？",
    "Cancel": "取消",
    "Clear": "清除",
    "Audit Log": "审计日志",
    "Refresh": "刷新",
    "No audit entries yet": "暂无审计记录",
    "Export JSON": "导出 JSON",
    "Close": "关闭",
    "Upload": "上传",
    "Download": "下载",
    "Delete": "删除",
    "Rename": "重命名",
    "Move": "移动",
    "Copy": "复制",
    "Create folder": "创建文件夹",
    "Sync": "同步",
  },
  "ja": {
    "Audit log copied to clipboard as JSON": "監査ログを JSON としてクリップボードにコピーしました",
    "Clear Audit Log": "監査ログを消去",
    "This will permanently delete all audit log entries. Continue?":
        "すべての監査ログ項目が完全に削除されます。続行しますか？",
    "Cancel": "キャンセル",
    "Clear": "消去",
    "Audit Log": "監査ログ",
    "Refresh": "更新",
    "No audit entries yet": "監査ログはまだありません",
    "Export JSON": "JSON をエクスポート",
    "Close": "閉じる",
    "Upload": "アップロード",
    "Download": "ダウンロード",
    "Delete": "削除",
    "Rename": "名前を変更",
    "Move": "移動",
    "Copy": "コピー",
    "Create folder": "フォルダーを作成",
    "Sync": "同期",
  },
  "ko": {
    "Audit log copied to clipboard as JSON": "감사 로그가 JSON으로 클립보드에 복사됨",
    "Clear Audit Log": "감사 로그 지우기",
    "This will permanently delete all audit log entries. Continue?":
        "모든 감사 로그 항목이 영구적으로 삭제됩니다. 계속하시겠습니까?",
    "Cancel": "취소",
    "Clear": "지우기",
    "Audit Log": "감사 로그",
    "Refresh": "새로고침",
    "No audit entries yet": "아직 감사 항목이 없습니다",
    "Export JSON": "JSON 내보내기",
    "Close": "닫기",
    "Upload": "업로드",
    "Download": "다운로드",
    "Delete": "삭제",
    "Rename": "이름 바꾸기",
    "Move": "이동",
    "Copy": "복사",
    "Create folder": "폴더 만들기",
    "Sync": "동기화",
  },
  "ar": {
    "Audit log copied to clipboard as JSON":
        "تم نسخ سجل التدقيق إلى الحافظة بصيغة JSON",
    "Clear Audit Log": "مسح سجل التدقيق",
    "This will permanently delete all audit log entries. Continue?":
        "سيؤدي هذا إلى حذف جميع إدخالات سجل التدقيق نهائيًا. هل تريد المتابعة؟",
    "Cancel": "إلغاء",
    "Clear": "مسح",
    "Audit Log": "سجل التدقيق",
    "Refresh": "تحديث",
    "No audit entries yet": "لا توجد إدخالات تدقيق بعد",
    "Export JSON": "تصدير JSON",
    "Close": "إغلاق",
    "Upload": "رفع",
    "Download": "تنزيل",
    "Delete": "حذف",
    "Rename": "إعادة التسمية",
    "Move": "نقل",
    "Copy": "نسخ",
    "Create folder": "إنشاء مجلد",
    "Sync": "مزامنة",
  },
};
