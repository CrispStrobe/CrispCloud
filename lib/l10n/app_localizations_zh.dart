// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => '本地';

  @override
  String get remote => '远程';

  @override
  String get connect => '连接';

  @override
  String get disconnect => '断开连接';

  @override
  String get login => '登录';

  @override
  String get logout => '退出登录';

  @override
  String get upload => '上传';

  @override
  String get download => '下载';

  @override
  String get delete => '删除';

  @override
  String get rename => '重命名';

  @override
  String get move => '移动';

  @override
  String get copy => '复制';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get create => '新建';

  @override
  String get close => '关闭';

  @override
  String get done => '完成';

  @override
  String get clear => '清除';

  @override
  String get ok => '确定';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get retry => '重试';

  @override
  String get refresh => '刷新';

  @override
  String get search => '搜索';

  @override
  String get filter => '筛选';

  @override
  String get settings => '设置';

  @override
  String get about => '关于';

  @override
  String get help => '帮助';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get emptyFolder => '空文件夹';

  @override
  String get noFolderSelected => '未选择文件夹';

  @override
  String get openLocalFolder => '打开本地文件夹';

  @override
  String get sortByName => '按名称排序';

  @override
  String get sortBySize => '按大小排序';

  @override
  String get sortByDate => '按日期排序';

  @override
  String get sortByExtension => '按扩展名排序';

  @override
  String get ascending => '升序';

  @override
  String get descending => '降序';

  @override
  String get selectAll => '全选';

  @override
  String get clearSelection => '清除选择';

  @override
  String nSelected(int count) {
    return '已选择 $count 项';
  }

  @override
  String get filterFiles => '筛选文件';

  @override
  String get typeToFilter => '输入以筛选...';

  @override
  String get filterFilesShortcut => '筛选文件 (Ctrl+F)';

  @override
  String get clearFilter => '清除筛选';

  @override
  String get browseTooltip => '浏览...';

  @override
  String get upTooltip => '向上 (退格键)';

  @override
  String get refreshTooltip => '刷新 (F5)';

  @override
  String get newFolderTooltip => '新建文件夹 (Ctrl+N)';

  @override
  String get searchAllFiles => '模糊搜索所有文件';

  @override
  String get findByPattern => '在此文件夹中按模式查找文件（如 *.pdf）';

  @override
  String get listView => '列表视图';

  @override
  String get gridView => '网格视图';

  @override
  String get columnView => '列视图';

  @override
  String get copyTo => '复制到...';

  @override
  String get moveTo => '移动到...';

  @override
  String get connected => '已连接';

  @override
  String get disconnected => '已断开';

  @override
  String get connecting => '连接中...';

  @override
  String get connectionFailed => '连接失败';

  @override
  String get provider => '提供商';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get host => '主机';

  @override
  String get port => '端口';

  @override
  String get serverUrl => '服务器地址';

  @override
  String get appKey => '应用密钥';

  @override
  String get clientId => '客户端 ID';

  @override
  String get clientSecret => '客户端密钥';

  @override
  String get accessKey => '访问密钥';

  @override
  String get secretKey => '私有密钥';

  @override
  String get endpoint => '端点';

  @override
  String get region => '区域';

  @override
  String get bucket => '存储桶';

  @override
  String get twoFactorCode => '2FA 验证码';

  @override
  String transferProgress(int percent) {
    return '已完成 $percent%';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/秒';
  }

  @override
  String transferEta(String time) {
    return '剩余 $time';
  }

  @override
  String get syncManager => '同步管理器';

  @override
  String get syncAll => '全部同步';

  @override
  String get syncNow => '立即同步';

  @override
  String get addPair => '添加配对';

  @override
  String get syncPairName => '配对名称';

  @override
  String get localPath => '本地路径';

  @override
  String get remotePath => '远程路径';

  @override
  String get conflictPolicy => '冲突策略';

  @override
  String get syncDirection => '方向';

  @override
  String get twoWay => '双向';

  @override
  String get uploadOnly => '仅上传';

  @override
  String get downloadOnly => '仅下载';

  @override
  String get newestWins => '最新优先';

  @override
  String get localWins => '本地优先';

  @override
  String get remoteWins => '远程优先';

  @override
  String get keepBoth => '保留两者';

  @override
  String get manual => '手动';

  @override
  String get backgroundSync => '后台同步';

  @override
  String get cloudOnlyFiles => '仅限云端文件';

  @override
  String get includePatterns => '包含模式';

  @override
  String get excludePatterns => '排除模式';

  @override
  String get encryption => '加密';

  @override
  String get encryptionEnabled => '已启用加密';

  @override
  String get passphrase => '密码短语';

  @override
  String get keyManagement => '密钥管理';

  @override
  String get exportKey => '导出密钥';

  @override
  String get importKey => '导入密钥';

  @override
  String get mnemonic => '助记词';

  @override
  String get backupBundle => '备份包';

  @override
  String get appLock => '应用锁定';

  @override
  String get setupLock => '设置锁定';

  @override
  String get changeLock => '更改锁定';

  @override
  String get disableLock => '禁用锁定';

  @override
  String get enterPin => '输入 PIN 或密码';

  @override
  String get biometricUnlock => '生物识别解锁';

  @override
  String get autoLockTimeout => '自动锁定超时';

  @override
  String get proxySettings => '代理设置';

  @override
  String get noProxy => '无代理';

  @override
  String get httpProxy => 'HTTP 代理';

  @override
  String get socks5Proxy => 'SOCKS5 代理';

  @override
  String get certificatePinning => '证书固定';

  @override
  String get preview => '预览';

  @override
  String get edit => '编辑';

  @override
  String get compare => '比较';

  @override
  String get permissions => '权限';

  @override
  String get checksum => '校验和';

  @override
  String get calculateSize => '计算大小';

  @override
  String get batchRename => '批量重命名';

  @override
  String get extractHere => '解压到此处';

  @override
  String get createZip => '创建 Zip';

  @override
  String get shareLink => '分享链接';

  @override
  String get versionHistory => '版本历史';

  @override
  String get findDuplicates => '查找重复项';

  @override
  String get commandPalette => '命令面板';

  @override
  String get theme => '主题';

  @override
  String get systemTheme => '系统';

  @override
  String get lightTheme => '浅色';

  @override
  String get darkTheme => '深色';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => '强调色';

  @override
  String get tabs => '标签页';

  @override
  String get newTab => '新标签页';

  @override
  String get closeTab => '关闭标签页';

  @override
  String get pinTab => '固定标签页';

  @override
  String get unpinTab => '取消固定标签页';

  @override
  String get duplicateTab => '复制标签页';

  @override
  String get closeOtherTabs => '关闭其他标签页';

  @override
  String get bookmarks => '书签';

  @override
  String get addBookmark => '添加书签';

  @override
  String get removeBookmark => '删除书签';

  @override
  String get recentLocations => '最近位置';

  @override
  String get sandboxedPathWarning => '沙盒路径 - 请使用浏览按钮选择真实文件夹';

  @override
  String get permissionDenied => '权限被拒绝。请使用浏览按钮来授予访问权限。';

  @override
  String get accessCancelled => '访问已取消。使用备用目录。';

  @override
  String deleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String renameFailed(String error) {
    return '重命名失败：$error';
  }

  @override
  String operationFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get dropFilesToUpload => '将文件拖放到此处以上传';

  @override
  String get confirmDeleteTitle => '确认删除';

  @override
  String confirmDeleteMessage(int count) {
    return '删除 $count 个项目？';
  }

  @override
  String get multiCloudManager => '多云管理器';

  @override
  String get addConnection => '添加连接';

  @override
  String get cloudToCloudTransfer => '云到云传输';

  @override
  String get compareProviders => '比较提供商';

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
  String get connectToCloud => '连接到云端';

  @override
  String browseProvider(String provider) {
    return 'Browse $provider';
  }

  @override
  String get pleaseConnectRemote => '请先连接以访问远程文件';

  @override
  String get notConnected => 'Not connected';

  @override
  String get connectToCloudShort => 'Connect to cloud';

  @override
  String get loggedIn => '已登录';

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
  String get open => '打开';

  @override
  String get editSystemEditor => '编辑（系统编辑器）';

  @override
  String get editBuiltIn => '编辑（内置编辑器）';

  @override
  String get openWithSystemApp => '使用系统应用打开';

  @override
  String get verifyAgainstRemote => '与远程文件校验';

  @override
  String get browseArchive => 'Browse Archive';

  @override
  String get archiveExtracted => 'Archive extracted successfully';

  @override
  String get revealInFinder => '在 Finder 中显示';

  @override
  String get showInExplorer => '在资源管理器中显示';

  @override
  String get openContainingFolder => '打开所在文件夹';

  @override
  String get properties => '属性';

  @override
  String get copyNames => '复制名称';

  @override
  String get copyPaths => '复制路径';

  @override
  String get createMd5 => '创建 .md5 文件';

  @override
  String get verifyChecksumFile => '验证校验和文件';

  @override
  String get splitFile => '拆分文件';

  @override
  String get combineParts => '合并分卷';

  @override
  String get createLink => '创建链接...';

  @override
  String get secureWipe => '安全擦除';

  @override
  String confirmDeleteBody(int count) {
    return '确定要删除 $count 个项目吗？';
  }

  @override
  String totalSize(String size) {
    return '总大小：$size';
  }

  @override
  String get cannotBeUndone => '此操作无法撤销。';

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
    return '复制 $count 个项目';
  }

  @override
  String moveNItems(int count) {
    return '移动 $count 个项目';
  }

  @override
  String get targetPath => '目标路径';

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
  String get appLocked => 'CrispCloud 已锁定';

  @override
  String get enterPinToContinue => '请输入 PIN 或密码以继续';

  @override
  String get pinPassword => 'PIN / 密码';

  @override
  String get incorrectPin => 'PIN 或密码不正确';

  @override
  String get tooManyAttempts => '失败次数过多。请重启应用后重试。';

  @override
  String attemptsRemaining(int count) {
    return '剩余 $count 次尝试';
  }

  @override
  String get appLockSetup => '设置应用锁';

  @override
  String get changeAppLockCode => '更改应用锁';

  @override
  String get currentPin => '当前 PIN / 密码';

  @override
  String get newPin => '新 PIN / 密码';

  @override
  String get confirmPin => '确认 PIN / 密码';

  @override
  String get minFourChars => '至少 4 个字符';

  @override
  String get codesDoNotMatch => '输入的代码不一致';

  @override
  String get autoLockAfter => '自动锁定时间';

  @override
  String get immediately => '立即';

  @override
  String get oneMinute => '1 分钟';

  @override
  String get fiveMinutes => '5 分钟';

  @override
  String get fifteenMinutes => '15 分钟';

  @override
  String get thirtyMinutes => '30 分钟';

  @override
  String get oneHour => '1 小时';

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
  String get noActiveOperations => '没有活动操作';

  @override
  String get refreshAll => '全部刷新';

  @override
  String get newName => '新名称';

  @override
  String get items => '项目：';

  @override
  String andMore(int count) {
    return '...以及另外 $count 个';
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
  String get computeMd5 => '计算 MD5';

  @override
  String get protocol => 'Protocol';
}
