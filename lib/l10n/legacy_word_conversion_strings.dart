import 'dart:ui' show Locale;

import 'package:legacy_doc_parser/legacy_doc_parser.dart'
    show LegacyWordConversionException, LegacyWordConversionLimitation;

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
  String get structuredMacroNotice => _structuredValues['macroNotice']!;
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
    'method': "Structured Word (built in)",
    'notice': "Preserves supported structure and formatting in a separate Word copy. Support is partial; review the copy before saving. The original file is kept.",
    'macroNotice': "Structured DOCX contains no active VBA, but original VBA project bytes may remain as inert evidence. DOCM can attach a supported VBA project. The built-in converter never runs macros.",
    'name': 'Built-in structured conversion',
    'accept': 'Save this partial conversion with the listed limitations',
    'unavailable': 'No supported installed converter was found. You can choose a built-in conversion method.',
    'limitations': 'Conversion limitations',
    'partialFormatting':
        'Formatting and page layout are only partially preserved.',
    'images': "Some images or drawing effects could not be reproduced.",
    'embeddedObjects': "Some objects, shapes or text boxes are approximate or retained only as data.",
    'headersFooters':
        "Some header or footer content could not be reconstructed.",
    'notesComments':
        "Some note or comment content could not be fully reconstructed.",
    'revisions': 'Tracked changes are not fully reconstructed.',
    'macrosSignatures': "Only supported VBA projects can be active in DOCM. Original signatures are retained as data and do not validate the converted copy.",
    'fieldsLists': "Some fields or list numbering remain incomplete. Stored field results are not recalculated.",
  };

  static const _structuredTranslations = <String, Map<String, String>>{
    'de': {
      'method': "Strukturiertes Word (integriert)",
      'notice': "Übernimmt unterstützte Strukturen und Formatierungen in eine separate Word-Kopie. Die Unterstützung ist teilweise; prüfen Sie die Kopie vor dem Speichern. Das Original bleibt erhalten.",
      'macroNotice': "Strukturierte DOCX-Dateien enthalten kein aktives VBA, können aber ursprüngliche VBA-Projektdaten als inaktive Belegdaten enthalten. DOCM kann ein unterstütztes VBA-Projekt einbinden. Die integrierte Konvertierung führt niemals Makros aus.",
      'name': 'Integrierte strukturierte Konvertierung',
      'accept': 'Diese teilweise Konvertierung mit den aufgeführten Einschränkungen speichern',
      'unavailable': 'Es wurde kein unterstützter installierter Konverter gefunden. Sie können eine integrierte Konvertierungsmethode wählen.',
      'limitations': 'Einschränkungen der Konvertierung',
      'partialFormatting':
          'Formatierung und Seitenlayout bleiben nur teilweise erhalten.',
      'images': "Einige Bilder oder Zeichnungseffekte konnten nicht wiedergegeben werden.",
      'embeddedObjects': "Einige Objekte, Formen oder Textfelder werden vereinfacht dargestellt oder nur als Daten aufbewahrt.",
      'headersFooters': "Einige Inhalte von Kopf- oder Fußzeilen konnten nicht rekonstruiert werden.",
      'notesComments': "Einige Inhalte von Anmerkungen oder Kommentaren konnten nicht vollständig rekonstruiert werden.",
      'revisions':
          'Nachverfolgte Änderungen werden nicht vollständig rekonstruiert.',
      'macrosSignatures': "Nur unterstützte VBA-Projekte können in DOCM aktiv sein. Originalsignaturen werden als Daten aufbewahrt und bestätigen nicht die Gültigkeit der konvertierten Kopie.",
      'fieldsLists': "Einige Felder oder Listennummerierungen bleiben unvollständig. Gespeicherte Feldergebnisse werden nicht neu berechnet.",
    },
    'fr': {
      'method': "Word structuré (intégré)",
      'notice': "Conserve les structures et la mise en forme prises en charge dans une copie Word séparée. La prise en charge est partielle ; vérifiez la copie avant de l’enregistrer. Le fichier original est conservé.",
      'macroNotice': "Un DOCX structuré ne contient pas de VBA actif, mais les données d’origine du projet VBA peuvent rester comme éléments de preuve inactifs. Un DOCM peut intégrer un projet VBA pris en charge. Le convertisseur intégré n’exécute jamais de macros.",
      'name': 'Conversion structurée intégrée',
      'accept':
          'Enregistrer cette conversion partielle avec les limites indiquées',
      'unavailable': 'Aucun convertisseur installé compatible n’a été trouvé. Vous pouvez choisir une méthode de conversion intégrée.',
      'limitations': 'Limites de la conversion',
      'partialFormatting': 'La mise en forme et la mise en page ne sont que partiellement conservées.',
      'images': "Certaines images ou certains effets de dessin n’ont pas pu être reproduits.",
      'embeddedObjects': "Certains objets, formes ou zones de texte sont approximatifs ou conservés uniquement comme données.",
      'headersFooters': "Certains contenus d’en-tête ou de pied de page n’ont pas pu être reconstitués.",
      'notesComments': "Certains contenus de notes ou de commentaires n’ont pas pu être entièrement reconstitués.",
      'revisions':
          'Les modifications suivies ne sont pas entièrement reconstituées.',
      'macrosSignatures': "Seuls les projets VBA pris en charge peuvent être actifs dans un DOCM. Les signatures originales sont conservées comme données et ne valident pas la copie convertie.",
      'fieldsLists': "Certains champs ou numérotations restent incomplets. Les résultats de champs enregistrés ne sont pas recalculés.",
    },
    'es': {
      'method': "Word estructurado (integrado)",
      'notice': "Conserva la estructura y el formato compatibles en una copia de Word separada. La compatibilidad es parcial; revise la copia antes de guardar. Se conserva el archivo original.",
      'macroNotice': "Un DOCX estructurado no contiene VBA activo, pero puede conservar los datos originales del proyecto VBA como evidencia inactiva. DOCM puede incorporar un proyecto VBA compatible. El convertidor integrado nunca ejecuta macros.",
      'name': 'Conversión estructurada integrada',
      'accept':
          'Guardar esta conversión parcial con las limitaciones indicadas',
      'unavailable': 'No se encontró ningún convertidor instalado compatible. Puede elegir un método de conversión integrado.',
      'limitations': 'Limitaciones de la conversión',
      'partialFormatting':
          'El formato y el diseño de página solo se conservan parcialmente.',
      'images':
          "No se pudieron reproducir algunas imágenes o efectos de dibujo.",
      'embeddedObjects': "Algunos objetos, formas o cuadros de texto son aproximados o se conservan solo como datos.",
      'headersFooters': "No se pudo reconstruir parte del contenido de los encabezados o pies de página.",
      'notesComments': "No se pudo reconstruir por completo parte del contenido de notas o comentarios.",
      'revisions': 'El control de cambios no se reconstruye por completo.',
      'macrosSignatures': "Solo los proyectos VBA compatibles pueden estar activos en DOCM. Las firmas originales se conservan como datos y no validan la copia convertida.",
      'fieldsLists': "Algunos campos o numeraciones siguen incompletos. Los resultados de campos guardados no se recalculan.",
    },
    'pt': {
      'method': "Word estruturado (integrado)",
      'notice': "Preserva a estrutura e formatação suportadas numa cópia Word separada. O suporte é parcial; reveja a cópia antes de guardar. O ficheiro original é mantido.",
      'macroNotice': "Um DOCX estruturado não contém VBA ativo, mas pode conservar os dados originais do projeto VBA como evidência inativa. O DOCM pode incluir um projeto VBA suportado. O conversor integrado nunca executa macros.",
      'name': 'Conversão estruturada integrada',
      'accept': 'Guardar esta conversão parcial com as limitações indicadas',
      'unavailable': 'Não foi encontrado nenhum conversor instalado compatível. Pode escolher um método de conversão integrado.',
      'limitations': 'Limitações da conversão',
      'partialFormatting': 'A formatação e a disposição das páginas são preservadas apenas parcialmente.',
      'images':
          "Não foi possível reproduzir algumas imagens ou efeitos de desenho.",
      'embeddedObjects': "Alguns objetos, formas ou caixas de texto são aproximados ou mantidos apenas como dados.",
      'headersFooters': "Não foi possível reconstruir parte do conteúdo dos cabeçalhos ou rodapés.",
      'notesComments': "Não foi possível reconstruir totalmente parte do conteúdo de notas ou comentários.",
      'revisions': 'As alterações registadas não são totalmente reconstruídas.',
      'macrosSignatures': "Só os projetos VBA suportados podem estar ativos em DOCM. As assinaturas originais são mantidas como dados e não validam a cópia convertida.",
      'fieldsLists': "Alguns campos ou numerações continuam incompletos. Os resultados de campos guardados não são recalculados.",
    },
    'zh': {
      'method': "结构化 Word（内置）",
      'notice': "将受支持的结构和格式保留在单独的 Word 副本中。仅提供部分支持；保存前请检查副本。原文件将保留。",
      'macroNotice': "结构化 DOCX 不含已启用的 VBA，但可能仍保留原始 VBA 项目数据作为非活动存证。DOCM 可关联受支持的 VBA 项目。内置转换器从不运行宏。",
      'name': '内置结构化转换',
      'accept': '接受列出的限制，保存此部分转换结果',
      'unavailable': '未找到受支持的已安装转换器。您可以选择内置转换方式。',
      'limitations': '转换限制',
      'partialFormatting': '仅部分保留格式和页面布局。',
      'images': "部分图片或绘图效果无法重现。",
      'embeddedObjects': "部分对象、形状或文本框只能近似重现，或仅作为数据保留。",
      'headersFooters': "部分页眉或页脚内容无法重建。",
      'notesComments': "部分注释或批注内容无法完整重建。",
      'revisions': '无法完整重建修订记录。',
      'macrosSignatures': "仅受支持的 VBA 项目可在 DOCM 中启用。原始签名作为数据保留，不能验证转换后的副本。",
      'fieldsLists': "部分域或列表编号仍不完整。不会重新计算已存储的域结果。",
    },
    'ja': {
      'method': "構造を保持する Word（内蔵）",
      'notice': "対応する構造と書式を別の Word コピーに保持します。対応は部分的です。保存前にコピーを確認してください。元のファイルは保持されます。",
      'macroNotice': "構造を保持する DOCX に有効化された VBA は含まれませんが、元の VBA プロジェクトのデータが非アクティブな記録として残る場合があります。DOCM には対応する VBA プロジェクトを組み込めます。内蔵コンバーターはマクロを実行しません。",
      'name': '内蔵の構造変換',
      'accept': '記載の制限事項を確認し、この部分変換を保存する',
      'unavailable': '対応するインストール済みの変換アプリが見つかりません。内蔵の変換方法を選択できます。',
      'limitations': '変換の制限事項',
      'partialFormatting': '書式とページレイアウトは部分的にのみ保持されます。',
      'images': "一部の画像や描画効果は再現できませんでした。",
      'embeddedObjects': "一部のオブジェクト、図形、テキストボックスは近似表示されるか、データとしてのみ保持されます。",
      'headersFooters': "一部のヘッダーやフッターの内容は復元できませんでした。",
      'notesComments': "一部の脚注やコメントの内容は完全には復元できませんでした。",
      'revisions': '変更履歴は完全には再現されません。',
      'macrosSignatures':
          "対応する VBA プロジェクトのみ DOCM で有効にできます。元の署名はデータとして保持され、変換後のコピーの有効性を証明しません。",
      'fieldsLists': "一部のフィールドやリスト番号は不完全です。保存されたフィールド結果は再計算されません。",
    },
    'ko': {
      'method': "구조화된 Word(내장)",
      'notice': "지원되는 구조와 서식을 별도의 Word 복사본에 유지합니다. 일부 기능만 지원되므로 저장 전에 복사본을 확인하세요. 원본 파일은 유지됩니다.",
      'macroNotice': "구조화된 DOCX에는 활성 VBA가 없지만 원래 VBA 프로젝트 데이터가 비활성 증거 자료로 남을 수 있습니다. DOCM에는 지원되는 VBA 프로젝트를 연결할 수 있습니다. 내장 변환기는 매크로를 실행하지 않습니다.",
      'name': '내장 구조화 변환',
      'accept': '나열된 제한 사항을 확인하고 이 부분 변환을 저장',
      'unavailable': '지원되는 설치된 변환기를 찾지 못했습니다. 내장 변환 방법을 선택할 수 있습니다.',
      'limitations': '변환 제한 사항',
      'partialFormatting': '서식과 페이지 레이아웃은 일부만 유지됩니다.',
      'images': "일부 이미지나 그리기 효과를 재현할 수 없습니다.",
      'embeddedObjects': "일부 개체, 도형 또는 텍스트 상자는 근사하게 표시되거나 데이터로만 보존됩니다.",
      'headersFooters': "일부 머리글 또는 바닥글 내용을 복원할 수 없습니다.",
      'notesComments': "일부 각주 또는 메모 내용을 완전히 복원할 수 없습니다.",
      'revisions': '추적된 변경 내용은 완전히 복원되지 않습니다.',
      'macrosSignatures': "지원되는 VBA 프로젝트만 DOCM에서 활성화할 수 있습니다. 원본 서명은 데이터로 보존되며 변환된 복사본의 유효성을 보장하지 않습니다.",
      'fieldsLists': "일부 필드나 목록 번호는 불완전합니다. 저장된 필드 결과는 다시 계산하지 않습니다.",
    },
    'ar': {
      'method': "Word منظم (مدمج)",
      'notice': "يحتفظ بالبنية والتنسيق المدعومين في نسخة Word منفصلة. الدعم جزئي؛ راجع النسخة قبل الحفظ. يبقى الملف الأصلي محفوظاً.",
      'macroNotice': "لا يحتوي DOCX المنظّم على VBA نشط، لكن قد تبقى بيانات مشروع VBA الأصلي كأدلة غير نشطة. يمكن لملف DOCM إرفاق مشروع VBA مدعوم. لا يشغّل المحوّل المدمج وحدات الماكرو مطلقاً.",
      'name': 'تحويل منظم مدمج',
      'accept': 'حفظ هذا التحويل الجزئي مع القيود المذكورة',
      'unavailable':
          'لم يُعثر على محول مثبت مدعوم. يمكنك اختيار طريقة تحويل مدمجة.',
      'limitations': 'قيود التحويل',
      'partialFormatting': 'يُحتفظ بالتنسيق وتخطيط الصفحات جزئياً فقط.',
      'images': "تعذرت إعادة إنتاج بعض الصور أو تأثيرات الرسومات.",
      'embeddedObjects': "تُعرض بعض الكائنات أو الأشكال أو مربعات النص بصورة تقريبية أو يُحتفظ بها كبيانات فقط.",
      'headersFooters': "تعذرت إعادة بناء بعض محتويات الرؤوس أو التذييلات.",
      'notesComments':
          "تعذرت إعادة بناء بعض محتويات الحواشي أو التعليقات بالكامل.",
      'revisions': 'لا يُعاد بناء التغييرات المتعقبة بالكامل.',
      'macrosSignatures': "يمكن تفعيل مشاريع VBA المدعومة فقط في DOCM. يُحتفظ بالتوقيعات الأصلية كبيانات ولا تثبت صحة النسخة المحولة.",
      'fieldsLists': "تبقى بعض الحقول أو أرقام القوائم غير مكتملة. لا تُعاد حساب نتائج الحقول المخزنة.",
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
