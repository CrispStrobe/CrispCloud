import 'dart:ui' show Locale;

import '../services/legacy_word_conversion.dart';
import 'word_format_strings.dart';

class LegacyWordConversionStrings {
  LegacyWordConversionStrings(this.locale)
    : _values = _translations[locale.languageCode] ?? _english;

  final Locale locale;
  final List<String> _values;

  String get title => _values[0];
  String get lossNotice => _values[1];
  String get fileName => _values[2];
  String get create => _values[3];
  String get cancel => _values[4];
  String get converting => _values[5];
  String get saving => _values[10];

  String error(Object error) {
    if (error is LegacyWordConversionException) {
      return _values[6 + error.issue.index];
    }
    return WordFormatStrings(locale).translate(error.toString()) ?? _values[9];
  }

  static const _english = <String>[
    'Convert to DOCX',
    'Create an editable DOCX from the extracted main body text. Formatting, page layout, images, objects, headers, notes, tracked-change state, macros and signatures are omitted. The original file is kept. Use Word or LibreOffice to convert with more formatting.',
    'New filename',
    'Create text-only DOCX',
    'Cancel',
    'Converting…',
    'Enter a single filename ending in .docx.',
    'The Word text contains invalid Unicode or XML characters. Open it in Word or LibreOffice to convert it.',
    'This document has too much text or too many breaks to convert safely.',
    'The document could not be converted. The original file was not changed.',
    'Saving copy…',
  ];

