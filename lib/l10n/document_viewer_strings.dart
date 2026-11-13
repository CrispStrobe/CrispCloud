import 'package:flutter/widgets.dart';

class DocumentViewerStrings {
  DocumentViewerStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) =>
      (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;

  static const _values = <String, Map<String, String>>{
    'en': {
      'preview': 'Preview',
      'nativeText': 'Text fallback',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'This file exceeds the preview limit. Open Source or Hex to inspect the complete file.',
      'sourceChanged': 'The file changed while reading. Reload it to preview the current document.',
      'readFailed': 'The document could not be read completely. Reload it or open Source.',
      'selectToCopy': 'Select text inside the document and use Copy. Source and Hex show the original file.',
    },
    'de': {
      'preview': 'Vorschau',
      'nativeText': 'Textansicht',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'Diese Datei überschreitet das Vorschaulimit. Öffnen Sie Quelltext oder Hex für die vollständige Datei.',
      'sourceChanged':
          'Die Datei wurde beim Lesen geändert. Laden Sie das Dokument neu.',
      'readFailed': 'Das Dokument konnte nicht vollständig gelesen werden. Laden Sie es neu oder öffnen Sie den Quelltext.',
      'selectToCopy': 'Wählen Sie Text im Dokument aus und kopieren Sie ihn. Quelltext und Hex zeigen die Originaldatei.',
    },
    'fr': {
      'preview': 'Aperçu',
      'nativeText': 'Vue texte',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'Ce fichier dépasse la limite d’aperçu. Ouvrez Source ou Hex pour examiner le fichier complet.',
      'sourceChanged':
          'Le fichier a changé pendant la lecture. Rechargez le document.',
      'readFailed': 'Le document n’a pas pu être lu entièrement. Rechargez-le ou ouvrez Source.',
      'selectToCopy': 'Sélectionnez le texte du document et copiez-le. Source et Hex affichent le fichier original.',
    },
    'es': {
      'preview': 'Vista previa',
      'nativeText': 'Vista de texto',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'El archivo supera el límite de vista previa. Abre Fuente o Hex para ver el archivo completo.',
      'sourceChanged':
          'El archivo cambió durante la lectura. Recarga el documento.',
      'readFailed':
          'No se pudo leer todo el documento. Recárgalo o abre Fuente.',
      'selectToCopy': 'Selecciona texto dentro del documento y cópialo. Fuente y Hex muestran el archivo original.',
    },
    'pt': {
      'preview': 'Pré-visualização',
      'nativeText': 'Vista de texto',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'O ficheiro excede o limite de pré-visualização. Abra Fonte ou Hex para ver o ficheiro completo.',
      'sourceChanged':
          'O ficheiro mudou durante a leitura. Recarregue o documento.',
      'readFailed': 'Não foi possível ler o documento completo. Recarregue-o ou abra Fonte.',
      'selectToCopy': 'Selecione texto no documento e copie-o. Fonte e Hex mostram o ficheiro original.',
    },
    'zh': {
      'preview': '预览',
      'nativeText': '文本视图',
      'xmlTools': 'XSD / XSLT',
      'readLimit': '此文件超过预览限制。打开源文件或十六进制视图查看完整文件。',
      'sourceChanged': '读取时文件已更改。请重新加载文档。',
      'readFailed': '无法完整读取文档。请重新加载或打开源文件。',
      'selectToCopy': '选择文档中的文本并复制。源文件和十六进制视图显示原始文件。',
    },
    'ja': {
      'preview': 'プレビュー',
      'nativeText': 'テキスト表示',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'プレビューの制限を超えています。ソースまたは16進表示でファイル全体を確認してください。',
      'sourceChanged': '読み込み中にファイルが変更されました。再読み込みしてください。',
      'readFailed': '文書全体を読み込めませんでした。再読み込みするかソースを開いてください。',
      'selectToCopy': '文書内のテキストを選択してコピーしてください。ソースと16進表示では元のファイルを表示します。',
    },
    'ko': {
      'preview': '미리 보기',
      'nativeText': '텍스트 보기',
      'xmlTools': 'XSD / XSLT',
      'readLimit': '미리 보기 제한을 초과했습니다. 소스 또는 16진수 보기에서 전체 파일을 확인하세요.',
      'sourceChanged': '읽는 동안 파일이 변경되었습니다. 문서를 다시 불러오세요.',
      'readFailed': '문서를 완전히 읽지 못했습니다. 다시 불러오거나 소스를 여세요.',
      'selectToCopy': '문서 안의 텍스트를 선택하여 복사하세요. 소스와 16진수 보기에는 원본 파일이 표시됩니다.',
    },
    'ar': {
      'preview': 'معاينة',
      'nativeText': 'عرض النص',
      'xmlTools': 'XSD / XSLT',
      'readLimit': 'يتجاوز هذا الملف حد المعاينة. افتح المصدر أو العرض السداسي لفحص الملف الكامل.',
      'sourceChanged': 'تغير الملف أثناء القراءة. أعد تحميل المستند.',
      'readFailed': 'تعذرت قراءة المستند بالكامل. أعد تحميله أو افتح المصدر.',
      'selectToCopy': 'حدد النص داخل المستند وانسخه. يعرض المصدر والعرض السداسي الملف الأصلي.',
    },
  };
}
