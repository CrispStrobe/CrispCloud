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
  String get host => 'Servidor';

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
  String get bucket => 'Depósito';

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
  String get oledTheme => 'Preto OLED';

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
  String get singlePanel => 'Um painel';

  @override
  String get dualPanel => 'Dois painéis';

  @override
  String get showTreeSidebar => 'Mostrar árvore lateral';

  @override
  String get hideTreeSidebar => 'Ocultar árvore lateral';

  @override
  String get detailsList => 'Lista detalhada';

  @override
  String get largeItems => 'Itens grandes';

  @override
  String get compactItems => 'Itens compactos';

  @override
  String get showPreview => 'Mostrar pré-visualização';

  @override
  String get hidePreview => 'Ocultar pré-visualização';

  @override
  String get showTerminal => 'Mostrar terminal';

  @override
  String get hideTerminal => 'Ocultar terminal';

  @override
  String get moreActions => 'Mais ações';

  @override
  String get mountAsDrive => 'Montar como unidade';

  @override
  String get auditLog => 'Registo de auditoria';

  @override
  String get systemLog => 'Registo do sistema';

  @override
  String get cacheSettings => 'Definições da cache';

  @override
  String get keyboardShortcuts => 'Atalhos de teclado';

  @override
  String get swapPanels => 'Trocar painéis';

  @override
  String get connectToCloud => 'Ligar à nuvem';

  @override
  String browseProvider(String provider) {
    return 'Explorar $provider';
  }

  @override
  String get pleaseConnectRemote =>
      'Ligue-se para aceder aos ficheiros remotos';

  @override
  String get notConnected => 'Não ligado';

  @override
  String get connectToCloudShort => 'Ligar à nuvem';

  @override
  String get loggedIn => 'Sessão iniciada';

  @override
  String get localFiles => 'Ficheiros locais';

  @override
  String get remoteFiles => 'Ficheiros remotos';

  @override
  String get bookmarkFolder => 'Adicionar pasta atual aos marcadores';

  @override
  String get noFolders => 'Nenhuma pasta';

  @override
  String get selectFileToPreview => 'Selecione um ficheiro para pré-visualizar';

  @override
  String fileTooLarge(String size) {
    return 'Ficheiro demasiado grande para pré-visualização ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'Falha na pré-visualização: $error';
  }

  @override
  String get firstPage => 'Primeira página';

  @override
  String get previousPage => 'Página anterior';

  @override
  String get nextPage => 'Página seguinte';

  @override
  String get lastPage => 'Última página';

  @override
  String get playAudio => 'Reproduzir áudio';

  @override
  String get playVideo => 'Reproduzir vídeo';

  @override
  String get emptyFile => 'Arquivo vazio';

  @override
  String systemLogTitle(int count) {
    return 'Registo do sistema ($count entradas)';
  }

  @override
  String get minimumLevel => 'Nível mínimo';

  @override
  String get pauseAutoScroll => 'Pausar deslocação automática';

  @override
  String get resumeAutoScroll => 'Retomar deslocação automática';

  @override
  String get copyVisible => 'Copiar linhas visíveis';

  @override
  String get copyAll => 'Copiar tudo';

  @override
  String get filterLogs => 'Filtrar registos...';

  @override
  String get visibleLinesCopied => 'Linhas visíveis copiadas';

  @override
  String get allLogsCopied => 'Todos os registos copiados';

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
  String get browseArchive => 'Explorar arquivo';

  @override
  String get archiveExtracted => 'Arquivo extraído com sucesso';

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
    return '$count itens';
  }

  @override
  String nTransfers(int count) {
    return '$count transferência(s)';
  }

  @override
  String get syncing => 'Sincronizando';

  @override
  String lastSyncChanges(int count) {
    return 'Última sincronização: $count alterações';
  }

  @override
  String nPairs(int count) {
    return '$count par(es)';
  }

  @override
  String get hidden => 'Ocultos';

  @override
  String free(String size) {
    return 'Livre: $size';
  }

  @override
  String get aboutLegal => 'Sobre / Aviso legal';

  @override
  String get appDescription =>
      'Um cliente não oficial e de código aberto para Filen.io, SFTP e WebDAV.';

  @override
  String get serviceProvider => 'Prestador de serviços';

  @override
  String get contact => 'Contacto';

  @override
  String get disclaimer => 'Aviso legal';

  @override
  String get disclaimerText =>
      'Este software é fornecido tal como está, sem qualquer garantia. Esta aplicação não está associada à Filen.io nem a qualquer outro fornecedor de nuvem.';

  @override
  String get sourceCode => 'Código-fonte (GitHub)';

  @override
  String get website => 'Site';

  @override
  String get viewLicenses => 'Ver licenças de código aberto';

  @override
  String get flatView => 'Vista plana (todas as subpastas)';

  @override
  String get exitFlatView => 'Sair da vista plana';

  @override
  String get showHiddenFiles => 'Mostrar ficheiros ocultos';

  @override
  String get hideHiddenFiles => 'Ocultar ficheiros ocultos';

  @override
  String get touchFriendlyView => 'Mudar para vista tátil';

  @override
  String get compactView => 'Mudar para vista compacta';

  @override
  String get sort => 'Ordenar';

  @override
  String get secondarySort => 'Ordenação secundária';

  @override
  String get none => 'Nenhum';

  @override
  String get byName => 'por nome';

  @override
  String get bySize => 'por tamanho';

  @override
  String get byDate => 'por data';

  @override
  String get enterPath => 'Introduzir caminho...';

  @override
  String get editPath => 'Editar caminho';

  @override
  String get searchResults => 'Resultados da pesquisa';

  @override
  String nFiles(int count) {
    return '$count arquivo(s)';
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
    return 'Guardado: $name';
  }

  @override
  String saveFailed(String error) {
    return 'Falha ao guardar: $error';
  }

  @override
  String get unsavedChanges => 'Alterações por guardar';

  @override
  String get discardChanges =>
      'Tem alterações por guardar. Pretende descartá-las?';

  @override
  String get discard => 'Descartar';

  @override
  String get saveShortcut => 'Guardar (Ctrl+S)';

  @override
  String get fileModifiedOnServer =>
      'Este ficheiro foi alterado no servidor desde que o abriu.';

  @override
  String get saveAnyway => 'Guardar mesmo assim';

  @override
  String get reload => 'Recarregar';

  @override
  String get saveProfile => 'Guardar perfil';

  @override
  String get profileName => 'Nome do perfil';

  @override
  String get profileNameHint => 'ex.: S3 de trabalho, SFTP pessoal';

  @override
  String profileSaved(String name) {
    return 'Perfil «$name» guardado';
  }

  @override
  String get connectToCloudStorage => 'Ligar ao armazenamento na nuvem';

  @override
  String get savedProfiles => 'Perfis guardados';

  @override
  String get loadProfile => 'Carregar um perfil guardado...';

  @override
  String get deleteProfile => 'Eliminar perfil';

  @override
  String get saveAsProfile => 'Guardar como perfil';

  @override
  String get enableEncryption => 'Ativar encriptação do lado do cliente';

  @override
  String get encryptBeforeUpload =>
      'Encriptar ficheiros antes do carregamento (AES-256-GCM)';

  @override
  String get encryptionPassphrase => 'Frase-passe de encriptação';

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
  String get connectToHetzner => 'Ligar à Hetzner Storage Box';

  @override
  String get sftpPort23 => 'SFTP (port 23)';

  @override
  String get webdavHttps => 'WebDAV (HTTPS)';

  @override
  String get testConnection => 'Testar ligação';

  @override
  String get connectionSuccessful => 'Ligação bem-sucedida';

  @override
  String testFailed(String error) {
    return 'Falha no teste: $error';
  }

  @override
  String get connectToAzure => 'Ligar ao Azure Blob Storage';

  @override
  String get authenticationMode => 'Modo de autenticação';

  @override
  String get accountName => 'Nome da conta';

  @override
  String get container => 'Contentor';

  @override
  String get sasUrl => 'SAS URL';

  @override
  String get sasToken => 'Token SAS';

  @override
  String get connectToB2 => 'Ligar ao Backblaze B2';

  @override
  String get applicationKeyId => 'ID da chave da aplicação';

  @override
  String get applicationKey => 'Chave da aplicação';

  @override
  String get bucketNameOptional => 'Nome do depósito (opcional)';

  @override
  String get mount => 'Montar';

  @override
  String get unmount => 'Desmontar';

  @override
  String get displayName => 'Nome apresentado';

  @override
  String get localMountPoint => 'Ponto de montagem local';

  @override
  String get newMount => 'Nova montagem';

  @override
  String get noMountsConfigured => 'Nenhuma montagem configurada';

  @override
  String get fuseDesktopOnly =>
      'As montagens FUSE só estão disponíveis no macOS, Linux e Windows de ambiente de trabalho.';

  @override
  String get multiCloud => 'Multinuvem';

  @override
  String get connections => 'Ligações';

  @override
  String get transfer => 'Transferência';

  @override
  String get compareAndSearch => 'Comparar e pesquisar';

  @override
  String get noConnectionsYet => 'Ainda não há ligações registadas.';

  @override
  String get startTransfer => 'Iniciar transferência';

  @override
  String get syncPairs => 'Pares de sincronização';

  @override
  String get enableAutoSync => 'Ativar sincronização automática';

  @override
  String get disableAutoSync => 'Desativar sincronização automática';

  @override
  String get noSyncPairs => 'Nenhum par de sincronização configurado';

  @override
  String get replayOffline => 'Repetir operações offline';

  @override
  String get newSyncPair => 'Novo par de sincronização';

  @override
  String get cacheUsage => 'Utilização da cache';

  @override
  String get maximumCacheSize => 'Tamanho máximo da cache';

  @override
  String get clearCacheConfirm =>
      'Remover todos os ficheiros em cache? Serão novamente transferidos quando necessário.';

  @override
  String batchRenameTitle(int count) {
    return 'Renomeação em lote ($count ficheiros)';
  }

  @override
  String get findReplace => 'Procurar/Substituir';

  @override
  String get number => 'Número';

  @override
  String get prefixSuffix => 'Prefixo/Sufixo';

  @override
  String get extension => 'Extensão';

  @override
  String get duplicateFinder => 'Localizador de duplicados';

  @override
  String get noDuplicatesFound => 'Não foram encontrados duplicados!';

  @override
  String get chooseTheme => 'Escolher tema';

  @override
  String get checkForUpdates => 'Procurar atualizações';

  @override
  String get youAreUpToDate => 'Está atualizado';

  @override
  String get updateAvailable => 'Atualização disponível';

  @override
  String get releaseNotes => 'Notas de versão';

  @override
  String get checkNow => 'Verificar agora';

  @override
  String get general => 'Geral';

  @override
  String get accessibility => 'Acessibilidade';

  @override
  String get privacy => 'Privacidade';

  @override
  String get advanced => 'Avançado';

  @override
  String get showFKeyButtons =>
      'Mostrar botões de atalho F3-F8 na parte inferior do ecrã';

  @override
  String get exportKeys => 'Exportar/Importar chaves de encriptação';

  @override
  String get backupRecovery =>
      'Cópia de segurança e recuperação com frase mnemónica BIP39';

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
  String get searchPattern => 'Padrão de pesquisa';

  @override
  String get findPattern => 'Padrão a procurar';

  @override
  String get searchHint => 'Pesquisar ficheiros...';

  @override
  String get findHint => 'ex.: *.pdf, relatório*';

  @override
  String get noResultsFound => 'Nenhum resultado encontrado';

  @override
  String get size => 'Tamanho';

  @override
  String get date => 'Data';

  @override
  String get name => 'Nome';

  @override
  String get type => 'Tipo';

  @override
  String get created => 'Criado';

  @override
  String get accessed => 'Último acesso';

  @override
  String get computeMd5 => 'Calcular MD5';

  @override
  String get protocol => 'Protocolo';
}
