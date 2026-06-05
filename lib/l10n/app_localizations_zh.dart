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
}
