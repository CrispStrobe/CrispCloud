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
