import 'package:flutter/widgets.dart';

import '../services/quick_open_service.dart';

class QuickOpenStrings {
  QuickOpenStrings(BuildContext context)
    : _language = Localizations.localeOf(context).languageCode;
  @visibleForTesting
  QuickOpenStrings.forLanguage(this._language);
  final String _language;
  String text(String key) =>
      (_translations[_language] ?? _translations['en']!)[key]!;
  String kind(QuickOpenKind kind) => text(kind.name);
  String reason(QuickOpenUnavailable reason) => text(reason.name);
  String reviewCount(String count) =>
      text('reviewCount').replaceAll('{count}', count);
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  'en': {
    'favorite': 'Favorite',
    'source': 'Connected source',
    'device': 'Device or location',
    'workspace': 'Workspace',
    'renamePreset': 'Rename preset',
    'unboundFavorite':
        'Bind this older favorite to its original source in Workspaces first.',
    'sourceUnavailable':
        'Reconnect the original storage account to open this target.',
    'collectionUnavailable':
        'This saved file list is unavailable. Import or restore it first.',
    'localAccessUnavailable':
        'Open the local folder and grant access before using this target.',
    'noSelection': 'Select files or folders to preview this rename preset.',
    'selectionUnavailable':
        'Refresh the original folder or file list before renaming.',
    'savedItemsUnavailable':
        'Saved items could not be loaded. Reopen Quick Open to retry.',
    'changed': 'The target or view changed while loading. Reopen Quick Open and choose again.',
    'loading': 'Loading saved items…',
    'reviewCount': 'Preview rules for {count} selected items',
    'hint': 'Find a command, favorite, source, workspace or preset…',
  },
  'de': {
    'favorite': 'Favorit',
    'source': 'Verbundene Quelle',
    'device': 'Gerät oder Ort',
    'workspace': 'Arbeitsbereich',
    'renamePreset': 'Umbenennungsvorlage',
    'unboundFavorite': 'Ordnen Sie diesen älteren Favoriten zuerst unter Arbeitsbereiche seiner ursprünglichen Quelle zu.',
    'sourceUnavailable': 'Verbinden Sie das ursprüngliche Speicherkonto erneut, um dieses Ziel zu öffnen.',
    'collectionUnavailable': 'Diese gespeicherte Dateiliste ist nicht verfügbar. Importieren Sie sie oder stellen Sie sie wieder her.',
    'localAccessUnavailable': 'Öffnen Sie den lokalen Ordner und gewähren Sie Zugriff, bevor Sie dieses Ziel verwenden.',
    'noSelection': 'Wählen Sie Dateien oder Ordner für die Vorschau dieser Umbenennungsvorlage aus.',
    'selectionUnavailable': 'Aktualisieren Sie den ursprünglichen Ordner oder die Dateiliste vor dem Umbenennen.',
    'savedItemsUnavailable': 'Gespeicherte Einträge konnten nicht geladen werden. Öffnen Sie die Schnellauswahl erneut.',
    'changed': 'Das Ziel oder die Ansicht wurde beim Laden geändert. Öffnen Sie die Schnellauswahl und wählen Sie erneut.',
    'loading': 'Gespeicherte Einträge werden geladen…',
    'reviewCount': 'Regelvorschau für {count} ausgewählte Einträge',
    'hint': 'Befehl, Favorit, Quelle, Arbeitsbereich oder Vorlage suchen…',
  },
  'fr': {
    'favorite': 'Favori',
    'source': 'Source connectée',
    'device': 'Appareil ou emplacement',
    'workspace': 'Espace de travail',
    'renamePreset': 'Préréglage de renommage',
    'unboundFavorite': 'Associez d’abord cet ancien favori à sa source d’origine dans Espaces de travail.',
    'sourceUnavailable': 'Reconnectez le compte de stockage d’origine pour ouvrir cette destination.',
    'collectionUnavailable': 'Cette liste de fichiers est indisponible. Importez-la ou restaurez-la d’abord.',
    'localAccessUnavailable': 'Ouvrez le dossier local et autorisez son accès avant de choisir cette destination.',
    'noSelection': 'Sélectionnez des fichiers ou dossiers pour prévisualiser ce préréglage.',
    'selectionUnavailable':
        'Actualisez le dossier ou la liste d’origine avant de renommer.',
    'savedItemsUnavailable': 'Impossible de charger les éléments enregistrés. Rouvrez l’ouverture rapide pour réessayer.',
    'changed': 'La destination ou la vue a changé pendant le chargement. Rouvrez l’ouverture rapide et choisissez à nouveau.',
    'loading': 'Chargement des éléments enregistrés…',
    'reviewCount':
        'Prévisualiser les règles pour {count} éléments sélectionnés',
    'hint': 'Rechercher une commande, un favori, une source, un espace ou un préréglage…',
  },
  'es': {
    'favorite': 'Favorito',
    'source': 'Origen conectado',
    'device': 'Dispositivo o ubicación',
    'workspace': 'Espacio de trabajo',
    'renamePreset': 'Preajuste de renombrado',
    'unboundFavorite': 'Vincule primero este favorito antiguo a su origen en Espacios de trabajo.',
    'sourceUnavailable': 'Vuelva a conectar la cuenta de almacenamiento original para abrir este destino.',
    'collectionUnavailable': 'Esta lista guardada no está disponible. Impórtela o restáurela primero.',
    'localAccessUnavailable':
        'Abra la carpeta local y conceda acceso antes de usar este destino.',
    'noSelection':
        'Seleccione archivos o carpetas para previsualizar este preajuste.',
    'selectionUnavailable':
        'Actualice la carpeta o lista original antes de renombrar.',
    'savedItemsUnavailable': 'No se pudieron cargar los elementos guardados. Vuelva a abrir Apertura rápida.',
    'changed': 'El destino o la vista cambió durante la carga. Vuelva a abrir Apertura rápida y elija de nuevo.',
    'loading': 'Cargando elementos guardados…',
    'reviewCount': 'Previsualizar reglas para {count} elementos seleccionados',
    'hint': 'Buscar un comando, favorito, origen, espacio o preajuste…',
  },
  'pt': {
    'favorite': 'Favorito',
    'source': 'Origem ligada',
    'device': 'Dispositivo ou localização',
    'workspace': 'Área de trabalho',
    'renamePreset': 'Predefinição de renomeação',
    'unboundFavorite': 'Associe primeiro este favorito antigo à origem original em Áreas de trabalho.',
    'sourceUnavailable': 'Volte a ligar a conta de armazenamento original para abrir este destino.',
    'collectionUnavailable': 'Esta lista guardada não está disponível. Importe-a ou restaure-a primeiro.',
    'localAccessUnavailable':
        'Abra a pasta local e conceda acesso antes de utilizar este destino.',
    'noSelection':
        'Selecione ficheiros ou pastas para pré-visualizar esta predefinição.',
    'selectionUnavailable':
        'Atualize a pasta ou lista original antes de renomear.',
    'savedItemsUnavailable': 'Não foi possível carregar os itens guardados. Volte a abrir Abertura rápida.',
    'changed': 'O destino ou a vista mudou durante o carregamento. Volte a abrir Abertura rápida e escolha novamente.',
    'loading': 'A carregar itens guardados…',
    'reviewCount': 'Pré-visualizar regras para {count} itens selecionados',
    'hint':
        'Procurar comando, favorito, origem, área de trabalho ou predefinição…',
  },
  'zh': {
    'favorite': '收藏位置',
    'source': '已连接来源',
    'device': '设备或位置',
    'workspace': '工作区',
    'renamePreset': '重命名预设',
    'unboundFavorite': '请先在“工作区”中将此旧收藏位置绑定到原始来源。',
    'sourceUnavailable': '请重新连接原始存储账户后打开此目标。',
    'collectionUnavailable': '此已保存的文件列表不可用。请先导入或恢复。',
    'localAccessUnavailable': '使用此目标前，请打开本地文件夹并授予访问权限。',
    'noSelection': '请选择文件或文件夹以预览此重命名预设。',
    'selectionUnavailable': '重命名前，请刷新原始文件夹或文件列表。',
    'savedItemsUnavailable': '无法加载已保存的项目。请重新打开“快速打开”重试。',
    'changed': '加载期间目标或视图已更改。请重新打开“快速打开”并再次选择。',
    'loading': '正在加载已保存的项目…',
    'reviewCount': '预览 {count} 个选定项目的规则',
    'hint': '查找命令、收藏位置、来源、工作区或预设…',
  },
  'ja': {
    'favorite': 'お気に入り',
    'source': '接続済みの場所',
    'device': 'デバイスまたは場所',
    'workspace': 'ワークスペース',
    'renamePreset': '名前変更プリセット',
    'unboundFavorite': 'ワークスペースで、この古いお気に入りを元の保存先に関連付けてください。',
    'sourceUnavailable': 'この場所を開くには、元のストレージアカウントに再接続してください。',
    'collectionUnavailable': '保存されたファイル一覧は利用できません。先にインポートまたは復元してください。',
    'localAccessUnavailable': 'この場所を使用する前に、ローカルフォルダーを開いてアクセスを許可してください。',
    'noSelection': 'プリセットをプレビューするには、ファイルまたはフォルダーを選択してください。',
    'selectionUnavailable': '名前を変更する前に、元のフォルダーまたは一覧を更新してください。',
    'savedItemsUnavailable': '保存された項目を読み込めませんでした。クイックオープンを開き直してください。',
    'changed': '読み込み中に場所または表示が変わりました。クイックオープンを開き直して再度選択してください。',
    'loading': '保存された項目を読み込み中…',
    'reviewCount': '選択した {count} 項目のルールをプレビュー',
    'hint': 'コマンド、お気に入り、場所、ワークスペース、プリセットを検索…',
  },
  'ko': {
    'favorite': '즐겨찾기',
    'source': '연결된 소스',
    'device': '장치 또는 위치',
    'workspace': '작업 공간',
    'renamePreset': '이름 변경 사전 설정',
    'unboundFavorite': '작업 공간에서 이 이전 즐겨찾기를 원래 소스에 먼저 연결하세요.',
    'sourceUnavailable': '이 대상을 열려면 원래 저장소 계정에 다시 연결하세요.',
    'collectionUnavailable': '저장된 파일 목록을 사용할 수 없습니다. 먼저 가져오거나 복원하세요.',
    'localAccessUnavailable': '이 대상을 사용하기 전에 로컬 폴더를 열고 접근을 허용하세요.',
    'noSelection': '사전 설정을 미리 보려면 파일이나 폴더를 선택하세요.',
    'selectionUnavailable': '이름을 변경하기 전에 원래 폴더나 파일 목록을 새로 고치세요.',
    'savedItemsUnavailable': '저장된 항목을 불러올 수 없습니다. 빠른 열기를 다시 열어 시도하세요.',
    'changed': '불러오는 동안 대상이나 보기가 변경되었습니다. 빠른 열기를 다시 열고 선택하세요.',
    'loading': '저장된 항목을 불러오는 중…',
    'reviewCount': '선택한 {count}개 항목의 규칙 미리 보기',
    'hint': '명령, 즐겨찾기, 소스, 작업 공간 또는 사전 설정 찾기…',
  },
  'ar': {
    'favorite': 'مفضلة',
    'source': 'مصدر متصل',
    'device': 'جهاز أو موقع',
    'workspace': 'مساحة عمل',
    'renamePreset': 'إعداد مسبق لإعادة التسمية',
    'unboundFavorite':
        'اربط هذه المفضلة القديمة بمصدرها الأصلي في مساحات العمل أولًا.',
    'sourceUnavailable': 'أعد توصيل حساب التخزين الأصلي لفتح هذا الهدف.',
    'collectionUnavailable':
        'قائمة الملفات المحفوظة غير متاحة. استوردها أو استعدها أولًا.',
    'localAccessUnavailable':
        'افتح المجلد المحلي وامنح الوصول قبل استخدام هذا الهدف.',
    'noSelection': 'حدد ملفات أو مجلدات لمعاينة إعداد إعادة التسمية.',
    'selectionUnavailable':
        'حدّث المجلد أو قائمة الملفات الأصلية قبل إعادة التسمية.',
    'savedItemsUnavailable':
        'تعذر تحميل العناصر المحفوظة. أعد فتح الفتح السريع للمحاولة مجددًا.',
    'changed':
        'تغير الهدف أو العرض أثناء التحميل. أعد فتح الفتح السريع واختر مجددًا.',
    'loading': 'جارٍ تحميل العناصر المحفوظة…',
    'reviewCount': 'معاينة القواعد لعدد {count} من العناصر المحددة',
    'hint': 'ابحث عن أمر أو مفضلة أو مصدر أو مساحة عمل أو إعداد مسبق…',
  },
};
