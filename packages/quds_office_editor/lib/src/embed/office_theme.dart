import 'dart:ui';

/// How the host wants the surface to behave when embedded.
enum OfficeInteractionMode {
  /// Scroll/zoom only. No caret, handles, IME, or mutations.
  viewing,

  /// Selection and copy. No IME or document mutations.
  selecting,

  /// Full Office-like editing.
  editing,
}

/// Visual tokens for every custom RenderBox surface.
class OfficeTheme {
  /// OfficeTheme API.
  const OfficeTheme({
    required this.canvasBackground,
    required this.pageBackground,
    required this.pageBorder,
    required this.caret,
    required this.selectionFill,
    required this.selectionStroke,
    required this.gridLine,
    required this.frozenFill,
    required this.headerFill,
    required this.headerText,
    required this.chromeFill,
    required this.chromeText,
    required this.handleStroke,
    required this.handleFill,
    required this.snapGuide,
    required this.slideBackground,
    required this.focusRing,
    this.fontFamily,
  });

  /// canvasBackground API.
  final Color canvasBackground;

  /// pageBackground API.
  final Color pageBackground;

  /// pageBorder API.
  final Color pageBorder;

  /// caret API.
  final Color caret;

  /// selectionFill API.
  final Color selectionFill;

  /// selectionStroke API.
  final Color selectionStroke;

  /// gridLine API.
  final Color gridLine;

  /// frozenFill API.
  final Color frozenFill;

  /// headerFill API.
  final Color headerFill;

  /// headerText API.
  final Color headerText;

  /// chromeFill API.
  final Color chromeFill;

  /// chromeText API.
  final Color chromeText;

  /// handleStroke API.
  final Color handleStroke;

  /// handleFill API.
  final Color handleFill;

  /// snapGuide API.
  final Color snapGuide;

  /// slideBackground API.
  final Color slideBackground;

  /// focusRing API.
  final Color focusRing;

  /// fontFamily API.
  final String? fontFamily;

  /// light API.
  static const OfficeTheme light = OfficeTheme(
    canvasBackground: Color(0xFF5B5B5B),
    pageBackground: Color(0xFFFFFFFF),
    pageBorder: Color(0xFFB0B0B0),
    caret: Color(0xC8000000),
    selectionFill: Color(0x332E75B6),
    selectionStroke: Color(0xFF2E75B6),
    gridLine: Color(0xFFD0D0D0),
    frozenFill: Color(0xFFE8E8E8),
    headerFill: Color(0xFFF3F3F3),
    headerText: Color(0xFF444444),
    chromeFill: Color(0xFFF7F7F7),
    chromeText: Color(0xFF222222),
    handleStroke: Color(0xFF2E75B6),
    handleFill: Color(0xFFFFFFFF),
    snapGuide: Color(0xFFFF4FA0),
    slideBackground: Color(0xFFFFFFFF),
    focusRing: Color(0xFF2E75B6),
  );

  /// dark API.
  static const OfficeTheme dark = OfficeTheme(
    canvasBackground: Color(0xFF1E1E1E),
    pageBackground: Color(0xFF2B2B2B),
    pageBorder: Color(0xFF555555),
    caret: Color(0xC8F2F2F2),
    selectionFill: Color(0x664478C4),
    selectionStroke: Color(0xFF5B9BD5),
    gridLine: Color(0xFF3F3F3F),
    frozenFill: Color(0xFF333333),
    headerFill: Color(0xFF2A2A2A),
    headerText: Color(0xFFDDDDDD),
    chromeFill: Color(0xFF252525),
    chromeText: Color(0xFFEEEEEE),
    handleStroke: Color(0xFF5B9BD5),
    handleFill: Color(0xFF2B2B2B),
    snapGuide: Color(0xFFFF7AC3),
    slideBackground: Color(0xFF2B2B2B),
    focusRing: Color(0xFF5B9BD5),
  );

