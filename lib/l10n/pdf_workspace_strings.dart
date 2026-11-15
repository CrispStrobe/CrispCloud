import 'package:flutter/widgets.dart';

String pdfWorkspaceTr(BuildContext context, String key) =>
    _strings[Localizations.localeOf(context).languageCode]?[key] ?? key;

const _strings = <String, Map<String, String>>{
  'de': {
    'Vertical toolbar': 'Vertikale Werkzeugleiste',
    'Attach note': 'Notiz anhängen',
    'Note': 'Notiz',
    'Snap toolbars': 'Werkzeugleisten einrasten',
    'Reset toolbar positions': 'Positionen zurücksetzen',
    'Move tools': 'Werkzeuge verschieben',
    'Move tool settings': 'Werkzeugeinstellungen verschieben',
    'The PDF changed. Select the text again.':
        'Die PDF wurde geändert. Wählen Sie den Text erneut aus.',
  },
  'fr': {
    'Vertical toolbar': 'Barre verticale',
    'Attach note': 'Joindre une note',
    'Note': 'Note',
    'Snap toolbars': 'Aligner les barres',
    'Reset toolbar positions': 'Réinitialiser les positions',
    'Move tools': 'Déplacer les outils',
    'Move tool settings': 'Déplacer les réglages',
    'The PDF changed. Select the text again.':
        'Le PDF a changé. Sélectionnez à nouveau le texte.',
  },
  'es': {
    'Vertical toolbar': 'Barra vertical',
    'Attach note': 'Adjuntar nota',
    'Note': 'Nota',
    'Snap toolbars': 'Acoplar barras',
    'Reset toolbar positions': 'Restablecer posiciones',
    'Move tools': 'Mover herramientas',
    'Move tool settings': 'Mover ajustes',
    'The PDF changed. Select the text again.':
        'El PDF ha cambiado. Seleccione el texto de nuevo.',
  },
  'pt': {
    'Vertical toolbar': 'Barra vertical',
    'Attach note': 'Anexar nota',
    'Note': 'Nota',
    'Snap toolbars': 'Encaixar barras',
    'Reset toolbar positions': 'Repor posições',
    'Move tools': 'Mover ferramentas',
    'Move tool settings': 'Mover definições',
    'The PDF changed. Select the text again.':
        'O PDF foi alterado. Selecione o texto novamente.',
  },
  'ar': {
    'Vertical toolbar': 'شريط عمودي',
    'Attach note': 'إرفاق ملاحظة',
    'Note': 'ملاحظة',
    'Snap toolbars': 'محاذاة أشرطة الأدوات',
    'Reset toolbar positions': 'إعادة تعيين المواضع',
    'Move tools': 'نقل الأدوات',
    'Move tool settings': 'نقل إعدادات الأدوات',
    'The PDF changed. Select the text again.':
        'تغيّر ملف PDF. حدد النص مرة أخرى.',
  },
  'zh': {
    'Vertical toolbar': '垂直工具栏',
    'Attach note': '附加备注',
    'Note': '备注',
    'Snap toolbars': '吸附工具栏',
    'Reset toolbar positions': '重置工具栏位置',
    'Move tools': '移动工具栏',
    'Move tool settings': '移动工具设置',
    'The PDF changed. Select the text again.': 'PDF 已更改，请重新选择文本。',
  },
  'ja': {
    'Vertical toolbar': '縦のツールバー',
    'Attach note': '注釈を追加',
    'Note': '注釈',
    'Snap toolbars': 'ツールバーを吸着',
    'Reset toolbar positions': '位置をリセット',
    'Move tools': 'ツールを移動',
    'Move tool settings': 'ツール設定を移動',
    'The PDF changed. Select the text again.': 'PDF が変更されました。テキストを選択し直してください。',
  },
  'ko': {
    'Vertical toolbar': '세로 도구 모음',
    'Attach note': '메모 첨부',
    'Note': '메모',
    'Snap toolbars': '도구 모음 맞춤',
    'Reset toolbar positions': '위치 초기화',
    'Move tools': '도구 이동',
    'Move tool settings': '도구 설정 이동',
    'The PDF changed. Select the text again.': 'PDF가 변경되었습니다. 텍스트를 다시 선택하세요.',
  },
};
