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
  String get host => 'Servidor';

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
  String get bucket => 'Depósito';

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
  String get oledTheme => 'Negro OLED';

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
  String get singlePanel => 'Un panel';

  @override
  String get dualPanel => 'Dos paneles';

  @override
  String get showTreeSidebar => 'Mostrar árbol lateral';

  @override
  String get hideTreeSidebar => 'Ocultar árbol lateral';

  @override
  String get detailsList => 'Lista detallada';

  @override
  String get largeItems => 'Elementos grandes';

  @override
  String get compactItems => 'Elementos compactos';

  @override
  String get showPreview => 'Mostrar vista previa';

  @override
  String get hidePreview => 'Ocultar vista previa';

  @override
  String get showTerminal => 'Mostrar terminal';

  @override
  String get hideTerminal => 'Ocultar terminal';

  @override
  String get moreActions => 'Más acciones';

  @override
  String get mountAsDrive => 'Montar como unidad';

  @override
  String get auditLog => 'Registro de auditoría';

  @override
  String get systemLog => 'Registro del sistema';

  @override
  String get cacheSettings => 'Ajustes de caché';

  @override
  String get keyboardShortcuts => 'Atajos de teclado';

  @override
  String get swapPanels => 'Intercambiar paneles';

  @override
  String get connectToCloud => 'Conectar a la nube';

  @override
  String browseProvider(String provider) {
    return 'Explorar $provider';
  }

  @override
  String get pleaseConnectRemote =>
      'Conéctese para acceder a los archivos remotos';

  @override
  String get notConnected => 'No conectado';

  @override
  String get connectToCloudShort => 'Conectar a la nube';

  @override
  String get loggedIn => 'Sesión iniciada';

  @override
  String get localFiles => 'Archivos locales';

  @override
  String get remoteFiles => 'Archivos remotos';

  @override
  String get bookmarkFolder => 'Añadir carpeta actual a marcadores';

  @override
  String get noFolders => 'No hay carpetas';

  @override
  String get selectFileToPreview => 'Selecciona un archivo para previsualizar';

  @override
  String fileTooLarge(String size) {
    return 'Archivo demasiado grande para previsualizar ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'Error de vista previa: $error';
  }

  @override
  String get firstPage => 'Primera página';

  @override
  String get previousPage => 'Página anterior';

  @override
  String get nextPage => 'Página siguiente';

  @override
  String get lastPage => 'Última página';

  @override
  String get playAudio => 'Reproducir audio';

  @override
  String get playVideo => 'Reproducir vídeo';

  @override
  String get emptyFile => 'Archivo vacío';

  @override
  String systemLogTitle(int count) {
    return 'Registro del sistema ($count entradas)';
  }

  @override
  String get minimumLevel => 'Nivel mínimo';

  @override
  String get pauseAutoScroll => 'Pausar desplazamiento automático';

  @override
  String get resumeAutoScroll => 'Reanudar desplazamiento automático';

  @override
  String get copyVisible => 'Copiar líneas visibles';

  @override
  String get copyAll => 'Copiar todo';

  @override
  String get filterLogs => 'Filtrar registros...';

  @override
  String get visibleLinesCopied => 'Líneas visibles copiadas';

  @override
  String get allLogsCopied => 'Todos los registros copiados';

  @override
  String get open => 'Abrir';

  @override
  String get editSystemEditor => 'Editar (editor del sistema)';

  @override
  String get editBuiltIn => 'Editar (editor integrado)';

  @override
  String get openWithSystemApp => 'Abrir con la aplicación del sistema';

  @override
  String get verifyAgainstRemote => 'Verificar con el archivo remoto';

  @override
  String get browseArchive => 'Explorar archivo comprimido';

  @override
  String get archiveExtracted => 'Archivo extraído correctamente';

  @override
  String get revealInFinder => 'Mostrar en Finder';

  @override
  String get showInExplorer => 'Mostrar en el Explorador';

  @override
  String get openContainingFolder => 'Abrir carpeta contenedora';

  @override
  String get properties => 'Propiedades';

  @override
  String get copyNames => 'Copiar nombres';

  @override
  String get copyPaths => 'Copiar rutas';

  @override
  String get createMd5 => 'Crear archivo .md5';

  @override
  String get verifyChecksumFile => 'Verificar archivo de sumas de comprobación';

  @override
  String get splitFile => 'Dividir archivo';

  @override
  String get combineParts => 'Combinar partes';

  @override
  String get createLink => 'Crear enlace...';

  @override
  String get secureWipe => 'Borrado seguro';

  @override
  String confirmDeleteBody(int count) {
    return '¿Seguro que quieres eliminar $count elemento(s)?';
  }

  @override
  String totalSize(String size) {
    return 'Tamaño total: $size';
  }

  @override
  String get cannotBeUndone => 'Esta acción no se puede deshacer.';

  @override
  String nItems(int count) {
    return '$count elementos';
  }

  @override
  String nTransfers(int count) {
    return '$count transferencia(s)';
  }

  @override
  String get syncing => 'Sincronizando';

  @override
  String lastSyncChanges(int count) {
    return 'Última sincronización: $count cambios';
  }

  @override
  String nPairs(int count) {
    return '$count par(es)';
  }

  @override
  String get hidden => 'Ocultos';

  @override
  String free(String size) {
    return 'Libre: $size';
  }

  @override
  String get aboutLegal => 'Acerca de / Aviso legal';

  @override
  String get appDescription =>
      'Un cliente no oficial y de código abierto para Filen.io, SFTP y WebDAV.';

  @override
  String get serviceProvider => 'Proveedor de servicios';

  @override
  String get contact => 'Contacto';

  @override
  String get disclaimer => 'Aviso legal';

  @override
  String get disclaimerText =>
      'Este software se proporciona tal cual, sin garantía de ningún tipo. Esta aplicación no está afiliada a Filen.io ni a ningún otro proveedor de nube.';

  @override
  String get sourceCode => 'Código fuente (GitHub)';

  @override
  String get website => 'Sitio web';

  @override
  String get viewLicenses => 'Ver licencias de código abierto';

  @override
  String get flatView => 'Vista plana (todas las subcarpetas)';

  @override
  String get exitFlatView => 'Salir de vista plana';

  @override
  String get showHiddenFiles => 'Mostrar archivos ocultos';

  @override
  String get hideHiddenFiles => 'Ocultar archivos ocultos';

  @override
  String get touchFriendlyView => 'Cambiar a vista táctil';

  @override
  String get compactView => 'Cambiar a vista compacta';

  @override
  String get sort => 'Ordenar';

  @override
  String get secondarySort => 'Orden secundario';

  @override
  String get none => 'Ninguno';

  @override
  String get byName => 'por nombre';

  @override
  String get bySize => 'por tamaño';

  @override
  String get byDate => 'por fecha';

  @override
  String get enterPath => 'Introducir ruta...';

  @override
  String get editPath => 'Editar ruta';

  @override
  String get searchResults => 'Resultados de búsqueda';

  @override
  String nFiles(int count) {
    return '$count archivo(s)';
  }

  @override
  String copyNItems(int count) {
    return 'Copiar $count elemento(s)';
  }

  @override
  String moveNItems(int count) {
    return 'Mover $count elemento(s)';
  }

  @override
  String get targetPath => 'Ruta de destino';

  @override
  String saved(String name) {
    return 'Guardado: $name';
  }

  @override
  String saveFailed(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get unsavedChanges => 'Cambios sin guardar';

  @override
  String get discardChanges => 'Tienes cambios sin guardar. ¿Descartarlos?';

  @override
  String get discard => 'Descartar';

  @override
  String get saveShortcut => 'Guardar (Ctrl+S)';

  @override
  String get fileModifiedOnServer =>
      'Este archivo se modificó en el servidor desde que lo abriste.';

  @override
  String get saveAnyway => 'Guardar de todos modos';

  @override
  String get reload => 'Recargar';

  @override
  String get saveProfile => 'Guardar perfil';

  @override
  String get profileName => 'Nombre del perfil';

  @override
  String get profileNameHint => 'p. ej., S3 de trabajo, SFTP personal';

  @override
  String profileSaved(String name) {
    return 'Perfil «$name» guardado';
  }

  @override
  String get connectToCloudStorage => 'Conectar al almacenamiento en la nube';

  @override
  String get savedProfiles => 'Perfiles guardados';

  @override
  String get loadProfile => 'Cargar un perfil guardado...';

  @override
  String get deleteProfile => 'Eliminar perfil';

  @override
  String get saveAsProfile => 'Guardar como perfil';

  @override
  String get enableEncryption => 'Activar cifrado del lado del cliente';

  @override
  String get encryptBeforeUpload =>
      'Cifrar archivos antes de subirlos (AES-256-GCM)';

  @override
  String get encryptionPassphrase => 'Frase de cifrado';

  @override
  String get appLocked => 'CrispCloud está bloqueado';

  @override
  String get enterPinToContinue =>
      'Introduce tu PIN o contraseña para continuar';

  @override
  String get pinPassword => 'PIN / Contraseña';

  @override
  String get incorrectPin => 'PIN o contraseña incorrectos';

  @override
  String get tooManyAttempts =>
      'Demasiados intentos fallidos. Reinicia la aplicación para volver a intentarlo.';

  @override
  String attemptsRemaining(int count) {
    return 'Quedan $count intentos';
  }

  @override
  String get appLockSetup => 'Configurar bloqueo';

  @override
  String get changeAppLockCode => 'Cambiar bloqueo';

  @override
  String get currentPin => 'PIN / Contraseña actual';

  @override
  String get newPin => 'Nuevo PIN / Contraseña';

  @override
  String get confirmPin => 'Confirmar PIN / Contraseña';

  @override
  String get minFourChars => 'Mínimo 4 caracteres';

  @override
  String get codesDoNotMatch => 'Los códigos no coinciden';

  @override
  String get autoLockAfter => 'Bloquear automáticamente después de';

  @override
  String get immediately => 'Inmediatamente';

  @override
  String get oneMinute => '1 minuto';

  @override
  String get fiveMinutes => '5 minutos';

  @override
  String get fifteenMinutes => '15 minutos';

  @override
  String get thirtyMinutes => '30 minutos';

  @override
  String get oneHour => '1 hora';

  @override
  String get connectToHetzner => 'Conectar a Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP (port 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => 'Probar conexión';

  @override
  String get connectionSuccessful => 'Conexión correcta';

  @override
  String testFailed(String error) {
    return 'Error de prueba: $error';
  }

  @override
  String get connectToAzure => 'Conectar a Azure Blob Storage';

  @override
  String get authenticationMode => 'Modo de autenticación';

  @override
  String get accountName => 'Nombre de cuenta';

  @override
  String get container => 'Contenedor';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'Token SAS';

  @override
  String get connectToB2 => 'Conectar a Backblaze B2';

  @override
  String get applicationKeyId => 'ID de clave de aplicación';

  @override
  String get applicationKey => 'Clave de aplicación';

  @override
  String get bucketNameOptional => 'Nombre del depósito (opcional)';

  @override
  String get mount => 'Montar';

  @override
  String get unmount => 'Desmontar';

  @override
  String get displayName => 'Nombre visible';

  @override
  String get localMountPoint => 'Punto de montaje local';

  @override
  String get newMount => 'Nuevo montaje';

  @override
  String get noMountsConfigured => 'No hay montajes configurados';

  @override
  String get fuseDesktopOnly =>
      'Los montajes FUSE solo están disponibles en macOS, Linux y Windows de escritorio.';

  @override
  String get multiCloud => 'Multinube';

  @override
  String get connections => 'Conexiones';

  @override
  String get transfer => 'Transferencia';

  @override
  String get compareAndSearch => 'Comparar y buscar';

  @override
  String get noConnectionsYet => 'No hay conexiones registradas.';

  @override
  String get startTransfer => 'Iniciar transferencia';

  @override
  String get syncPairs => 'Pares de sincronización';

  @override
  String get enableAutoSync => 'Activar sincronización automática';

  @override
  String get disableAutoSync => 'Desactivar sincronización automática';

  @override
  String get noSyncPairs => 'No hay pares de sincronización configurados';

  @override
  String get replayOffline => 'Reanudar operaciones sin conexión';

  @override
  String get newSyncPair => 'Nuevo par de sincronización';

  @override
  String get cacheUsage => 'Uso de caché';

  @override
  String get maximumCacheSize => 'Tamaño máximo de caché';

  @override
  String get clearCacheConfirm =>
      '¿Eliminar todos los archivos de la caché? Se descargarán de nuevo cuando sea necesario.';

  @override
  String batchRenameTitle(int count) {
    return 'Renombrado por lotes ($count archivos)';
  }

  @override
  String get findReplace => 'Buscar/Reemplazar';

  @override
  String get number => 'Número';

  @override
  String get prefixSuffix => 'Prefijo/Sufijo';

  @override
  String get extension => 'Extensión';

  @override
  String get duplicateFinder => 'Buscador de duplicados';

  @override
  String get noDuplicatesFound => 'No se encontraron duplicados.';

  @override
  String get chooseTheme => 'Elegir tema';

  @override
  String get checkForUpdates => 'Buscar actualizaciones';

  @override
  String get youAreUpToDate => 'Estás al día';

  @override
  String get updateAvailable => 'Actualización disponible';

  @override
  String get releaseNotes => 'Notas de la versión';

  @override
  String get checkNow => 'Comprobar ahora';

  @override
  String get general => 'General';

  @override
  String get accessibility => 'Accesibilidad';

  @override
  String get privacy => 'Privacidad';

  @override
  String get advanced => 'Avanzado';

  @override
  String get showFKeyButtons =>
      'Mostrar los botones de atajo F3-F8 en la parte inferior';

  @override
  String get exportKeys => 'Exportar/Importar claves de cifrado';

  @override
  String get backupRecovery =>
      'Copia de seguridad y recuperación con frase mnemónica BIP39';

  @override
  String get noActiveOperations => 'No hay operaciones activas';

  @override
  String get refreshAll => 'Actualizar todo';

  @override
  String get newName => 'Nombre nuevo';

  @override
  String get items => 'Elementos:';

  @override
  String andMore(int count) {
    return '... y $count más';
  }

  @override
  String get searchPattern => 'Patrón de búsqueda';

  @override
  String get findPattern => 'Patrón a buscar';

  @override
  String get searchHint => 'Buscar archivos...';

  @override
  String get findHint => 'p. ej., *.pdf, informe*';

  @override
  String get noResultsFound => 'No se encontraron resultados';

  @override
  String get size => 'Tamaño';

  @override
  String get date => 'Fecha';

  @override
  String get name => 'Nombre';

  @override
  String get type => 'Tipo';

  @override
  String get created => 'Creado';

  @override
  String get accessed => 'Último acceso';

  @override
  String get computeMd5 => 'Calcular MD5';

  @override
  String get protocol => 'Protocolo';
}
