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
  String get oledTheme => 'OLED Black';

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
}
