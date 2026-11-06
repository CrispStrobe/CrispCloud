import 'package:flutter/widgets.dart';

class FileDeleteStrings {
  FileDeleteStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key]!;
  String count(String key, int value) =>
      text(key).replaceAll('{count}', '$value');
  static const _values = <String, Map<String, String>>{
    "en": {
      "permanentTitle": "Delete without restore",
      "trashTitle": "Move to trash",
      "selected": "{count} selected item(s)",
      "permanent": "Delete permanently",
      "skipTrash": "Bypass trash and disable Undo.",
      "permanentHelp": "CrispCloud cannot restore this deletion. The provider may retain its own versions or trash.",
      "trashHelp": "Files go to the system or provider trash. Undo restores them if their original paths remain available.",
      "working": "Working…",
      "deleted": "{count} item(s) moved to trash.",
      "undo": "Undo last",
    },
    "de": {
      "permanentTitle": "Ohne Wiederherstellung löschen",
      "trashTitle": "In den Papierkorb verschieben",
      "selected": "{count} ausgewählte(s) Element(e)",
      "permanent": "Endgültig löschen",
      "skipTrash": "Papierkorb umgehen und Rückgängig deaktivieren.",
      "permanentHelp": "CrispCloud kann diese Löschung nicht rückgängig machen. Der Anbieter behält möglicherweise eigene Versionen oder einen Papierkorb.",
      "trashHelp": "Dateien werden in den Papierkorb des Systems oder Anbieters verschoben. Rückgängig stellt sie wieder her, sofern ihre ursprünglichen Pfade verfügbar sind.",
      "working": "Wird ausgeführt…",
      "deleted": "{count} Element(e) in den Papierkorb verschoben.",
      "undo": "Letzte Aktion rückgängig",
    },
    "fr": {
      "permanentTitle": "Supprimer sans restauration",
      "trashTitle": "Déplacer vers la corbeille",
      "selected": "{count} élément(s) sélectionné(s)",
      "permanent": "Supprimer définitivement",
      "skipTrash": "Ignorer la corbeille et désactiver l’annulation.",
      "permanentHelp": "CrispCloud ne peut pas restaurer cette suppression. Le fournisseur peut conserver ses propres versions ou sa corbeille.",
      "trashHelp": "Les fichiers vont dans la corbeille du système ou du fournisseur. L’annulation les restaure si leurs chemins d’origine restent disponibles.",
      "working": "Traitement…",
      "deleted": "{count} élément(s) déplacé(s) vers la corbeille.",
      "undo": "Annuler la dernière action",
    },
    "es": {
      "permanentTitle": "Eliminar sin restauración",
      "trashTitle": "Mover a la papelera",
      "selected": "{count} elemento(s) seleccionado(s)",
      "permanent": "Eliminar permanentemente",
      "skipTrash": "Omitir la papelera y desactivar Deshacer.",
      "permanentHelp": "CrispCloud no puede restaurar esta eliminación. El proveedor puede conservar sus propias versiones o papelera.",
      "trashHelp": "Los archivos van a la papelera del sistema o del proveedor. Deshacer los restaura si sus rutas originales siguen disponibles.",
      "working": "Procesando…",
      "deleted": "{count} elemento(s) movido(s) a la papelera.",
      "undo": "Deshacer última acción",
    },
    "pt": {
      "permanentTitle": "Eliminar sem restauro",
      "trashTitle": "Mover para o lixo",
      "selected": "{count} item(ns) selecionado(s)",
      "permanent": "Eliminar permanentemente",
      "skipTrash": "Ignorar o lixo e desativar Anular.",
      "permanentHelp": "O CrispCloud não pode restaurar esta eliminação. O fornecedor pode manter as suas próprias versões ou lixo.",
      "trashHelp": "Os ficheiros vão para o lixo do sistema ou do fornecedor. Anular restaura-os se os caminhos originais continuarem disponíveis.",
      "working": "A processar…",
      "deleted": "{count} item(ns) movido(s) para o lixo.",
      "undo": "Anular última ação",
    },
    "zh": {
      "permanentTitle": "删除且无法恢复",
      "trashTitle": "移到回收站",
      "selected": "已选择 {count} 个项目",
      "permanent": "永久删除",
      "skipTrash": "绕过回收站并禁用撤销。",
      "permanentHelp": "CrispCloud 无法恢复此次删除。服务商可能保留自己的版本或回收站。",
      "trashHelp": "文件将移到系统或服务商的回收站。如果原路径仍可用，可以撤销以恢复文件。",
      "working": "正在处理…",
      "deleted": "已将 {count} 个项目移到回收站。",
      "undo": "撤销上一步",
    },
    "ja": {
      "permanentTitle": "復元せずに削除",
      "trashTitle": "ゴミ箱に移動",
      "selected": "{count} 件選択済み",
      "permanent": "完全に削除",
      "skipTrash": "ゴミ箱を使わず、元に戻せなくなります。",
      "permanentHelp":
          "CrispCloud はこの削除を復元できません。プロバイダーが独自の版やゴミ箱を保持している場合があります。",
      "trashHelp": "ファイルはシステムまたはプロバイダーのゴミ箱に移動します。元のパスが利用可能なら、元に戻す操作で復元できます。",
      "working": "処理中…",
      "deleted": "{count} 件をゴミ箱に移動しました。",
      "undo": "直前の操作を元に戻す",
    },
    "ko": {
      "permanentTitle": "복원 없이 삭제",
      "trashTitle": "휴지통으로 이동",
      "selected": "항목 {count}개 선택됨",
      "permanent": "영구 삭제",
      "skipTrash": "휴지통을 건너뛰고 실행 취소를 비활성화합니다.",
      "permanentHelp":
          "CrispCloud는 이 삭제를 복원할 수 없습니다. 제공업체가 자체 버전이나 휴지통을 보관할 수 있습니다.",
      "trashHelp":
          "파일이 시스템 또는 제공업체 휴지통으로 이동합니다. 원래 경로를 사용할 수 있으면 실행 취소로 복원합니다.",
      "working": "처리 중…",
      "deleted": "항목 {count}개를 휴지통으로 이동했습니다.",
      "undo": "마지막 작업 실행 취소",
    },
    "ar": {
      "permanentTitle": "حذف دون استعادة",
      "trashTitle": "نقل إلى سلة المهملات",
      "selected": "تم تحديد {count} عنصرًا",
      "permanent": "حذف نهائي",
      "skipTrash": "تجاوز سلة المهملات وتعطيل التراجع.",
      "permanentHelp": "لا يستطيع CrispCloud استعادة هذا الحذف. قد يحتفظ المزود بإصداراته أو بسلة المهملات الخاصة به.",
      "trashHelp": "تُنقل الملفات إلى سلة مهملات النظام أو المزود. يعيدها التراجع إذا ظلت مساراتها الأصلية متاحة.",
      "working": "جارٍ التنفيذ…",
      "deleted": "تم نقل {count} عنصرًا إلى سلة المهملات.",
      "undo": "التراجع عن الإجراء الأخير",
    },
  };
}
