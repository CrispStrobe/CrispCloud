import 'dart:ui' show Locale;

import '../services/legacy_word_conversion.dart';
import 'word_format_strings.dart';

class LegacyWordConversionStrings {
  LegacyWordConversionStrings(this.locale)
    : _values = _translations[locale.languageCode] ?? _english,
      _structuredValues =
          _structuredTranslations[locale.languageCode] ?? _structuredEnglish;

  final Locale locale;
  final List<String> _values;
  final Map<String, String> _structuredValues;

  String get title => _values[0];
  String get lossNotice => _values[1];
  String get fileName => _values[2];
  String get create => _values[3];
  String get cancel => _values[4];
  String get converting => _values[5];
  String get saving => _values[10];
  String get structuredMethod => _structuredValues['method']!;
  String get structuredNotice => _structuredValues['notice']!;
  String get builtInName => _structuredValues['name']!;
  String get structuredAcceptLoss => _structuredValues['accept']!;
  String get unavailable => _structuredValues['unavailable']!;
  String get limitationsTitle => _structuredValues['limitations']!;

  String limitation(LegacyWordConversionLimitation limitation) =>
      _structuredValues[limitation.name]!;

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

  static const _structuredEnglish = <String, String>{
    'method': 'Structured DOCX (built in)',
    'notice': 'Create a DOCX from the document structure the built-in parser can recover. Support is partial; review the limitations before saving. The original file is kept.',
    'name': 'Built-in structured conversion',
    'accept': 'Save this partial conversion with the listed limitations',
    'unavailable': 'No supported installed converter was found. You can choose a built-in conversion method.',
    'limitations': 'Conversion limitations',
    'partialFormatting':
        'Formatting and page layout are only partially preserved.',
    'images': 'Images and drawing placement are omitted.',
    'embeddedObjects':
        'Embedded objects, floating shapes and text boxes are omitted.',
    'headersFooters': 'Headers and footers are omitted.',
    'notesComments': 'Footnotes, endnotes and comments are omitted.',
    'revisions': 'Tracked changes are not fully reconstructed.',
    'macrosSignatures': 'Macros and digital signatures are omitted.',
    'fieldsLists': 'Fields and lists are reduced to the text or numbering the parser can recover.',
  };

