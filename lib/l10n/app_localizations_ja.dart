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
  String get ok => '確認';

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
  String get oledTheme => 'OLED ブラック';

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
  String get singlePanel => 'シングルパネル';

  @override
  String get dualPanel => 'デュアルパネル';

  @override
  String get showTreeSidebar => 'ツリーサイドバーを表示';

  @override
  String get hideTreeSidebar => 'ツリーサイドバーを隠す';

  @override
  String get detailsList => '詳細リスト';

  @override
  String get largeItems => '大きい項目';

  @override
  String get compactItems => 'コンパクト表示';

  @override
  String get showPreview => 'プレビューを表示';

  @override
  String get hidePreview => 'プレビューを隠す';

  @override
  String get showTerminal => 'ターミナルを表示';

  @override
  String get hideTerminal => 'ターミナルを隠す';

  @override
  String get moreActions => 'その他の操作';

  @override
  String get mountAsDrive => 'ドライブとしてマウント';

  @override
  String get auditLog => '監査ログ';

  @override
  String get systemLog => 'システムログ';

  @override
  String get cacheSettings => 'キャッシュ設定';

  @override
  String get keyboardShortcuts => 'キーボードショートカット';

  @override
  String get swapPanels => 'パネルを入れ替え';

  @override
  String get connectToCloud => 'クラウドに接続';

  @override
  String browseProvider(String provider) {
    return '$provider を参照';
  }

  @override
  String get pleaseConnectRemote => 'リモートファイルにアクセスするには接続してください';

  @override
  String get notConnected => '未接続';

  @override
  String get connectToCloudShort => 'クラウドに接続';

  @override
  String get loggedIn => 'ログイン済み';

  @override
  String get localFiles => 'ローカルファイル';

  @override
  String get remoteFiles => 'リモートファイル';

  @override
  String get bookmarkFolder => '現在のフォルダーをブックマーク';

  @override
  String get noFolders => 'フォルダーがありません';

  @override
  String get selectFileToPreview => 'プレビューするファイルを選択';

  @override
  String fileTooLarge(String size) {
    return 'ファイルが大きすぎてプレビューできません（$size）';
  }

  @override
  String previewFailed(String error) {
    return 'プレビューに失敗しました: $error';
  }

  @override
  String get firstPage => '最初のページ';

  @override
  String get previousPage => '前のページ';

  @override
  String get nextPage => '次のページ';

  @override
  String get lastPage => '最後のページ';

  @override
  String get playAudio => '音声を再生';

  @override
  String get playVideo => '動画を再生';

  @override
  String get emptyFile => '空のファイル';

  @override
  String systemLogTitle(int count) {
    return 'システムログ（$count 件）';
  }

  @override
  String get minimumLevel => '最低レベル';

  @override
  String get pauseAutoScroll => '自動スクロールを一時停止';

  @override
  String get resumeAutoScroll => '自動スクロールを再開';

  @override
  String get copyVisible => '表示中をコピー';

  @override
  String get copyAll => 'すべてコピー';

  @override
  String get filterLogs => 'ログを絞り込み...';

  @override
  String get visibleLinesCopied => '表示中の行をコピーしました';

  @override
  String get allLogsCopied => 'すべてのログをコピーしました';

  @override
  String get open => '開く';

  @override
  String get editSystemEditor => '編集（システムエディター）';

  @override
  String get editBuiltIn => '編集（内蔵エディター）';

  @override
  String get openWithSystemApp => 'システムアプリで開く';

  @override
  String get verifyAgainstRemote => 'リモートファイルと照合';

  @override
  String get browseArchive => 'アーカイブを参照';

  @override
  String get archiveExtracted => 'アーカイブを展開しました';

  @override
  String get revealInFinder => 'Finder に表示';

  @override
  String get showInExplorer => 'エクスプローラーに表示';

  @override
  String get openContainingFolder => '保存先フォルダーを開く';

  @override
  String get properties => 'プロパティ';

  @override
  String get copyNames => '名前をコピー';

  @override
  String get copyPaths => 'パスをコピー';

  @override
  String get createMd5 => '.md5 ファイルを作成';

  @override
  String get verifyChecksumFile => 'チェックサムファイルを検証';

  @override
  String get splitFile => 'ファイルを分割';

  @override
  String get combineParts => '分割ファイルを結合';

  @override
  String get createLink => 'リンクを作成...';

  @override
  String get secureWipe => '安全に消去';

  @override
  String confirmDeleteBody(int count) {
    return '$count 件の項目を削除しますか？';
  }

  @override
  String totalSize(String size) {
    return '合計サイズ: $size';
  }

  @override
  String get cannotBeUndone => 'この操作は元に戻せません。';

  @override
  String nItems(int count) {
    return '$count 項目';
  }

  @override
  String nTransfers(int count) {
    return '転送 $count 件';
  }

  @override
  String get syncing => '同期中';

  @override
  String lastSyncChanges(int count) {
    return '前回の同期: $count 件の変更';
  }

  @override
  String nPairs(int count) {
    return 'ペア $count 件';
  }

  @override
  String get hidden => '非表示';

  @override
  String free(String size) {
    return '空き: $size';
  }

  @override
  String get aboutLegal => '概要 / 法的情報';

  @override
  String get appDescription => 'Filen.io、SFTP、WebDAV 向けの非公式オープンソースクライアントです。';

  @override
  String get serviceProvider => 'サービスプロバイダー';

  @override
  String get contact => 'お問い合わせ';

  @override
  String get disclaimer => '免責事項';

  @override
  String get disclaimerText =>
      '本ソフトウェアは無保証で現状のまま提供されます。本アプリは Filen.io や他のクラウドプロバイダーとは関係ありません。';

  @override
  String get sourceCode => 'ソースコード（GitHub）';

  @override
  String get website => 'ウェブサイト';

  @override
  String get viewLicenses => 'オープンソースライセンスを表示';

  @override
  String get flatView => 'フラット表示（すべてのサブフォルダー）';

  @override
  String get exitFlatView => 'フラット表示を終了';

  @override
  String get showHiddenFiles => '隠しファイルを表示';

  @override
  String get hideHiddenFiles => '隠しファイルを隠す';

  @override
  String get touchFriendlyView => 'タッチ向け表示に切り替え';

  @override
  String get compactView => 'コンパクト表示に切り替え';

  @override
  String get sort => '並べ替え';

  @override
  String get secondarySort => '二次並べ替え';

  @override
  String get none => 'なし';

  @override
  String get byName => '名前順';

  @override
  String get bySize => 'サイズ順';

  @override
  String get byDate => '日付順';

  @override
  String get enterPath => 'パスを入力...';

  @override
  String get editPath => 'パスを編集';

  @override
  String get searchResults => '検索結果';

  @override
  String nFiles(int count) {
    return '$count ファイル';
  }

  @override
  String copyNItems(int count) {
    return '$count 件の項目をコピー';
  }

  @override
  String moveNItems(int count) {
    return '$count 件の項目を移動';
  }

  @override
  String get targetPath => '移動先のパス';

  @override
  String saved(String name) {
    return '$name を保存しました';
  }

  @override
  String saveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String get unsavedChanges => '未保存の変更';

  @override
  String get discardChanges => '未保存の変更があります。破棄しますか？';

  @override
  String get discard => '破棄';

  @override
  String get saveShortcut => '保存（Ctrl+S）';

  @override
  String get fileModifiedOnServer => 'このファイルは開いてからサーバー上で変更されました。';

  @override
  String get saveAnyway => '上書き保存';

  @override
  String get reload => '再読み込み';

  @override
  String get saveProfile => 'プロファイルを保存';

  @override
  String get profileName => 'プロファイル名';

  @override
  String get profileNameHint => '例: 仕事用 S3、個人用 SFTP';

  @override
  String profileSaved(String name) {
    return 'プロファイル「$name」を保存しました';
  }

  @override
  String get connectToCloudStorage => 'クラウドストレージに接続';

  @override
  String get savedProfiles => '保存済みプロファイル';

  @override
  String get loadProfile => '保存済みプロファイルを読み込み...';

  @override
  String get deleteProfile => 'プロファイルを削除';

  @override
  String get saveAsProfile => 'プロファイルとして保存';

  @override
  String get enableEncryption => 'クライアント側の暗号化を有効化';

  @override
  String get encryptBeforeUpload => 'アップロード前にファイルを暗号化（AES-256-GCM）';

  @override
  String get encryptionPassphrase => '暗号化パスフレーズ';

  @override
  String get appLocked => 'CrispCloudはロックされています';

  @override
  String get enterPinToContinue => '続行するにはPINまたはパスワードを入力してください';

  @override
  String get pinPassword => 'PIN / パスワード';

  @override
  String get incorrectPin => 'PINまたはパスワードが正しくありません';

  @override
  String get tooManyAttempts => '失敗回数が多すぎます。アプリを再起動して再試行してください。';

  @override
  String attemptsRemaining(int count) {
    return '残り試行回数: $count回';
  }

  @override
  String get appLockSetup => 'アプリロックを設定';

  @override
  String get changeAppLockCode => 'アプリロックを変更';

  @override
  String get currentPin => '現在のPIN / パスワード';

  @override
  String get newPin => '新しいPIN / パスワード';

  @override
  String get confirmPin => 'PIN / パスワードを確認';

  @override
  String get minFourChars => '4文字以上';

  @override
  String get codesDoNotMatch => 'コードが一致しません';

  @override
  String get autoLockAfter => '自動ロックまでの時間';

  @override
  String get immediately => 'すぐに';

  @override
  String get oneMinute => '1分';

  @override
  String get fiveMinutes => '5分';

  @override
  String get fifteenMinutes => '15分';

  @override
  String get thirtyMinutes => '30分';

  @override
  String get oneHour => '1時間';

  @override
  String get connectToHetzner => 'Hetzner Storage Box に接続';

  @override
  String get sftpPort23 => 'SFTP（ポート 23）';

  @override
  String get webdavHttps => 'WebDAV（HTTPS）';

  @override
  String get testConnection => '接続テスト';

  @override
  String get connectionSuccessful => '接続に成功しました';

  @override
  String testFailed(String error) {
    return 'テストに失敗しました: $error';
  }

  @override
  String get connectToAzure => 'Azure Blob Storage に接続';

  @override
  String get authenticationMode => '認証方式';

  @override
  String get accountName => 'アカウント名';

  @override
  String get container => 'コンテナー';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'SAS トークン';

  @override
  String get connectToB2 => 'Backblaze B2 に接続';

  @override
  String get applicationKeyId => 'アプリケーションキー ID';

  @override
  String get applicationKey => 'アプリケーションキー';

  @override
  String get bucketNameOptional => 'バケット名（任意）';

  @override
  String get mount => 'マウント';

  @override
  String get unmount => 'マウント解除';

  @override
  String get displayName => '表示名';

  @override
  String get localMountPoint => 'ローカルマウントポイント';

  @override
  String get newMount => '新しいマウント';

  @override
  String get noMountsConfigured => 'マウントが設定されていません';

  @override
  String get fuseDesktopOnly =>
      'FUSE マウントは macOS、Linux、Windows のデスクトップでのみ利用できます。';

  @override
  String get multiCloud => 'マルチクラウド';

  @override
  String get connections => '接続';

  @override
  String get transfer => '転送';

  @override
  String get compareAndSearch => '比較と検索';

  @override
  String get noConnectionsYet => '登録された接続はありません。';

  @override
  String get startTransfer => '転送を開始';

  @override
  String get syncPairs => '同期ペア';

  @override
  String get enableAutoSync => '自動同期を有効化';

  @override
  String get disableAutoSync => '自動同期を無効化';

  @override
  String get noSyncPairs => '同期ペアが設定されていません';

  @override
  String get replayOffline => 'オフライン操作を再実行';

  @override
  String get newSyncPair => '新しい同期ペア';

  @override
  String get cacheUsage => 'キャッシュ使用量';

  @override
  String get maximumCacheSize => '最大キャッシュサイズ';

  @override
  String get clearCacheConfirm => 'キャッシュされたファイルをすべて削除しますか？必要に応じて再ダウンロードされます。';

  @override
  String batchRenameTitle(int count) {
    return '一括名前変更（$count ファイル）';
  }

  @override
  String get findReplace => '検索/置換';

  @override
  String get number => '番号付け';

  @override
  String get prefixSuffix => '接頭辞/接尾辞';

  @override
  String get extension => '拡張子';

  @override
  String get duplicateFinder => '重複ファイル検索';

  @override
  String get noDuplicatesFound => '重複ファイルはありません！';

  @override
  String get chooseTheme => 'テーマを選択';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get youAreUpToDate => '最新バージョンです';

  @override
  String get updateAvailable => '更新があります';

  @override
  String get releaseNotes => 'リリースノート';

  @override
  String get checkNow => '今すぐ確認';

  @override
  String get general => '一般';

  @override
  String get accessibility => 'アクセシビリティ';

  @override
  String get privacy => 'プライバシー';

  @override
  String get advanced => '詳細設定';

  @override
  String get showFKeyButtons => '画面下部に F3〜F8 のショートカットを表示';

  @override
  String get exportKeys => '暗号化キーをエクスポート/インポート';

  @override
  String get backupRecovery => 'BIP39 復元フレーズのバックアップと復元';

  @override
  String get noActiveOperations => '実行中の操作はありません';

  @override
  String get refreshAll => 'すべて更新';

  @override
  String get newName => '新しい名前';

  @override
  String get items => '項目:';

  @override
  String andMore(int count) {
    return '...他 $count 件';
  }

  @override
  String get searchPattern => '検索パターン';

  @override
  String get findPattern => '検索パターン';

  @override
  String get searchHint => 'ファイルを検索...';

  @override
  String get findHint => '例: *.pdf, report*';

  @override
  String get noResultsFound => '結果がありません';

  @override
  String get size => 'サイズ';

  @override
  String get date => '日付';

  @override
  String get name => '名前';

  @override
  String get type => '種類';

  @override
  String get created => '作成日時';

  @override
  String get accessed => 'アクセス日時';

  @override
  String get computeMd5 => 'MD5 を計算';

  @override
  String get protocol => 'プロトコル';
}
