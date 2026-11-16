import 'package:flutter/widgets.dart';

extension TmuxControlStrings on BuildContext {
  String tmuxControlTr(String english) {
    final language = Localizations.maybeLocaleOf(this)?.languageCode ?? 'en';
    final index = _languages.indexOf(language);
    return index < 0 ? english : _values[english]?[index] ?? english;
  }
}

const _languages = ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'];
const _values = <String, List<String>>{
  'Native tmux panes': [
    'Native tmux-Bereiche',
    'Volets tmux natifs',
    'Paneles tmux nativos',
    'Painéis tmux nativos',
    '原生 tmux 窗格',
    'ネイティブ tmux ペイン',
    '네이티브 tmux 창',
    'أجزاء tmux الأصلية',
  ],
  'Render tmux windows and panes as native terminals. Requires tmux 3.2 or later.':
      [
        'tmux-Fenster und -Bereiche als native Terminals anzeigen. Erfordert tmux 3.2 oder neuer.',
        'Afficher les fenêtres et volets tmux comme des terminaux natifs. Nécessite tmux 3.2 ou ultérieur.',
        'Muestra las ventanas y paneles de tmux como terminales nativas. Requiere tmux 3.2 o posterior.',
        'Apresenta janelas e painéis tmux como terminais nativos. Requer tmux 3.2 ou posterior.',
        '将 tmux 窗口和窗格显示为原生终端。需要 tmux 3.2 或更高版本。',
        'tmux のウィンドウとペインをネイティブ端末として表示します。tmux 3.2 以降が必要です。',
        'tmux 창과 패널을 네이티브 터미널로 표시합니다. tmux 3.2 이상이 필요합니다.',
        'عرض نوافذ وأجزاء tmux كطرفيات أصلية. يتطلب tmux 3.2 أو أحدث.',
      ],
  'New tmux window': [
    'Neues tmux-Fenster',
    'Nouvelle fenêtre tmux',
    'Nueva ventana tmux',
    'Nova janela tmux',
    '新建 tmux 窗口',
    '新しい tmux ウィンドウ',
    '새 tmux 창',
    'نافذة tmux جديدة',
  ],
  'tmux actions': [
    'tmux-Aktionen',
    'Actions tmux',
    'Acciones de tmux',
    'Ações tmux',
    'tmux 操作',
    'tmux の操作',
    'tmux 작업',
    'إجراءات tmux',
  ],
  'Select tmux pane': [
    'tmux-Bereich auswählen',
    'Sélectionner un volet tmux',
    'Seleccionar panel de tmux',
    'Selecionar painel tmux',
    '选择 tmux 窗格',
    'tmux ペインを選択',
    'tmux 패널 선택',
    'اختيار جزء tmux',
  ],
  'Pane {id}': [
    'Bereich {id}',
    'Volet {id}',
    'Panel {id}',
    'Painel {id}',
    '窗格 {id}',
    'ペイン {id}',
    '패널 {id}',
    'الجزء {id}',
  ],
  'Loading tmux windows…': [
    'tmux-Fenster werden geladen…',
    'Chargement des fenêtres tmux…',
    'Cargando ventanas de tmux…',
    'A carregar janelas tmux…',
    '正在加载 tmux 窗口…',
    'tmux ウィンドウを読み込み中…',
    'tmux 창을 불러오는 중…',
    'جارٍ تحميل نوافذ tmux…',
  ],
  'tmux connection closed': [
    'tmux-Verbindung geschlossen',
    'Connexion tmux fermée',
    'Conexión tmux cerrada',
    'Ligação tmux fechada',
    'tmux 连接已关闭',
    'tmux 接続が終了しました',
    'tmux 연결 닫힘',
    'أُغلق اتصال tmux',
  ],
  'The tmux action could not be completed.': [
    'Die tmux-Aktion konnte nicht abgeschlossen werden.',
    'L’action tmux n’a pas pu être effectuée.',
    'No se pudo completar la acción de tmux.',
    'Não foi possível concluir a ação tmux.',
    '无法完成 tmux 操作。',
    'tmux の操作を完了できませんでした。',
    'tmux 작업을 완료하지 못했습니다.',
    'تعذر إكمال إجراء tmux.',
  ],
};
