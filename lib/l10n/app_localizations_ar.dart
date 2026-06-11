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

  @override
  String get singlePanel => 'Single Panel';

  @override
  String get dualPanel => 'Dual Panel';

  @override
  String get showTreeSidebar => 'Show Tree Sidebar';

  @override
  String get hideTreeSidebar => 'Hide Tree Sidebar';

  @override
  String get detailsList => 'Details List';

  @override
  String get largeItems => 'Large Items';

  @override
  String get compactItems => 'Compact Items';

  @override
  String get showPreview => 'Show Preview';

  @override
  String get hidePreview => 'Hide Preview';

  @override
  String get showTerminal => 'Show Terminal';

  @override
  String get hideTerminal => 'Hide Terminal';

  @override
  String get moreActions => 'More actions';

  @override
  String get mountAsDrive => 'Mount as Drive';

  @override
  String get auditLog => 'Audit Log';

  @override
  String get systemLog => 'System Log';

  @override
  String get cacheSettings => 'Cache Settings';

  @override
  String get keyboardShortcuts => 'Keyboard Shortcuts';

  @override
  String get swapPanels => 'Swap Panels';

  @override
  String get connectToCloud => 'Connect to Cloud';

  @override
  String browseProvider(String provider) {
    return 'Browse $provider';
  }

  @override
  String get pleaseConnectRemote => 'Please connect to access remote files';

  @override
  String get notConnected => 'Not connected';

  @override
  String get connectToCloudShort => 'Connect to cloud';

  @override
  String get loggedIn => 'Logged in';

  @override
  String get localFiles => 'Local Files';

  @override
  String get remoteFiles => 'Remote Files';

  @override
  String get bookmarkFolder => 'Bookmark current folder';

  @override
  String get noFolders => 'No folders';

  @override
  String get selectFileToPreview => 'Select a file to preview';

  @override
  String fileTooLarge(String size) {
    return 'File too large to preview ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'Preview failed: $error';
  }

  @override
  String get firstPage => 'First page';

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String get lastPage => 'Last page';

  @override
  String get playAudio => 'Play Audio';

  @override
  String get playVideo => 'Play Video';

  @override
  String get emptyFile => 'Empty file';

  @override
  String systemLogTitle(int count) {
    return 'System Log ($count entries)';
  }

  @override
  String get minimumLevel => 'Minimum level';

  @override
  String get pauseAutoScroll => 'Pause auto-scroll';

  @override
  String get resumeAutoScroll => 'Resume auto-scroll';

  @override
  String get copyVisible => 'Copy visible';

  @override
  String get copyAll => 'Copy all';

  @override
  String get filterLogs => 'Filter logs...';

  @override
  String get visibleLinesCopied => 'Visible lines copied';

  @override
  String get allLogsCopied => 'All logs copied';

  @override
  String get open => 'Open';

  @override
  String get editSystemEditor => 'Edit (System Editor)';

  @override
  String get editBuiltIn => 'Edit (Built-in)';

  @override
  String get openWithSystemApp => 'Open with System App';

  @override
  String get verifyAgainstRemote => 'Verify against remote';

  @override
  String get browseArchive => 'Browse Archive';

  @override
  String get archiveExtracted => 'Archive extracted successfully';

  @override
  String get revealInFinder => 'Reveal in Finder';

  @override
  String get showInExplorer => 'Show in Explorer';

  @override
  String get openContainingFolder => 'Open containing folder';

  @override
  String get properties => 'Properties';

  @override
  String get copyNames => 'Copy name(s)';

  @override
  String get copyPaths => 'Copy path(s)';

  @override
  String get createMd5 => 'Create .md5 file';

  @override
  String get verifyChecksumFile => 'Verify checksum file';

  @override
  String get splitFile => 'Split File';

  @override
  String get combineParts => 'Combine Parts';

  @override
  String get createLink => 'Create Link...';

  @override
  String get secureWipe => 'Secure Wipe';

  @override
  String confirmDeleteBody(int count) {
    return 'Are you sure you want to delete $count item(s)?';
  }

  @override
  String totalSize(String size) {
    return 'Total size: $size';
  }

  @override
  String get cannotBeUndone => 'This action cannot be undone.';

  @override
  String nItems(int count) {
    return '$count items';
  }

  @override
  String nTransfers(int count) {
    return '$count transfer(s)';
  }

  @override
  String get syncing => 'Syncing';

  @override
  String lastSyncChanges(int count) {
    return 'Last sync: $count changes';
  }

  @override
  String nPairs(int count) {
    return '$count pair(s)';
  }

  @override
  String get hidden => 'Hidden';

  @override
  String free(String size) {
    return 'Free: $size';
  }

  @override
  String get aboutLegal => 'About / Legal';

  @override
  String get appDescription =>
      'An unofficial, open-source client for Filen.io, SFTP & WebDAV.';

  @override
  String get serviceProvider => 'Service Provider';

  @override
  String get contact => 'Contact';

  @override
  String get disclaimer => 'Disclaimer';

  @override
  String get disclaimerText =>
      'This software is provided \"as is\", without warranty of any kind. This app is not affiliated with Filen.io, or any other cloud provider.';

  @override
  String get sourceCode => 'Source Code (GitHub)';

  @override
  String get website => 'Website';

  @override
  String get viewLicenses => 'View Open Source Licenses';

  @override
  String get flatView => 'Flat View (all subdirectories)';

  @override
  String get exitFlatView => 'Exit Flat View';

  @override
  String get showHiddenFiles => 'Show hidden files';

  @override
  String get hideHiddenFiles => 'Hide hidden files';

  @override
  String get touchFriendlyView => 'Switch to touch-friendly view';

  @override
  String get compactView => 'Switch to compact view';

  @override
  String get sort => 'Sort';

  @override
  String get secondarySort => 'Secondary Sort';

  @override
  String get none => 'None';

  @override
  String get byName => 'by Name';

  @override
  String get bySize => 'by Size';

  @override
  String get byDate => 'by Date';

  @override
  String get enterPath => 'Enter path...';

  @override
  String get editPath => 'Edit path';

  @override
  String get searchResults => 'Search results';

  @override
  String nFiles(int count) {
    return '$count file(s)';
  }

  @override
  String copyNItems(int count) {
    return 'Copy $count item(s)';
  }

  @override
  String moveNItems(int count) {
    return 'Move $count item(s)';
  }

  @override
  String get targetPath => 'Target path';

  @override
  String saved(String name) {
    return 'Saved $name';
  }

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get unsavedChanges => 'Unsaved Changes';

  @override
  String get discardChanges => 'You have unsaved changes. Discard them?';

  @override
  String get discard => 'Discard';

  @override
  String get saveShortcut => 'Save (Ctrl+S)';

  @override
  String get fileModifiedOnServer =>
      'This file was modified on the server since you opened it.';

  @override
  String get saveAnyway => 'Save Anyway';

  @override
  String get reload => 'Reload';

  @override
  String get saveProfile => 'Save Profile';

  @override
  String get profileName => 'Profile Name';

  @override
  String get profileNameHint => 'e.g., Work S3, Personal SFTP';

  @override
  String profileSaved(String name) {
    return 'Profile \"$name\" saved';
  }

  @override
  String get connectToCloudStorage => 'Connect to Cloud Storage';

  @override
  String get savedProfiles => 'Saved Profiles';

  @override
  String get loadProfile => 'Load a saved profile...';

  @override
  String get deleteProfile => 'Delete Profile';

  @override
  String get saveAsProfile => 'Save as Profile';

  @override
  String get enableEncryption => 'Enable Client-Side Encryption';

  @override
  String get encryptBeforeUpload => 'Encrypt files before upload (AES-256-GCM)';

  @override
  String get encryptionPassphrase => 'Encryption Passphrase';

  @override
  String get appLocked => 'CrispCloud is Locked';

  @override
  String get enterPinToContinue => 'Enter your PIN or password to continue';

  @override
  String get pinPassword => 'PIN / Password';

  @override
  String get incorrectPin => 'Incorrect PIN or password';

  @override
  String get tooManyAttempts =>
      'Too many failed attempts. Restart the app to try again.';

  @override
  String attemptsRemaining(int count) {
    return '$count attempts remaining';
  }

  @override
  String get appLockSetup => 'Set Up App Lock';

  @override
  String get changeAppLockCode => 'Change App Lock';

  @override
  String get currentPin => 'Current PIN / Password';

  @override
  String get newPin => 'New PIN / Password';

  @override
  String get confirmPin => 'Confirm PIN / Password';

  @override
  String get minFourChars => 'Minimum 4 characters';

  @override
  String get codesDoNotMatch => 'Codes do not match';

  @override
  String get autoLockAfter => 'Auto-lock after';

  @override
  String get immediately => 'Immediately';

  @override
  String get oneMinute => '1 minute';

  @override
  String get fiveMinutes => '5 minutes';

  @override
  String get fifteenMinutes => '15 minutes';

  @override
  String get thirtyMinutes => '30 minutes';

  @override
  String get oneHour => '1 hour';

  @override
  String get connectToHetzner => 'Connect to Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP (port 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get connectionSuccessful => 'Connection successful';

  @override
  String testFailed(String error) {
    return 'Test failed: $error';
  }

  @override
  String get connectToAzure => 'Connect to Azure Blob Storage';

  @override
  String get authenticationMode => 'Authentication Mode';

  @override
  String get accountName => 'Account Name';

  @override
  String get container => 'Container';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'SAS Token';

  @override
  String get connectToB2 => 'Connect to Backblaze B2';

  @override
  String get applicationKeyId => 'Application Key ID';

  @override
  String get applicationKey => 'Application Key';

  @override
  String get bucketNameOptional => 'Bucket Name (optional)';

  @override
  String get mount => 'Mount';

  @override
  String get unmount => 'Unmount';

  @override
  String get displayName => 'Display Name';

  @override
  String get localMountPoint => 'Local Mount Point';

  @override
  String get newMount => 'New Mount';

  @override
  String get noMountsConfigured => 'No mounts configured';

  @override
  String get fuseDesktopOnly =>
      'FUSE mounts are only available on macOS, Linux, and Windows desktop.';

  @override
  String get multiCloud => 'Multi-Cloud';

  @override
  String get connections => 'Connections';

  @override
  String get transfer => 'Transfer';

  @override
  String get compareAndSearch => 'Compare & Search';

  @override
  String get noConnectionsYet => 'No connections registered yet.';

  @override
  String get startTransfer => 'Start Transfer';

  @override
  String get syncPairs => 'Sync Pairs';

  @override
  String get enableAutoSync => 'Enable Auto-Sync';

  @override
  String get disableAutoSync => 'Disable Auto-Sync';

  @override
  String get noSyncPairs => 'No sync pairs configured';

  @override
  String get replayOffline => 'Replay Offline';

  @override
  String get newSyncPair => 'New Sync Pair';

  @override
  String get cacheUsage => 'Cache Usage';

  @override
  String get maximumCacheSize => 'Maximum Cache Size';

  @override
  String get clearCacheConfirm =>
      'Remove all cached files? They will be re-downloaded when needed.';

  @override
  String batchRenameTitle(int count) {
    return 'Batch Rename ($count files)';
  }

  @override
  String get findReplace => 'Find/Replace';

  @override
  String get number => 'Number';

  @override
  String get prefixSuffix => 'Prefix/Suffix';

  @override
  String get extension => 'Extension';

  @override
  String get duplicateFinder => 'Duplicate Finder';

  @override
  String get noDuplicatesFound => 'No duplicates found!';

  @override
  String get chooseTheme => 'Choose Theme';

  @override
  String get checkForUpdates => 'Check for Updates';

  @override
  String get youAreUpToDate => 'You\'re up to date';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get releaseNotes => 'Release notes';

  @override
  String get checkNow => 'Check Now';

  @override
  String get general => 'General';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get privacy => 'Privacy';

  @override
  String get advanced => 'Advanced';

  @override
  String get showFKeyButtons =>
      'Show F3-F8 shortcut buttons at the bottom of the screen';

  @override
  String get exportKeys => 'Export/Import Encryption Keys';

  @override
  String get backupRecovery => 'BIP39 Mnemonic Backup and Recovery';

  @override
  String get noActiveOperations => 'No active operations';

  @override
  String get refreshAll => 'Refresh All';

  @override
  String get newName => 'New name';

  @override
  String get items => 'Items:';

  @override
  String andMore(int count) {
    return '... and $count more';
  }

  @override
  String get searchPattern => 'Search Pattern';

  @override
  String get findPattern => 'Find Pattern';

  @override
  String get searchHint => 'Search for files...';

  @override
  String get findHint => 'e.g., *.pdf, report*';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get size => 'Size';

  @override
  String get date => 'Date';

  @override
  String get name => 'Name';

  @override
  String get type => 'Type';

  @override
  String get created => 'Created';

  @override
  String get accessed => 'Accessed';

  @override
  String get computeMd5 => 'Compute MD5';

  @override
  String get protocol => 'Protocol';
}
