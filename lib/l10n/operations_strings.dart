import 'package:flutter/widgets.dart';

/// Text for active and completed transfers.
class OperationsStrings {
  OperationsStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  OperationsStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String format(String template, Map<String, Object?> values) =>
      text(template).replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
        final name = match.group(1)!;
        return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
      });
  String eta(double seconds) {
    final s = seconds.round();
    if (s < 60) return format('{seconds}s left', {'seconds': s});
    if (s < 3600) {
      return format('{minutes}m {seconds}s left',
          {'minutes': s ~/ 60, 'seconds': s % 60});
    }
    return format('{hours}h {minutes}m left',
        {'hours': s ~/ 3600, 'minutes': (s % 3600) ~/ 60});
  }

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Cancel all active transfers": "Alle aktiven Übertragungen abbrechen",
    "Clear finished transfers": "Abgeschlossene Übertragungen entfernen",
    "Operations: {count}": "Vorgänge: {count}",
    "Files: {done}/{total}": "Dateien: {done}/{total}",
    "Cancelled": "Abgebrochen",
    "Paused": "Pausiert",
    "Resume": "Fortsetzen",
    "Pause": "Pausieren",
    "Cancel": "Abbrechen",
    "Expand file details": "Dateidetails aufklappen",
    "Collapse file details": "Dateidetails einklappen",
    "Remove transfer": "Übertragung entfernen",
    "Complete": "Abgeschlossen",
    "Error: {error}": "Fehler: {error}",
    "{seconds}s left": "Noch {seconds} Sek.",
    "{minutes}m {seconds}s left": "Noch {minutes} Min. {seconds} Sek.",
    "{hours}h {minutes}m left": "Noch {hours} Std. {minutes} Min.",
  },
  "fr": {
    "Cancel all active transfers": "Annuler tous les transferts actifs",
    "Clear finished transfers": "Effacer les transferts terminés",
    "Operations: {count}": "Opérations : {count}",
    "Files: {done}/{total}": "Fichiers : {done}/{total}",
    "Cancelled": "Annulé",
    "Paused": "En pause",
    "Resume": "Reprendre",
    "Pause": "Mettre en pause",
    "Cancel": "Annuler",
    "Expand file details": "Afficher le détail des fichiers",
    "Collapse file details": "Masquer le détail des fichiers",
    "Remove transfer": "Retirer le transfert",
    "Complete": "Terminé",
    "Error: {error}": "Erreur : {error}",
    "{seconds}s left": "{seconds} s restantes",
    "{minutes}m {seconds}s left": "{minutes} min {seconds} s restantes",
    "{hours}h {minutes}m left": "{hours} h {minutes} min restantes",
  },
  "es": {
    "Cancel all active transfers": "Cancelar todas las transferencias activas",
    "Clear finished transfers": "Borrar transferencias finalizadas",
    "Operations: {count}": "Operaciones: {count}",
    "Files: {done}/{total}": "Archivos: {done}/{total}",
    "Cancelled": "Cancelado",
    "Paused": "En pausa",
    "Resume": "Reanudar",
    "Pause": "Pausar",
    "Cancel": "Cancelar",
    "Expand file details": "Expandir detalles de archivos",
    "Collapse file details": "Contraer detalles de archivos",
    "Remove transfer": "Quitar transferencia",
    "Complete": "Completado",
    "Error: {error}": "Error: {error}",
    "{seconds}s left": "Quedan {seconds} s",
    "{minutes}m {seconds}s left": "Quedan {minutes} min {seconds} s",
    "{hours}h {minutes}m left": "Quedan {hours} h {minutes} min",
  },
  "pt": {
    "Cancel all active transfers": "Cancelar todas as transferências ativas",
    "Clear finished transfers": "Limpar transferências terminadas",
    "Operations: {count}": "Operações: {count}",
    "Files: {done}/{total}": "Ficheiros: {done}/{total}",
    "Cancelled": "Cancelado",
    "Paused": "Em pausa",
    "Resume": "Retomar",
    "Pause": "Pausar",
    "Cancel": "Cancelar",
    "Expand file details": "Expandir detalhes dos ficheiros",
    "Collapse file details": "Recolher detalhes dos ficheiros",
    "Remove transfer": "Remover transferência",
    "Complete": "Concluído",
    "Error: {error}": "Erro: {error}",
    "{seconds}s left": "Restam {seconds} s",
    "{minutes}m {seconds}s left": "Restam {minutes} min {seconds} s",
    "{hours}h {minutes}m left": "Restam {hours} h {minutes} min",
  },
  "zh": {
    "Cancel all active transfers": "取消所有活动传输",
    "Clear finished transfers": "清除已完成的传输",
    "Operations: {count}": "操作数：{count}",
    "Files: {done}/{total}": "文件：{done}/{total}",
    "Cancelled": "已取消",
    "Paused": "已暂停",
    "Resume": "继续",
    "Pause": "暂停",
    "Cancel": "取消",
    "Expand file details": "展开文件详情",
    "Collapse file details": "收起文件详情",
    "Remove transfer": "移除传输",
    "Complete": "已完成",
    "Error: {error}": "错误：{error}",
    "{seconds}s left": "剩余 {seconds} 秒",
    "{minutes}m {seconds}s left": "剩余 {minutes} 分 {seconds} 秒",
    "{hours}h {minutes}m left": "剩余 {hours} 小时 {minutes} 分",
  },
  "ja": {
    "Cancel all active transfers": "実行中の転送をすべてキャンセル",
    "Clear finished transfers": "完了した転送を消去",
    "Operations: {count}": "操作：{count} 件",
    "Files: {done}/{total}": "ファイル：{done}/{total}",
    "Cancelled": "キャンセル済み",
    "Paused": "一時停止中",
    "Resume": "再開",
    "Pause": "一時停止",
    "Cancel": "キャンセル",
    "Expand file details": "ファイルの詳細を展開",
    "Collapse file details": "ファイルの詳細を折りたたむ",
    "Remove transfer": "転送を削除",
    "Complete": "完了",
    "Error: {error}": "エラー：{error}",
    "{seconds}s left": "残り {seconds} 秒",
    "{minutes}m {seconds}s left": "残り {minutes} 分 {seconds} 秒",
    "{hours}h {minutes}m left": "残り {hours} 時間 {minutes} 分",
  },
  "ko": {
    "Cancel all active transfers": "진행 중인 모든 전송 취소",
    "Clear finished transfers": "완료된 전송 지우기",
    "Operations: {count}": "작업: {count}개",
    "Files: {done}/{total}": "파일: {done}/{total}",
    "Cancelled": "취소됨",
    "Paused": "일시 중지됨",
    "Resume": "재개",
    "Pause": "일시 중지",
    "Cancel": "취소",
    "Expand file details": "파일 세부 정보 펼치기",
    "Collapse file details": "파일 세부 정보 접기",
    "Remove transfer": "전송 제거",
    "Complete": "완료",
    "Error: {error}": "오류: {error}",
    "{seconds}s left": "{seconds}초 남음",
    "{minutes}m {seconds}s left": "{minutes}분 {seconds}초 남음",
    "{hours}h {minutes}m left": "{hours}시간 {minutes}분 남음",
  },
  "ar": {
    "Cancel all active transfers": "إلغاء جميع عمليات النقل النشطة",
    "Clear finished transfers": "مسح عمليات النقل المنتهية",
    "Operations: {count}": "العمليات: {count}",
    "Files: {done}/{total}": "الملفات: {done}/{total}",
    "Cancelled": "أُلغيت",
    "Paused": "متوقفة مؤقتًا",
    "Resume": "استئناف",
    "Pause": "إيقاف مؤقت",
    "Cancel": "إلغاء",
    "Expand file details": "توسيع تفاصيل الملفات",
    "Collapse file details": "طي تفاصيل الملفات",
    "Remove transfer": "إزالة عملية النقل",
    "Complete": "اكتملت",
    "Error: {error}": "خطأ: {error}",
    "{seconds}s left": "متبقي {seconds} ث",
    "{minutes}m {seconds}s left": "متبقي {minutes} د {seconds} ث",
    "{hours}h {minutes}m left": "متبقي {hours} س {minutes} د",
  },
};
