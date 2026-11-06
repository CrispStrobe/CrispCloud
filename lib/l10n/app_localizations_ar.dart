// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'محلي';

  @override
  String get remote => 'بعيد';

  @override
  String get connect => 'اتصال';

  @override
  String get disconnect => 'قطع الاتصال';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get upload => 'رفع';

  @override
  String get download => 'تنزيل';

  @override
  String get delete => 'حذف';

  @override
  String get rename => 'إعادة التسمية';

  @override
  String get move => 'نقل';

  @override
  String get copy => 'نسخ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get create => 'إنشاء';

  @override
  String get close => 'إغلاق';

  @override
  String get done => 'تم';

  @override
  String get clear => 'مسح';

  @override
  String get ok => 'موافق';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get refresh => 'تحديث';

  @override
  String get search => 'بحث';

  @override
  String get filter => 'تصفية';

  @override
  String get settings => 'الإعدادات';

  @override
  String get about => 'حول التطبيق';

  @override
  String get help => 'مساعدة';

  @override
  String get newFolder => 'مجلد جديد';

  @override
  String get folderName => 'اسم المجلد';

  @override
  String get emptyFolder => 'مجلد فارغ';

  @override
  String get noFolderSelected => 'لم يتم تحديد مجلد';

  @override
  String get openLocalFolder => 'فتح مجلد محلي';

  @override
  String get sortByName => 'ترتيب حسب الاسم';

  @override
  String get sortBySize => 'ترتيب حسب الحجم';

  @override
  String get sortByDate => 'ترتيب حسب التاريخ';

  @override
  String get sortByExtension => 'ترتيب حسب الامتداد';

  @override
  String get ascending => 'تصاعدي';

  @override
  String get descending => 'تنازلي';

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get clearSelection => 'إلغاء التحديد';

  @override
  String nSelected(int count) {
    return 'تم تحديد $count';
  }

  @override
  String get filterFiles => 'تصفية الملفات';

  @override
  String get typeToFilter => 'اكتب للتصفية...';

  @override
  String get filterFilesShortcut => 'تصفية الملفات (Ctrl+F)';

  @override
  String get clearFilter => 'مسح التصفية';

  @override
  String get browseTooltip => 'استعراض...';

  @override
  String get upTooltip => 'للأعلى (Backspace)';

  @override
  String get refreshTooltip => 'تحديث (F5)';

  @override
  String get newFolderTooltip => 'مجلد جديد (Ctrl+N)';

  @override
  String get searchAllFiles => 'البحث الضبابي في جميع الملفات';

  @override
  String get findByPattern => 'البحث عن ملفات بنمط في هذا المجلد (مثال: *.pdf)';

  @override
  String get listView => 'عرض القائمة';

  @override
  String get gridView => 'عرض الشبكة';

  @override
  String get columnView => 'عرض الأعمدة';

  @override
  String get copyTo => 'نسخ إلى...';

  @override
  String get moveTo => 'نقل إلى...';

  @override
  String get connected => 'متصل';

  @override
  String get disconnected => 'غير متصل';

  @override
  String get connecting => 'جارٍ الاتصال...';

  @override
  String get connectionFailed => 'فشل الاتصال';

  @override
  String get provider => 'المزود';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get password => 'كلمة المرور';

  @override
  String get host => 'المضيف';

  @override
  String get port => 'المنفذ';

  @override
  String get serverUrl => 'عنوان URL للخادم';

  @override
  String get appKey => 'مفتاح التطبيق';

  @override
  String get clientId => 'معرف العميل';

  @override
  String get clientSecret => 'سر العميل';

  @override
  String get accessKey => 'مفتاح الوصول';

  @override
  String get secretKey => 'المفتاح السري';

  @override
  String get endpoint => 'نقطة النهاية';

  @override
  String get region => 'المنطقة';

  @override
  String get bucket => 'الحاوية';

  @override
  String get twoFactorCode => 'رمز المصادقة الثنائية';

  @override
  String transferProgress(int percent) {
    return '$percent% مكتمل';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/ث';
  }

  @override
  String transferEta(String time) {
    return 'متبقي $time';
  }

  @override
  String get syncManager => 'مدير المزامنة';

  @override
  String get syncAll => 'مزامنة الكل';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String get addPair => 'إضافة زوج';

  @override
  String get syncPairName => 'اسم الزوج';

  @override
  String get localPath => 'المسار المحلي';

  @override
  String get remotePath => 'المسار البعيد';

  @override
  String get conflictPolicy => 'سياسة التعارض';

  @override
  String get syncDirection => 'الاتجاه';

  @override
  String get twoWay => 'ثنائي الاتجاه';

  @override
  String get uploadOnly => 'رفع فقط';

  @override
  String get downloadOnly => 'تنزيل فقط';

  @override
  String get newestWins => 'الأحدث يفوز';

  @override
  String get localWins => 'المحلي يفوز';

  @override
  String get remoteWins => 'البعيد يفوز';

  @override
  String get keepBoth => 'الاحتفاظ بكليهما';

  @override
  String get manual => 'يدوي';

  @override
  String get backgroundSync => 'المزامنة في الخلفية';

  @override
  String get cloudOnlyFiles => 'ملفات السحابة فقط';

  @override
  String get includePatterns => 'أنماط التضمين';

  @override
  String get excludePatterns => 'أنماط الاستبعاد';

  @override
  String get encryption => 'التشفير';

  @override
  String get encryptionEnabled => 'التشفير مفعّل';

  @override
  String get passphrase => 'عبارة المرور';

  @override
  String get keyManagement => 'إدارة المفاتيح';

  @override
  String get exportKey => 'تصدير المفتاح';

  @override
  String get importKey => 'استيراد المفتاح';

  @override
  String get mnemonic => 'العبارة التذكيرية';

  @override
  String get backupBundle => 'حزمة النسخ الاحتياطي';

  @override
  String get appLock => 'قفل التطبيق';

  @override
  String get setupLock => 'إعداد القفل';

  @override
  String get changeLock => 'تغيير القفل';

  @override
  String get disableLock => 'تعطيل القفل';

  @override
  String get enterPin => 'أدخل PIN أو كلمة المرور';

  @override
  String get biometricUnlock => 'فتح القفل البيومتري';

  @override
  String get autoLockTimeout => 'مهلة القفل التلقائي';

  @override
  String get proxySettings => 'إعدادات الوكيل';

  @override
  String get noProxy => 'بلا وكيل';

  @override
  String get httpProxy => 'وكيل HTTP';

  @override
  String get socks5Proxy => 'وكيل SOCKS5';

  @override
  String get certificatePinning => 'تثبيت الشهادة';

  @override
  String get preview => 'معاينة';

  @override
  String get edit => 'تحرير';

  @override
  String get compare => 'مقارنة';

  @override
  String get permissions => 'الأذونات';

  @override
  String get checksum => 'مجموع الاختبار';

  @override
  String get calculateSize => 'حساب الحجم';

  @override
  String get batchRename => 'إعادة التسمية الجماعية';

  @override
  String get extractHere => 'استخراج هنا';

  @override
  String get createZip => 'إنشاء Zip';

  @override
  String get shareLink => 'مشاركة الرابط';

  @override
  String get versionHistory => 'سجل الإصدارات';

  @override
  String get findDuplicates => 'البحث عن المكررات';

  @override
  String get commandPalette => 'لوحة الأوامر';

  @override
  String get theme => 'السمة';

  @override
  String get systemTheme => 'النظام';

  @override
  String get lightTheme => 'فاتح';

  @override
  String get darkTheme => 'داكن';

  @override
  String get oledTheme => 'أسود OLED';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'لون التمييز';

  @override
  String get tabs => 'علامات التبويب';

  @override
  String get newTab => 'علامة تبويب جديدة';

  @override
  String get closeTab => 'إغلاق علامة التبويب';

  @override
  String get pinTab => 'تثبيت علامة التبويب';

  @override
  String get unpinTab => 'إلغاء تثبيت علامة التبويب';

  @override
  String get duplicateTab => 'تكرار علامة التبويب';

  @override
  String get closeOtherTabs => 'إغلاق علامات التبويب الأخرى';

  @override
  String get bookmarks => 'الإشارات المرجعية';

  @override
  String get addBookmark => 'إضافة إشارة مرجعية';

  @override
  String get removeBookmark => 'إزالة الإشارة المرجعية';

  @override
  String get recentLocations => 'المواقع الأخيرة';

  @override
  String get sandboxedPathWarning =>
      'مسار محمي - استخدم زر الاستعراض لتحديد مجلد حقيقي';

  @override
  String get permissionDenied =>
      'تم رفض الإذن. استخدم زر الاستعراض لمنح الوصول.';

  @override
  String get accessCancelled =>
      'تم إلغاء الوصول. يتم استخدام الدليل الاحتياطي.';

  @override
  String deleteFailed(String error) {
    return 'فشل الحذف: $error';
  }

  @override
  String renameFailed(String error) {
    return 'فشلت إعادة التسمية: $error';
  }

  @override
  String operationFailed(String error) {
    return 'فشلت العملية: $error';
  }

  @override
  String get dropFilesToUpload => 'أسقط الملفات هنا للرفع';

  @override
  String get confirmDeleteTitle => 'تأكيد الحذف';

  @override
  String confirmDeleteMessage(int count) {
    return 'هل تريد حذف $count عنصر؟';
  }

  @override
  String get multiCloudManager => 'مدير السحابة المتعددة';

  @override
  String get addConnection => 'إضافة اتصال';

  @override
  String get cloudToCloudTransfer => 'نقل من سحابة إلى سحابة';

  @override
  String get compareProviders => 'مقارنة المزودين';

  @override
  String get singlePanel => 'لوحة واحدة';

  @override
  String get dualPanel => 'لوحتان';

  @override
  String get showTreeSidebar => 'إظهار الشريط الجانبي للشجرة';

  @override
  String get hideTreeSidebar => 'إخفاء الشريط الجانبي للشجرة';

  @override
  String get detailsList => 'قائمة التفاصيل';

  @override
  String get largeItems => 'عناصر كبيرة';

  @override
  String get compactItems => 'عناصر مضغوطة';

  @override
  String get showPreview => 'إظهار المعاينة';

  @override
  String get hidePreview => 'إخفاء المعاينة';

  @override
  String get showTerminal => 'إظهار الطرفية';

  @override
  String get hideTerminal => 'إخفاء الطرفية';

  @override
  String get moreActions => 'مزيد من الإجراءات';

  @override
  String get mountAsDrive => 'التركيب كمحرك أقراص';

  @override
  String get auditLog => 'سجل التدقيق';

  @override
  String get systemLog => 'سجل النظام';

  @override
  String get cacheSettings => 'إعدادات ذاكرة التخزين المؤقت';

  @override
  String get keyboardShortcuts => 'اختصارات لوحة المفاتيح';

  @override
  String get swapPanels => 'تبديل اللوحتين';

  @override
  String get connectToCloud => 'الاتصال بالسحابة';

  @override
  String browseProvider(String provider) {
    return 'استعراض $provider';
  }

  @override
  String get pleaseConnectRemote => 'يرجى الاتصال للوصول إلى الملفات البعيدة';

  @override
  String get notConnected => 'غير متصل';

  @override
  String get connectToCloudShort => 'الاتصال بالسحابة';

  @override
  String get loggedIn => 'تم تسجيل الدخول';

  @override
  String get localFiles => 'الملفات المحلية';

  @override
  String get remoteFiles => 'الملفات البعيدة';

  @override
  String get bookmarkFolder => 'إضافة المجلد الحالي للمفضلة';

  @override
  String get noFolders => 'لا توجد مجلدات';

  @override
  String get selectFileToPreview => 'اختر ملفًا للمعاينة';

  @override
  String fileTooLarge(String size) {
    return 'الملف كبير جدًا للمعاينة ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'فشلت المعاينة: $error';
  }

  @override
  String get firstPage => 'الصفحة الأولى';

  @override
  String get previousPage => 'الصفحة السابقة';

  @override
  String get nextPage => 'الصفحة التالية';

  @override
  String get lastPage => 'الصفحة الأخيرة';

  @override
  String get playAudio => 'تشغيل الصوت';

  @override
  String get playVideo => 'تشغيل الفيديو';

  @override
  String get emptyFile => 'ملف فارغ';

  @override
  String systemLogTitle(int count) {
    return 'سجل النظام ($count إدخال)';
  }

  @override
  String get minimumLevel => 'الحد الأدنى للمستوى';

  @override
  String get pauseAutoScroll => 'إيقاف التمرير التلقائي مؤقتًا';

  @override
  String get resumeAutoScroll => 'استئناف التمرير التلقائي';

  @override
  String get copyVisible => 'نسخ الظاهر';

  @override
  String get copyAll => 'نسخ الكل';

  @override
  String get filterLogs => 'تصفية السجلات...';

  @override
  String get visibleLinesCopied => 'تم نسخ الأسطر الظاهرة';

  @override
  String get allLogsCopied => 'تم نسخ جميع السجلات';

  @override
  String get open => 'فتح';

  @override
  String get editSystemEditor => 'تحرير (محرر النظام)';

  @override
  String get editBuiltIn => 'تحرير (المحرر المدمج)';

  @override
  String get openWithSystemApp => 'فتح باستخدام تطبيق النظام';

  @override
  String get verifyAgainstRemote => 'التحقق من الملف البعيد';

  @override
  String get browseArchive => 'استعراض الأرشيف';

  @override
  String get archiveExtracted => 'تم استخراج الأرشيف بنجاح';

  @override
  String get revealInFinder => 'إظهار في Finder';

  @override
  String get showInExplorer => 'إظهار في المستكشف';

  @override
  String get openContainingFolder => 'فتح المجلد المحتوي';

  @override
  String get properties => 'الخصائص';

  @override
  String get copyNames => 'نسخ الأسماء';

  @override
  String get copyPaths => 'نسخ المسارات';

  @override
  String get createMd5 => 'إنشاء ملف ‎.md5';

  @override
  String get verifyChecksumFile => 'التحقق من ملف المجموع الاختباري';

  @override
  String get splitFile => 'تقسيم الملف';

  @override
  String get combineParts => 'دمج الأجزاء';

  @override
  String get createLink => 'إنشاء رابط...';

  @override
  String get secureWipe => 'مسح آمن';

  @override
  String confirmDeleteBody(int count) {
    return 'هل تريد بالتأكيد حذف $count من العناصر؟';
  }

  @override
  String totalSize(String size) {
    return 'الحجم الإجمالي: $size';
  }

  @override
  String get cannotBeUndone => 'لا يمكن التراجع عن هذا الإجراء.';

  @override
  String nItems(int count) {
    return 'العناصر: $count';
  }

  @override
  String nTransfers(int count) {
    return 'عمليات النقل: $count';
  }

  @override
  String get syncing => 'جارٍ المزامنة';

  @override
  String lastSyncChanges(int count) {
    return 'آخر مزامنة: $count تغييرات';
  }

  @override
  String nPairs(int count) {
    return 'الأزواج: $count';
  }

  @override
  String get hidden => 'مخفية';

  @override
  String free(String size) {
    return 'المتاح: $size';
  }

  @override
  String get aboutLegal => 'حول التطبيق / معلومات قانونية';

  @override
  String get appDescription =>
      'عميل مفتوح المصدر وغير رسمي لـ Filen.io وSFTP وWebDAV.';

  @override
  String get serviceProvider => 'مزوّد الخدمة';

  @override
  String get contact => 'اتصل بنا';

  @override
  String get disclaimer => 'إخلاء المسؤولية';

  @override
  String get disclaimerText =>
      'يُقدّم هذا البرنامج «كما هو» دون أي ضمان. هذا التطبيق غير تابع لـ Filen.io أو أي مزوّد سحابي آخر.';

  @override
  String get sourceCode => 'الشفرة المصدرية (GitHub)';

  @override
  String get website => 'الموقع الإلكتروني';

  @override
  String get viewLicenses => 'عرض تراخيص المصادر المفتوحة';

  @override
  String get flatView => 'عرض مسطح (كل المجلدات الفرعية)';

  @override
  String get exitFlatView => 'الخروج من العرض المسطح';

  @override
  String get showHiddenFiles => 'إظهار الملفات المخفية';

  @override
  String get hideHiddenFiles => 'إخفاء الملفات المخفية';

  @override
  String get touchFriendlyView => 'التبديل إلى العرض المناسب للمس';

  @override
  String get compactView => 'التبديل إلى العرض المضغوط';

  @override
  String get sort => 'ترتيب';

  @override
  String get secondarySort => 'ترتيب ثانوي';

  @override
  String get none => 'بلا';

  @override
  String get byName => 'حسب الاسم';

  @override
  String get bySize => 'حسب الحجم';

  @override
  String get byDate => 'حسب التاريخ';

  @override
  String get enterPath => 'أدخل المسار...';

  @override
  String get editPath => 'تحرير المسار';

  @override
  String get searchResults => 'نتائج البحث';

  @override
  String nFiles(int count) {
    return 'الملفات: $count';
  }

  @override
  String copyNItems(int count) {
    return 'نسخ $count من العناصر';
  }

  @override
  String moveNItems(int count) {
    return 'نقل $count من العناصر';
  }

  @override
  String get targetPath => 'مسار الوجهة';

  @override
  String saved(String name) {
    return 'تم حفظ $name';
  }

  @override
  String saveFailed(String error) {
    return 'فشل الحفظ: $error';
  }

  @override
  String get unsavedChanges => 'تغييرات غير محفوظة';

  @override
  String get discardChanges => 'لديك تغييرات غير محفوظة. هل تريد تجاهلها؟';

  @override
  String get discard => 'تجاهل';

  @override
  String get saveShortcut => 'حفظ (Ctrl+S)';

  @override
  String get fileModifiedOnServer => 'تم تعديل هذا الملف على الخادم منذ فتحه.';

  @override
  String get saveAnyway => 'الحفظ على أي حال';

  @override
  String get reload => 'إعادة التحميل';

  @override
  String get saveProfile => 'حفظ الملف التعريفي';

  @override
  String get profileName => 'اسم الملف التعريفي';

  @override
  String get profileNameHint => 'مثال: S3 للعمل، SFTP شخصي';

  @override
  String profileSaved(String name) {
    return 'تم حفظ الملف التعريفي \"$name\"';
  }

  @override
  String get connectToCloudStorage => 'الاتصال بالتخزين السحابي';

  @override
  String get savedProfiles => 'الملفات التعريفية المحفوظة';

  @override
  String get loadProfile => 'تحميل ملف تعريفي محفوظ...';

  @override
  String get deleteProfile => 'حذف الملف التعريفي';

  @override
  String get saveAsProfile => 'حفظ كملف تعريفي';

  @override
  String get enableEncryption => 'تفعيل التشفير من جهة العميل';

  @override
  String get encryptBeforeUpload => 'تشفير الملفات قبل الرفع (AES-256-GCM)';

  @override
  String get encryptionPassphrase => 'عبارة مرور التشفير';

  @override
  String get appLocked => 'CrispCloud مقفل';

  @override
  String get enterPinToContinue => 'أدخل رمز PIN أو كلمة المرور للمتابعة';

  @override
  String get pinPassword => 'رمز PIN / كلمة المرور';

  @override
  String get incorrectPin => 'رمز PIN أو كلمة المرور غير صحيحة';

  @override
  String get tooManyAttempts =>
      'محاولات فاشلة كثيرة. أعد تشغيل التطبيق للمحاولة مجدداً.';

  @override
  String attemptsRemaining(int count) {
    return 'المحاولات المتبقية: $count';
  }

  @override
  String get appLockSetup => 'إعداد قفل التطبيق';

  @override
  String get changeAppLockCode => 'تغيير قفل التطبيق';

  @override
  String get currentPin => 'رمز PIN / كلمة المرور الحالية';

  @override
  String get newPin => 'رمز PIN / كلمة المرور الجديدة';

  @override
  String get confirmPin => 'تأكيد رمز PIN / كلمة المرور';

  @override
  String get minFourChars => '4 أحرف على الأقل';

  @override
  String get codesDoNotMatch => 'الرمزان غير متطابقين';

  @override
  String get autoLockAfter => 'القفل التلقائي بعد';

  @override
  String get immediately => 'فوراً';

  @override
  String get oneMinute => 'دقيقة واحدة';

  @override
  String get fiveMinutes => '5 دقائق';

  @override
  String get fifteenMinutes => '15 دقيقة';

  @override
  String get thirtyMinutes => '30 دقيقة';

  @override
  String get oneHour => 'ساعة واحدة';

  @override
  String get connectToHetzner => 'الاتصال بـ Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP (المنفذ 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => 'اختبار الاتصال';

  @override
  String get connectionSuccessful => 'نجح الاتصال';

  @override
  String testFailed(String error) {
    return 'فشل الاختبار: $error';
  }

  @override
  String get connectToAzure => 'الاتصال بـ Azure Blob Storage';

  @override
  String get authenticationMode => 'طريقة المصادقة';

  @override
  String get accountName => 'اسم الحساب';

  @override
  String get container => 'الحاوية';

  @override
  String get sasUrl => 'عنوان SAS';

  @override
  String get sasToken => 'رمز SAS';

  @override
  String get connectToB2 => 'الاتصال بـ Backblaze B2';

  @override
  String get applicationKeyId => 'معرّف مفتاح التطبيق';

  @override
  String get applicationKey => 'مفتاح التطبيق';

  @override
  String get bucketNameOptional => 'اسم الحاوية (اختياري)';

  @override
  String get mount => 'تركيب';

  @override
  String get unmount => 'إلغاء التركيب';

  @override
  String get displayName => 'الاسم المعروض';

  @override
  String get localMountPoint => 'نقطة التركيب المحلية';

  @override
  String get newMount => 'تركيب جديد';

  @override
  String get noMountsConfigured => 'لم تُضبط أي عمليات تركيب';

  @override
  String get fuseDesktopOnly =>
      'تتوفر عمليات تركيب FUSE على أنظمة macOS وLinux وWindows لسطح المكتب فقط.';

  @override
  String get multiCloud => 'سحابات متعددة';

  @override
  String get connections => 'الاتصالات';

  @override
  String get transfer => 'نقل';

  @override
  String get compareAndSearch => 'المقارنة والبحث';

  @override
  String get noConnectionsYet => 'لم تُسجّل أي اتصالات بعد.';

  @override
  String get startTransfer => 'بدء النقل';

  @override
  String get syncPairs => 'أزواج المزامنة';

  @override
  String get enableAutoSync => 'تفعيل المزامنة التلقائية';

  @override
  String get disableAutoSync => 'تعطيل المزامنة التلقائية';

  @override
  String get noSyncPairs => 'لم تُضبط أزواج مزامنة';

  @override
  String get replayOffline => 'إعادة العمليات دون اتصال';

  @override
  String get newSyncPair => 'زوج مزامنة جديد';

  @override
  String get cacheUsage => 'استخدام ذاكرة التخزين المؤقت';

  @override
  String get maximumCacheSize => 'الحد الأقصى لحجم ذاكرة التخزين المؤقت';

  @override
  String get clearCacheConfirm =>
      'هل تريد إزالة كل الملفات المخزنة مؤقتًا؟ ستُنزّل مجددًا عند الحاجة.';

  @override
  String batchRenameTitle(int count) {
    return 'إعادة تسمية جماعية ($count ملف)';
  }

  @override
  String get findReplace => 'بحث/استبدال';

  @override
  String get number => 'ترقيم';

  @override
  String get prefixSuffix => 'بادئة/لاحقة';

  @override
  String get extension => 'الامتداد';

  @override
  String get duplicateFinder => 'البحث عن الملفات المكررة';

  @override
  String get noDuplicatesFound => 'لم تُعثر على ملفات مكررة!';

  @override
  String get chooseTheme => 'اختيار المظهر';

  @override
  String get checkForUpdates => 'التحقق من التحديثات';

  @override
  String get youAreUpToDate => 'لديك أحدث إصدار';

  @override
  String get updateAvailable => 'يتوفر تحديث';

  @override
  String get releaseNotes => 'ملاحظات الإصدار';

  @override
  String get checkNow => 'تحقق الآن';

  @override
  String get general => 'عام';

  @override
  String get accessibility => 'إمكانية الوصول';

  @override
  String get privacy => 'الخصوصية';

  @override
  String get advanced => 'متقدم';

  @override
  String get showFKeyButtons => 'إظهار أزرار الاختصارات F3-F8 أسفل الشاشة';

  @override
  String get exportKeys => 'تصدير/استيراد مفاتيح التشفير';

  @override
  String get backupRecovery => 'نسخ واستعادة عبارة BIP39';

  @override
  String get noActiveOperations => 'لا توجد عمليات نشطة';

  @override
  String get refreshAll => 'تحديث الكل';

  @override
  String get newName => 'الاسم الجديد';

  @override
  String get items => 'العناصر:';

  @override
  String andMore(int count) {
    return '... و$count أخرى';
  }

  @override
  String get searchPattern => 'نمط البحث';

  @override
  String get findPattern => 'نمط البحث';

  @override
  String get searchHint => 'البحث عن ملفات...';

  @override
  String get findHint => 'مثال: *.pdf، report*';

  @override
  String get noResultsFound => 'لم تُعثر على نتائج';

  @override
  String get size => 'الحجم';

  @override
  String get date => 'التاريخ';

  @override
  String get name => 'الاسم';

  @override
  String get type => 'النوع';

  @override
  String get created => 'تاريخ الإنشاء';

  @override
  String get accessed => 'تاريخ الوصول';

  @override
  String get computeMd5 => 'حساب MD5';

  @override
  String get protocol => 'البروتوكول';
}
