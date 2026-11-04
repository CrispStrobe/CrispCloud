import 'dart:ui';

/// User-interface language of the report designer.
///
/// Labels are authored in English; [t] looks up the translation and falls
/// back to the English text, so a missing entry never hides a control.
/// Counts go through [count] so each language picks its plural form.
///
/// ```dart
/// QudsReportDesigner(
///   controller: controller,
///   strings: ReportDesignerStrings.forLocale(const Locale('ar')),
/// );
/// ```
class ReportDesignerStrings {
  const ReportDesignerStrings._(this.languageCode, this._table);

  /// English (the authored text).
  static const ReportDesignerStrings english = ReportDesignerStrings._(
    'en',
    <String, String>{},
  );

  /// Arabic, laid out right to left.
  static const ReportDesignerStrings arabic = ReportDesignerStrings._(
    'ar',
    _arabic,
  );

  /// Languages with a translation.
  static const List<ReportDesignerStrings> all = <ReportDesignerStrings>[
    english,
    arabic,
  ];

  /// Strings for [locale]; English when the language has no translation.
  static ReportDesignerStrings forLocale(Locale? locale) {
    for (final ReportDesignerStrings s in all) {
      if (s.languageCode == locale?.languageCode) {
        return s;
      }
    }
    return english;
  }

  /// ISO 639-1 code (`en`, `ar`).
  final String languageCode;

  final Map<String, String> _table;

  /// Locale of this language.
  Locale get locale => Locale(languageCode);

  /// Whether the interface reads right to left.
  bool get isRtl => languageCode == 'ar';

  /// Reading direction of the interface.
  TextDirection get direction => isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// Translation of the English label [english].
  String t(String english) => _table[english] ?? english;

  static final RegExp _sourceTail = RegExp(r'^(.*?) in "(.*)"(?: at (\d+))?$');

  /// Translation of a diagnostic message ([ReportDiagnostic.summary]),
  /// including parser messages that end with `in "source" at N`. Messages
  /// with values in them (`Unknown function X()`) stay in English.
  String diagnostic(String summary) {
    final String? whole = _table[summary];
    if (whole != null) {
      return whole;
    }
    final RegExpMatch? m = _sourceTail.firstMatch(summary);
    final String? head = m == null ? null : _table[m.group(1)!];
    if (m == null || head == null) {
      return summary;
    }
    final String? at = m.group(3);
    return '$head ${t('in')} "${m.group(2)}"'
        '${at == null ? '' : ' ${t('at character')} $at'}';
  }

  /// `3 elements`: [n] with the plural of [noun], an English singular noun
  /// with a known plural in this table (`element`, `variable`, …).
  String count(int n, String noun) {
    final _Plural? p = _plurals[noun];
    if (p == null) {
      return '$n $noun';
    }
    if (!isRtl) {
      return '$n ${n == 1 ? noun : p.english}';
    }
    if (n == 0) {
      return '0 ${p.many}';
    }
    if (n == 1) {
      return '${p.one} ${p.oneSuffix}'.trim();
    }
    if (n == 2) {
      return p.two;
    }
    if (n <= 10) {
      return '$n ${p.few}';
    }
    return '$n ${p.many}';
  }

  /// Label of an enum option or keyword (`contain`, `rtl`, `qr`).
  String option(String option) {
    if (option.isEmpty) {
      return t('None');
    }
    final String? direct = _table[option];
    if (direct != null) {
      return direct;
    }
    switch (option) {
      case 'rtl' || 'ltr' || 'qr' || 'pt' || 'mm' || 'cm' || 'px':
        return t(option.toUpperCase());
      case 'inch':
        return t('IN');
    }
    final String spaced = option.replaceAllMapped(
      RegExp('([a-z])([A-Z0-9])'),
      (Match m) => '${m[1]} ${m[2]!.toLowerCase()}',
    );
    return t(spaced[0].toUpperCase() + spaced.substring(1));
  }

  static const Map<String, _Plural> _plurals = <String, _Plural>{
    'element': _Plural('elements', 'عنصر', 'واحد', 'عنصران', 'عناصر', 'عنصر'),
    'variable': _Plural(
      'variables',
      'متغير',
      'واحد',
      'متغيران',
      'متغيرات',
      'متغير',
    ),
    'image': _Plural('images', 'صورة', 'واحدة', 'صورتان', 'صور', 'صورة'),
    'family': _Plural('families', 'خط', 'واحد', 'خطان', 'خطوط', 'خطًا'),
    'font': _Plural('fonts', 'خط', 'واحد', 'خطان', 'خطوط', 'خطًا'),
    'band': _Plural('bands', 'شريط', 'واحد', 'شريطان', 'أشرطة', 'شريطًا'),
    'problem': _Plural(
      'problems',
      'مشكلة',
      'واحدة',
      'مشكلتان',
      'مشاكل',
      'مشكلة',
    ),
    'error': _Plural('errors', 'خطأ', 'واحد', 'خطآن', 'أخطاء', 'خطأ'),
    'warning': _Plural(
      'warnings',
      'تحذير',
      'واحد',
      'تحذيران',
      'تحذيرات',
      'تحذيرًا',
    ),
    'row': _Plural('rows', 'صف', 'واحد', 'صفان', 'صفوف', 'صفًا'),
    'column': _Plural('columns', 'عمود', 'واحد', 'عمودان', 'أعمدة', 'عمودًا'),
    'field': _Plural('fields', 'حقل', 'واحد', 'حقلان', 'حقول', 'حقلًا'),
    'value': _Plural('values', 'قيمة', 'واحدة', 'قيمتان', 'قيم', 'قيمة'),
  };

