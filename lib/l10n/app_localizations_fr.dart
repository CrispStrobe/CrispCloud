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
}