  static const _translations = <String, List<String>>{
    'de': [
      'In DOCX konvertieren',
      'Erstellt eine bearbeitbare DOCX-Datei aus dem extrahierten Haupttext. Formatierung, Seitenlayout, Bilder, Objekte, Kopfzeilen, Anmerkungen, Änderungsverfolgung, Makros und Signaturen werden nicht übernommen. Das Original bleibt erhalten. Für eine Konvertierung mit mehr Formatierung verwenden Sie Word oder LibreOffice.',
      'Neuer Dateiname',
      'DOCX nur mit Text erstellen',
      'Abbrechen',
      'Wird konvertiert…',
      'Geben Sie einen einzelnen Dateinamen mit der Endung .docx ein.',
      'Der Word-Text enthält ungültige Unicode- oder XML-Zeichen. Öffnen Sie ihn zum Konvertieren in Word oder LibreOffice.',
      'Dieses Dokument enthält zu viel Text oder zu viele Umbrüche für eine sichere Konvertierung.',
      'Das Dokument konnte nicht konvertiert werden. Die Originaldatei wurde nicht verändert.',
      'Kopie wird gespeichert…',
    ],
    'fr': [
      'Convertir en DOCX',
      'Créez un DOCX modifiable à partir du texte principal extrait. La mise en forme, la disposition, les images, objets, en-têtes, notes, état des révisions, macros et signatures sont omis. Le fichier original est conservé. Utilisez Word ou LibreOffice pour préserver davantage la mise en forme.',
      'Nouveau nom de fichier',
      'Créer un DOCX texte seul',
      'Annuler',
      'Conversion…',
      'Saisissez un nom de fichier unique se terminant par .docx.',
      'Le texte Word contient des caractères Unicode ou XML invalides. Ouvrez-le dans Word ou LibreOffice pour le convertir.',
      'Ce document contient trop de texte ou de sauts pour être converti en toute sécurité.',
      'Le document n’a pas pu être converti. Le fichier original n’a pas été modifié.',
      'Enregistrement de la copie…',
    ],
    'es': [
      'Convertir a DOCX',
      'Cree un DOCX editable a partir del texto principal extraído. Se omiten el formato, la distribución, imágenes, objetos, encabezados, notas, estado de las revisiones, macros y firmas. Se conserva el original. Use Word o LibreOffice para conservar más formato.',
      'Nuevo nombre de archivo',
      'Crear DOCX de solo texto',
      'Cancelar',
      'Convirtiendo…',
      'Introduzca un solo nombre de archivo terminado en .docx.',
      'El texto Word contiene caracteres Unicode o XML no válidos. Ábralo en Word o LibreOffice para convertirlo.',
      'El documento tiene demasiado texto o demasiados saltos para convertirlo de forma segura.',
      'No se pudo convertir el documento. El archivo original no se ha modificado.',
      'Guardando copia…',
    ],
    'pt': [
      'Converter para DOCX',
      'Crie um DOCX editável a partir do texto principal extraído. A formatação, disposição, imagens, objetos, cabeçalhos, notas, estado das revisões, macros e assinaturas são omitidos. O original é mantido. Use o Word ou LibreOffice para preservar mais formatação.',
      'Novo nome do ficheiro',
      'Criar DOCX apenas com texto',
      'Cancelar',
      'A converter…',
      'Introduza um único nome de ficheiro terminado em .docx.',
      'O texto Word contém caracteres Unicode ou XML inválidos. Abra-o no Word ou LibreOffice para o converter.',
      'Este documento tem demasiado texto ou demasiadas quebras para uma conversão segura.',
      'Não foi possível converter o documento. O ficheiro original não foi alterado.',
      'A guardar cópia…',
    ],
    'zh': [
      '转换为 DOCX',
      '根据提取的正文创建可编辑的 DOCX。不会保留格式、页面布局、图片、对象、页眉、注释、修订状态、宏和签名。原文件将保留。若要保留更多格式，请使用 Word 或 LibreOffice 转换。',
      '新文件名',
      '创建纯文本 DOCX',
      '取消',
      '正在转换…',
      '请输入以 .docx 结尾的单个文件名。',
      'Word 文本包含无效的 Unicode 或 XML 字符。请在 Word 或 LibreOffice 中打开并转换。',
      '此文档的文本或换行过多，无法安全转换。',
      '无法转换此文档。原文件未更改。',
      '正在保存副本…',
    ],
    'ja': [
      'DOCX に変換',
      '抽出した本文から編集可能な DOCX を作成します。書式、ページレイアウト、画像、オブジェクト、ヘッダー、注釈、変更履歴の状態、マクロ、署名は引き継がれません。元のファイルは保持されます。書式をより多く保持するには Word または LibreOffice で変換してください。',
      '新しいファイル名',
      'テキストのみの DOCX を作成',
      'キャンセル',
      '変換中…',
      '.docx で終わる単一のファイル名を入力してください。',
      'Word テキストに無効な Unicode または XML 文字が含まれています。Word または LibreOffice で開いて変換してください。',
      'テキストまたは改行が多すぎるため、安全に変換できません。',
      '文書を変換できませんでした。元のファイルは変更されていません。',
      'コピーを保存中…',
    ],
    'ko': [
      'DOCX로 변환',
      '추출한 본문에서 편집 가능한 DOCX를 만듭니다. 서식, 페이지 레이아웃, 이미지, 개체, 머리글, 주석, 변경 내용 추적 상태, 매크로 및 서명은 포함되지 않습니다. 원본 파일은 유지됩니다. 더 많은 서식을 보존하려면 Word 또는 LibreOffice로 변환하세요.',
      '새 파일 이름',
      '텍스트 전용 DOCX 만들기',
      '취소',
      '변환 중…',
      '.docx로 끝나는 단일 파일 이름을 입력하세요.',
      'Word 텍스트에 잘못된 Unicode 또는 XML 문자가 있습니다. Word 또는 LibreOffice에서 열어 변환하세요.',
      '텍스트나 줄 바꿈이 너무 많아 안전하게 변환할 수 없습니다.',
      '문서를 변환할 수 없습니다. 원본 파일은 변경되지 않았습니다.',
      '사본 저장 중…',
    ],
    'ar': [
      'تحويل إلى DOCX',
      'أنشئ ملف DOCX قابلاً للتحرير من النص الأساسي المستخرج. تُحذف التنسيقات وتخطيط الصفحات والصور والكائنات والرؤوس والملاحظات وحالة تعقب التغييرات ووحدات الماكرو والتوقيعات. يبقى الملف الأصلي محفوظاً. استخدم Word أو LibreOffice للحفاظ على المزيد من التنسيق.',
      'اسم الملف الجديد',
      'إنشاء DOCX نصي فقط',
      'إلغاء',
      'جارٍ التحويل…',
      'أدخل اسم ملف واحد ينتهي بالامتداد .docx.',
      'يحتوي نص Word على أحرف Unicode أو XML غير صالحة. افتحه في Word أو LibreOffice لتحويله.',
      'يحتوي هذا المستند على نص أو فواصل أكثر مما يمكن تحويله بأمان.',
      'تعذر تحويل المستند. لم يتغير الملف الأصلي.',
      'جارٍ حفظ النسخة…',
    ],
  };
}
