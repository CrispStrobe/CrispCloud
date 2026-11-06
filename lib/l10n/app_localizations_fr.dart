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
  String get bucket => 'Compartiment';

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
  String get oledTheme => 'Noir OLED';

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
  String get singlePanel => 'Panneau unique';

  @override
  String get dualPanel => 'Deux panneaux';

  @override
  String get showTreeSidebar => 'Afficher l’arborescence';

  @override
  String get hideTreeSidebar => 'Masquer l’arborescence';

  @override
  String get detailsList => 'Liste détaillée';

  @override
  String get largeItems => 'Grands éléments';

  @override
  String get compactItems => 'Éléments compacts';

  @override
  String get showPreview => 'Afficher l’aperçu';

  @override
  String get hidePreview => 'Masquer l’aperçu';

  @override
  String get showTerminal => 'Afficher le terminal';

  @override
  String get hideTerminal => 'Masquer le terminal';

  @override
  String get moreActions => 'Plus d’actions';

  @override
  String get mountAsDrive => 'Monter comme lecteur';

  @override
  String get auditLog => 'Journal d’audit';

  @override
  String get systemLog => 'Journal système';

  @override
  String get cacheSettings => 'Paramètres du cache';

  @override
  String get keyboardShortcuts => 'Raccourcis clavier';

  @override
  String get swapPanels => 'Inverser les panneaux';

  @override
  String get connectToCloud => 'Connecter au cloud';

  @override
  String browseProvider(String provider) {
    return 'Parcourir $provider';
  }

  @override
  String get pleaseConnectRemote =>
      'Connectez-vous pour accéder aux fichiers distants';

  @override
  String get notConnected => 'Non connecté';

  @override
  String get connectToCloudShort => 'Se connecter au cloud';

  @override
  String get loggedIn => 'Connecté';

  @override
  String get localFiles => 'Fichiers locaux';

  @override
  String get remoteFiles => 'Fichiers distants';

  @override
  String get bookmarkFolder => 'Ajouter le dossier actuel aux favoris';

  @override
  String get noFolders => 'Aucun dossier';

  @override
  String get selectFileToPreview => 'Sélectionnez un fichier à prévisualiser';

  @override
  String fileTooLarge(String size) {
    return 'Fichier trop volumineux pour l’aperçu ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'Échec de l’aperçu : $error';
  }

  @override
  String get firstPage => 'Première page';

  @override
  String get previousPage => 'Page précédente';

  @override
  String get nextPage => 'Page suivante';

  @override
  String get lastPage => 'Dernière page';

  @override
  String get playAudio => 'Lire l’audio';

  @override
  String get playVideo => 'Lire la vidéo';

  @override
  String get emptyFile => 'Fichier vide';

  @override
  String systemLogTitle(int count) {
    return 'Journal système ($count entrées)';
  }

  @override
  String get minimumLevel => 'Niveau minimal';

  @override
  String get pauseAutoScroll => 'Suspendre le défilement automatique';

  @override
  String get resumeAutoScroll => 'Reprendre le défilement automatique';

  @override
  String get copyVisible => 'Copier les lignes visibles';

  @override
  String get copyAll => 'Tout copier';

  @override
  String get filterLogs => 'Filtrer les journaux...';

  @override
  String get visibleLinesCopied => 'Lignes visibles copiées';

  @override
  String get allLogsCopied => 'Tous les journaux copiés';

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
  String get browseArchive => 'Parcourir l’archive';

  @override
  String get archiveExtracted => 'Archive extraite avec succès';

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
    return '$count éléments';
  }

  @override
  String nTransfers(int count) {
    return '$count transfert(s)';
  }

  @override
  String get syncing => 'Synchronisation';

  @override
  String lastSyncChanges(int count) {
    return 'Dernière synchronisation : $count modifications';
  }

  @override
  String nPairs(int count) {
    return '$count paire(s)';
  }

  @override
  String get hidden => 'Masqués';

  @override
  String free(String size) {
    return 'Libre : $size';
  }

  @override
  String get aboutLegal => 'À propos / Mentions légales';

  @override
  String get appDescription =>
      'Un client non officiel et open source pour Filen.io, SFTP et WebDAV.';

  @override
  String get serviceProvider => 'Fournisseur de services';

  @override
  String get contact => 'Contact';

  @override
  String get disclaimer => 'Avertissement';

  @override
  String get disclaimerText =>
      'Ce logiciel est fourni en l’état, sans aucune garantie. Cette application n’est affiliée ni à Filen.io ni à aucun autre fournisseur cloud.';

  @override
  String get sourceCode => 'Code source (GitHub)';

  @override
  String get website => 'Site web';

  @override
  String get viewLicenses => 'Voir les licences open source';

  @override
  String get flatView => 'Vue à plat (tous les sous-dossiers)';

  @override
  String get exitFlatView => 'Quitter la vue à plat';

  @override
  String get showHiddenFiles => 'Afficher les fichiers cachés';

  @override
  String get hideHiddenFiles => 'Masquer les fichiers cachés';

  @override
  String get touchFriendlyView => 'Passer à la vue tactile';

  @override
  String get compactView => 'Passer à la vue compacte';

  @override
  String get sort => 'Trier';

  @override
  String get secondarySort => 'Tri secondaire';

  @override
  String get none => 'Aucun';

  @override
  String get byName => 'par nom';

  @override
  String get bySize => 'par taille';

  @override
  String get byDate => 'par date';

  @override
  String get enterPath => 'Saisir le chemin...';

  @override
  String get editPath => 'Modifier le chemin';

  @override
  String get searchResults => 'Résultats de recherche';

  @override
  String nFiles(int count) {
    return '$count fichier(s)';
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
    return 'Enregistré : $name';
  }

  @override
  String saveFailed(String error) {
    return 'Échec de l’enregistrement : $error';
  }

  @override
  String get unsavedChanges => 'Modifications non enregistrées';

  @override
  String get discardChanges =>
      'Vous avez des modifications non enregistrées. Les abandonner ?';

  @override
  String get discard => 'Abandonner';

  @override
  String get saveShortcut => 'Enregistrer (Ctrl+S)';

  @override
  String get fileModifiedOnServer =>
      'Ce fichier a été modifié sur le serveur depuis son ouverture.';

  @override
  String get saveAnyway => 'Enregistrer quand même';

  @override
  String get reload => 'Recharger';

  @override
  String get saveProfile => 'Enregistrer le profil';

  @override
  String get profileName => 'Nom du profil';

  @override
  String get profileNameHint => 'ex. S3 professionnel, SFTP personnel';

  @override
  String profileSaved(String name) {
    return 'Profil « $name » enregistré';
  }

  @override
  String get connectToCloudStorage => 'Se connecter au stockage cloud';

  @override
  String get savedProfiles => 'Profils enregistrés';

  @override
  String get loadProfile => 'Charger un profil enregistré...';

  @override
  String get deleteProfile => 'Supprimer le profil';

  @override
  String get saveAsProfile => 'Enregistrer comme profil';

  @override
  String get enableEncryption => 'Activer le chiffrement côté client';

  @override
  String get encryptBeforeUpload =>
      'Chiffrer les fichiers avant l’envoi (AES-256-GCM)';

  @override
  String get encryptionPassphrase => 'Phrase secrète de chiffrement';

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
  String get connectToHetzner => 'Se connecter à Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP (port 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => 'Tester la connexion';

  @override
  String get connectionSuccessful => 'Connexion réussie';

  @override
  String testFailed(String error) {
    return 'Échec du test : $error';
  }

  @override
  String get connectToAzure => 'Se connecter à Azure Blob Storage';

  @override
  String get authenticationMode => 'Mode d’authentification';

  @override
  String get accountName => 'Nom du compte';

  @override
  String get container => 'Conteneur';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'Jeton SAS';

  @override
  String get connectToB2 => 'Se connecter à Backblaze B2';

  @override
  String get applicationKeyId => 'Identifiant de clé d’application';

  @override
  String get applicationKey => 'Clé d’application';

  @override
  String get bucketNameOptional => 'Nom du compartiment (facultatif)';

  @override
  String get mount => 'Monter';

  @override
  String get unmount => 'Démonter';

  @override
  String get displayName => 'Nom affiché';

  @override
  String get localMountPoint => 'Point de montage local';

  @override
  String get newMount => 'Nouveau montage';

  @override
  String get noMountsConfigured => 'Aucun montage configuré';

  @override
  String get fuseDesktopOnly =>
      'Les montages FUSE sont disponibles uniquement sur macOS, Linux et Windows.';

  @override
  String get multiCloud => 'Multi-cloud';

  @override
  String get connections => 'Connexions';

  @override
  String get transfer => 'Transfert';

  @override
  String get compareAndSearch => 'Comparer et rechercher';

  @override
  String get noConnectionsYet => 'Aucune connexion enregistrée.';

  @override
  String get startTransfer => 'Démarrer le transfert';

  @override
  String get syncPairs => 'Paires de synchronisation';

  @override
  String get enableAutoSync => 'Activer la synchronisation automatique';

  @override
  String get disableAutoSync => 'Désactiver la synchronisation automatique';

  @override
  String get noSyncPairs => 'Aucune paire de synchronisation configurée';

  @override
  String get replayOffline => 'Rejouer les opérations hors ligne';

  @override
  String get newSyncPair => 'Nouvelle paire de synchronisation';

  @override
  String get cacheUsage => 'Utilisation du cache';

  @override
  String get maximumCacheSize => 'Taille maximale du cache';

  @override
  String get clearCacheConfirm =>
      'Supprimer tous les fichiers en cache ? Ils seront téléchargés à nouveau si nécessaire.';

  @override
  String batchRenameTitle(int count) {
    return 'Renommage par lot ($count fichiers)';
  }

  @override
  String get findReplace => 'Rechercher/Remplacer';

  @override
  String get number => 'Numéro';

  @override
  String get prefixSuffix => 'Préfixe/Suffixe';

  @override
  String get extension => 'Extension';

  @override
  String get duplicateFinder => 'Recherche de doublons';

  @override
  String get noDuplicatesFound => 'Aucun doublon trouvé !';

  @override
  String get chooseTheme => 'Choisir le thème';

  @override
  String get checkForUpdates => 'Rechercher des mises à jour';

  @override
  String get youAreUpToDate => 'Vous êtes à jour';

  @override
  String get updateAvailable => 'Mise à jour disponible';

  @override
  String get releaseNotes => 'Notes de version';

  @override
  String get checkNow => 'Vérifier maintenant';

  @override
  String get general => 'Général';

  @override
  String get accessibility => 'Accessibilité';

  @override
  String get privacy => 'Confidentialité';

  @override
  String get advanced => 'Avancé';

  @override
  String get showFKeyButtons =>
      'Afficher les boutons de raccourci F3 à F8 en bas de l’écran';

  @override
  String get exportKeys => 'Exporter/Importer les clés de chiffrement';

  @override
  String get backupRecovery =>
      'Sauvegarde et récupération par phrase mnémonique BIP39';

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
  String get searchPattern => 'Motif de recherche';

  @override
  String get findPattern => 'Motif à rechercher';

  @override
  String get searchHint => 'Rechercher des fichiers...';

  @override
  String get findHint => 'ex. *.pdf, rapport*';

  @override
  String get noResultsFound => 'Aucun résultat trouvé';

  @override
  String get size => 'Taille';

  @override
  String get date => 'Date';

  @override
  String get name => 'Nom';

  @override
  String get type => 'Type';

  @override
  String get created => 'Créé';

  @override
  String get accessed => 'Dernier accès';

  @override
  String get computeMd5 => 'Calculer MD5';

  @override
  String get protocol => 'Protocole';
}
