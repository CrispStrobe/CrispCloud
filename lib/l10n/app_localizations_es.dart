// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'Local';

  @override
  String get remote => 'Remoto';

  @override
  String get connect => 'Conectar';

  @override
  String get disconnect => 'Desconectar';

  @override
  String get login => 'Iniciar sesión';

  @override
  String get logout => 'Cerrar sesión';

  @override
  String get upload => 'Subir';

  @override
  String get download => 'Descargar';

  @override
  String get delete => 'Eliminar';

  @override
  String get rename => 'Renombrar';

  @override
  String get move => 'Mover';

  @override
  String get copy => 'Copiar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get create => 'Crear';

  @override
  String get close => 'Cerrar';

  @override
  String get done => 'Listo';

  @override
  String get clear => 'Limpiar';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Sí';

  @override
  String get no => 'No';

  @override
  String get retry => 'Reintentar';

  @override
  String get refresh => 'Actualizar';

  @override
  String get search => 'Buscar';

  @override
  String get filter => 'Filtrar';

  @override
  String get settings => 'Ajustes';

  @override
  String get about => 'Acerca de';

  @override
  String get help => 'Ayuda';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get folderName => 'Nombre de carpeta';

  @override
  String get emptyFolder => 'Carpeta vacía';

  @override
  String get noFolderSelected => 'Ninguna carpeta seleccionada';

  @override
  String get openLocalFolder => 'Abrir carpeta local';

  @override
  String get sortByName => 'Ordenar por nombre';

  @override
  String get sortBySize => 'Ordenar por tamaño';

  @override
  String get sortByDate => 'Ordenar por fecha';

  @override
  String get sortByExtension => 'Ordenar por extensión';

  @override
  String get ascending => 'Ascendente';

  @override
  String get descending => 'Descendente';

  @override
  String get selectAll => 'Seleccionar todo';

  @override
  String get clearSelection => 'Borrar selección';

  @override
  String nSelected(int count) {
    return '$count seleccionado(s)';
  }

  @override
  String get filterFiles => 'Filtrar archivos';

  @override
  String get typeToFilter => 'Escriba para filtrar...';

  @override
  String get filterFilesShortcut => 'Filtrar archivos (Ctrl+F)';

  @override
  String get clearFilter => 'Borrar filtro';

  @override
  String get browseTooltip => 'Examinar...';

  @override
  String get upTooltip => 'Arriba (Retroceso)';

  @override
  String get refreshTooltip => 'Actualizar (F5)';

  @override
  String get newFolderTooltip => 'Nueva carpeta (Ctrl+N)';

  @override
  String get searchAllFiles => 'Búsqueda difusa en todos los archivos';

  @override
  String get findByPattern =>
      'Buscar archivos por patrón en esta carpeta (p. ej. *.pdf)';

  @override
  String get listView => 'Vista de lista';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get columnView => 'Vista de columnas';

  @override
  String get copyTo => 'Copiar a...';

  @override
  String get moveTo => 'Mover a...';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get connecting => 'Conectando...';

  @override
  String get connectionFailed => 'Error de conexión';

  @override
  String get provider => 'Proveedor';

  @override
  String get username => 'Nombre de usuario';

  @override
  String get password => 'Contraseña';

  @override
  String get host => 'Host';

  @override
  String get port => 'Puerto';

  @override
  String get serverUrl => 'URL del servidor';

  @override
  String get appKey => 'Clave de aplicación';

  @override
  String get clientId => 'ID de cliente';

  @override
  String get clientSecret => 'Secreto de cliente';

  @override
  String get accessKey => 'Clave de acceso';

  @override
  String get secretKey => 'Clave secreta';

  @override
  String get endpoint => 'Punto de enlace';

  @override
  String get region => 'Región';

  @override
  String get bucket => 'Bucket';

  @override
  String get twoFactorCode => 'Código 2FA';

  @override
  String transferProgress(int percent) {
    return '$percent% completado';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String transferEta(String time) {
    return '$time restante';
  }

  @override
  String get syncManager => 'Administrador de sincronización';

  @override
  String get syncAll => 'Sincronizar todo';

  @override
  String get syncNow => 'Sincronizar ahora';

  @override
  String get addPair => 'Agregar par';

  @override
  String get syncPairName => 'Nombre del par';

  @override
  String get localPath => 'Ruta local';

  @override
  String get remotePath => 'Ruta remota';

  @override
  String get conflictPolicy => 'Política de conflictos';

  @override
  String get syncDirection => 'Dirección';

  @override
  String get twoWay => 'Bidireccional';

  @override
  String get uploadOnly => 'Solo subida';

  @override
  String get downloadOnly => 'Solo descarga';

  @override
  String get newestWins => 'Más reciente gana';

  @override
  String get localWins => 'Local gana';

  @override
  String get remoteWins => 'Remoto gana';

  @override
  String get keepBoth => 'Conservar ambos';

  @override
  String get manual => 'Manual';

  @override
  String get backgroundSync => 'Sincronización en segundo plano';

  @override
  String get cloudOnlyFiles => 'Archivos solo en la nube';

  @override
  String get includePatterns => 'Patrones de inclusión';

  @override
  String get excludePatterns => 'Patrones de exclusión';

  @override
  String get encryption => 'Cifrado';

  @override
  String get encryptionEnabled => 'Cifrado habilitado';

  @override
  String get passphrase => 'Frase de contraseña';

  @override
  String get keyManagement => 'Gestión de claves';

  @override
  String get exportKey => 'Exportar clave';

  @override
  String get importKey => 'Importar clave';

  @override
  String get mnemonic => 'Mnemónico';

  @override
  String get backupBundle => 'Paquete de copia de seguridad';

  @override
  String get appLock => 'Bloqueo de aplicación';

  @override
  String get setupLock => 'Configurar bloqueo';

  @override
  String get changeLock => 'Cambiar bloqueo';

  @override
  String get disableLock => 'Desactivar bloqueo';

  @override
  String get enterPin => 'Introduzca PIN o contraseña';

  @override
  String get biometricUnlock => 'Desbloqueo biométrico';

  @override
  String get autoLockTimeout => 'Tiempo de bloqueo automático';

  @override
  String get proxySettings => 'Configuración de proxy';

  @override
  String get noProxy => 'Sin proxy';

  @override
  String get httpProxy => 'Proxy HTTP';

  @override
  String get socks5Proxy => 'Proxy SOCKS5';

  @override
  String get certificatePinning => 'Fijación de certificado';

  @override
  String get preview => 'Vista previa';

  @override
  String get edit => 'Editar';

  @override
  String get compare => 'Comparar';

  @override
  String get permissions => 'Permisos';

  @override
  String get checksum => 'Suma de verificación';

  @override
  String get calculateSize => 'Calcular tamaño';

  @override
  String get batchRename => 'Renombrado por lotes';

  @override
  String get extractHere => 'Extraer aquí';

  @override
  String get createZip => 'Crear Zip';

  @override
  String get shareLink => 'Compartir enlace';

  @override
  String get versionHistory => 'Historial de versiones';

  @override
  String get findDuplicates => 'Buscar duplicados';

  @override
  String get commandPalette => 'Paleta de comandos';

  @override
  String get theme => 'Tema';

  @override
  String get systemTheme => 'Sistema';

  @override
  String get lightTheme => 'Claro';

  @override
  String get darkTheme => 'Oscuro';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'Color de acento';

  @override
  String get tabs => 'Pestañas';

  @override
  String get newTab => 'Nueva pestaña';

  @override
  String get closeTab => 'Cerrar pestaña';

  @override
  String get pinTab => 'Fijar pestaña';

  @override
  String get unpinTab => 'Desfijar pestaña';

  @override
  String get duplicateTab => 'Duplicar pestaña';

  @override
  String get closeOtherTabs => 'Cerrar otras pestañas';

  @override
  String get bookmarks => 'Marcadores';

  @override
  String get addBookmark => 'Agregar marcador';

  @override
  String get removeBookmark => 'Eliminar marcador';

  @override
  String get recentLocations => 'Ubicaciones recientes';

  @override
  String get sandboxedPathWarning =>
      'Ruta de sandbox - Use el botón Examinar para seleccionar una carpeta real';

  @override
  String get permissionDenied =>
      'Permiso denegado. Use el botón Examinar para otorgar acceso.';

  @override
  String get accessCancelled =>
      'Acceso cancelado. Usando directorio alternativo.';

  @override
  String deleteFailed(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String renameFailed(String error) {
    return 'Error al renombrar: $error';
  }

  @override
  String operationFailed(String error) {
    return 'Error en la operación: $error';
  }

  @override
  String get dropFilesToUpload => 'Suelte archivos aquí para subir';

  @override
  String get confirmDeleteTitle => 'Confirmar eliminación';

  @override
  String confirmDeleteMessage(int count) {
    return '¿Eliminar $count elemento(s)?';
  }

  @override
  String get multiCloudManager => 'Administrador multi-nube';

  @override
  String get addConnection => 'Agregar conexión';

  @override
  String get cloudToCloudTransfer => 'Transferencia nube a nube';

  @override
  String get compareProviders => 'Comparar proveedores';

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