  static const _structuredTranslations = <String, Map<String, String>>{
    'de': {
      'method': 'Strukturiertes DOCX (integriert)',
      'notice': 'Erstellt ein DOCX aus der Dokumentstruktur, die der integrierte Parser wiederherstellen kann. Die Unterstützung ist teilweise; prüfen Sie vor dem Speichern die Einschränkungen. Das Original bleibt erhalten.',
      'name': 'Integrierte strukturierte Konvertierung',
      'accept': 'Diese teilweise Konvertierung mit den aufgeführten Einschränkungen speichern',
      'unavailable': 'Es wurde kein unterstützter installierter Konverter gefunden. Sie können eine integrierte Konvertierungsmethode wählen.',
      'limitations': 'Einschränkungen der Konvertierung',
      'partialFormatting':
          'Formatierung und Seitenlayout bleiben nur teilweise erhalten.',
      'images':
          'Bilder und die Platzierung von Zeichnungen werden nicht übernommen.',
      'embeddedObjects': 'Eingebettete Objekte, schwebende Formen und Textfelder werden nicht übernommen.',
      'headersFooters': 'Kopf- und Fußzeilen werden nicht übernommen.',
      'notesComments':
          'Fußnoten, Endnoten und Kommentare werden nicht übernommen.',
      'revisions':
          'Nachverfolgte Änderungen werden nicht vollständig rekonstruiert.',
      'macrosSignatures':
          'Makros und digitale Signaturen werden nicht übernommen.',
      'fieldsLists': 'Felder und Listen werden auf den Text oder die Nummerierung reduziert, die der Parser wiederherstellen kann.',
    },
    'fr': {
      'method': 'DOCX structuré (intégré)',
      'notice': 'Crée un DOCX à partir de la structure du document que l’analyseur intégré peut récupérer. La prise en charge est partielle ; vérifiez les limites avant d’enregistrer. Le fichier original est conservé.',
      'name': 'Conversion structurée intégrée',
      'accept':
          'Enregistrer cette conversion partielle avec les limites indiquées',
      'unavailable': 'Aucun convertisseur installé compatible n’a été trouvé. Vous pouvez choisir une méthode de conversion intégrée.',
      'limitations': 'Limites de la conversion',
      'partialFormatting': 'La mise en forme et la mise en page ne sont que partiellement conservées.',
      'images': 'Les images et le placement des dessins sont omis.',
      'embeddedObjects': 'Les objets intégrés, les formes flottantes et les zones de texte sont omis.',
      'headersFooters': 'Les en-têtes et pieds de page sont omis.',
      'notesComments':
          'Les notes de bas de page, notes de fin et commentaires sont omis.',
      'revisions':
          'Les modifications suivies ne sont pas entièrement reconstituées.',
      'macrosSignatures': 'Les macros et signatures numériques sont omises.',
      'fieldsLists': 'Les champs et listes sont réduits au texte ou à la numérotation que l’analyseur peut récupérer.',
    },
    'es': {
      'method': 'DOCX estructurado (integrado)',
      'notice': 'Crea un DOCX a partir de la estructura del documento que puede recuperar el analizador integrado. La compatibilidad es parcial; revise las limitaciones antes de guardar. Se conserva el archivo original.',
      'name': 'Conversión estructurada integrada',
      'accept':
          'Guardar esta conversión parcial con las limitaciones indicadas',
      'unavailable': 'No se encontró ningún convertidor instalado compatible. Puede elegir un método de conversión integrado.',
      'limitations': 'Limitaciones de la conversión',
      'partialFormatting':
          'El formato y el diseño de página solo se conservan parcialmente.',
      'images': 'Se omiten las imágenes y la colocación de los dibujos.',
      'embeddedObjects': 'Se omiten los objetos incrustados, las formas flotantes y los cuadros de texto.',
      'headersFooters': 'Se omiten los encabezados y pies de página.',
      'notesComments':
          'Se omiten las notas al pie, notas al final y comentarios.',
      'revisions': 'El control de cambios no se reconstruye por completo.',
      'macrosSignatures': 'Se omiten las macros y firmas digitales.',
      'fieldsLists': 'Los campos y listas se reducen al texto o a la numeración que puede recuperar el analizador.',
    },
    'pt': {
      'method': 'DOCX estruturado (integrado)',
      'notice': 'Cria um DOCX a partir da estrutura do documento que o analisador integrado consegue recuperar. O suporte é parcial; reveja as limitações antes de guardar. O ficheiro original é mantido.',
      'name': 'Conversão estruturada integrada',
      'accept': 'Guardar esta conversão parcial com as limitações indicadas',
      'unavailable': 'Não foi encontrado nenhum conversor instalado compatível. Pode escolher um método de conversão integrado.',
      'limitations': 'Limitações da conversão',
      'partialFormatting': 'A formatação e a disposição das páginas são preservadas apenas parcialmente.',
      'images': 'As imagens e o posicionamento dos desenhos são omitidos.',
      'embeddedObjects': 'Os objetos incorporados, formas flutuantes e caixas de texto são omitidos.',
      'headersFooters': 'Os cabeçalhos e rodapés são omitidos.',
      'notesComments':
          'As notas de rodapé, notas de fim e comentários são omitidos.',
      'revisions': 'As alterações registadas não são totalmente reconstruídas.',
      'macrosSignatures': 'As macros e assinaturas digitais são omitidas.',
      'fieldsLists': 'Os campos e listas são reduzidos ao texto ou à numeração que o analisador consegue recuperar.',
    },
    'zh': {
      'method': '结构化 DOCX（内置）',
      'notice': '根据内置解析器能够恢复的文档结构创建 DOCX。仅提供部分支持；保存前请查看限制。原文件将保留。',
      'name': '内置结构化转换',
      'accept': '接受列出的限制，保存此部分转换结果',
      'unavailable': '未找到受支持的已安装转换器。您可以选择内置转换方式。',
      'limitations': '转换限制',
      'partialFormatting': '仅部分保留格式和页面布局。',
      'images': '不会保留图片和绘图位置。',
      'embeddedObjects': '不会保留嵌入对象、浮动形状和文本框。',
      'headersFooters': '不会保留页眉和页脚。',
      'notesComments': '不会保留脚注、尾注和批注。',
      'revisions': '无法完整重建修订记录。',
      'macrosSignatures': '不会保留宏和数字签名。',
      'fieldsLists': '域和列表将简化为解析器能够恢复的文本或编号。',
    },
    'ja': {
      'method': '構造を保持する DOCX（内蔵）',
      'notice': '内蔵パーサーが復元できる文書構造から DOCX を作成します。対応は部分的です。保存前に制限事項を確認してください。元のファイルは保持されます。',
      'name': '内蔵の構造変換',
      'accept': '記載の制限事項を確認し、この部分変換を保存する',
      'unavailable': '対応するインストール済みの変換アプリが見つかりません。内蔵の変換方法を選択できます。',
      'limitations': '変換の制限事項',
      'partialFormatting': '書式とページレイアウトは部分的にのみ保持されます。',
      'images': '画像と描画の配置は省略されます。',
      'embeddedObjects': '埋め込みオブジェクト、浮動する図形、テキストボックスは省略されます。',
      'headersFooters': 'ヘッダーとフッターは省略されます。',
      'notesComments': '脚注、文末脚注、コメントは省略されます。',
      'revisions': '変更履歴は完全には再現されません。',
      'macrosSignatures': 'マクロとデジタル署名は省略されます。',
      'fieldsLists': 'フィールドとリストは、パーサーが復元できるテキストまたは番号に変換されます。',
    },
    'ko': {
      'method': '구조화된 DOCX(내장)',
      'notice': '내장 파서가 복원할 수 있는 문서 구조에서 DOCX를 만듭니다. 일부 기능만 지원되므로 저장 전에 제한 사항을 확인하세요. 원본 파일은 유지됩니다.',
      'name': '내장 구조화 변환',
      'accept': '나열된 제한 사항을 확인하고 이 부분 변환을 저장',
      'unavailable': '지원되는 설치된 변환기를 찾지 못했습니다. 내장 변환 방법을 선택할 수 있습니다.',
      'limitations': '변환 제한 사항',
      'partialFormatting': '서식과 페이지 레이아웃은 일부만 유지됩니다.',
      'images': '이미지와 그리기 위치는 생략됩니다.',
      'embeddedObjects': '포함된 개체, 부동 도형 및 텍스트 상자는 생략됩니다.',
      'headersFooters': '머리글과 바닥글은 생략됩니다.',
      'notesComments': '각주, 미주 및 메모는 생략됩니다.',
      'revisions': '추적된 변경 내용은 완전히 복원되지 않습니다.',
      'macrosSignatures': '매크로와 디지털 서명은 생략됩니다.',
      'fieldsLists': '필드와 목록은 파서가 복원할 수 있는 텍스트나 번호로 축소됩니다.',
    },
    'ar': {
      'method': 'DOCX منظم (مدمج)',
      'notice': 'إنشاء DOCX من بنية المستند التي يستطيع المحلل المدمج استعادتها. الدعم جزئي؛ راجع القيود قبل الحفظ. يبقى الملف الأصلي محفوظاً.',
      'name': 'تحويل منظم مدمج',
      'accept': 'حفظ هذا التحويل الجزئي مع القيود المذكورة',
      'unavailable':
          'لم يُعثر على محول مثبت مدعوم. يمكنك اختيار طريقة تحويل مدمجة.',
      'limitations': 'قيود التحويل',
      'partialFormatting': 'يُحتفظ بالتنسيق وتخطيط الصفحات جزئياً فقط.',
      'images': 'تُحذف الصور ومواضع الرسومات.',
      'embeddedObjects':
          'تُحذف الكائنات المضمنة والأشكال العائمة ومربعات النص.',
      'headersFooters': 'تُحذف الرؤوس والتذييلات.',
      'notesComments': 'تُحذف الحواشي السفلية والختامية والتعليقات.',
      'revisions': 'لا يُعاد بناء التغييرات المتعقبة بالكامل.',
      'macrosSignatures': 'تُحذف وحدات الماكرو والتوقيعات الرقمية.',
      'fieldsLists': 'تُختزل الحقول والقوائم إلى النص أو الترقيم الذي يستطيع المحلل استعادته.',
    },
  };

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