  /// highContrast API.
  static const OfficeTheme highContrast = OfficeTheme(
    canvasBackground: Color(0xFF000000),
    pageBackground: Color(0xFF000000),
    pageBorder: Color(0xFFFFFFFF),
    caret: Color(0xFFFFFF00),
    selectionFill: Color(0x99FFFF00),
    selectionStroke: Color(0xFFFFFF00),
    gridLine: Color(0xFFFFFFFF),
    frozenFill: Color(0xFF1A1A1A),
    headerFill: Color(0xFF000000),
    headerText: Color(0xFFFFFFFF),
    chromeFill: Color(0xFF000000),
    chromeText: Color(0xFFFFFFFF),
    handleStroke: Color(0xFFFFFF00),
    handleFill: Color(0xFF000000),
    snapGuide: Color(0xFF00FFFF),
    slideBackground: Color(0xFF000000),
    focusRing: Color(0xFFFFFF00),
  );

  /// copyWith API.
  OfficeTheme copyWith({
    Color? canvasBackground,
    Color? pageBackground,
    Color? pageBorder,
    Color? caret,
    Color? selectionFill,
    Color? selectionStroke,
    Color? gridLine,
    Color? frozenFill,
    Color? headerFill,
    Color? headerText,
    Color? chromeFill,
    Color? chromeText,
    Color? handleStroke,
    Color? handleFill,
    Color? snapGuide,
    Color? slideBackground,
    Color? focusRing,
    String? fontFamily,
  }) {
    return OfficeTheme(
      canvasBackground: canvasBackground ?? this.canvasBackground,
      pageBackground: pageBackground ?? this.pageBackground,
      pageBorder: pageBorder ?? this.pageBorder,
      caret: caret ?? this.caret,
      selectionFill: selectionFill ?? this.selectionFill,
      selectionStroke: selectionStroke ?? this.selectionStroke,
      gridLine: gridLine ?? this.gridLine,
      frozenFill: frozenFill ?? this.frozenFill,
      headerFill: headerFill ?? this.headerFill,
      headerText: headerText ?? this.headerText,
      chromeFill: chromeFill ?? this.chromeFill,
      chromeText: chromeText ?? this.chromeText,
      handleStroke: handleStroke ?? this.handleStroke,
      handleFill: handleFill ?? this.handleFill,
      snapGuide: snapGuide ?? this.snapGuide,
      slideBackground: slideBackground ?? this.slideBackground,
      focusRing: focusRing ?? this.focusRing,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

/// Target form-factor. [automatic] is resolved from layout constraints.
enum OfficeFormFactor { phone, tablet, desktop, automatic }

/// Control spacing for host chrome (ribbons stay in the host).
enum OfficeDensity { compact, comfortable, spacious }

/// Host-facing chrome and interaction flags for an embedded surface.
class OfficeSurfaceConfig {
  /// OfficeSurfaceConfig API.
  const OfficeSurfaceConfig({
    this.mode = OfficeInteractionMode.editing,
    this.theme = OfficeTheme.light,
    this.showRulers = true,
    this.showFormulaBar = true,
    this.showGridHeaders = true,
    this.showGridlines = true,
    this.showSlideHandles = true,
    this.enableUndo = true,
    this.autofocus = false,
    this.textDirection = TextDirection.ltr,
    this.strings = OfficeStrings.english,
    this.formFactor = OfficeFormFactor.automatic,
    this.density = OfficeDensity.comfortable,
    this.adaptiveChrome = true,
    this.showFindChrome = false,
    this.interactiveRulers = true,
    this.showNavigationPane = false,
    this.showNotesPane = false,
  });

  /// mode API.
  final OfficeInteractionMode mode;

  /// theme API.
  final OfficeTheme theme;

  /// showRulers API.
  final bool showRulers;

  /// showFormulaBar API.
  final bool showFormulaBar;

  /// showGridHeaders API.
  final bool showGridHeaders;

  /// showGridlines API.
  final bool showGridlines;

  /// showSlideHandles API.
  final bool showSlideHandles;

  /// enableUndo API.
  final bool enableUndo;

  /// autofocus API.
  final bool autofocus;

  /// textDirection API.
  final TextDirection textDirection;

  /// strings API.
  final OfficeStrings strings;

  /// formFactor API.
  final OfficeFormFactor formFactor;

  /// density API.
  final OfficeDensity density;

  /// When true, phone widths hide rulers / side panes unless the host forces them.
  final bool adaptiveChrome;

  /// showFindChrome API.
  final bool showFindChrome;

  /// interactiveRulers API.
  final bool interactiveRulers;

  /// showNavigationPane API.
  final bool showNavigationPane;

  /// showNotesPane API.
  final bool showNotesPane;

  /// resolveFormFactor API.
  OfficeFormFactor resolveFormFactor(Size size) {
    if (formFactor != OfficeFormFactor.automatic) {
      return formFactor;
    }
    if (size.shortestSide < 600) {
      return OfficeFormFactor.phone;
    }
    if (size.shortestSide < 840) {
      return OfficeFormFactor.tablet;
    }
    return OfficeFormFactor.desktop;
  }

  /// touchPreferred API.
  bool touchPreferred(Size size) {
    final OfficeFormFactor factor = resolveFormFactor(size);
    return factor == OfficeFormFactor.phone ||
        factor == OfficeFormFactor.tablet;
  }

  /// chromeScale API.
  double get chromeScale => switch (density) {
    OfficeDensity.compact => 0.85,
    OfficeDensity.comfortable => 1,
    OfficeDensity.spacious => 1.2,
  };

  /// effectiveShowRulers API.
  bool effectiveShowRulers(Size size) {
    if (!showRulers) {
      return false;
    }
    if (!adaptiveChrome) {
      return true;
    }
    return resolveFormFactor(size) != OfficeFormFactor.phone;
  }

  /// effectiveShowNavigationPane API.
  bool effectiveShowNavigationPane(Size size) {
    if (!showNavigationPane) {
      return false;
    }
    if (!adaptiveChrome) {
      return true;
    }
    return resolveFormFactor(size) == OfficeFormFactor.desktop;
  }

  /// allowsMutation API.
  bool get allowsMutation => mode == OfficeInteractionMode.editing;

  /// allowsSelection API.
  bool get allowsSelection =>
      mode == OfficeInteractionMode.editing ||
      mode == OfficeInteractionMode.selecting;

  /// showsCaret API.
  bool get showsCaret => mode == OfficeInteractionMode.editing;

  /// copyWith API.
  OfficeSurfaceConfig copyWith({
    OfficeInteractionMode? mode,
    OfficeTheme? theme,
    bool? showRulers,
    bool? showFormulaBar,
    bool? showGridHeaders,
    bool? showGridlines,
    bool? showSlideHandles,
    bool? enableUndo,
    bool? autofocus,
    TextDirection? textDirection,
    OfficeStrings? strings,
    OfficeFormFactor? formFactor,
    OfficeDensity? density,
    bool? adaptiveChrome,
    bool? showFindChrome,
    bool? interactiveRulers,
    bool? showNavigationPane,
    bool? showNotesPane,
  }) {
    return OfficeSurfaceConfig(
      mode: mode ?? this.mode,
      theme: theme ?? this.theme,
      showRulers: showRulers ?? this.showRulers,
      showFormulaBar: showFormulaBar ?? this.showFormulaBar,
      showGridHeaders: showGridHeaders ?? this.showGridHeaders,
      showGridlines: showGridlines ?? this.showGridlines,
      showSlideHandles: showSlideHandles ?? this.showSlideHandles,
      enableUndo: enableUndo ?? this.enableUndo,
      autofocus: autofocus ?? this.autofocus,
      textDirection: textDirection ?? this.textDirection,
      strings: strings ?? this.strings,
      formFactor: formFactor ?? this.formFactor,
      density: density ?? this.density,
      adaptiveChrome: adaptiveChrome ?? this.adaptiveChrome,
      showFindChrome: showFindChrome ?? this.showFindChrome,
      interactiveRulers: interactiveRulers ?? this.interactiveRulers,
      showNavigationPane: showNavigationPane ?? this.showNavigationPane,
      showNotesPane: showNotesPane ?? this.showNotesPane,
    );
  }
}

/// Accessible labels for screen readers and chrome (English / Arabic).
class OfficeStrings {
  /// OfficeStrings API.
  const OfficeStrings({
    required this.wordEditor,
    required this.sheetEditor,
    required this.slideEditor,
    required this.formulaBar,
    required this.pageLabel,
    required this.cellLabel,
    required this.shapeLabel,
    required this.viewing,
    required this.editing,
    required this.undo,
    required this.redo,
    this.speakerNotes = 'Speaker notes',
    this.cut = 'Cut',
    this.copy = 'Copy',
    this.paste = 'Paste',
    this.pasteKeepSource = 'Keep source formatting',
    this.pasteMerge = 'Merge formatting',
    this.pasteTextOnly = 'Keep text only',
    this.pictureLabel = 'Picture',
    this.cropMode = 'Crop mode',
    this.pictureHint =
        'Drag handles to resize. Drag the picture to move. Press C to crop. Shift plus arrows resize.',
    this.followLinkHint = 'Press Ctrl and click to follow the link',
    this.selectAll = 'Select all',
    this.insertComment = 'New comment',
    this.replyComment = 'Reply',
    this.resolveComment = 'Resolve',
    this.reopenComment = 'Reopen',
    this.deleteComment = 'Delete comment',
    this.insertRowAbove = 'Insert row above',
    this.insertRowBelow = 'Insert row below',
    this.insertColumnLeft = 'Insert column left',
    this.insertColumnRight = 'Insert column right',
    this.deleteRow = 'Delete row',
    this.deleteColumn = 'Delete column',
    this.deleteTable = 'Delete table',
    this.autoFitContents = 'AutoFit contents',
    this.autoFitWindow = 'AutoFit window',
    this.autoFitFixed = 'Fixed column width',
    this.mergeTableCells = 'Merge cells',
    this.unmergeTableCells = 'Split cells',
    this.insertSheetRow = 'Insert row',
    this.insertSheetColumn = 'Insert column',
    this.deleteSheetRow = 'Delete row',
    this.deleteSheetColumn = 'Delete column',
    this.clearCells = 'Clear contents',
    this.mergeAndCenter = 'Merge & Center',
    this.unmergeCells = 'Unmerge Cells',
    this.deleteShape = 'Delete',
    this.followLink = 'Open link',
    this.hideSlide = 'Hide Slide',
    this.showSlide = 'Show Slide',
    this.copySlide = 'Copy Slide',
    this.pasteSlide = 'Paste Slide',
    this.duplicateSlide = 'Duplicate Slide',
    this.find = 'Find',
    this.replace = 'Replace',
    this.print = 'Print',
    this.properties = 'Properties',
    this.wordCount = 'Word count',
    this.pdfViewer = 'PDF viewer',
    this.pdfEditor = 'PDF editor',
    this.selectPage = 'Select all on page',
    this.zoomIn = 'Zoom in',
    this.zoomOut = 'Zoom out',
    this.actualSize = 'Actual size',
    this.fitWidth = 'Fit width',
    this.fitPage = 'Fit page',
    this.previousPage = 'Previous page',
    this.nextPage = 'Next page',
    this.goToDestination = 'Go to destination',
    this.highlight = 'Highlight',
    this.strikethrough = 'Strikethrough',
    this.underline = 'Underline',
    this.deleteAnnotation = 'Delete annotation',
    this.rotatePage = 'Rotate page',
    this.rotatePageLeft = 'Rotate 90° left',
    this.insertPage = 'Insert blank page',
    this.deletePage = 'Delete page',
    this.pdfMenuSelection = 'Selection',
    this.pdfMenuView = 'View',
    this.pdfMenuPage = 'Page',
    this.pdfMenuMarkup = 'Markup',
  });

  /// wordEditor API.
  final String wordEditor;

  /// sheetEditor API.
  final String sheetEditor;

  /// slideEditor API.
  final String slideEditor;

  /// formulaBar API.
  final String formulaBar;

  /// pageLabel API.
  final String pageLabel;

  /// cellLabel API.
  final String cellLabel;

  /// shapeLabel API.
  final String shapeLabel;

  /// viewing API.
  final String viewing;

  /// editing API.
  final String editing;

  /// undo API.
  final String undo;

  /// redo API.
  final String redo;

  /// speakerNotes API.
  final String speakerNotes;

  /// cut API.
  final String cut;

  /// copy API.
  final String copy;

  /// paste API.
  final String paste;

  /// pasteKeepSource API.
  final String pasteKeepSource;

  /// pasteMerge API.
  final String pasteMerge;

  /// pasteTextOnly API.
  final String pasteTextOnly;

  /// pictureLabel API.
  final String pictureLabel;

  /// cropMode API.
  final String cropMode;

  /// pictureHint API.
  final String pictureHint;

  /// followLinkHint API.
  final String followLinkHint;

  /// selectAll API.
  final String selectAll;

  /// insertComment API.
  final String insertComment;

  /// replyComment API.
  final String replyComment;

  /// resolveComment API.
  final String resolveComment;

  /// reopenComment API.
  final String reopenComment;

  /// deleteComment API.
  final String deleteComment;

  /// insertRowAbove API.
  final String insertRowAbove;

  /// insertRowBelow API.
  final String insertRowBelow;

  /// insertColumnLeft API.
  final String insertColumnLeft;

  /// insertColumnRight API.
  final String insertColumnRight;

  /// deleteRow API.
  final String deleteRow;

  /// deleteColumn API.
  final String deleteColumn;

  /// deleteTable API.
  final String deleteTable;

  /// autoFitContents API.
  final String autoFitContents;

  /// autoFitWindow API.
  final String autoFitWindow;

  /// autoFitFixed API.
  final String autoFitFixed;

  /// mergeTableCells API.
  final String mergeTableCells;

  /// unmergeTableCells API.
  final String unmergeTableCells;

  /// insertSheetRow API.
  final String insertSheetRow;

  /// insertSheetColumn API.
  final String insertSheetColumn;

  /// deleteSheetRow API.
  final String deleteSheetRow;

  /// deleteSheetColumn API.
  final String deleteSheetColumn;

  /// clearCells API.
  final String clearCells;

  /// mergeAndCenter API.
  final String mergeAndCenter;

  /// unmergeCells API.
  final String unmergeCells;

  /// deleteShape API.
  final String deleteShape;

  /// followLink API.
  final String followLink;

  /// hideSlide API.
  final String hideSlide;

  /// showSlide API.
  final String showSlide;

  /// copySlide API.
  final String copySlide;

  /// pasteSlide API.
  final String pasteSlide;

  /// duplicateSlide API.
  final String duplicateSlide;

  /// find API.
  final String find;

  /// replace API.
  final String replace;

  /// print API.
  final String print;

  /// properties API.
  final String properties;

  /// wordCount API.
  final String wordCount;

  /// pdfViewer API.
  final String pdfViewer;

  /// pdfEditor API.
  final String pdfEditor;

  /// selectPage API.
  final String selectPage;

  /// zoomIn API.
  final String zoomIn;

  /// zoomOut API.
  final String zoomOut;

  /// actualSize API.
  final String actualSize;

  /// fitWidth API.
  final String fitWidth;

  /// fitPage API.
  final String fitPage;

  /// previousPage API.
  final String previousPage;

  /// nextPage API.
  final String nextPage;

  /// goToDestination API.
  final String goToDestination;

  /// highlight API.
  final String highlight;

  /// strikethrough API.
  final String strikethrough;

  /// underline API.
  final String underline;

  /// deleteAnnotation API.
  final String deleteAnnotation;

  /// rotatePage API.
  final String rotatePage;

  /// Clockwise is [rotatePage]. This is the other quarter-turn.
  final String rotatePageLeft;

  /// insertPage API.
  final String insertPage;

  /// deletePage API.
  final String deletePage;

  /// pdfMenuSelection API.
  final String pdfMenuSelection;

  /// pdfMenuView API.
  final String pdfMenuView;

  /// pdfMenuPage API.
  final String pdfMenuPage;

  /// pdfMenuMarkup API.
  final String pdfMenuMarkup;

  /// english API.
  static const OfficeStrings english = OfficeStrings(
    wordEditor: 'Word document',
    sheetEditor: 'Spreadsheet',
    slideEditor: 'Slide',
    formulaBar: 'Formula bar',
    pageLabel: 'Page',
    cellLabel: 'Cell',
    shapeLabel: 'Shape',
    viewing: 'Viewing',
    editing: 'Editing',
    undo: 'Undo',
    redo: 'Redo',
    speakerNotes: 'Speaker notes',
    cut: 'Cut',
    copy: 'Copy',
    paste: 'Paste',
    pasteKeepSource: 'Keep source formatting',
    pasteMerge: 'Merge formatting',
    pasteTextOnly: 'Keep text only',
    pictureLabel: 'Picture',
    cropMode: 'Crop mode',
    pictureHint:
        'Drag handles to resize. Drag the picture to move. Press C to crop. Shift plus arrows resize.',
    followLinkHint: 'Press Ctrl and click to follow the link',
    selectAll: 'Select all',
    insertComment: 'New comment',
    replyComment: 'Reply',
    resolveComment: 'Resolve',
    reopenComment: 'Reopen',
    deleteComment: 'Delete comment',
    insertRowAbove: 'Insert row above',
    insertRowBelow: 'Insert row below',
    insertColumnLeft: 'Insert column left',
    insertColumnRight: 'Insert column right',
    deleteRow: 'Delete row',
    deleteColumn: 'Delete column',
    deleteTable: 'Delete table',
    autoFitContents: 'AutoFit contents',
    autoFitWindow: 'AutoFit window',
    autoFitFixed: 'Fixed column width',
    mergeTableCells: 'Merge cells',
    unmergeTableCells: 'Split cells',
    insertSheetRow: 'Insert row',
    insertSheetColumn: 'Insert column',
    deleteSheetRow: 'Delete row',
    deleteSheetColumn: 'Delete column',
    clearCells: 'Clear contents',
    mergeAndCenter: 'Merge & Center',
    unmergeCells: 'Unmerge Cells',
    deleteShape: 'Delete',
    followLink: 'Open link',
    hideSlide: 'Hide Slide',
    showSlide: 'Show Slide',
    copySlide: 'Copy Slide',
    pasteSlide: 'Paste Slide',
    duplicateSlide: 'Duplicate Slide',
    find: 'Find',
    replace: 'Replace',
    print: 'Print',
    properties: 'Properties',
    wordCount: 'Word count',
    pdfViewer: 'PDF viewer',
    pdfEditor: 'PDF editor',
    selectPage: 'Select all on page',
    zoomIn: 'Zoom in',
    zoomOut: 'Zoom out',
    actualSize: 'Actual size',
    fitWidth: 'Fit width',
    fitPage: 'Fit page',
    previousPage: 'Previous page',
    nextPage: 'Next page',
    goToDestination: 'Go to destination',
    highlight: 'Highlight',
    strikethrough: 'Strikethrough',
    underline: 'Underline',
    deleteAnnotation: 'Delete annotation',
    rotatePage: 'Rotate 90° right',
    rotatePageLeft: 'Rotate 90° left',
    insertPage: 'Insert blank page',
    deletePage: 'Delete page',
    pdfMenuSelection: 'Selection',
    pdfMenuView: 'View',
    pdfMenuPage: 'Page',
    pdfMenuMarkup: 'Markup',
  );

  /// arabic API.
  static const OfficeStrings arabic = OfficeStrings(
    wordEditor: 'مستند وورد',
    sheetEditor: 'ورقة عمل',
    slideEditor: 'شريحة',
    formulaBar: 'شريط الصيغة',
    pageLabel: 'صفحة',
    cellLabel: 'خلية',
    shapeLabel: 'شكل',
    viewing: 'عرض',
    editing: 'تحرير',
    undo: 'تراجع',
    redo: 'إعادة',
    speakerNotes: 'ملاحظات المحاضر',
    cut: 'قص',
    copy: 'نسخ',
    paste: 'لصق',
    pasteKeepSource: 'الاحتفاظ بتنسيق المصدر',
    pasteMerge: 'دمج التنسيق',
    pasteTextOnly: 'الاحتفاظ بالنص فقط',
    pictureLabel: 'صورة',
    cropMode: 'وضع القص',
    pictureHint:
        'اسحب المقابض لتغيير الحجم. اسحب الصورة لنقلها. اضغط C للقص. Shift مع الأسهم لتغيير الحجم.',
    followLinkHint: 'اضغط Ctrl ثم انقر للانتقال',
    selectAll: 'تحديد الكل',
    insertComment: 'تعليق جديد',
    replyComment: 'رد',
    resolveComment: 'حلّ',
    reopenComment: 'إعادة فتح',
    deleteComment: 'حذف التعليق',
    insertRowAbove: 'إدراج صف أعلى',
    insertRowBelow: 'إدراج صف أسفل',
    insertColumnLeft: 'إدراج عمود يسار',
    insertColumnRight: 'إدراج عمود يمين',
    deleteRow: 'حذف الصف',
    deleteColumn: 'حذف العمود',
    deleteTable: 'حذف الجدول',
    autoFitContents: 'ملاءمة المحتوى',
    autoFitWindow: 'ملاءمة النافذة',
    autoFitFixed: 'عرض أعمدة ثابت',
    mergeTableCells: 'دمج الخلايا',
    unmergeTableCells: 'إلغاء الدمج',
    insertSheetRow: 'إدراج صف',
    insertSheetColumn: 'إدراج عمود',
    deleteSheetRow: 'حذف الصف',
    deleteSheetColumn: 'حذف العمود',
    clearCells: 'مسح المحتوى',
    mergeAndCenter: 'دمج وتوسيط',
    unmergeCells: 'إلغاء الدمج',
    deleteShape: 'حذف',
    followLink: 'فتح الرابط',
    hideSlide: 'إخفاء الشريحة',
    showSlide: 'إظهار الشريحة',
    copySlide: 'نسخ الشريحة',
    pasteSlide: 'لصق الشريحة',
    duplicateSlide: 'تكرار الشريحة',
    find: 'بحث',
    replace: 'استبدال',
    print: 'طباعة',
    properties: 'خصائص',
    wordCount: 'عدد الكلمات',
    pdfViewer: 'عارض PDF',
    pdfEditor: 'محرر PDF',
    selectPage: 'تحديد الصفحة',
    zoomIn: 'تكبير',
    zoomOut: 'تصغير',
    actualSize: 'الحجم الفعلي',
    fitWidth: 'ملاءمة العرض',
    fitPage: 'ملاءمة الصفحة',
    previousPage: 'الصفحة السابقة',
    nextPage: 'الصفحة التالية',
    goToDestination: 'الانتقال إلى الوجهة',
    highlight: 'تمييز',
    strikethrough: 'يتوسطه خط',
    underline: 'تسطير',
    deleteAnnotation: 'حذف التعليق',
    rotatePage: 'تدوير 90° يميناً',
    rotatePageLeft: 'تدوير 90° يساراً',
    insertPage: 'إدراج صفحة فارغة',
    deletePage: 'حذف الصفحة',
    pdfMenuSelection: 'تحديد',
    pdfMenuView: 'عرض',
    pdfMenuPage: 'صفحة',
    pdfMenuMarkup: 'تمييز',
  );
}
