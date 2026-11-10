import 'package:flutter/widgets.dart';

class NavigationStrings {
  NavigationStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;

  String text(String key) =>
      (_messages[language] ?? _messages['en']!)[key] ??
      _messages['en']![key] ??
      key;

  String failure(Object error) =>
      text('failed').replaceAll('{error}', '$error');

  static const _messages = {
    'en': {
      "folders": "Folders",
      "loadingFolders": "Loading folders…",
      "treeUnavailable": "Open an available folder to browse its tree.",
      "retryFolder": "Could not load folders. Retry",
      "expandFolder": "Expand folder",
      "collapseFolder": "Collapse folder",
      'history': 'Location history',
      'reopen': 'Reopen closed tab',
      'unavailable': 'Reconnect the original storage for this location.',
      'older': 'This older location does not identify its storage. Open it from its original source.',
      'failed': 'Could not open the saved location: {error}',
    },
    'de': {
      "folders": "Ordner",
      "loadingFolders": "Ordner werden geladen…",
      "treeUnavailable": "Öffnen Sie einen verfügbaren Ordner, um seinen Verzeichnisbaum zu sehen.",
      "retryFolder": "Ordner konnten nicht geladen werden. Erneut versuchen",
      "expandFolder": "Ordner aufklappen",
      "collapseFolder": "Ordner zuklappen",
      'history': 'Ortsverlauf',
      'reopen': 'Geschlossenen Tab wieder öffnen',
      'unavailable':
          'Verbinden Sie den ursprünglichen Speicher für diesen Ort erneut.',
      'older': 'Dieser ältere Ort enthält keine Speicherzuordnung. Öffnen Sie ihn über seine ursprüngliche Quelle.',
      'failed': 'Der gespeicherte Ort konnte nicht geöffnet werden: {error}',
    },
    'fr': {
      "folders": "Dossiers",
      "loadingFolders": "Chargement des dossiers…",
      "treeUnavailable":
          "Ouvrez un dossier disponible pour parcourir son arborescence.",
      "retryFolder": "Chargement impossible. Réessayer",
      "expandFolder": "Développer le dossier",
      "collapseFolder": "Réduire le dossier",
      'history': 'Historique des emplacements',
      'reopen': 'Rouvrir l’onglet fermé',
      'unavailable': 'Reconnectez le stockage d’origine de cet emplacement.',
      'older': 'Cet ancien emplacement n’identifie pas son stockage. Ouvrez-le depuis sa source d’origine.',
      'failed': 'Impossible d’ouvrir l’emplacement enregistré : {error}',
    },
    'es': {
      "folders": "Carpetas",
      "loadingFolders": "Cargando carpetas…",
      "treeUnavailable": "Abre una carpeta disponible para explorar su árbol.",
      "retryFolder": "No se pudieron cargar las carpetas. Reintentar",
      "expandFolder": "Expandir carpeta",
      "collapseFolder": "Contraer carpeta",
      'history': 'Historial de ubicaciones',
      'reopen': 'Reabrir pestaña cerrada',
      'unavailable':
          'Vuelve a conectar el almacenamiento original de esta ubicación.',
      'older': 'Esta ubicación antigua no identifica su almacenamiento. Ábrela desde su origen.',
      'failed': 'No se pudo abrir la ubicación guardada: {error}',
    },
    'pt': {
      "folders": "Pastas",
      "loadingFolders": "A carregar pastas…",
      "treeUnavailable": "Abra uma pasta disponível para explorar a árvore.",
      "retryFolder": "Não foi possível carregar pastas. Tentar novamente",
      "expandFolder": "Expandir pasta",
      "collapseFolder": "Recolher pasta",
      'history': 'Histórico de locais',
      'reopen': 'Reabrir separador fechado',
      'unavailable': 'Ligue novamente o armazenamento original deste local.',
      'older': 'Este local antigo não identifica o armazenamento. Abra-o a partir da origem.',
      'failed': 'Não foi possível abrir o local guardado: {error}',
    },
    'zh': {
      "folders": "文件夹",
      "loadingFolders": "正在加载文件夹…",
      "treeUnavailable": "打开可用的文件夹以浏览其目录树。",
      "retryFolder": "无法加载文件夹。重试",
      "expandFolder": "展开文件夹",
      "collapseFolder": "折叠文件夹",
      'history': '位置历史记录',
      'reopen': '重新打开已关闭的标签页',
      'unavailable': '请重新连接此位置的原始存储。',
      'older': '此旧位置未标明其存储。请从原始来源打开。',
      'failed': '无法打开已保存的位置：{error}',
    },
    'ja': {
      "folders": "フォルダー",
      "loadingFolders": "フォルダーを読み込み中…",
      "treeUnavailable": "利用可能なフォルダーを開いてツリーを参照してください。",
      "retryFolder": "読み込めませんでした。再試行",
      "expandFolder": "フォルダーを展開",
      "collapseFolder": "フォルダーを折りたたむ",
      'history': '場所の履歴',
      'reopen': '閉じたタブを開き直す',
      'unavailable': 'この場所の元のストレージに再接続してください。',
      'older': 'この古い場所にはストレージ情報がありません。元のソースから開いてください。',
      'failed': '保存した場所を開けませんでした: {error}',
    },
    'ko': {
      "folders": "폴더",
      "loadingFolders": "폴더 불러오는 중…",
      "treeUnavailable": "사용 가능한 폴더를 열어 트리를 탐색하세요.",
      "retryFolder": "폴더를 불러올 수 없습니다. 다시 시도",
      "expandFolder": "폴더 펼치기",
      "collapseFolder": "폴더 접기",
      'history': '위치 기록',
      'reopen': '닫은 탭 다시 열기',
      'unavailable': '이 위치의 원래 저장소를 다시 연결하세요.',
      'older': '이 이전 위치에는 저장소 정보가 없습니다. 원래 소스에서 여세요.',
      'failed': '저장된 위치를 열 수 없습니다: {error}',
    },
    'ar': {
      "folders": "المجلدات",
      "loadingFolders": "جارٍ تحميل المجلدات…",
      "treeUnavailable": "افتح مجلدًا متاحًا لاستعراض شجرته.",
      "retryFolder": "تعذر تحميل المجلدات. إعادة المحاولة",
      "expandFolder": "توسيع المجلد",
      "collapseFolder": "طي المجلد",
      'history': 'سجل المواقع',
      'reopen': 'إعادة فتح علامة التبويب المغلقة',
      'unavailable': 'أعد توصيل وحدة التخزين الأصلية لهذا الموقع.',
      'older': 'هذا الموقع القديم لا يحدد وحدة التخزين الخاصة به. افتحه من مصدره الأصلي.',
      'failed': 'تعذر فتح الموقع المحفوظ: {error}',
    },
  };
}
