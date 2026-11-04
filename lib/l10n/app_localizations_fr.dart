// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Distant';

  @override
  String get connect => 'Connecter';

  @override
  String get disconnect => 'Déconnecter';

  @override
  String get login => 'Connexion';

  @override
  String get logout => 'Déconnexion';

  @override
  String get upload => 'Envoyer';

  @override
  String get download => 'Télécharger';

  @override
  String get delete => 'Supprimer';

  @override
  String get rename => 'Renommer';

  @override
  String get move => 'Déplacer';

  @override
  String get copy => 'Copier';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get create => 'Créer';

  @override
  String get close => 'Fermer';

  @override
  String get done => 'Terminé';

  @override
  String get clear => 'Effacer';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get retry => 'Réessayer';

  @override
  String get refresh => 'Actualiser';

  @override
  String get search => 'Rechercher';

  @override
  String get filter => 'Filtrer';

  @override
  String get settings => 'Paramètres';

  @override
  String get about => 'À propos';

  @override
  String get help => 'Aide';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get emptyFolder => 'Dossier vide';

  @override
  String get noFolderSelected => 'Aucun dossier sélectionné';

  @override
  String get openLocalFolder => 'Ouvrir le dossier local';

  @override
  String get sortByName => 'Trier par nom';

  @override
  String get sortBySize => 'Trier par taille';

  @override
  String get sortByDate => 'Trier par date';

  @override
  String get sortByExtension => 'Trier par extension';

  @override
  String get ascending => 'Croissant';

  @override
  String get descending => 'Décroissant';

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String get clearSelection => 'Effacer la sélection';

  @override
  String nSelected(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get filterFiles => 'Filtrer les fichiers';

  @override
  String get typeToFilter => 'Tapez pour filtrer...';

  @override
  String get filterFilesShortcut => 'Filtrer les fichiers (Ctrl+F)';

  @override
  String get clearFilter => 'Effacer le filtre';

  @override
  String get browseTooltip => 'Parcourir...';

  @override
  String get upTooltip => 'Haut (Retour arrière)';

  @override
  String get refreshTooltip => 'Actualiser (F5)';

  @override
  String get newFolderTooltip => 'Nouveau dossier (Ctrl+N)';

  @override
  String get searchAllFiles => 'Recherche floue dans tous les fichiers';

  @override
  String get findByPattern =>
      'Trouver des fichiers par motif dans ce dossier (ex. *.pdf)';

  @override
  String get listView => 'Vue liste';

  @override
  String get gridView => 'Vue grille';

  @override
  String get columnView => 'Vue colonnes';

  @override
  String get copyTo => 'Copier vers...';

  @override
  String get moveTo => 'Déplacer vers...';

  @override
  String get connected => 'Connecté';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get connecting => 'Connexion en cours...';

  @override
  String get connectionFailed => 'Échec de la connexion';

  @override
  String get provider => 'Fournisseur';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get host => 'Hôte';

  @override
  String get port => 'Port';

  @override
  String get serverUrl => 'URL du serveur';

  @override
  String get appKey => 'Clé d\'application';

  @override
  String get clientId => 'ID client';

  @override
  String get clientSecret => 'Secret client';

  @override
  String get accessKey => 'Clé d\'accès';

  @override
  String get secretKey => 'Clé secrète';

  @override
  String get endpoint => 'Point de terminaison';

  @override
  String get region => 'Région';

  @override
  String get bucket => 'Bucket';

  @override
  String get twoFactorCode => 'Code 2FA';

  @override
  String transferProgress(int percent) {
    return '$percent% terminé';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String transferEta(String time) {
    return '$time restant';
  }

  @override
  String get syncManager => 'Gestionnaire de synchronisation';

  @override
  String get syncAll => 'Tout synchroniser';

  @override
  String get syncNow => 'Synchroniser maintenant';

  @override
  String get addPair => 'Ajouter une paire';

  @override
  String get syncPairName => 'Nom de la paire';

  @override
  String get localPath => 'Chemin local';

  @override
  String get remotePath => 'Chemin distant';

  @override
  String get conflictPolicy => 'Politique de conflit';

  @override
  String get syncDirection => 'Direction';

  @override
  String get twoWay => 'Bidirectionnel';

  @override
  String get uploadOnly => 'Envoi uniquement';

  @override
  String get downloadOnly => 'Téléchargement uniquement';

  @override
  String get newestWins => 'Le plus récent l\'emporte';

  @override
  String get localWins => 'Local l\'emporte';

  @override
  String get remoteWins => 'Distant l\'emporte';

  @override
  String get keepBoth => 'Garder les deux';

  @override
  String get manual => 'Manuel';

  @override
  String get backgroundSync => 'Synchronisation en arrière-plan';

  @override
  String get cloudOnlyFiles => 'Fichiers cloud uniquement';

  @override
  String get includePatterns => 'Motifs d\'inclusion';

  @override
  String get excludePatterns => 'Motifs d\'exclusion';

  @override
  String get encryption => 'Chiffrement';

  @override
  String get encryptionEnabled => 'Chiffrement activé';

  @override
  String get passphrase => 'Phrase de passe';

  @override
  String get keyManagement => 'Gestion des clés';

  @override
  String get exportKey => 'Exporter la clé';

  @override
  String get importKey => 'Importer la clé';

  @override
  String get mnemonic => 'Mnémonique';

  @override
  String get backupBundle => 'Paquet de sauvegarde';

  @override
  String get appLock => 'Verrouillage de l\'application';

  @override
  String get setupLock => 'Configurer le verrou';

  @override
  String get changeLock => 'Modifier le verrou';

  @override
  String get disableLock => 'Désactiver le verrou';

  @override
  String get enterPin => 'Entrer le PIN ou le mot de passe';

  @override
  String get biometricUnlock => 'Déverrouillage biométrique';

  @override
  String get autoLockTimeout => 'Délai de verrouillage automatique';

  @override
  String get proxySettings => 'Paramètres du proxy';

  @override
  String get noProxy => 'Pas de proxy';

  @override
  String get httpProxy => 'Proxy HTTP';

  @override
  String get socks5Proxy => 'Proxy SOCKS5';

  @override
  String get certificatePinning => 'Épinglage de certificat';

  @override
  String get preview => 'Aperçu';

  @override
  String get edit => 'Modifier';

  @override
  String get compare => 'Comparer';

  @override
  String get permissions => 'Permissions';

  @override
  String get checksum => 'Somme de contrôle';

  @override
  String get calculateSize => 'Calculer la taille';

  @override
  String get batchRename => 'Renommage par lot';

  @override
  String get extractHere => 'Extraire ici';

  @override
  String get createZip => 'Créer un Zip';

  @override
  String get shareLink => 'Partager le lien';

  @override
  String get versionHistory => 'Historique des versions';

  @override
  String get findDuplicates => 'Trouver les doublons';

  @override
  String get commandPalette => 'Palette de commandes';

  @override
  String get theme => 'Thème';

  @override
  String get systemTheme => 'Système';

  @override
  String get lightTheme => 'Clair';

  @override
  String get darkTheme => 'Sombre';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'Couleur d\'accentuation';

  @override
  String get tabs => 'Onglets';

  @override
  String get newTab => 'Nouvel onglet';

  @override
  String get closeTab => 'Fermer l\'onglet';

  @override
  String get pinTab => 'Épingler l\'onglet';

  @override
  String get unpinTab => 'Désépingler l\'onglet';

  @override
  String get duplicateTab => 'Dupliquer l\'onglet';

  @override
  String get closeOtherTabs => 'Fermer les autres onglets';

  @override
  String get bookmarks => 'Signets';

  @override
  String get addBookmark => 'Ajouter un signet';

  @override
  String get removeBookmark => 'Supprimer le signet';

  @override
  String get recentLocations => 'Emplacements récents';

  @override
  String get sandboxedPathWarning =>
      'Chemin sandbox - Utilisez le bouton Parcourir pour sélectionner un vrai dossier';

  @override
  String get permissionDenied =>
      'Permission refusée. Utilisez le bouton Parcourir pour accorder l\'accès.';

  @override
  String get accessCancelled =>
      'Accès annulé. Utilisation du répertoire de secours.';

  @override
  String deleteFailed(String error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String renameFailed(String error) {
    return 'Échec du renommage : $error';
  }

  @override
  String operationFailed(String error) {
    return 'Échec de l\'opération : $error';
  }

  @override
  String get dropFilesToUpload => 'Déposez les fichiers ici pour les envoyer';

  @override
  String get confirmDeleteTitle => 'Confirmer la suppression';

  @override
  String confirmDeleteMessage(int count) {
    return 'Supprimer $count élément(s) ?';
  }

  @override
  String get multiCloudManager => 'Gestionnaire multi-cloud';

  @override
  String get addConnection => 'Ajouter une connexion';

  @override
  String get cloudToCloudTransfer => 'Transfert cloud à cloud';

  @override
  String get compareProviders => 'Comparer les fournisseurs';

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
  String get connectToCloud => 'Connecter au cloud';

  @override
  String browseProvider(String provider) {
    return 'Browse $provider';
  }

  @override
  String get pleaseConnectRemote =>
      'Connectez-vous pour accéder aux fichiers distants';

  @override
  String get notConnected => 'Not connected';

  @override
  String get connectToCloudShort => 'Connect to cloud';

  @override
  String get loggedIn => 'Connecté';

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
  String get emptyFile => 'Fichier vide';

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
  String get open => 'Ouvrir';

  @override
  String get editSystemEditor => 'Modifier (éditeur système)';

  @override
  String get editBuiltIn => 'Modifier (éditeur intégré)';

  @override
  String get openWithSystemApp => 'Ouvrir avec l’application système';

  @override
  String get verifyAgainstRemote => 'Comparer avec le fichier distant';

  @override
  String get browseArchive => 'Browse Archive';

  @override
  String get archiveExtracted => 'Archive extracted successfully';

  @override
  String get revealInFinder => 'Afficher dans le Finder';

  @override
  String get showInExplorer => 'Afficher dans l’Explorateur';

  @override
  String get openContainingFolder => 'Ouvrir le dossier contenant';

  @override
  String get properties => 'Propriétés';

  @override
  String get copyNames => 'Copier les noms';

  @override
  String get copyPaths => 'Copier les chemins';

  @override
  String get createMd5 => 'Créer un fichier .md5';

  @override
  String get verifyChecksumFile => 'Vérifier le fichier de sommes de contrôle';

  @override
  String get splitFile => 'Diviser le fichier';

  @override
  String get combineParts => 'Assembler les parties';

  @override
  String get createLink => 'Créer un lien...';

  @override
  String get secureWipe => 'Effacement sécurisé';

  @override
  String confirmDeleteBody(int count) {
    return 'Voulez-vous vraiment supprimer $count élément(s) ?';
  }

  @override
  String totalSize(String size) {
    return 'Taille totale : $size';
  }

  @override
  String get cannotBeUndone => 'Cette action est irréversible.';

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
    return 'Copier $count élément(s)';
  }

  @override
  String moveNItems(int count) {
    return 'Déplacer $count élément(s)';
  }

  @override
  String get targetPath => 'Chemin de destination';

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
  String get appLocked => 'CrispCloud est verrouillé';

  @override
  String get enterPinToContinue =>
      'Saisissez votre code PIN ou mot de passe pour continuer';

  @override
  String get pinPassword => 'Code PIN / Mot de passe';

  @override
  String get incorrectPin => 'Code PIN ou mot de passe incorrect';

  @override
  String get tooManyAttempts =>
      'Trop de tentatives échouées. Redémarrez l’application pour réessayer.';

  @override
  String attemptsRemaining(int count) {
    return '$count tentatives restantes';
  }

  @override
  String get appLockSetup => 'Configurer le verrouillage';

  @override
  String get changeAppLockCode => 'Modifier le verrouillage';

  @override
  String get currentPin => 'Code PIN / Mot de passe actuel';

  @override
  String get newPin => 'Nouveau code PIN / mot de passe';

  @override
  String get confirmPin => 'Confirmer le code PIN / mot de passe';

  @override
  String get minFourChars => '4 caractères minimum';

  @override
  String get codesDoNotMatch => 'Les codes ne correspondent pas';

  @override
  String get autoLockAfter => 'Verrouiller automatiquement après';

  @override
  String get immediately => 'Immédiatement';

  @override
  String get oneMinute => '1 minute';

  @override
  String get fiveMinutes => '5 minutes';

  @override
  String get fifteenMinutes => '15 minutes';

  @override
  String get thirtyMinutes => '30 minutes';

  @override
  String get oneHour => '1 heure';

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
  String get noActiveOperations => 'Aucune opération en cours';

  @override
  String get refreshAll => 'Tout actualiser';

  @override
  String get newName => 'Nouveau nom';

  @override
  String get items => 'Éléments :';

  @override
  String andMore(int count) {
    return '... et $count de plus';
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
  String get computeMd5 => 'Calculer MD5';

  @override
  String get protocol => 'Protocol';
}