  static const Map<String, String> _arabic = <String, String>{
    // Problems panel.
    'Problems': 'المشاكل',
    'Unreadable file': 'ملف غير قابل للقراءة',
    'Formula error': 'خطأ في الصيغة',
    'Unknown function': 'دالة غير معروفة',
    'Size or position': 'الحجم أو الموضع',
    'Missing value': 'قيمة ناقصة',
    'Duplicate name': 'اسم مكرر',
    'Invalid value': 'قيمة غير صالحة',
    'Report structure': 'بنية التقرير',
    'Not supported': 'غير مدعوم',
    'The file is damaged or is not a Quds report.':
        'الملف تالف أو ليس تقرير Quds.',
    'Check the brackets, quotes, and operators of the formula.':
        'راجع الأقواس وعلامات الاقتباس والعمليات في الصيغة.',
    'Check the spelling of the function name.': 'تحقق من كتابة اسم الدالة.',
    'Move or resize the element so it fits its band and the page.':
        'حرّك العنصر أو غيّر حجمه ليتسع داخل الشريط والصفحة.',
    'Fill in the missing value.': 'أدخل القيمة الناقصة.',
    'Give each one a different name.': 'أعطِ كل واحد منها اسمًا مختلفًا.',
    'Enter the value in the form the property expects.':
        'أدخل القيمة بالصيغة التي تتوقعها الخاصية.',
    'Check which band holds the element and which data set it uses.':
        'تحقق من الشريط الذي يحتوي العنصر ومن مجموعة البيانات التي يستخدمها.',
    'This version does not support this part of the file.':
        'هذا الإصدار لا يدعم هذا الجزء من الملف.',
    'Found when the file was opened': 'وُجد عند فتح الملف',
    'Bands': 'الأشرطة',
    'File': 'الملف',
    'Cell': 'الخلية',
    'Footer cell': 'خلية التذييل',
    'Margins': 'الهوامش',
    'Extends below the band height': 'يمتد أسفل ارتفاع الشريط',
    'Extends past the page edge': 'يتجاوز حافة الصفحة',
    'Band is taller than the printable page height':
        'الشريط أطول من الارتفاع القابل للطباعة في الصفحة',
    'No Detail band; data rows will not print':
        'لا يوجد شريط تفاصيل؛ لن تُطبع صفوف البيانات',
    'Group bands need a Detail band': 'أشرطة المجموعات تحتاج شريط تفاصيل',
    'Page header + footer leave no room for content':
        'رأس الصفحة وتذييلها لا يتركان مساحة للمحتوى',
    'Margins leave no printable area': 'الهوامش لا تترك مساحة قابلة للطباعة',
    'dataSet is only used on the Detail band':
        'مجموعة البيانات تُستخدم في شريط التفاصيل فقط',
    'Table outside Detail needs dataSet to repeat rows':
        'الجدول خارج شريط التفاصيل يحتاج مجموعة بيانات لتكرار الصفوف',
    'Table in Detail without a dataSet prints one empty row':
        'الجدول في شريط التفاصيل بدون مجموعة بيانات يطبع صفًا فارغًا واحدًا',
    'Chart in Detail without a dataSet plots one row':
        'المخطط في شريط التفاصيل بدون مجموعة بيانات يرسم صفًا واحدًا',
    'Detail supports one repeating Table':
        'شريط التفاصيل يدعم جدولًا متكررًا واحدًا فقط',
    'Chart has no <Series> or <Point>; it prints empty':
        'المخطط بلا سلاسل أو نقاط؛ سيُطبع فارغًا',
    'Image has no source': 'الصورة بلا مصدر',
    'Image needs width and height': 'الصورة تحتاج عرضًا وارتفاعًا',
    'Barcode needs width and height': 'الباركود يحتاج عرضًا وارتفاعًا',
    'Shape needs width and height': 'الشكل يحتاج عرضًا وارتفاعًا',
    'Chart needs width and height': 'المخطط يحتاج عرضًا وارتفاعًا',
    'No width; using the remaining line width':
        'بلا عرض؛ سيُستخدم باقي عرض السطر',
    'width must not be negative': 'العرض لا يجوز أن يكون سالبًا',
    'height must not be negative': 'الارتفاع لا يجوز أن يكون سالبًا',
    'limit must not be negative': 'الحد لا يجوز أن يكون سالبًا',
    'Expression is empty': 'الصيغة فارغة',
    'Unknown element ignored': 'عنصر غير معروف تم تجاهله',
    'Unknown setting ignored': 'إعداد غير معروف تم تجاهله',
    'Unknown band': 'شريط غير معروف',
    'Band outside <Bands>; accepted': 'شريط خارج قسم الأشرطة؛ تم قبوله',
    'No <Bands> section': 'لا يوجد قسم أشرطة',
    'Empty document': 'المستند فارغ',
    'Root element must be <QudsReport>':
        'العنصر الجذر يجب أن يكون <QudsReport>',
    'Element needs a type': 'العنصر يحتاج نوعًا',
    'Color needs name and value': 'اللون يحتاج اسمًا وقيمة',
    'Duplicate variable name': 'اسم متغير مكرر',
    'Duplicate table': 'جدول مكرر',
    'Duplicate column': 'عمود مكرر',
    'Duplicate field': 'حقل مكرر',
    'Variable needs a name': 'المتغير يحتاج اسمًا',
    'Table needs a name': 'الجدول يحتاج اسمًا',
    'Column needs a name': 'العمود يحتاج اسمًا',
    'Field needs a name': 'الحقل يحتاج اسمًا',
    'Table needs at least one <Column>': 'الجدول يحتاج عمودًا واحدًا على الأقل',
    'Series needs a value expression': 'السلسلة تحتاج صيغة قيمة',
    'Point needs a value': 'النقطة تحتاج قيمة',
    'Data-bound chart needs a category expression':
        'المخطط المرتبط بالبيانات يحتاج صيغة فئة',
    'Unexpected end of expression': 'نهاية غير متوقعة للصيغة',
    'Empty placeholder': 'عنصر نائب فارغ',
    'Unclosed "{{"': 'لم يُغلق "{{"',
    'Unterminated string': 'نص غير مغلق بعلامة اقتباس',
    'Expected a member name after "."': 'متوقع اسم حقل بعد "."',
    'in': 'في',
    'at character': 'عند الحرف',
    // Inspector pages and chrome.
    'Properties': 'الخصائص',
    'Variables': 'المتغيرات',
    'Images': 'الصور',
    'Fonts': 'الخطوط',
    'Diagnostics': 'التشخيص',
    'No problems found.': 'لا توجد مشاكل.',
    'Report properties': 'خصائص التقرير',
    'Shared properties of the selection': 'الخصائص المشتركة للعناصر المحددة',
    'Report settings': 'إعدادات التقرير',
    'Report': 'التقرير',
    'Band': 'الشريط',
    'band': 'شريط',
    'Data': 'البيانات',
    'Column': 'العمود',
    // Element kinds.
    'Text': 'نص',
    'Image': 'صورة',
    'Table': 'جدول',
    'QR code': 'رمز QR',
    'Barcode': 'باركود',
    'Line': 'خط',
    'Ellipse': 'شكل بيضاوي',
    'Rectangle': 'مستطيل',
    'Chart': 'مخطط',
    'Shape': 'شكل',
    // Bands.
    'Report Header': 'رأس التقرير',
    'Page Header': 'رأس الصفحة',
    'Group Header': 'رأس المجموعة',
    'Detail': 'التفاصيل',
    'Group Footer': 'تذييل المجموعة',
    'Page Footer': 'تذييل الصفحة',
    'Report Summary': 'ملخص التقرير',
    'Report header': 'رأس التقرير',
    'Page header': 'رأس الصفحة',
    'Group header': 'رأس المجموعة',
    'Group footer': 'تذييل المجموعة',
    'Page footer': 'تذييل الصفحة',
    'Report summary': 'ملخص التقرير',
    // Property groups.
    'Layout': 'التخطيط',
    'Font': 'الخط',
    'Box': 'الإطار',
    'Style': 'النمط',
    'Paging': 'الترقيم والصفحات',
    'Page': 'الصفحة',
    'Totals': 'الإجماليات',
    'Series': 'السلاسل',
    'Sample data': 'بيانات تجريبية',
    'Fields': 'الحقول',
    'Palette': 'لوحة الألوان',
    // Property labels.
    'Name': 'الاسم',
    'Width': 'العرض',
    'Height': 'الارتفاع',
    'Visible when': 'يظهر عندما',
    'Source': 'المصدر',
    'Fit': 'الملاءمة',
    'Symbology': 'نوع الرمز',
    'Show text': 'إظهار النص',
    'Font size': 'حجم الخط',
    'Color': 'اللون',
    'Background': 'الخلفية',
    'Kind': 'النوع',
    'Stroke': 'الحد',
    'Stroke width': 'سماكة الحد',
    'Line style': 'نمط الخط',
    'Rising': 'صاعد',
    'Fill': 'التعبئة',
    'Corner radius': 'نصف قطر الزاوية',
    'Chart type': 'نوع المخطط',
    'Percent stacked bar': 'أعمدة مكدسة 100٪',
    'Stacked area': 'مساحة مكدسة',
    'Combo': 'عمود وخط',
    'Waterfall': 'شلال',
    'Gauge': 'مقياس',
    'Bullet': 'رصاصة',
    'Funnel': 'قمع',
    'Shape map': 'خريطة أشكال',
    'Map': 'خريطة',
    'Remove map file': 'حذف ملف الخريطة',
    'Region color': 'لون المنطقة',
    'Row.color — #hex or a palette name for each region':
        'Row.color — لون #hex أو اسم من لوحة الألوان لكل منطقة',
    'This file is not longitude and latitude. Reproject it to WGS84 (EPSG:4326) and import it again.':
        'هذا الملف ليس بخطوط الطول والعرض. أعد إسقاطه إلى WGS84 (EPSG:4326) ثم استورده من جديد.',
    'Shapes': 'الأشكال',
    'Region key': 'مفتاح المنطقة',
    'LY, LBY, or Libya': 'LY أو LBY أو Libya أو ليبيا',
    'Row.code — the column that matches the shape key':
        'Row.code — العمود الذي يطابق مفتاح الشكل',
    'Row.amount — the number colored on each region':
        'Row.amount — الرقم الذي يلوّن كل منطقة',
    'Shape key field': 'حقل مفتاح الشكل',
    'Attribute that matches the table, such as a district code':
        'عمود الملف الذي يطابق الجدول، مثل رمز الحي',
    'Label field': 'حقل التسمية',
    'The column drawn on each region': 'العمود الذي يُرسم اسماً لكل منطقة',
    'A map column, or a formula such as CONCAT(name, "\\n", code) or CONCAT(Row.name, "\\n", Row.code)':
        'عمود من ملف الخريطة، أو صيغة مثل CONCAT(name, "\\n", code) أو CONCAT(Row.name, "\\n", Row.code)',
    'Region labels': 'تسميات المناطق',
    'Low color': 'لون القيمة الصغرى',
    'High color': 'لون القيمة الكبرى',
    'Empty color': 'لون بلا قيمة',
    'Import shapes…': 'استيراد أشكال…',
    'world': 'دول العالم',
    'Scatter': 'نقطي',
    'Bubble': 'فقاعات',
    'Radar': 'رادار',
    'Heatmap': 'خريطة حرارة',
    'Sparkline': 'شرارة',
    'Extruded bar': 'عمود مجسّم',
    'Extruded pie': 'دائري مجسّم',
    'Extruded donut': 'حلقي مجسّم',
    'Plot': 'الرسم',
    'Smooth': 'منحني ناعم',
    'Markers': 'علامات',
    'On': 'ظاهر',
    'Off': 'مخفي',
    'Marker size': 'حجم العلامة',
    'Line width': 'سماكة الخط',
    'Depth': 'العمق',
    'Skew': 'الميل',
    'Hole': 'فتحة الوسط',
    'Start angle': 'زاوية البداية',
    'Axis minimum': 'أدنى المحور',
    'Axis maximum': 'أعلى المحور',
    'Secondary minimum': 'أدنى المحور الثاني',
    'Secondary maximum': 'أعلى المحور الثاني',
    'Target': 'الهدف',
    'Range bands': 'نطاقات القياس',
    'Percent labels': 'تسميات نسبية',
    'Last is total': 'الأخير إجمالي',
    'Increase color': 'لون الزيادة',
    'Decrease color': 'لون النقص',
    'Total color': 'لون الإجمالي',
    'Series style': 'شكل السلسلة',
    'Secondary axis': 'المحور الثاني',
    'X value': 'قيمة س',
    'Size value': 'قيمة الحجم',
    'Point total': 'إجمالي',
    'Title': 'العنوان',
    'Chart title': 'عنوان المخطط',
    'Legend': 'وسيلة الإيضاح',
    'Value labels': 'تسميات القيم',
    'Grid lines': 'خطوط الشبكة',
    'Axes': 'المحاور',
    'Value format': 'تنسيق القيمة',
    'Data set': 'مجموعة البيانات',
    'Category': 'الفئة',
    'Aggregate': 'التجميع',
    'Sort by': 'ترتيب حسب',
    'Descending': 'تنازلي',
    'Top N (0 = all)': 'أعلى N (0 = الكل)',
    'Static points': 'نقاط ثابتة',
    'Series (0 = static points)': 'السلاسل (0 = نقاط ثابتة)',
    'Font family': 'عائلة الخط',
    'Text color': 'لون النص',
    'Value': 'القيمة',
    'Ask before preview': 'اسأل قبل المعاينة',
    'Required': 'مطلوب',
    'Label': 'التسمية',
    'Border color': 'لون الإطار',
    'Border width': 'سماكة الإطار',
    'Format': 'التنسيق',
    'Align': 'المحاذاة',
    'Vertical align': 'المحاذاة العمودية',
    'Direction': 'الاتجاه',
    'Can grow': 'يتمدد',
    'Can shrink': 'ينكمش',
    'Word wrap': 'التفاف النص',
    'Padding': 'الحشوة',
    'Line spacing': 'تباعد الأسطر',
    'Family': 'العائلة',
    'Size': 'الحجم',
    'Bold': 'عريض',
    'Italic': 'مائل',
    'Underline': 'تسطير',
    'Columns': 'الأعمدة',
    'Show header': 'إظهار الرأس',
    'Repeat header': 'تكرار الرأس',
    'Show grid': 'إظهار الشبكة',
    'Totals row': 'صف الإجماليات',
    'Row height': 'ارتفاع الصف',
    'Header height': 'ارتفاع الرأس',
    'Cell padding': 'حشوة الخلية',
    'Header font size': 'حجم خط الرأس',
    'Bold header': 'رأس عريض',
    'Header fill': 'تعبئة الرأس',
    'Header text': 'نص الرأس',
    'Stripe fill': 'تعبئة الصفوف المتناوبة',
    'Grid color': 'لون الشبكة',
    'Grid width': 'سماكة الشبكة',
    'Header': 'الرأس',
    'Field': 'الحقل',
    'Filter': 'التصفية',
    'Group by': 'تجميع حسب',
    'Print on first page': 'الطباعة في الصفحة الأولى',
    'Print on last page': 'الطباعة في الصفحة الأخيرة',
    'New page before': 'صفحة جديدة قبله',
    'New page after': 'صفحة جديدة بعده',
    'Keep together': 'إبقاؤه متصلًا',
    'Repeat on every page': 'التكرار في كل صفحة',
    'Right to left': 'من اليمين لليسار',
    'Mirror layout in RTL': 'عكس التخطيط في RTL',
    'Default font': 'الخط الافتراضي',
    'Default font size': 'حجم الخط الافتراضي',
    'Unit': 'الوحدة',
    'Page size': 'حجم الصفحة',
    'Orientation': 'الاتجاه',
    'X measured from': 'قياس X من',
    'X (RTL)': 'X (من اليمين)',
    'Type': 'النوع',
    'Insert format': 'تنسيق الإدراج',
    'Description': 'الوصف',
    'Formula': 'الصيغة',
    'Error': 'خطأ',
    'Row': 'الصف',
    'Items': 'العناصر',
    'Date': 'تاريخ',
    // Hints.
    'auto': 'تلقائي',
    'inherit': 'موروث',
    'none': 'بدون',
    'always': 'دائمًا',
    'all rows': 'كل الصفوف',
    'text, {{ }} allowed': 'نص، ويُسمح بـ {{ }}',
    'shown in autocomplete': 'يظهر في الإكمال التلقائي',
    'comma separated colors': 'ألوان مفصولة بفواصل',
    'Embedded image name, data URI, or {{expression}}':
        'اسم صورة مضمّنة أو data URI أو {{تعبير}}',
    'Letters, digits, _ and -; used as <Image source="…">':
        'حروف وأرقام و_ و-؛ يُستخدم في <Image source="…">',
    'Filter installed fonts': 'ابحث في الخطوط المثبتة',
    'Type to search': 'اكتب للبحث',
    'stored values': 'قيم مخزنة',
    'qty * price — columns of this table by name':
        'qty * price — أعمدة هذا الجدول بالاسم مباشرة',
    // Options.
    'None': 'بدون',
    'Auto': 'تلقائي',
    'RTL': 'يمين ← يسار',
    'LTR': 'يسار ← يمين',
    'QR': 'QR',
    'PT': 'نقطة',
    'MM': 'مم',
    'CM': 'سم',
    'PX': 'بكسل',
    'IN': 'إنش',
    'Left': 'يسار',
    'Right': 'يمين',
    'Center': 'وسط',
    'Top': 'أعلى',
    'Middle': 'منتصف',
    'Bottom': 'أسفل',
    'Justify': 'ضبط',
    'Start': 'البداية',
    'End': 'النهاية',
    'Contain': 'احتواء',
    'Cover': 'تغطية',
    'Fill width': 'ملء العرض',
    'Stretch': 'تمديد',
    'Portrait': 'عمودي',
    'Landscape': 'أفقي',
    'Solid': 'متصل',
    'Dashed': 'متقطع',
    'Dotted': 'منقط',
    'Rounded rectangle': 'مستطيل بزوايا دائرية',
    'Bar': 'أعمدة',
    'Column chart': 'أعمدة',
    'Pie': 'دائري',
    'Donut': 'حلقي',
    'Area': 'مساحي',
    'Sum': 'المجموع',
    'Count': 'العدد',
    'Average': 'المتوسط',
    'Min': 'الأدنى',
    'Max': 'الأعلى',
    'Number': 'رقم',
    'Boolean': 'منطقي',
    'List': 'قائمة',
    'Expression': 'تعبير',
    'Currency': 'عملة',
    'Percent': 'نسبة مئوية',
    'Integer': 'عدد صحيح',
    'Decimal': 'عدد عشري',
    // Actions.
    'Remove': 'حذف',
    'Delete': 'حذف',
    'Rename': 'إعادة تسمية',
    'Add color': 'إضافة لون',
    'Add variable': 'إضافة متغير',
    'Insert into report': 'إدراج في التقرير',
    'Import image…': 'استيراد صورة…',
    'Replace image…': 'استبدال الصورة…',
    'Replace': 'استبدال',
    'The chosen file is not a PNG or JPEG image':
        'الملف المختار ليس صورة PNG أو JPEG',
    'Import font file…': 'استيراد ملف خط…',
    'Remove image': 'حذف الصورة',
    'Remove font': 'حذف الخط',
    'Remove variable': 'حذف المتغير',
    'Embed': 'تضمين',
    'Embedding…': 'جارٍ التضمين…',
    'New field': 'حقل جديد',
    'Delete field': 'حذف الحقل',
    'Add row': 'إضافة صف',
    'Add column': 'إضافة عمود',
    'Add calculated column': 'إضافة عمود محسوب',
    'Add constant column': 'إضافة عمود ثابت',
    'Value on every row': 'قيمة لكل الصفوف',
    'Writes this into every row': 'تُكتب هذه القيمة في كل الصفوف',
    'Attributes of the map file': 'خصائص ملف الخريطة',
    'Rows come from the map file': 'الصفوف تأتي من ملف الخريطة',
    'This table comes from the map file. Remove the map file to drop it.':
        'هذا الجدول من ملف الخريطة. احذف ملف الخريطة لإزالته.',
    'Delete table': 'حذف الجدول',
    'Delete column': 'حذف العمود',
    'New table': 'جدول جديد',
    'Import CSV / JSON…': 'استيراد CSV / JSON…',
    'Discard sample data': 'تجاهل البيانات التجريبية',
    'Add field': 'إضافة حقل',
    'Remove last column': 'حذف آخر عمود',
    // Fonts page.
    'Embedded fonts': 'الخطوط المضمّنة',
    'Add a font': 'إضافة خط',
    'Installed font…': 'خط مثبّت…',
    'Add an installed font': 'إضافة خط مثبّت على الجهاز',
    'Search installed fonts': 'ابحث في خطوط الجهاز',
    'Type to search, then pick a font': 'اكتب للبحث ثم اختر خطًا',
    'No embedded fonts yet': 'لا توجد خطوط مضمّنة بعد',
    'Embedded fonts are saved inside the .qrep so the report looks the same on every machine.':
        'الخطوط المضمّنة تُحفظ داخل ملف ‎.qrep‎ ليظهر التقرير بنفس الشكل على أي جهاز.',
    'Report default': 'الخط الافتراضي للتقرير',
    'Make report default': 'اجعله الخط الافتراضي',
    'Used by': 'مستخدم في',
    'All text without its own font': 'كل نص بلا خط خاص',
    'No elements': 'لا عناصر',
    'Regular': 'عادي',
    'Regular + Bold': 'عادي + عريض',
    'In this report': 'في هذا التقرير',
    'Installed on this device': 'مثبّت على الجهاز',
    'Built in': 'مدمج',
    'Looking for installed fonts…': 'جارٍ البحث عن الخطوط المثبتة…',
    'No installed font matches': 'لا يوجد خط مثبّت مطابق',
    'No embeddable TrueType fonts found':
        'لم يُعثر على خطوط TrueType قابلة للتضمين',
    'Could not list installed fonts': 'تعذّر عرض الخطوط المثبتة',
    // Images page.
    'Embedded images': 'الصور المضمّنة',
    'No embedded images yet': 'لا توجد صور مضمّنة بعد',
    'Imported images are saved inside the .qrep.':
        'الصور المستوردة تُحفظ داخل ملف ‎.qrep‎.',
    'No embedded images. The host app has not enabled image import.':
        'لا توجد صور مضمّنة، والتطبيق لم يفعّل استيراد الصور.',
    // Variables page.
    'Template variables': 'متغيرات القالب',
    'New folder': 'مجلد جديد',
    'Expand all': 'توسيع الكل',
    'Collapse all': 'طي الكل',
    'Variable': 'متغير',
    'Folder': 'مجلد',
    'Folder name': 'اسم المجلد',
    'Add variable here': 'إضافة متغير هنا',
    'Delete folder': 'حذف المجلد',
    'Select a variable or folder to edit it.':
        'اختر متغيرًا أو مجلدًا لتعديله.',
    'No template variables yet': 'لا توجد متغيرات بعد',
    'Variables hold values you reuse across the report, such as a company name or a tax rate. Use dots to group them: stats.sum.':
        'المتغيرات تحفظ قيمًا تتكرر في التقرير مثل اسم الشركة أو نسبة الضريبة. استخدم النقطة لتجميعها: stats.sum.',
    'No template variables.': 'لا توجد متغيرات.',
    'Reference': 'المرجع',
    // Toolbar and menus.
    'Templates': 'القوالب',
    'Start from a ready-made report': 'ابدأ من تقرير جاهز',
    'Insert or edit template variables': 'إدراج المتغيرات أو تعديلها',
    'Blank report': 'تقرير فارغ',
    'New variable…': 'متغير جديد…',
    'Edit variables': 'تعديل المتغيرات',
    'Insert at the caret': 'إدراج عند المؤشر',
    'Insert as a text box': 'إدراج كمربع نص',
    'Select (Esc)': 'تحديد (Esc)',
    'Insert': 'إدراج',
    'Pick, move, and resize what is already on the page.':
        'اختر ما على الصفحة ثم حرّكه أو غيّر مقاسه.',
    'Fixed words, or a field such as {{Data.customer}}.':
        'نص ثابت، أو حقل مثل {{Data.customer}}.',
    'Page number': 'رقم الصفحة',
    'Prints the number of this page.': 'يطبع رقم هذه الصفحة.',
    'Page count': 'عدد الصفحات',
    'This page and the page count, such as 2 / 5.':
        'هذه الصفحة وعدد الصفحات، مثل 2 / 5.',
    'Print date': 'تاريخ الطباعة',
    'The date the report is printed.': 'تاريخ طباعة التقرير.',
    'Report name': 'اسم التقرير',
    'The name stored on the report.': 'الاسم المحفوظ على التقرير.',
    'Row number': 'رقم الصف',
    '1, 2, 3… for the current record. Place it in the detail band.':
        '١، ٢، ٣… للسجل الحالي. ضعه في شريط التفاصيل.',
    'Column total': 'مجموع العمود',
    'The sum of a column. Change Row.total to your own field.':
        'مجموع عمود. غيّر Row.total إلى اسم حقلك.',
    'Signature': 'التوقيع',
    'A line to sign on, with a caption underneath.':
        'خط للتوقيع، وتحته عبارة توضيحية.',
    'A picture. Import a PNG or JPEG and it is stored inside the report.':
        'صورة. استورد PNG أو JPEG فتُحفظ داخل التقرير.',
    'One row for every record. Bind each column to a field.':
        'صف لكل سجل. اربط كل عمود بحقل.',
    'A Code 128 barcode from a number or a field.':
        'باركود Code 128 من رقم أو من حقل.',
    'A square code for a link, a reference, or a field.':
        'رمز مربّع لرابط أو مرجع أو حقل.',
    'A straight rule for separators and underlines.':
        'خط مستقيم للفواصل والتسطير.',
    'A box. Fill it, or leave it as an outline.':
        'صندوق. عبّئه أو اتركه إطارًا فقط.',
    'Rounded box': 'صندوق دائري الزوايا',
    'A box with rounded corners, for a card or a frame.':
        'صندوق بزوايا دائرية، لبطاقة أو إطار.',
    'A circle or an oval.': 'دائرة أو شكل بيضوي.',
    'Columns, lines, pies, and the other charts, bound to a table.':
        'أعمدة وخطوط ودوائر وبقية المخططات، مربوطة بجدول.',
    'Regions from a shape file. Color each one from a column, joined by a key.':
        'مناطق من ملف أشكال. لوّن كل منطقة من عمود، والربط بالمفتاح.',
    'Text box': 'مربع نص',
    'Repeating table': 'جدول متكرر',
    'Undo (Ctrl+Z)': 'تراجع (Ctrl+Z)',
    'Redo (Ctrl+Y)': 'إعادة (Ctrl+Y)',
    'Duplicate (Ctrl+D)': 'تكرار (Ctrl+D)',
    'Delete (Del)': 'حذف (Del)',
    'Add band': 'إضافة شريط',
    'Grid and snapping': 'الشبكة والالتقاط',
    'Zoom out (Ctrl+-)': 'تصغير (Ctrl+-)',
    'Zoom in (Ctrl+=)': 'تكبير (Ctrl+=)',
    'Fit page width': 'ملاءمة عرض الصفحة',
    'Export with preview data': 'تصدير ببيانات المعاينة',
    'Export': 'تصدير',
    'PDF document': 'مستند PDF',
    'Excel workbook': 'مصنف Excel',
    'Word document': 'مستند Word',
    'Align left': 'محاذاة لليسار',
    'Align centers': 'توسيط أفقي',
    'Align right': 'محاذاة لليمين',
    'Align top': 'محاذاة للأعلى',
    'Align middles': 'توسيط عمودي',
    'Align bottom': 'محاذاة للأسفل',
    'Same width': 'نفس العرض',
    'Same height': 'نفس الارتفاع',
    'Design': 'تصميم',
    'Preview': 'معاينة',
    'Live preview (F5)': 'معاينة حية (F5)',
    'Back to design (F5)': 'رجوع للتصميم (F5)',
    'Back to design (F6)': 'رجوع للتصميم (F6)',
    'Explore and edit the report data (F6)':
        'استعراض بيانات التقرير وتعديلها (F6)',
    'Edit text': 'تعديل النص',
    'Cut': 'قص',
    'Copy': 'نسخ',
    'Paste': 'لصق',
    'Duplicate': 'تكرار',
    'Bring to front': 'إحضار للأمام',
    'Send to back': 'إرسال للخلف',
    'Edit cell': 'تعديل الخلية',
    'Clear cell': 'مسح الخلية',
    'Insert row above': 'إدراج صف أعلاه',
    'Insert row below': 'إدراج صف أسفله',
    'Delete row': 'حذف الصف',
    'No template variables yet.': 'لا توجد متغيرات بعد.',
    'No color': 'بلا لون',
    'TEMPLATE PALETTE': 'ألوان القالب',
    'THEME COLORS': 'ألوان السمة',
    'STANDARD COLORS': 'ألوان قياسية',
    'Nothing to preview': 'لا يوجد ما يُعرض',
    // Data explorer.
    'The preview data comes from the host app and is read-only':
        'بيانات المعاينة من التطبيق وهي للقراءة فقط',
    'JSON data must be an object or an array of objects':
        'بيانات JSON يجب أن تكون كائنًا أو مصفوفة كائنات',
    'Supplied by the host app (read-only)': 'من التطبيق (للقراءة فقط)',
    'Saved with the report': 'محفوظة مع التقرير',
    'Generated from the layout; edits save it with the report':
        'مولّدة من التخطيط؛ أي تعديل يحفظها مع التقرير',
    'No single-value fields. Add one with "+ Field".':
        'لا توجد حقول مفردة. أضف حقلًا بزر «+ حقل».',
    'The host data has no rows for this table.':
        'بيانات التطبيق لا تحتوي صفوفًا لهذا الجدول.',
    'Select a single element to rename it': 'حدد عنصرًا واحدًا لإعادة تسميته',
    'saved in the .qrep': 'محفوظة داخل ملف ‎.qrep‎',
    'No matching fonts': 'لا توجد خطوط مطابقة',
    'Point': 'النقطة',
    'Remove band': 'حذف الشريط',
    'ReportHeader': 'رأس التقرير',
    'PageHeader': 'رأس الصفحة',
    'GroupHeader': 'رأس المجموعة',
    'GroupFooter': 'تذييل المجموعة',
    'PageFooter': 'تذييل الصفحة',
    'ReportSummary': 'ملخص التقرير',
    'calculated': 'محسوب',
    'read-only': 'للقراءة فقط',
    'host data (read-only)': 'بيانات التطبيق (للقراءة فقط)',
    'Loaded': 'تم تحميل',
    'Exporting': 'جارٍ تصدير',
    'Exported': 'تم تصدير',
    'Export failed': 'فشل التصدير',
    'Print': 'طباعة',
    'Print with preview data (Ctrl+P)': 'طباعة ببيانات المعاينة (Ctrl+P)',
    'Preparing to print': 'جارٍ تجهيز الطباعة',
    'Print failed': 'فشلت الطباعة',
    'Distribute horizontally': 'توزيع أفقي',
    'Distribute vertically': 'توزيع عمودي',
    'DATA': 'البيانات',
    'Field Explorer': 'مستكشف الحقول',
    'Database Fields': 'حقول قاعدة البيانات',
    '+ Formula': '+ صيغة',
    'Add a table before a formula field': 'أضف جدولاً قبل الحقل الاحتسابي',
    '+ Field': '+ حقل',
    '+ Row': '+ صف',
    '+ Column': '+ عمود',
    'ƒx Column': 'ƒx عمود',
    'Import…': 'استيراد…',
    'host data · read-only': 'بيانات التطبيق · للقراءة فقط',
    'sample data': 'بيانات تجريبية',
    'generated': 'مولّدة',
    'This table has no columns yet. Add a column or import a CSV or JSON file.':
        'هذا الجدول بلا أعمدة بعد. أضف عمودًا أو استورد ملف CSV أو JSON.',
    'No rows yet. Add a row with "+ Row" or import a CSV / JSON file.':
        'لا توجد صفوف بعد. أضف صفًا بزر «+ صف» أو استورد ملف CSV / JSON.',
    'Report data explorer': 'مستعرض بيانات التقرير',
    // Tooltips of inspector buttons.
    'Collapse': 'طي',
    'Expand': 'توسيع',
    'Increase': 'زيادة',
    'Decrease': 'إنقاص',
    'Pick a color': 'اختر لونًا',
    'Suggestions': 'اقتراحات',
  };
}

class _Plural {
  const _Plural(
    this.english,
    this.one,
    this.oneSuffix,
    this.two,
    this.few,
    this.many,
  );

  final String english;
  final String one;
  final String oneSuffix;
  final String two;
  final String few;
  final String many;
}
