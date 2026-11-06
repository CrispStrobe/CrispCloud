import 'package:flutter/widgets.dart';

/// Text used for file version history.
class VersionHistoryStrings {
  VersionHistoryStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  VersionHistoryStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String format(String template, Map<String, Object?> values) {
    return text(template).replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
      final name = match.group(1)!;
      return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
    });
  }

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Version History — {name}": "Versionsverlauf — {name}",
    "No version history available": "Kein Versionsverlauf verfügbar",
    "Restore Version?": "Version wiederherstellen?",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "Die aktuelle Datei wird durch die Version vom {date} ersetzt. Die aktuelle Version bleibt im Versionsverlauf erhalten.",
    "Cancel": "Abbrechen",
    "Restore": "Wiederherstellen",
    "unknown date": "unbekanntes Datum",
    "Restored {name} to version from {date}":
        "{name} auf die Version vom {date} zurückgesetzt",
    "Restore failed: {error}": "Wiederherstellung fehlgeschlagen: {error}",
    "Failed to download revision: {status}":
        "Revision konnte nicht heruntergeladen werden: {status}",
    "Failed to upload restored content: {status}":
        "Wiederhergestellter Inhalt konnte nicht hochgeladen werden: {status}",
    "{provider} restore failed: {status} {details}":
        "Wiederherstellung bei {provider} fehlgeschlagen: {status} {details}",
    "Not authenticated": "Nicht angemeldet",
    "{provider} does not support version history":
        "{provider} unterstützt keinen Versionsverlauf",
    "Unknown": "Unbekannt",
    "Failed to download version": "Version konnte nicht heruntergeladen werden",
    "Version {id}": "Version {id}",
    "Version: {version}": "Version: {version}",
    "Current": "Aktuell",
    "Diff": "Vergleichen",
    "Diff failed: {error}": "Vergleich fehlgeschlagen: {error}",
    "Restoring...": "Wiederherstellung läuft...",
    "Close": "Schließen",
  },
  "fr": {
    "Version History — {name}": "Historique des versions — {name}",
    "No version history available": "Aucun historique des versions disponible",
    "Restore Version?": "Restaurer la version ?",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "Le fichier actuel sera remplacé par la version du {date}. La version actuelle sera conservée dans l’historique.",
    "Cancel": "Annuler",
    "Restore": "Restaurer",
    "unknown date": "date inconnue",
    "Restored {name} to version from {date}":
        "{name} restauré à la version du {date}",
    "Restore failed: {error}": "Échec de la restauration : {error}",
    "Failed to download revision: {status}":
        "Impossible de télécharger la révision : {status}",
    "Failed to upload restored content: {status}":
        "Impossible d’envoyer le contenu restauré : {status}",
    "{provider} restore failed: {status} {details}":
        "Échec de la restauration {provider} : {status} {details}",
    "Not authenticated": "Non authentifié",
    "{provider} does not support version history":
        "{provider} ne prend pas en charge l’historique des versions",
    "Unknown": "Inconnu",
    "Failed to download version": "Impossible de télécharger la version",
    "Version {id}": "Version {id}",
    "Version: {version}": "Version : {version}",
    "Current": "Actuelle",
    "Diff": "Comparer",
    "Diff failed: {error}": "Échec de la comparaison : {error}",
    "Restoring...": "Restauration...",
    "Close": "Fermer",
  },
  "es": {
    "Version History — {name}": "Historial de versiones — {name}",
    "No version history available": "No hay historial de versiones disponible",
    "Restore Version?": "¿Restaurar versión?",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "El archivo actual se reemplazará por la versión del {date}. La versión actual se conservará en el historial.",
    "Cancel": "Cancelar",
    "Restore": "Restaurar",
    "unknown date": "fecha desconocida",
    "Restored {name} to version from {date}":
        "{name} restaurado a la versión del {date}",
    "Restore failed: {error}": "Error al restaurar: {error}",
    "Failed to download revision: {status}":
        "No se pudo descargar la revisión: {status}",
    "Failed to upload restored content: {status}":
        "No se pudo subir el contenido restaurado: {status}",
    "{provider} restore failed: {status} {details}":
        "Error de restauración de {provider}: {status} {details}",
    "Not authenticated": "No autenticado",
    "{provider} does not support version history":
        "{provider} no admite historial de versiones",
    "Unknown": "Desconocido",
    "Failed to download version": "No se pudo descargar la versión",
    "Version {id}": "Versión {id}",
    "Version: {version}": "Versión: {version}",
    "Current": "Actual",
    "Diff": "Comparar",
    "Diff failed: {error}": "Error al comparar: {error}",
    "Restoring...": "Restaurando...",
    "Close": "Cerrar",
  },
  "pt": {
    "Version History — {name}": "Histórico de versões — {name}",
    "No version history available": "Não há histórico de versões disponível",
    "Restore Version?": "Restaurar versão?",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "O ficheiro atual será substituído pela versão de {date}. A versão atual será mantida no histórico.",
    "Cancel": "Cancelar",
    "Restore": "Restaurar",
    "unknown date": "data desconhecida",
    "Restored {name} to version from {date}":
        "{name} restaurado para a versão de {date}",
    "Restore failed: {error}": "Falha ao restaurar: {error}",
    "Failed to download revision: {status}":
        "Não foi possível transferir a revisão: {status}",
    "Failed to upload restored content: {status}":
        "Não foi possível enviar o conteúdo restaurado: {status}",
    "{provider} restore failed: {status} {details}":
        "Falha na reposição de {provider}: {status} {details}",
    "Not authenticated": "Não autenticado",
    "{provider} does not support version history":
        "{provider} não suporta histórico de versões",
    "Unknown": "Desconhecido",
    "Failed to download version": "Não foi possível transferir a versão",
    "Version {id}": "Versão {id}",
    "Version: {version}": "Versão: {version}",
    "Current": "Atual",
    "Diff": "Comparar",
    "Diff failed: {error}": "Falha na comparação: {error}",
    "Restoring...": "A restaurar...",
    "Close": "Fechar",
  },
  "zh": {
    "Version History — {name}": "版本历史 — {name}",
    "No version history available": "没有可用的版本历史",
    "Restore Version?": "恢复版本？",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "当前文件将替换为 {date} 的版本。当前版本将保留在版本历史中。",
    "Cancel": "取消",
    "Restore": "恢复",
    "unknown date": "未知日期",
    "Restored {name} to version from {date}": "已将 {name} 恢复为 {date} 的版本",
    "Restore failed: {error}": "恢复失败：{error}",
    "Failed to download revision: {status}": "无法下载修订版本：{status}",
    "Failed to upload restored content: {status}": "无法上传恢复的内容：{status}",
    "{provider} restore failed: {status} {details}":
        "{provider} 恢复失败：{status} {details}",
    "Not authenticated": "未登录",
    "{provider} does not support version history": "{provider} 不支持版本历史",
    "Unknown": "未知",
    "Failed to download version": "无法下载版本",
    "Version {id}": "版本 {id}",
    "Version: {version}": "版本：{version}",
    "Current": "当前",
    "Diff": "比较",
    "Diff failed: {error}": "比较失败：{error}",
    "Restoring...": "正在恢复...",
    "Close": "关闭",
  },
  "ja": {
    "Version History — {name}": "バージョン履歴 — {name}",
    "No version history available": "バージョン履歴はありません",
    "Restore Version?": "バージョンを復元しますか？",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "現在のファイルを {date} のバージョンで置き換えます。現在のバージョンは履歴に保持されます。",
    "Cancel": "キャンセル",
    "Restore": "復元",
    "unknown date": "不明な日付",
    "Restored {name} to version from {date}": "{name} を {date} のバージョンに復元しました",
    "Restore failed: {error}": "復元に失敗しました：{error}",
    "Failed to download revision: {status}": "リビジョンをダウンロードできませんでした：{status}",
    "Failed to upload restored content: {status}":
        "復元した内容をアップロードできませんでした：{status}",
    "{provider} restore failed: {status} {details}":
        "{provider} の復元に失敗しました：{status} {details}",
    "Not authenticated": "認証されていません",
    "{provider} does not support version history":
        "{provider} はバージョン履歴に対応していません",
    "Unknown": "不明",
    "Failed to download version": "バージョンをダウンロードできませんでした",
    "Version {id}": "バージョン {id}",
    "Version: {version}": "バージョン：{version}",
    "Current": "現在",
    "Diff": "比較",
    "Diff failed: {error}": "比較に失敗しました：{error}",
    "Restoring...": "復元中...",
    "Close": "閉じる",
  },
  "ko": {
    "Version History — {name}": "버전 기록 — {name}",
    "No version history available": "사용 가능한 버전 기록이 없습니다",
    "Restore Version?": "버전을 복원하시겠습니까?",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "현재 파일이 {date}의 버전으로 대체됩니다. 현재 버전은 버전 기록에 보존됩니다.",
    "Cancel": "취소",
    "Restore": "복원",
    "unknown date": "알 수 없는 날짜",
    "Restored {name} to version from {date}": "{name}을(를) {date}의 버전으로 복원했습니다",
    "Restore failed: {error}": "복원 실패: {error}",
    "Failed to download revision: {status}": "리비전을 다운로드하지 못했습니다: {status}",
    "Failed to upload restored content: {status}":
        "복원된 콘텐츠를 업로드하지 못했습니다: {status}",
    "{provider} restore failed: {status} {details}":
        "{provider} 복원 실패: {status} {details}",
    "Not authenticated": "인증되지 않음",
    "{provider} does not support version history":
        "{provider}은(는) 버전 기록을 지원하지 않습니다",
    "Unknown": "알 수 없음",
    "Failed to download version": "버전을 다운로드하지 못했습니다",
    "Version {id}": "버전 {id}",
    "Version: {version}": "버전: {version}",
    "Current": "현재",
    "Diff": "비교",
    "Diff failed: {error}": "비교 실패: {error}",
    "Restoring...": "복원 중...",
    "Close": "닫기",
  },
  "ar": {
    "Version History — {name}": "سجل الإصدارات — {name}",
    "No version history available": "لا يوجد سجل إصدارات متاح",
    "Restore Version?": "استعادة الإصدار؟",
    "This will replace the current file with the version from {date}. The current version will be preserved in the version history.":
        "سيُستبدل الملف الحالي بإصدار {date}. سيُحفظ الإصدار الحالي في سجل الإصدارات.",
    "Cancel": "إلغاء",
    "Restore": "استعادة",
    "unknown date": "تاريخ غير معروف",
    "Restored {name} to version from {date}":
        "تمت استعادة {name} إلى إصدار {date}",
    "Restore failed: {error}": "فشلت الاستعادة: {error}",
    "Failed to download revision: {status}": "تعذّر تنزيل المراجعة: {status}",
    "Failed to upload restored content: {status}":
        "تعذّر رفع المحتوى المستعاد: {status}",
    "{provider} restore failed: {status} {details}":
        "فشلت استعادة {provider}: {status} {details}",
    "Not authenticated": "لم تتم المصادقة",
    "{provider} does not support version history":
        "لا يدعم {provider} سجل الإصدارات",
    "Unknown": "غير معروف",
    "Failed to download version": "تعذّر تنزيل الإصدار",
    "Version {id}": "الإصدار {id}",
    "Version: {version}": "الإصدار: {version}",
    "Current": "الحالي",
    "Diff": "مقارنة",
    "Diff failed: {error}": "فشلت المقارنة: {error}",
    "Restoring...": "جارٍ الاستعادة...",
    "Close": "إغلاق",
  },
};
