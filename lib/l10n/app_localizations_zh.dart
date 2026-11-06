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
  String get oledTheme => 'OLED 黑色';

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
  String get singlePanel => '单面板';

  @override
  String get dualPanel => '双面板';

  @override
  String get showTreeSidebar => '显示目录树侧栏';

  @override
  String get hideTreeSidebar => '隐藏目录树侧栏';

  @override
  String get detailsList => '详细列表';

  @override
  String get largeItems => '大图标';

  @override
  String get compactItems => '紧凑视图';

  @override
  String get showPreview => '显示预览';

  @override
  String get hidePreview => '隐藏预览';

  @override
  String get showTerminal => '显示终端';

  @override
  String get hideTerminal => '隐藏终端';

  @override
  String get moreActions => '更多操作';

  @override
  String get mountAsDrive => '挂载为驱动器';

  @override
  String get auditLog => '审计日志';

  @override
  String get systemLog => '系统日志';

  @override
  String get cacheSettings => '缓存设置';

  @override
  String get keyboardShortcuts => '键盘快捷键';

  @override
  String get swapPanels => '交换面板';

  @override
  String get connectToCloud => '连接到云端';

  @override
  String browseProvider(String provider) {
    return '浏览 $provider';
  }

  @override
  String get pleaseConnectRemote => '请先连接以访问远程文件';

  @override
  String get notConnected => '未连接';

  @override
  String get connectToCloudShort => '连接云端';

  @override
  String get loggedIn => '已登录';

  @override
  String get localFiles => '本地文件';

  @override
  String get remoteFiles => '远程文件';

  @override
  String get bookmarkFolder => '收藏当前文件夹';

  @override
  String get noFolders => '没有文件夹';

  @override
  String get selectFileToPreview => '选择文件以预览';

  @override
  String fileTooLarge(String size) {
    return '文件过大，无法预览（$size）';
  }

  @override
  String previewFailed(String error) {
    return '预览失败：$error';
  }

  @override
  String get firstPage => '首页';

  @override
  String get previousPage => '上一页';

  @override
  String get nextPage => '下一页';

  @override
  String get lastPage => '末页';

  @override
  String get playAudio => '播放音频';

  @override
  String get playVideo => '播放视频';

  @override
  String get emptyFile => '空文件';

  @override
  String systemLogTitle(int count) {
    return '系统日志（$count 条）';
  }

  @override
  String get minimumLevel => '最低级别';

  @override
  String get pauseAutoScroll => '暂停自动滚动';

  @override
  String get resumeAutoScroll => '恢复自动滚动';

  @override
  String get copyVisible => '复制可见内容';

  @override
  String get copyAll => '复制全部';

  @override
  String get filterLogs => '筛选日志...';

  @override
  String get visibleLinesCopied => '已复制可见行';

  @override
  String get allLogsCopied => '已复制所有日志';

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
  String get browseArchive => '浏览归档';

  @override
  String get archiveExtracted => '归档解压成功';

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
    return '$count 个项目';
  }

  @override
  String nTransfers(int count) {
    return '$count 个传输';
  }

  @override
  String get syncing => '正在同步';

  @override
  String lastSyncChanges(int count) {
    return '上次同步：$count 项更改';
  }

  @override
  String nPairs(int count) {
    return '$count 对';
  }

  @override
  String get hidden => '隐藏';

  @override
  String free(String size) {
    return '可用：$size';
  }

  @override
  String get aboutLegal => '关于 / 法律信息';

  @override
  String get appDescription => '适用于 Filen.io、SFTP 和 WebDAV 的非官方开源客户端。';

  @override
  String get serviceProvider => '服务提供商';

  @override
  String get contact => '联系方式';

  @override
  String get disclaimer => '免责声明';

  @override
  String get disclaimerText =>
      '本软件按“原样”提供，不提供任何保证。本应用与 Filen.io 或任何其他云服务提供商无关联。';

  @override
  String get sourceCode => '源代码（GitHub）';

  @override
  String get website => '网站';

  @override
  String get viewLicenses => '查看开源许可证';

  @override
  String get flatView => '平铺视图（所有子目录）';

  @override
  String get exitFlatView => '退出平铺视图';

  @override
  String get showHiddenFiles => '显示隐藏文件';

  @override
  String get hideHiddenFiles => '隐藏隐藏文件';

  @override
  String get touchFriendlyView => '切换到触控视图';

  @override
  String get compactView => '切换到紧凑视图';

  @override
  String get sort => '排序';

  @override
  String get secondarySort => '次级排序';

  @override
  String get none => '无';

  @override
  String get byName => '按名称';

  @override
  String get bySize => '按大小';

  @override
  String get byDate => '按日期';

  @override
  String get enterPath => '输入路径...';

  @override
  String get editPath => '编辑路径';

  @override
  String get searchResults => '搜索结果';

  @override
  String nFiles(int count) {
    return '$count 个文件';
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
    return '已保存 $name';
  }

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get unsavedChanges => '未保存的更改';

  @override
  String get discardChanges => '有未保存的更改。要放弃吗？';

  @override
  String get discard => '放弃';

  @override
  String get saveShortcut => '保存（Ctrl+S）';

  @override
  String get fileModifiedOnServer => '打开后，此文件已在服务器上被修改。';

  @override
  String get saveAnyway => '仍然保存';

  @override
  String get reload => '重新加载';

  @override
  String get saveProfile => '保存配置';

  @override
  String get profileName => '配置名称';

  @override
  String get profileNameHint => '例如：工作 S3、个人 SFTP';

  @override
  String profileSaved(String name) {
    return '已保存配置“$name”';
  }

  @override
  String get connectToCloudStorage => '连接云存储';

  @override
  String get savedProfiles => '已保存的配置';

  @override
  String get loadProfile => '加载已保存的配置...';

  @override
  String get deleteProfile => '删除配置';

  @override
  String get saveAsProfile => '保存为配置';

  @override
  String get enableEncryption => '启用客户端加密';

  @override
  String get encryptBeforeUpload => '上传前加密文件（AES-256-GCM）';

  @override
  String get encryptionPassphrase => '加密密码短语';

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
  String get connectToHetzner => '连接 Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP（端口 23）';

  @override
  String get webdavHttps => 'WebDAV（HTTPS）';

  @override
  String get testConnection => '测试连接';

  @override
  String get connectionSuccessful => '连接成功';

  @override
  String testFailed(String error) {
    return '测试失败：$error';
  }

  @override
  String get connectToAzure => '连接 Azure Blob Storage';

  @override
  String get authenticationMode => '身份验证方式';

  @override
  String get accountName => '账户名';

  @override
  String get container => '容器';

  @override
  String get sasUrl => 'SAS 地址';

  @override
  String get sasToken => 'SAS 令牌';

  @override
  String get connectToB2 => '连接 Backblaze B2';

  @override
  String get applicationKeyId => '应用密钥 ID';

  @override
  String get applicationKey => '应用密钥';

  @override
  String get bucketNameOptional => '存储桶名称（可选）';

  @override
  String get mount => '挂载';

  @override
  String get unmount => '卸载';

  @override
  String get displayName => '显示名称';

  @override
  String get localMountPoint => '本地挂载点';

  @override
  String get newMount => '新建挂载';

  @override
  String get noMountsConfigured => '尚未配置挂载';

  @override
  String get fuseDesktopOnly => 'FUSE 挂载仅适用于 macOS、Linux 和 Windows 桌面系统。';

  @override
  String get multiCloud => '多云';

  @override
  String get connections => '连接';

  @override
  String get transfer => '传输';

  @override
  String get compareAndSearch => '比较与搜索';

  @override
  String get noConnectionsYet => '尚未注册连接。';

  @override
  String get startTransfer => '开始传输';

  @override
  String get syncPairs => '同步配对';

  @override
  String get enableAutoSync => '启用自动同步';

  @override
  String get disableAutoSync => '关闭自动同步';

  @override
  String get noSyncPairs => '尚未配置同步配对';

  @override
  String get replayOffline => '重放离线操作';

  @override
  String get newSyncPair => '新建同步配对';

  @override
  String get cacheUsage => '缓存使用量';

  @override
  String get maximumCacheSize => '最大缓存大小';

  @override
  String get clearCacheConfirm => '删除所有缓存文件？需要时将重新下载。';

  @override
  String batchRenameTitle(int count) {
    return '批量重命名（$count 个文件）';
  }

  @override
  String get findReplace => '查找/替换';

  @override
  String get number => '编号';

  @override
  String get prefixSuffix => '前缀/后缀';

  @override
  String get extension => '扩展名';

  @override
  String get duplicateFinder => '重复文件查找';

  @override
  String get noDuplicatesFound => '未找到重复文件！';

  @override
  String get chooseTheme => '选择主题';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get youAreUpToDate => '已是最新版本';

  @override
  String get updateAvailable => '有可用更新';

  @override
  String get releaseNotes => '发行说明';

  @override
  String get checkNow => '立即检查';

  @override
  String get general => '常规';

  @override
  String get accessibility => '无障碍';

  @override
  String get privacy => '隐私';

  @override
  String get advanced => '高级';

  @override
  String get showFKeyButtons => '在屏幕底部显示 F3-F8 快捷按钮';

  @override
  String get exportKeys => '导出/导入加密密钥';

  @override
  String get backupRecovery => 'BIP39 助记词备份与恢复';

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
  String get searchPattern => '搜索模式';

  @override
  String get findPattern => '查找模式';

  @override
  String get searchHint => '搜索文件...';

  @override
  String get findHint => '例如：*.pdf, report*';

  @override
  String get noResultsFound => '未找到结果';

  @override
  String get size => '大小';

  @override
  String get date => '日期';

  @override
  String get name => '名称';

  @override
  String get type => '类型';

  @override
  String get created => '创建时间';

  @override
  String get accessed => '访问时间';

  @override
  String get computeMd5 => '计算 MD5';

  @override
  String get protocol => '协议';
}
