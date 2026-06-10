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
