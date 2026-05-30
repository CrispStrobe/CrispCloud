import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'CrispCloud'**
  String get appTitle;

  /// No description provided for @local.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get emptyFolder;

  /// No description provided for @noFolderSelected.
  ///
  /// In en, this message translates to:
  /// **'No folder selected'**
  String get noFolderSelected;

  /// No description provided for @openLocalFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Local Folder'**
  String get openLocalFolder;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Sort by Name'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Sort by Size'**
  String get sortBySize;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Sort by Date'**
  String get sortByDate;

  /// No description provided for @sortByExtension.
  ///
  /// In en, this message translates to:
  /// **'Sort by Extension'**
  String get sortByExtension;

  /// No description provided for @ascending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

  /// No description provided for @descending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descending;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelection;

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String nSelected(int count);

  /// No description provided for @filterFiles.
  ///
  /// In en, this message translates to:
  /// **'Filter Files'**
  String get filterFiles;

  /// No description provided for @typeToFilter.
  ///
  /// In en, this message translates to:
  /// **'Type to filter...'**
  String get typeToFilter;

  /// No description provided for @filterFilesShortcut.
  ///
  /// In en, this message translates to:
  /// **'Filter files (Ctrl+F)'**
  String get filterFilesShortcut;

  /// No description provided for @clearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filter'**
  String get clearFilter;

  /// No description provided for @browseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Browse...'**
  String get browseTooltip;

  /// No description provided for @upTooltip.
  ///
  /// In en, this message translates to:
  /// **'Up (Backspace)'**
  String get upTooltip;

  /// No description provided for @refreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh (F5)'**
  String get refreshTooltip;

  /// No description provided for @newFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'New Folder (Ctrl+N)'**
  String get newFolderTooltip;

  /// No description provided for @searchAllFiles.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy search all files'**
  String get searchAllFiles;

  /// No description provided for @findByPattern.
  ///
  /// In en, this message translates to:
  /// **'Find files by pattern in this folder (e.g. *.pdf)'**
  String get findByPattern;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List View'**
  String get listView;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get gridView;

  /// No description provided for @columnView.
  ///
  /// In en, this message translates to:
  /// **'Column View'**
  String get columnView;

  /// No description provided for @copyTo.
  ///
  /// In en, this message translates to:
  /// **'Copy to...'**
  String get copyTo;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to...'**
  String get moveTo;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionFailed;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @appKey.
  ///
  /// In en, this message translates to:
  /// **'App Key'**
  String get appKey;

  /// No description provided for @clientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get clientId;

  /// No description provided for @clientSecret.
  ///
  /// In en, this message translates to:
  /// **'Client Secret'**
  String get clientSecret;

  /// No description provided for @accessKey.
  ///
  /// In en, this message translates to:
  /// **'Access Key'**
  String get accessKey;

  /// No description provided for @secretKey.
  ///
  /// In en, this message translates to:
  /// **'Secret Key'**
  String get secretKey;

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get endpoint;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @bucket.
  ///
  /// In en, this message translates to:
  /// **'Bucket'**
  String get bucket;

  /// No description provided for @twoFactorCode.
  ///
  /// In en, this message translates to:
  /// **'2FA Code'**
  String get twoFactorCode;

  /// No description provided for @transferProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% complete'**
  String transferProgress(int percent);

  /// No description provided for @transferSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String transferSpeed(String speed);

  /// No description provided for @transferEta.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String transferEta(String time);

  /// No description provided for @syncManager.
  ///
  /// In en, this message translates to:
  /// **'Sync Manager'**
  String get syncManager;

  /// No description provided for @syncAll.
  ///
  /// In en, this message translates to:
  /// **'Sync All'**
  String get syncAll;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get syncNow;

  /// No description provided for @addPair.
  ///
  /// In en, this message translates to:
  /// **'Add Pair'**
  String get addPair;

  /// No description provided for @syncPairName.
  ///
  /// In en, this message translates to:
  /// **'Pair Name'**
  String get syncPairName;

  /// No description provided for @localPath.
  ///
  /// In en, this message translates to:
  /// **'Local Path'**
  String get localPath;

  /// No description provided for @remotePath.
  ///
  /// In en, this message translates to:
  /// **'Remote Path'**
  String get remotePath;

  /// No description provided for @conflictPolicy.
  ///
  /// In en, this message translates to:
  /// **'Conflict Policy'**
  String get conflictPolicy;

  /// No description provided for @syncDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get syncDirection;

  /// No description provided for @twoWay.
  ///
  /// In en, this message translates to:
  /// **'Two-Way'**
  String get twoWay;

  /// No description provided for @uploadOnly.
  ///
  /// In en, this message translates to:
  /// **'Upload Only'**
  String get uploadOnly;

  /// No description provided for @downloadOnly.
  ///
  /// In en, this message translates to:
  /// **'Download Only'**
  String get downloadOnly;

  /// No description provided for @newestWins.
  ///
  /// In en, this message translates to:
  /// **'Newest Wins'**
  String get newestWins;

  /// No description provided for @localWins.
  ///
  /// In en, this message translates to:
  /// **'Local Wins'**
  String get localWins;

  /// No description provided for @remoteWins.
  ///
  /// In en, this message translates to:
  /// **'Remote Wins'**
  String get remoteWins;

  /// No description provided for @keepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep Both'**
  String get keepBoth;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @backgroundSync.
  ///
  /// In en, this message translates to:
  /// **'Background Sync'**
  String get backgroundSync;

  /// No description provided for @cloudOnlyFiles.
  ///
  /// In en, this message translates to:
  /// **'Cloud-only files'**
  String get cloudOnlyFiles;

  /// No description provided for @includePatterns.
  ///
  /// In en, this message translates to:
  /// **'Include patterns'**
  String get includePatterns;

  /// No description provided for @excludePatterns.
  ///
  /// In en, this message translates to:
  /// **'Exclude patterns'**
  String get excludePatterns;

  /// No description provided for @encryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryption;

  /// No description provided for @encryptionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Encryption enabled'**
  String get encryptionEnabled;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @keyManagement.
  ///
  /// In en, this message translates to:
  /// **'Key Management'**
  String get keyManagement;

  /// No description provided for @exportKey.
  ///
  /// In en, this message translates to:
  /// **'Export Key'**
  String get exportKey;

  /// No description provided for @importKey.
  ///
  /// In en, this message translates to:
  /// **'Import Key'**
  String get importKey;

  /// No description provided for @mnemonic.
  ///
  /// In en, this message translates to:
  /// **'Mnemonic'**
  String get mnemonic;

  /// No description provided for @backupBundle.
  ///
  /// In en, this message translates to:
  /// **'Backup Bundle'**
  String get backupBundle;

  /// No description provided for @appLock.
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get appLock;

  /// No description provided for @setupLock.
  ///
  /// In en, this message translates to:
  /// **'Set Up Lock'**
  String get setupLock;

  /// No description provided for @changeLock.
  ///
  /// In en, this message translates to:
  /// **'Change Lock'**
  String get changeLock;

  /// No description provided for @disableLock.
  ///
  /// In en, this message translates to:
  /// **'Disable Lock'**
  String get disableLock;

  /// No description provided for @enterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN or Password'**
  String get enterPin;

  /// No description provided for @biometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get biometricUnlock;

  /// No description provided for @autoLockTimeout.
  ///
  /// In en, this message translates to:
  /// **'Auto-Lock Timeout'**
  String get autoLockTimeout;

  /// No description provided for @proxySettings.
  ///
  /// In en, this message translates to:
  /// **'Proxy Settings'**
  String get proxySettings;

  /// No description provided for @noProxy.
  ///
  /// In en, this message translates to:
  /// **'No Proxy'**
  String get noProxy;

  /// No description provided for @httpProxy.
  ///
  /// In en, this message translates to:
  /// **'HTTP Proxy'**
  String get httpProxy;

  /// No description provided for @socks5Proxy.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5 Proxy'**
  String get socks5Proxy;

  /// No description provided for @certificatePinning.
  ///
  /// In en, this message translates to:
  /// **'Certificate Pinning'**
  String get certificatePinning;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compare;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @checksum.
  ///
  /// In en, this message translates to:
  /// **'Checksum'**
  String get checksum;

  /// No description provided for @calculateSize.
  ///
  /// In en, this message translates to:
  /// **'Calculate Size'**
  String get calculateSize;

  /// No description provided for @batchRename.
  ///
  /// In en, this message translates to:
  /// **'Batch Rename'**
  String get batchRename;

  /// No description provided for @extractHere.
  ///
  /// In en, this message translates to:
  /// **'Extract Here'**
  String get extractHere;

  /// No description provided for @createZip.
  ///
  /// In en, this message translates to:
  /// **'Create Zip'**
  String get createZip;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share Link'**
  String get shareLink;

  /// No description provided for @versionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version History'**
  String get versionHistory;

  /// No description provided for @findDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Find Duplicates'**
  String get findDuplicates;

  /// No description provided for @commandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get commandPalette;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @oledTheme.
  ///
  /// In en, this message translates to:
  /// **'OLED Black'**
  String get oledTheme;

  /// No description provided for @nordTheme.
  ///
  /// In en, this message translates to:
  /// **'Nord'**
  String get nordTheme;

  /// No description provided for @draculaTheme.
  ///
  /// In en, this message translates to:
  /// **'Dracula'**
  String get draculaTheme;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// No description provided for @tabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabs;

  /// No description provided for @newTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get newTab;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get closeTab;

  /// No description provided for @pinTab.
  ///
  /// In en, this message translates to:
  /// **'Pin Tab'**
  String get pinTab;

  /// No description provided for @unpinTab.
  ///
  /// In en, this message translates to:
  /// **'Unpin Tab'**
  String get unpinTab;

  /// No description provided for @duplicateTab.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Tab'**
  String get duplicateTab;

  /// No description provided for @closeOtherTabs.
  ///
  /// In en, this message translates to:
  /// **'Close Other Tabs'**
  String get closeOtherTabs;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add Bookmark'**
  String get addBookmark;

  /// No description provided for @removeBookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove Bookmark'**
  String get removeBookmark;

  /// No description provided for @recentLocations.
  ///
  /// In en, this message translates to:
  /// **'Recent Locations'**
  String get recentLocations;

  /// No description provided for @sandboxedPathWarning.
  ///
  /// In en, this message translates to:
  /// **'Sandboxed path - Use Browse button to select a real folder'**
  String get sandboxedPathWarning;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. Use the Browse button to grant access.'**
  String get permissionDenied;

  /// No description provided for @accessCancelled.
  ///
  /// In en, this message translates to:
  /// **'Access cancelled. Using fallback directory.'**
  String get accessCancelled;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(String error);

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String renameFailed(String error);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String operationFailed(String error);

  /// No description provided for @dropFilesToUpload.
  ///
  /// In en, this message translates to:
  /// **'Drop files here to upload'**
  String get dropFilesToUpload;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} item(s)?'**
  String confirmDeleteMessage(int count);

  /// No description provided for @multiCloudManager.
  ///
  /// In en, this message translates to:
  /// **'Multi-Cloud Manager'**
  String get multiCloudManager;

  /// No description provided for @addConnection.
  ///
  /// In en, this message translates to:
  /// **'Add Connection'**
  String get addConnection;

  /// No description provided for @cloudToCloudTransfer.
  ///
  /// In en, this message translates to:
  /// **'Cloud-to-Cloud Transfer'**
  String get cloudToCloudTransfer;

  /// No description provided for @compareProviders.
  ///
  /// In en, this message translates to:
  /// **'Compare Providers'**
  String get compareProviders;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
