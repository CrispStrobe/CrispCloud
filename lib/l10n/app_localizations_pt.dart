// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

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
  String get login => 'Entrar';

  @override
  String get logout => 'Sair';

  @override
  String get upload => 'Enviar';

  @override
  String get download => 'Baixar';

  @override
  String get delete => 'Excluir';

  @override
  String get rename => 'Renomear';

  @override
  String get move => 'Mover';

  @override
  String get copy => 'Copiar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Salvar';

  @override
  String get create => 'Criar';

  @override
  String get close => 'Fechar';

  @override
  String get done => 'Concluído';

  @override
  String get clear => 'Limpar';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Sim';

  @override
  String get no => 'Não';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get refresh => 'Atualizar';

  @override
  String get search => 'Pesquisar';

  @override
  String get filter => 'Filtrar';

  @override
  String get settings => 'Configurações';

  @override
  String get about => 'Sobre';

  @override
  String get help => 'Ajuda';

  @override
  String get newFolder => 'Nova pasta';

  @override
  String get folderName => 'Nome da pasta';

  @override
  String get emptyFolder => 'Pasta vazia';

  @override
  String get noFolderSelected => 'Nenhuma pasta selecionada';

  @override
  String get openLocalFolder => 'Abrir pasta local';

  @override
  String get sortByName => 'Ordenar por nome';

  @override
  String get sortBySize => 'Ordenar por tamanho';

  @override
  String get sortByDate => 'Ordenar por data';

  @override
  String get sortByExtension => 'Ordenar por extensão';

  @override
  String get ascending => 'Crescente';

  @override
  String get descending => 'Decrescente';

  @override
  String get selectAll => 'Selecionar tudo';

  @override
  String get clearSelection => 'Limpar seleção';

  @override
  String nSelected(int count) {
    return '$count selecionado(s)';
  }

  @override
  String get filterFiles => 'Filtrar arquivos';

  @override
  String get typeToFilter => 'Digite para filtrar...';

  @override
  String get filterFilesShortcut => 'Filtrar arquivos (Ctrl+F)';

  @override
  String get clearFilter => 'Limpar filtro';

  @override
  String get browseTooltip => 'Navegar...';

  @override
  String get upTooltip => 'Acima (Backspace)';

  @override
  String get refreshTooltip => 'Atualizar (F5)';

  @override
  String get newFolderTooltip => 'Nova pasta (Ctrl+N)';

  @override
  String get searchAllFiles => 'Pesquisa difusa em todos os arquivos';

  @override
  String get findByPattern =>
      'Encontrar arquivos por padrão nesta pasta (ex. *.pdf)';

  @override
  String get listView => 'Visualização em lista';

  @override
  String get gridView => 'Visualização em grade';

  @override
  String get columnView => 'Visualização em colunas';

  @override
  String get copyTo => 'Copiar para...';

  @override
  String get moveTo => 'Mover para...';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get connecting => 'Conectando...';

  @override
  String get connectionFailed => 'Falha na conexão';

  @override
  String get provider => 'Provedor';

  @override
  String get username => 'Nome de usuário';

  @override
  String get password => 'Senha';

  @override
  String get host => 'Host';

  @override
  String get port => 'Porta';

  @override
  String get serverUrl => 'URL do servidor';

  @override
  String get appKey => 'Chave do aplicativo';

  @override
  String get clientId => 'ID do cliente';

  @override
  String get clientSecret => 'Segredo do cliente';

  @override
  String get accessKey => 'Chave de acesso';

  @override
  String get secretKey => 'Chave secreta';

  @override
  String get endpoint => 'Ponto de extremidade';

  @override
  String get region => 'Região';

  @override
  String get bucket => 'Bucket';

  @override
  String get twoFactorCode => 'Código 2FA';

  @override
  String transferProgress(int percent) {
    return '$percent% concluído';
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
  String get syncManager => 'Gerenciador de sincronização';

  @override
  String get syncAll => 'Sincronizar tudo';

  @override
  String get syncNow => 'Sincronizar agora';

  @override
  String get addPair => 'Adicionar par';

  @override
  String get syncPairName => 'Nome do par';

  @override
  String get localPath => 'Caminho local';

  @override
  String get remotePath => 'Caminho remoto';

  @override
  String get conflictPolicy => 'Política de conflito';

  @override
  String get syncDirection => 'Direção';

  @override
  String get twoWay => 'Bidirecional';

  @override
  String get uploadOnly => 'Somente envio';

  @override
  String get downloadOnly => 'Somente download';

  @override
  String get newestWins => 'Mais recente vence';

  @override
  String get localWins => 'Local vence';

  @override
  String get remoteWins => 'Remoto vence';

  @override
  String get keepBoth => 'Manter ambos';

  @override
  String get manual => 'Manual';

  @override
  String get backgroundSync => 'Sincronização em segundo plano';

  @override
  String get cloudOnlyFiles => 'Arquivos somente na nuvem';

  @override
  String get includePatterns => 'Padrões de inclusão';

  @override
  String get excludePatterns => 'Padrões de exclusão';

  @override
  String get encryption => 'Criptografia';

  @override
  String get encryptionEnabled => 'Criptografia ativada';

  @override
  String get passphrase => 'Frase-senha';

  @override
  String get keyManagement => 'Gerenciamento de chaves';

  @override
  String get exportKey => 'Exportar chave';

  @override
  String get importKey => 'Importar chave';

  @override
  String get mnemonic => 'Mnemônico';

  @override
  String get backupBundle => 'Pacote de backup';

  @override
  String get appLock => 'Bloqueio do aplicativo';

  @override
  String get setupLock => 'Configurar bloqueio';

  @override
  String get changeLock => 'Alterar bloqueio';

  @override
  String get disableLock => 'Desativar bloqueio';

  @override
  String get enterPin => 'Inserir PIN ou senha';

  @override
  String get biometricUnlock => 'Desbloqueio biométrico';

  @override
  String get autoLockTimeout => 'Tempo limite de bloqueio automático';

  @override
  String get proxySettings => 'Configurações de proxy';

  @override
  String get noProxy => 'Sem proxy';

  @override
  String get httpProxy => 'Proxy HTTP';

  @override
  String get socks5Proxy => 'Proxy SOCKS5';

  @override
  String get certificatePinning => 'Fixação de certificado';

  @override
  String get preview => 'Visualizar';

  @override
  String get edit => 'Editar';

  @override
  String get compare => 'Comparar';

  @override
  String get permissions => 'Permissões';

  @override
  String get checksum => 'Soma de verificação';

  @override
  String get calculateSize => 'Calcular tamanho';

  @override
  String get batchRename => 'Renomear em lote';

  @override
  String get extractHere => 'Extrair aqui';

  @override
  String get createZip => 'Criar Zip';

  @override
  String get shareLink => 'Compartilhar link';

  @override
  String get versionHistory => 'Histórico de versões';

  @override
  String get findDuplicates => 'Encontrar duplicatas';

  @override
  String get commandPalette => 'Paleta de comandos';

  @override
  String get theme => 'Tema';

  @override
  String get systemTheme => 'Sistema';

  @override
  String get lightTheme => 'Claro';

  @override
  String get darkTheme => 'Escuro';

  @override
  String get oledTheme => 'OLED Black';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'Cor de destaque';

  @override
  String get tabs => 'Guias';

  @override
  String get newTab => 'Nova guia';

  @override
  String get closeTab => 'Fechar guia';

  @override
  String get pinTab => 'Fixar guia';

  @override
  String get unpinTab => 'Desafixar guia';

  @override
  String get duplicateTab => 'Duplicar guia';

  @override
  String get closeOtherTabs => 'Fechar outras guias';

  @override
  String get bookmarks => 'Favoritos';

  @override
  String get addBookmark => 'Adicionar favorito';

  @override
  String get removeBookmark => 'Remover favorito';

  @override
  String get recentLocations => 'Locais recentes';

  @override
  String get sandboxedPathWarning =>
      'Caminho sandbox - Use o botão Navegar para selecionar uma pasta real';

  @override
  String get permissionDenied =>
      'Permissão negada. Use o botão Navegar para conceder acesso.';

  @override
  String get accessCancelled =>
      'Acesso cancelado. Usando diretório alternativo.';

  @override
  String deleteFailed(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String renameFailed(String error) {
    return 'Falha ao renomear: $error';
  }

  @override
  String operationFailed(String error) {
    return 'Falha na operação: $error';
  }

  @override
  String get dropFilesToUpload => 'Solte arquivos aqui para enviar';

  @override
  String get confirmDeleteTitle => 'Confirmar exclusão';

  @override
  String confirmDeleteMessage(int count) {
    return 'Excluir $count item(ns)?';
  }

  @override
  String get multiCloudManager => 'Gerenciador multi-nuvem';

  @override
  String get addConnection => 'Adicionar conexão';

  @override
  String get cloudToCloudTransfer => 'Transferência nuvem a nuvem';

  @override
  String get compareProviders => 'Comparar provedores';

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
  String get connectToCloud => 'Ligar à nuvem';

  @override
  String browseProvider(String provider) {
    return 'Browse $provider';
  }

  @override
  String get pleaseConnectRemote =>
      'Ligue-se para aceder aos ficheiros remotos';

  @override
  String get notConnected => 'Not connected';

  @override
  String get connectToCloudShort => 'Connect to cloud';

  @override
  String get loggedIn => 'Sessão iniciada';

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
  String get emptyFile => 'Arquivo vazio';

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
  String get open => 'Abrir';

  @override
  String get editSystemEditor => 'Editar (editor do sistema)';

  @override
  String get editBuiltIn => 'Editar (editor integrado)';

  @override
  String get openWithSystemApp => 'Abrir com a aplicação do sistema';

  @override
  String get verifyAgainstRemote => 'Verificar com o ficheiro remoto';

  @override
  String get browseArchive => 'Browse Archive';

  @override
  String get archiveExtracted => 'Archive extracted successfully';

  @override
  String get revealInFinder => 'Mostrar no Finder';

  @override
  String get showInExplorer => 'Mostrar no Explorador';

  @override
  String get openContainingFolder => 'Abrir pasta de origem';

  @override
  String get properties => 'Propriedades';

  @override
  String get copyNames => 'Copiar nomes';

  @override
  String get copyPaths => 'Copiar caminhos';

  @override
  String get createMd5 => 'Criar ficheiro .md5';

  @override
  String get verifyChecksumFile => 'Verificar ficheiro de somas de verificação';

  @override
  String get splitFile => 'Dividir ficheiro';

  @override
  String get combineParts => 'Combinar partes';

  @override
  String get createLink => 'Criar ligação...';

  @override
  String get secureWipe => 'Eliminação segura';

  @override
  String confirmDeleteBody(int count) {
    return 'Tem a certeza de que pretende eliminar $count item(ns)?';
  }

  @override
  String totalSize(String size) {
    return 'Tamanho total: $size';
  }

  @override
  String get cannotBeUndone => 'Esta ação não pode ser anulada.';

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
    return 'Copiar $count item(ns)';
  }

  @override
  String moveNItems(int count) {
    return 'Mover $count item(ns)';
  }

  @override
  String get targetPath => 'Caminho de destino';

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
  String get appLocked => 'O CrispCloud está bloqueado';

  @override
  String get enterPinToContinue => 'Digite seu PIN ou senha para continuar';

  @override
  String get pinPassword => 'PIN / Senha';

  @override
  String get incorrectPin => 'PIN ou senha incorretos';

  @override
  String get tooManyAttempts =>
      'Muitas tentativas malsucedidas. Reinicie o aplicativo para tentar novamente.';

  @override
  String attemptsRemaining(int count) {
    return '$count tentativas restantes';
  }

  @override
  String get appLockSetup => 'Configurar bloqueio';

  @override
  String get changeAppLockCode => 'Alterar bloqueio';

  @override
  String get currentPin => 'PIN / Senha atual';

  @override
  String get newPin => 'Novo PIN / Senha';

  @override
  String get confirmPin => 'Confirmar PIN / Senha';

  @override
  String get minFourChars => 'Mínimo de 4 caracteres';

  @override
  String get codesDoNotMatch => 'Os códigos não coincidem';

  @override
  String get autoLockAfter => 'Bloquear automaticamente após';

  @override
  String get immediately => 'Imediatamente';

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
  String get noActiveOperations => 'Sem operações ativas';

  @override
  String get refreshAll => 'Atualizar tudo';

  @override
  String get newName => 'Novo nome';

  @override
  String get items => 'Itens:';

  @override
  String andMore(int count) {
    return '... e mais $count';
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
  String get computeMd5 => 'Calcular MD5';

  @override
  String get protocol => 'Protocol';
}
