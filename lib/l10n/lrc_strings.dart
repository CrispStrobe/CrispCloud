import 'package:flutter/widgets.dart';

class LrcStrings {
  LrcStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

  final String language;

  String text(String key) =>
      (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;

  String timedLines(int count) =>
      text('timedLines').replaceAll('{count}', '$count');
  String offset(int ms) =>
      text('offset').replaceAll('{ms}', '${ms > 0 ? '+' : ''}$ms');

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'lyrics': 'Lyrics',
      'timeline': 'Timeline',
      'source': 'Source',
      'timedLines': 'Timed lines: {count}',
      'offset': 'Timing offset: {ms} ms',
      'noTimedLines': 'No valid line timestamps were found. The text is shown in source order.',
      'empty': 'This lyrics file is empty.',
      'untimed': 'Untimed',
      'wordTiming': 'Word timing',
      'shortened': 'This line is shortened for preview. Open Source for the complete text.',
      'limit': 'This lyrics file exceeds the preview limit. Open Source to view the complete text.',
      'sourceChanged': 'The file changed while reading. Reload it to preview the current lyrics.',
      'readFailed': 'The lyrics could not be read completely. Try reloading the file or opening Source.',
    },
    'de': {
      'lyrics': 'Liedtext',
      'timeline': 'Zeitfolge',
      'source': 'Quelltext',
      'timedLines': 'Zeilen mit Zeitmarken: {count}',
      'offset': 'Zeitversatz: {ms} ms',
      'noTimedLines': 'Keine gültigen Zeilenzeitmarken gefunden. Der Text wird in der ursprünglichen Reihenfolge angezeigt.',
      'empty': 'Diese Liedtextdatei ist leer.',
      'untimed': 'Ohne Zeitmarke',
      'wordTiming': 'Wortzeitmarken',
      'shortened': 'Diese Zeile ist für die Vorschau gekürzt. Der vollständige Text ist im Quelltext verfügbar.',
      'limit': 'Diese Liedtextdatei überschreitet das Vorschaulimit. Öffnen Sie den Quelltext für den vollständigen Text.',
      'sourceChanged': 'Die Datei wurde beim Lesen geändert. Laden Sie sie neu, um den aktuellen Liedtext anzuzeigen.',
      'readFailed': 'Der Liedtext konnte nicht vollständig gelesen werden. Laden Sie die Datei neu oder öffnen Sie den Quelltext.',
    },
    'fr': {
      'lyrics': 'Paroles',
      'timeline': 'Chronologie',
      'source': 'Source',
      'timedLines': 'Lignes horodatées : {count}',
      'offset': 'Décalage temporel : {ms} ms',
      'noTimedLines': 'Aucun horodatage de ligne valide. Le texte suit l’ordre du fichier source.',
      'empty': 'Ce fichier de paroles est vide.',
      'untimed': 'Sans horodatage',
      'wordTiming': 'Horodatage des mots',
      'shortened': 'Cette ligne est raccourcie pour l’aperçu. Ouvrez la source pour le texte complet.',
      'limit': 'Ce fichier de paroles dépasse la limite d’aperçu. Ouvrez la source pour le texte complet.',
      'sourceChanged': 'Le fichier a changé pendant la lecture. Rechargez-le pour afficher les paroles actuelles.',
      'readFailed': 'Les paroles n’ont pas pu être lues entièrement. Rechargez le fichier ou ouvrez la source.',
    },
    'es': {
      'lyrics': 'Letra',
      'timeline': 'Cronología',
      'source': 'Fuente',
      'timedLines': 'Líneas con tiempo: {count}',
      'offset': 'Desfase temporal: {ms} ms',
      'noTimedLines': 'No se encontraron marcas de tiempo válidas. El texto sigue el orden original.',
      'empty': 'Este archivo de letra está vacío.',
      'untimed': 'Sin tiempo',
      'wordTiming': 'Tiempo por palabra',
      'shortened': 'Esta línea se acortó para la vista previa. Abre la fuente para ver el texto completo.',
      'limit': 'Este archivo de letra supera el límite de vista previa. Abre la fuente para ver el texto completo.',
      'sourceChanged': 'El archivo cambió durante la lectura. Recárgalo para ver la letra actual.',
      'readFailed':
          'No se pudo leer toda la letra. Recarga el archivo o abre la fuente.',
    },
    'pt': {
      'lyrics': 'Letra',
      'timeline': 'Cronologia',
      'source': 'Fonte',
      'timedLines': 'Linhas com tempo: {count}',
      'offset': 'Desvio temporal: {ms} ms',
      'noTimedLines': 'Não foram encontradas marcas de tempo válidas. O texto segue a ordem original.',
      'empty': 'Este ficheiro de letra está vazio.',
      'untimed': 'Sem tempo',
      'wordTiming': 'Tempo por palavra',
      'shortened': 'Esta linha foi abreviada para a pré-visualização. Abra a fonte para ver o texto completo.',
      'limit': 'Este ficheiro de letra excede o limite de pré-visualização. Abra a fonte para ver o texto completo.',
      'sourceChanged': 'O ficheiro mudou durante a leitura. Recarregue-o para ver a letra atual.',
      'readFailed': 'Não foi possível ler toda a letra. Recarregue o ficheiro ou abra a fonte.',
    },
    'zh': {
      'lyrics': '歌词',
      'timeline': '时间顺序',
      'source': '源文本',
      'timedLines': '带时间戳的行数：{count}',
      'offset': '时间偏移：{ms} 毫秒',
      'noTimedLines': '未找到有效的行时间戳。文本按源文件顺序显示。',
      'empty': '此歌词文件为空。',
      'untimed': '无时间戳',
      'wordTiming': '逐词时间戳',
      'shortened': '此行在预览中已缩短。打开源文本可查看完整内容。',
      'limit': '此歌词文件超出预览限制。打开源文本可查看完整内容。',
      'sourceChanged': '读取时文件发生了变化。请重新加载以预览当前歌词。',
      'readFailed': '无法完整读取歌词。请重新加载文件或打开源文本。',
    },
    'ja': {
      'lyrics': '歌詞',
      'timeline': '時刻順',
      'source': 'ソース',
      'timedLines': '時刻付きの行数：{count}',
      'offset': '時刻の補正：{ms} ミリ秒',
      'noTimedLines': '有効な行の時刻が見つかりません。元の順序でテキストを表示します。',
      'empty': 'この歌詞ファイルは空です。',
      'untimed': '時刻なし',
      'wordTiming': '単語の時刻',
      'shortened': 'プレビューではこの行を短縮しています。全文はソースを開いて確認してください。',
      'limit': 'この歌詞ファイルはプレビューの制限を超えています。全文はソースを開いて確認してください。',
      'sourceChanged': '読み込み中にファイルが変更されました。再読み込みして現在の歌詞を表示してください。',
      'readFailed': '歌詞を最後まで読み込めませんでした。再読み込みするかソースを開いてください。',
    },
    'ko': {
      'lyrics': '가사',
      'timeline': '시간순',
      'source': '원문',
      'timedLines': '시간이 있는 줄: {count}',
      'offset': '시간 오프셋: {ms} 밀리초',
      'noTimedLines': '유효한 줄 타임스탬프가 없습니다. 원래 순서대로 텍스트를 표시합니다.',
      'empty': '이 가사 파일은 비어 있습니다.',
      'untimed': '시간 없음',
      'wordTiming': '단어별 시간',
      'shortened': '미리보기에서 이 줄을 줄였습니다. 전체 텍스트는 원문을 여세요.',
      'limit': '이 가사 파일이 미리보기 제한을 초과했습니다. 전체 텍스트는 원문을 여세요.',
      'sourceChanged': '읽는 동안 파일이 변경되었습니다. 현재 가사를 보려면 다시 불러오세요.',
      'readFailed': '가사를 끝까지 읽을 수 없습니다. 파일을 다시 불러오거나 원문을 여세요.',
    },
    'ar': {
      'lyrics': 'الكلمات',
      'timeline': 'الترتيب الزمني',
      'source': 'المصدر',
      'timedLines': 'الأسطر الموقّتة: {count}',
      'offset': 'الإزاحة الزمنية: {ms} مللي ثانية',
      'noTimedLines': 'لم يتم العثور على طوابع زمنية صالحة للأسطر. يظهر النص بترتيبه الأصلي.',
      'empty': 'ملف الكلمات هذا فارغ.',
      'untimed': 'بلا توقيت',
      'wordTiming': 'توقيت الكلمات',
      'shortened':
          'تم اختصار هذا السطر في المعاينة. افتح المصدر لعرض النص الكامل.',
      'limit': 'يتجاوز ملف الكلمات حد المعاينة. افتح المصدر لعرض النص الكامل.',
      'sourceChanged':
          'تغيّر الملف أثناء القراءة. أعد تحميله لمعاينة الكلمات الحالية.',
      'readFailed':
          'تعذّرت قراءة الكلمات بالكامل. أعد تحميل الملف أو افتح المصدر.',
    },
  };
}
