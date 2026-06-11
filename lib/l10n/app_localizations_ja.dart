// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'ローカル';

  @override
  String get remote => 'リモート';

  @override
  String get connect => '接続';

  @override
  String get disconnect => '切断';

  @override
  String get login => 'ログイン';

  @override
  String get logout => 'ログアウト';

  @override
  String get upload => 'アップロード';

  @override
  String get download => 'ダウンロード';

  @override
  String get delete => '削除';

  @override
  String get rename => '名前を変更';

  @override
  String get move => '移動';

  @override
  String get copy => 'コピー';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get create => '作成';

  @override
  String get close => '閉じる';

  @override
  String get done => '完了';

  @override
  String get clear => 'クリア';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'はい';

  @override
  String get no => 'いいえ';

  @override
  String get retry => '再試行';

  @override
  String get refresh => '更新';

  @override
  String get search => '検索';

  @override
  String get filter => 'フィルター';

  @override
  String get settings => '設定';

  @override
  String get about => 'このアプリについて';

  @override
  String get help => 'ヘルプ';

  @override
  String get newFolder => '新しいフォルダ';

  @override
  String get folderName => 'フォルダ名';

  @override
  String get emptyFolder => '空のフォルダ';

  @override
  String get noFolderSelected => 'フォルダが選択されていません';

  @override
  String get openLocalFolder => 'ローカルフォルダを開く';

  @override
  String get sortByName => '名前で並び替え';

  @override
  String get sortBySize => 'サイズで並び替え';

  @override
  String get sortByDate => '日付で並び替え';

  @override
  String get sortByExtension => '拡張子で並び替え';

  @override
  String get ascending => '昇順';

  @override
  String get descending => '降順';

  @override
  String get selectAll => 'すべて選択';

  @override
  String get clearSelection => '選択を解除';

  @override
  String nSelected(int count) {
    return '$count 件選択中';
  }

  @override
  String get filterFiles => 'ファイルをフィルター';

  @override
  String get typeToFilter => 'フィルターするには入力...';

  @override
  String get filterFilesShortcut => 'ファイルをフィルター (Ctrl+F)';

  @override
  String get clearFilter => 'フィルターをクリア';

  @override
  String get browseTooltip => '参照...';

  @override
  String get upTooltip => '上へ (Backspace)';

  @override
  String get refreshTooltip => '更新 (F5)';

  @override
  String get newFolderTooltip => '新しいフォルダ (Ctrl+N)';

  @override
  String get searchAllFiles => '全ファイルをあいまい検索';

  @override
  String get findByPattern => 'このフォルダでパターンによりファイルを検索（例: *.pdf）';

  @override
  String get listView => 'リスト表示';

  @override
  String get gridView => 'グリッド表示';

  @override
  String get columnView => '列表示';

  @override
  String get copyTo => 'コピー先...';

  @override
  String get moveTo => '移動先...';

  @override
  String get connected => '接続済み';

  @override
  String get disconnected => '切断済み';

  @override
  String get connecting => '接続中...';

  @override
  String get connectionFailed => '接続に失敗しました';

  @override
  String get provider => 'プロバイダー';

  @override
  String get username => 'ユーザー名';

  @override
  String get password => 'パスワード';

  @override
  String get host => 'ホスト';

  @override
  String get port => 'ポート';

  @override
  String get serverUrl => 'サーバー URL';

  @override
  String get appKey => 'アプリキー';

  @override
  String get clientId => 'クライアント ID';

  @override
  String get clientSecret => 'クライアントシークレット';

  @override
  String get accessKey => 'アクセスキー';

  @override
  String get secretKey => 'シークレットキー';

  @override
  String get endpoint => 'エンドポイント';

  @override
  String get region => 'リージョン';

  @override
  String get bucket => 'バケット';

  @override
  String get twoFactorCode => '2FA コード';

  @override
  String transferProgress(int percent) {
    return '$percent% 完了';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/秒';
  }

  @override
  String transferEta(String time) {
    return '残り $time';
  }

  @override
  String get syncManager => '同期マネージャー';

  @override
  String get syncAll => 'すべて同期';

  @override
  String get syncNow => '今すぐ同期';

  @override
  String get addPair => 'ペアを追加';

  @override
  String get syncPairName => 'ペア名';

  @override
  String get localPath => 'ローカルパス';

  @override
  String get remotePath => 'リモートパス';

  @override
  String get conflictPolicy => '競合ポリシー';

  @override
  String get syncDirection => '方向';

  @override
  String get twoWay => '双方向';

  @override
  String get uploadOnly => 'アップロードのみ';

  @override
  String get downloadOnly => 'ダウンロードのみ';

  @override
  String get newestWins => '最新優先';

  @override
  String get localWins => 'ローカル優先';

  @override
  String get remoteWins => 'リモート優先';

  @override
  String get keepBoth => '両方を保持';

  @override
  String get manual => '手動';

  @override
  String get backgroundSync => 'バックグラウンド同期';

  @override
  String get cloudOnlyFiles => 'クラウド専用ファイル';

  @override
  String get includePatterns => '含めるパターン';

  @override
  String get excludePatterns => '除外するパターン';

  @override
  String get encryption => '暗号化';

  @override
  String get encryptionEnabled => '暗号化が有効';

  @override
  String get passphrase => 'パスフレーズ';

  @override
  String get keyManagement => '鍵管理';

  @override
  String get exportKey => '鍵をエクスポート';

  @override
  String get importKey => '鍵をインポート';

  @override
  String get mnemonic => 'ニーモニック';

  @override
  String get backupBundle => 'バックアップバンドル';

  @override
  String get appLock => 'アプリロック';

  @override
  String get setupLock => 'ロックを設定';

  @override
  String get changeLock => 'ロックを変更';

  @override
  String get disableLock => 'ロックを無効化';

  @override
  String get enterPin => 'PIN またはパスワードを入力';

  @override
  String get biometricUnlock => '生体認証でロック解除';

  @override
  String get autoLockTimeout => '自動ロックのタイムアウト';

  @override
  String get proxySettings => 'プロキシ設定';

  @override
  String get noProxy => 'プロキシなし';

  @override
  String get httpProxy => 'HTTP プロキシ';

  @override
  String get socks5Proxy => 'SOCKS5 プロキシ';

  @override
  String get certificatePinning => '証明書ピンニング';

  @override
  String get preview => 'プレビュー';

  @override
  String get edit => '編集';

  @override
  String get compare => '比較';

  @override
  String get permissions => '権限';

  @override
  String get checksum => 'チェックサム';

  @override
  String get calculateSize => 'サイズを計算';

  @override
  String get batchRename => '一括名前変更';

  @override
  String get extractHere => 'ここに展開';

  @override
  String get createZip => 'Zip を作成';

  @override
  String get shareLink => 'リンクを共有';

  @override
  String get versionHistory => 'バージョン履歴';

  @override
  String get findDuplicates => '重複を検索';

  @override
  String get commandPalette => 'コマンドパレット';

  @override
  String get theme => 'テーマ';

  @override
  String get systemTheme => 'システム';

  @override
  String get lightTheme => 'ライト';

  @override
  String get darkTheme => 'ダーク';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'アクセントカラー';

  @override
  String get tabs => 'タブ';

  @override
  String get newTab => '新しいタブ';

  @override
  String get closeTab => 'タブを閉じる';

  @override
  String get pinTab => 'タブをピン留め';

  @override
  String get unpinTab => 'タブのピン留めを解除';

  @override
  String get duplicateTab => 'タブを複製';

  @override
  String get closeOtherTabs => '他のタブを閉じる';

  @override
  String get bookmarks => 'ブックマーク';

  @override
  String get addBookmark => 'ブックマークを追加';

  @override
  String get removeBookmark => 'ブックマークを削除';

  @override
  String get recentLocations => '最近の場所';

  @override
  String get sandboxedPathWarning => 'サンドボックスパス - 参照ボタンを使用して実際のフォルダを選択してください';

  @override
  String get permissionDenied => 'アクセスが拒否されました。参照ボタンを使用してアクセスを許可してください。';

  @override
  String get accessCancelled => 'アクセスがキャンセルされました。代替ディレクトリを使用します。';

  @override
  String deleteFailed(String error) {
    return '削除に失敗しました：$error';
  }

  @override
  String renameFailed(String error) {
    return '名前の変更に失敗しました：$error';
  }

  @override
  String operationFailed(String error) {
    return '操作に失敗しました：$error';
  }

  @override
  String get dropFilesToUpload => 'ファイルをここにドロップしてアップロード';

  @override
  String get confirmDeleteTitle => '削除の確認';

  @override
  String confirmDeleteMessage(int count) {
    return '$count 件のアイテムを削除しますか？';
  }

  @override
  String get multiCloudManager => 'マルチクラウドマネージャー';

  @override
  String get addConnection => '接続を追加';

  @override
  String get cloudToCloudTransfer => 'クラウド間転送';

  @override
  String get compareProviders => 'プロバイダーを比較';

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
