// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remote';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get login => 'Login';

  @override
  String get logout => 'Logout';

  @override
  String get upload => 'Upload';

  @override
  String get download => 'Download';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get move => 'Move';

  @override
  String get copy => 'Copy';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get clear => 'Clear';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get settings => 'Settings';

  @override
  String get about => 'About';

  @override
  String get help => 'Help';

  @override
  String get newFolder => 'New Folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get emptyFolder => 'Empty folder';

  @override
  String get noFolderSelected => 'No folder selected';

  @override
  String get openLocalFolder => 'Open Local Folder';

  @override
  String get sortByName => 'Sort by Name';

  @override
  String get sortBySize => 'Sort by Size';

  @override
  String get sortByDate => 'Sort by Date';

  @override
  String get sortByExtension => 'Sort by Extension';

  @override
  String get ascending => 'Ascending';

  @override
  String get descending => 'Descending';

  @override
  String get selectAll => 'Select All';

  @override
  String get clearSelection => 'Clear Selection';

  @override
  String nSelected(int count) {
    return '$count selected';
  }

  @override
  String get filterFiles => 'Filter Files';

  @override
  String get typeToFilter => 'Type to filter...';

  @override
  String get filterFilesShortcut => 'Filter files (Ctrl+F)';

  @override
  String get clearFilter => 'Clear filter';

  @override
  String get browseTooltip => 'Browse...';

  @override
  String get upTooltip => 'Up (Backspace)';

  @override
  String get refreshTooltip => 'Refresh (F5)';

  @override
  String get newFolderTooltip => 'New Folder (Ctrl+N)';

  @override
  String get searchAllFiles => 'Fuzzy search all files';

  @override
  String get findByPattern =>
      'Find files by pattern in this folder (e.g. *.pdf)';

  @override
  String get listView => 'List View';

  @override
  String get gridView => 'Grid View';

  @override
  String get columnView => 'Column View';

  @override
  String get copyTo => 'Copy to...';

  @override
  String get moveTo => 'Move to...';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get connecting => 'Connecting...';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String get provider => 'Provider';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get host => 'Host';

  @override
  String get port => 'Port';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get appKey => 'App Key';

  @override
  String get clientId => 'Client ID';

  @override
  String get clientSecret => 'Client Secret';

  @override
  String get accessKey => 'Access Key';

  @override
  String get secretKey => 'Secret Key';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get region => 'Region';

  @override
  String get bucket => 'Bucket';

  @override
  String get twoFactorCode => '2FA Code';

  @override
  String transferProgress(int percent) {
    return '$percent% complete';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String transferEta(String time) {
    return '$time left';
  }

  @override
  String get syncManager => 'Sync Manager';

  @override
  String get syncAll => 'Sync All';

  @override
  String get syncNow => 'Sync Now';

  @override
  String get addPair => 'Add Pair';

  @override
  String get syncPairName => 'Pair Name';

  @override
  String get localPath => 'Local Path';

  @override
  String get remotePath => 'Remote Path';

  @override
  String get conflictPolicy => 'Conflict Policy';

  @override
  String get syncDirection => 'Direction';

  @override
  String get twoWay => 'Two-Way';

  @override
  String get uploadOnly => 'Upload Only';

  @override
  String get downloadOnly => 'Download Only';

  @override
  String get newestWins => 'Newest Wins';

  @override
  String get localWins => 'Local Wins';

  @override
  String get remoteWins => 'Remote Wins';

  @override
  String get keepBoth => 'Keep Both';

  @override
  String get manual => 'Manual';

  @override
  String get backgroundSync => 'Background Sync';

  @override
  String get cloudOnlyFiles => 'Cloud-only files';

  @override
  String get includePatterns => 'Include patterns';

  @override
  String get excludePatterns => 'Exclude patterns';

  @override
  String get encryption => 'Encryption';

  @override
  String get encryptionEnabled => 'Encryption enabled';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get keyManagement => 'Key Management';

  @override
  String get exportKey => 'Export Key';

  @override
  String get importKey => 'Import Key';

  @override
  String get mnemonic => 'Mnemonic';

  @override
  String get backupBundle => 'Backup Bundle';

  @override
  String get appLock => 'App Lock';

  @override
  String get setupLock => 'Set Up Lock';

  @override
  String get changeLock => 'Change Lock';

  @override
  String get disableLock => 'Disable Lock';

  @override
  String get enterPin => 'Enter PIN or Password';

  @override
  String get biometricUnlock => 'Biometric Unlock';

  @override
  String get autoLockTimeout => 'Auto-Lock Timeout';

  @override
  String get proxySettings => 'Proxy Settings';

  @override
  String get noProxy => 'No Proxy';

  @override
  String get httpProxy => 'HTTP Proxy';

  @override
  String get socks5Proxy => 'SOCKS5 Proxy';

  @override
  String get certificatePinning => 'Certificate Pinning';

  @override
  String get preview => 'Preview';

  @override
  String get edit => 'Edit';

  @override
  String get compare => 'Compare';

  @override
  String get permissions => 'Permissions';

  @override
  String get checksum => 'Checksum';

  @override
  String get calculateSize => 'Calculate Size';

  @override
  String get batchRename => 'Batch Rename';

  @override
  String get extractHere => 'Extract Here';

  @override
  String get createZip => 'Create Zip';

  @override
  String get shareLink => 'Share Link';

  @override
  String get versionHistory => 'Version History';

  @override
  String get findDuplicates => 'Find Duplicates';

  @override
  String get commandPalette => 'Command Palette';

  @override
  String get theme => 'Theme';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'Accent Color';

  @override
  String get tabs => 'Tabs';

  @override
  String get newTab => 'New Tab';

  @override
  String get closeTab => 'Close Tab';

  @override
  String get pinTab => 'Pin Tab';

  @override
  String get unpinTab => 'Unpin Tab';

  @override
  String get duplicateTab => 'Duplicate Tab';

  @override
  String get closeOtherTabs => 'Close Other Tabs';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get addBookmark => 'Add Bookmark';

  @override
  String get removeBookmark => 'Remove Bookmark';

  @override
  String get recentLocations => 'Recent Locations';

  @override
  String get sandboxedPathWarning =>
      'Sandboxed path - Use Browse button to select a real folder';

  @override
  String get permissionDenied =>
      'Permission denied. Use the Browse button to grant access.';

  @override
  String get accessCancelled => 'Access cancelled. Using fallback directory.';

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String renameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String operationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get dropFilesToUpload => 'Drop files here to upload';

  @override
  String get confirmDeleteTitle => 'Confirm Delete';

  @override
  String confirmDeleteMessage(int count) {
    return 'Delete $count item(s)?';
  }

  @override
  String get multiCloudManager => 'Multi-Cloud Manager';

  @override
  String get addConnection => 'Add Connection';

  @override
  String get cloudToCloudTransfer => 'Cloud-to-Cloud Transfer';

  @override
  String get compareProviders => 'Compare Providers';
}
