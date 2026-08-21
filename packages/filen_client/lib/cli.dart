/// CLI dispatcher for the Filen CLI.
///
/// Routes user commands to the appropriate handler methods.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_dav/shelf_dav.dart';

import 'package:filen_client/filen_client.dart';
import 'package:filen_client/webdav_filesystem.dart';

class FilenCLI {
  final ConfigService config;
  late final FilenClient client;
  bool debugMode = false;
  bool force = false;

  FilenCLI()
      : config = ConfigService(
            configPath: p.join(
                Platform.environment['HOME'] ??
                    Platform.environment['USERPROFILE'] ??
                    '.',
                '.filen-cli')) {
    client = FilenClient(config: config);
  }

  Future<void> run(List<String> arguments) async {
    final parser = ArgParser()
      ..addFlag('verbose', abbr: 'v', help: 'Enable verbose debug output')
      ..addFlag('force', abbr: 'f', help: 'Force overwrite / ignore conflicts')
      ..addFlag('uuids', help: 'Show full UUIDs in list/search commands')
      ..addFlag('recursive', abbr: 'r', help: 'Recursive operation')
      ..addFlag('preserve-timestamps',
          abbr: 'p', help: 'Preserve file modification times')
      ..addOption('target', abbr: 't', help: 'Destination path')
      ..addOption('on-conflict',
          help: 'Action if target exists (overwrite/skip/newer)',
          allowed: ['overwrite', 'skip', 'newer'],
          defaultsTo: 'skip')
      ..addMultiOption('include', help: 'Include only files matching pattern')
      ..addMultiOption('exclude', help: 'Exclude files matching pattern')
      ..addFlag('detailed', abbr: 'd', help: 'Show detailed information')
      ..addOption('depth',
          abbr: 'l', help: 'Maximum depth for tree', defaultsTo: '3')
      ..addOption('maxdepth',
          help: 'Limit find to N levels (-1 for infinite)', defaultsTo: '-1')
      ..addFlag('background',
          abbr: 'b', help: 'Run WebDAV server in background')
      ..addFlag('daemon', hide: true, help: 'Internal: run as daemon process')
      ..addFlag('password-stdin',
          negatable: false,
          help: 'Read the password from stdin instead of prompting '
              r'(printf %s "$PW" | filen login --password-stdin)')
      ..addOption('mount-point', abbr: 'm', help: 'WebDAV mount point path')
      ..addOption('port', help: 'WebDAV server port', defaultsTo: '8080')
      ..addFlag('webdav-debug', help: 'Enable WebDAV debug logging')
      ..addOption('ssl-cert',
          help: 'Path to SSL certificate file for WebDAV HTTPS')
      ..addOption('ssl-key',
          help: 'Path to SSL private key file for WebDAV HTTPS');

    try {
      final argResults = parser.parse(arguments);
      debugMode = argResults['verbose'];
      force = argResults['force'];
      client.debugMode = debugMode;

      final commandArgs = argResults.rest;
      if (commandArgs.isEmpty) {
        printHelp();
        return;
      }

      final command = commandArgs[0];

      switch (command) {
        case 'login':
          await handleLogin(commandArgs.sublist(1),
              passwordStdin: argResults['password-stdin'] as bool);
          break;
        case 'ls':
        case 'list':
          await handleList(argResults, commandArgs.sublist(1));
          break;
        case 'mkdir':
        case 'mkdir-path':
          if (commandArgs.length < 2) _exit('Usage: mkdir <path>');
          await handleMkdir(commandArgs[1]);
          break;
        case 'upload':
        case 'up':
          await handleUpload(argResults);
          break;
        case 'download':
        case 'dl':
          if (commandArgs.length < 2) _exit('Usage: dl <file-uuid>');
          await handleDownload(argResults);
          break;
        case 'download-path':
          await handleDownloadPath(argResults);
          break;
        case 'mv':
        case 'move':
        case 'move-path':
          if (commandArgs.length < 3) _exit('Usage: mv <source> <dest>');
          await handleMove(commandArgs[1], commandArgs[2]);
          break;
        case 'cp':
        case 'copy':
          if (commandArgs.length < 3) _exit('Usage: cp <source> <dest>');
          await handleCopy(commandArgs[1], commandArgs[2]);
          break;
        case 'rm':
        case 'trash':
        case 'trash-path':
          if (commandArgs.length < 2) _exit('Usage: rm <path>');
          await handleTrash(argResults, commandArgs[1]);
          break;
        case 'delete-path':
          if (commandArgs.length < 2) _exit('Usage: delete-path <path>');
          await handleDeletePath(argResults, commandArgs[1]);
          break;
        case 'rename':
        case 'rename-path':
          if (commandArgs.length < 3) _exit('Usage: rename <path> <new_name>');
          await handleRename(commandArgs[1], commandArgs[2]);
          break;
        case 'verify':
          await handleVerify(argResults);
          break;
        case 'list-trash':
          await handleListTrash(argResults);
          break;
        case 'restore-uuid':
          await handleRestoreUuid(argResults);
          break;
        case 'restore-path':
          await handleRestorePath(argResults);
          break;
        case 'resolve':
          if (commandArgs.length < 2) _exit('Usage: resolve <path>');
          await handleResolve(commandArgs[1]);
          break;
        case 'search':
          await handleSearch(argResults);
          break;
        case 'find':
          await handleFind(argResults);
          break;
        case 'tree':
          await handleTree(argResults);
          break;
        case 'whoami':
          await handleWhoami();
          break;
        case 'logout':
          await handleLogout();
          break;
        case 'config':
          await handleConfig();
          break;
        case 'quota':
          await handleQuota();
          break;
        case 'help':
          printHelp();
          break;
        case 'mount':
        case 'webdav':
          await handleMount(argResults);
          break;
        case 'webdav-start':
          await handleWebdavStart(argResults);
          break;
        case 'webdav-stop':
          await handleWebdavStop(argResults);
          break;
        case 'webdav-status':
          await handleWebdavStatus(argResults);
          break;
        case 'webdav-test':
          await handleWebdavTest(argResults);
          break;
        case 'webdav-mount':
          await handleWebdavMount(argResults);
          break;
        case 'webdav-config':
          await handleWebdavConfig(argResults);
          break;
        default:
          _exit('Unknown command: $command');
      }
    } catch (e, stackTrace) {
      stderr.writeln('\u274c Error: $e');
      if (debugMode) stderr.writeln(stackTrace);
      exit(1);
    }
  }

  void printHelp() {
    print(
        '\u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557');
    print('\u2551    Filen CLI - v0.0.4                       \u2551');
    print(
        '\u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d');
    print('');
    print('Flags:');
    print('  -v, --verbose              Enable debug output');
    print('  -f, --force                Skip confirmations');
    print('  -b, --background           Run WebDAV in background');
    print('  --uuids                    Show full UUIDs');
    print('  -r, --recursive            Recursive operations');
    print('  -p, --preserve-timestamps  Preserve modification times');
    print('  -d, --detailed             Show detailed info');
    print('  -t, --target <path>        Destination path');
    print('  --on-conflict <mode>       skip/overwrite/newer (default: skip)');
    print('  --include <pattern>        Include file pattern');
    print('  --exclude <pattern>        Exclude file pattern');
    print('  -l, --depth <n>            Tree depth (default: 3)');
    print('  --maxdepth <n>             Find depth (-1: infinite)');
    print('  -m, --mount-point <path>   WebDAV mount point');
    print('  --port <n>                 WebDAV port (default: 8080)');
    print('  --webdav-debug             WebDAV debug logging');
    print('');
    print('File Operations:');
    print('  login                            Login to account');
    print('  whoami                           Show current user');
    print('  logout                           Logout and clear credentials');
    print('  ls [path]                        List folder contents');
    print('  mkdir <path>                     Create folder(s)');
    print('  up <sources...>                  Upload files/folders');
    print('  dl <uuid>                        Download file by UUID');
    print('  download-path <path>             Download by path');
    print('  mv <src> <dest>                  Move file/folder');
    print('  cp <src> <dest>                  Copy file/folder');
    print('  rm <path>                        Move to trash');
    print('  delete-path <path>               Permanently delete');
    print('  rename <path> <name>             Rename item');
    print('  verify <uuid|path> <local file>  Verify upload (SHA-512)');
    print('  list-trash                       Show trash contents');
    print('  restore-uuid <uuid>              Restore from trash by UUID');
    print('  restore-path <name>              Restore from trash by name');
    print('  resolve <path>                   Debug path resolution');
    print('  search <query>                   Server-side search');
    print('  find <path> <pattern>            Recursive file find');
    print('  tree [path]                      Show folder tree');
    print('  config                           Show configuration');
    print('  quota                            Show storage usage');
    print('');
    print('WebDAV Server:');
    print('  mount                      Start WebDAV (foreground)');
    print('  webdav-start               Start WebDAV server');
    print('  webdav-start -b            Start in background');
    print('  webdav-stop                Stop background server');
    print('  webdav-status              Check server status');
    print('  webdav-test                Test server connection');
    print('  webdav-mount               Show mount instructions');
    print('  webdav-config              Show server config');
  }

  // ---------------------------------------------------------------------------
  // HANDLERS
  // ---------------------------------------------------------------------------

  Future<void> handleLogin(List<String> args,
      {bool passwordStdin = false}) async {
    // Email: FILEN_EMAIL env var, else interactive prompt.
    var email = (Platform.environment['FILEN_EMAIL'] ?? '').trim();
    if (email.isEmpty) {
      stdout.write('Email: ');
      email = stdin.readLineSync()?.trim() ?? '';
    }
    if (email.isEmpty) _exit('Email is required (or set FILEN_EMAIL)');

    // Password (most to least secure): --password-stdin, FILEN_PASSWORD env,
    // interactive no-echo prompt.
    final String password;
    final envPassword = Platform.environment['FILEN_PASSWORD'];
    if (passwordStdin) {
      password =
          stdin.readLineSync()?.replaceAll(RegExp(r'[\r\n]+$'), '') ?? '';
    } else if (envPassword != null && envPassword.isNotEmpty) {
      password = envPassword;
    } else {
      stdout.write('Password: ');
      stdin.echoMode = false;
      password =
          (stdin.readLineSync() ?? '').replaceAll(RegExp(r'[\r\n]+$'), '');
      stdin.echoMode = true;
      print('');
    }
    if (password.isEmpty) _exit('Password is required');

    print('\ud83d\udd10 Logging in...');

    try {
      var credentials = await client.login(email, password);
      print('\ud83d\udcc2 Fetching root folder info...');
      client.setAuth(credentials);
      final rootUUID = await client.fetchBaseFolderUUID();
      credentials['baseFolderUUID'] = rootUUID;
      await config.saveCredentials(credentials);
      _printSuccess(credentials);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('enter_2fa') || errStr.contains('wrong_2fa')) {
        // 2FA: FILEN_2FA env var (for automation), else interactive prompt.
        var tfaCode = (Platform.environment['FILEN_2FA'] ?? '').trim();
        if (tfaCode.isEmpty) {
          print('\n\ud83d\udd10 Two-factor authentication required.');
          stdout.write('Enter 2FA code: ');
          tfaCode = stdin.readLineSync()?.trim() ?? '';
        }
        if (tfaCode.isEmpty) _exit('2FA code is required (or set FILEN_2FA)');

        try {
          var credentials =
              await client.login(email, password, twoFactorCode: tfaCode);
          print('\ud83d\udcc2 Fetching root folder info...');
          client.setAuth(credentials);
          final rootUUID = await client.fetchBaseFolderUUID();
          credentials['baseFolderUUID'] = rootUUID;
          await config.saveCredentials(credentials);
          _printSuccess(credentials);
        } catch (e2) {
          _exit('Login failed: ${e2.toString().replaceAll('Exception: ', '')}');
        }
      } else {
        _exit('Login failed: ${errStr.replaceAll('Exception: ', '')}');
      }
    }
  }

  void _printSuccess(Map<String, dynamic> creds) {
    print('\u2705 Login successful!');
    print('   User: ${creds['email']}');
    print('   Root: ${creds['baseFolderUUID']}');
    final keys = (creds['masterKeys'] ?? '').toString().split('|');
    print('   Master Keys: ${keys.length}');
  }

  Future<void> handleList(ArgResults flags, List<String> pathArgs) async {
    await _prepareClient();
    final path = pathArgs.isNotEmpty ? pathArgs.join(' ') : '/';
    final bool showFullUUIDs = flags['uuids'] || flags['detailed'];
    final bool detailed = flags['detailed'];

    final res = await client.resolvePath(path);

    if (res['type'] == 'file') {
      print('\ud83d\udcc4 File: ${p.basename(path)} (${res['uuid']})');
      return;
    }

    final uuid = res['uuid'];
    print('\ud83d\udcc2 ${res['path']} (UUID: ${uuid.substring(0, 8)}...)\n');

    final folders = await client.listFoldersAsync(uuid, detailed: detailed);
    final files = await client.listFolderFiles(uuid, detailed: detailed);
    final items = [...folders, ...files];

    if (items.isEmpty) {
      print('   (empty)');
      return;
    }

    const int nameWidth = 40;
    const int sizeWidth = 12;
    const int dateWidth = 10;
    final int uuidWidth = showFullUUIDs ? 36 : 11;

    String header;
    String top;
    String footer;

    if (detailed) {
      header =
          '\u2551  Type    ${"Name".padRight(nameWidth)}  ${"Size".padLeft(sizeWidth)}  ${"Modified".padLeft(dateWidth)}  ${"UUID".padRight(uuidWidth)} \u2551';
      top =
          '\u2554${"=" * 9}${"=" * nameWidth}${"=" * (sizeWidth + 2)}${"=" * (dateWidth + 2)}${"=" * (uuidWidth + 2)}\u2557';
      footer =
          '\u255a${"=" * 9}${"=" * nameWidth}${"=" * (sizeWidth + 2)}${"=" * (dateWidth + 2)}${"=" * (uuidWidth + 2)}\u255d';
    } else {
      header =
          '\u2551  Type    ${"Name".padRight(nameWidth)}  ${"Size".padLeft(sizeWidth)}  ${"UUID".padRight(uuidWidth)} \u2551';
      top =
          '\u2554${"=" * 9}${"=" * nameWidth}${"=" * (sizeWidth + 2)}${"=" * (uuidWidth + 2)}\u2557';
      footer =
          '\u255a${"=" * 9}${"=" * nameWidth}${"=" * (sizeWidth + 2)}${"=" * (uuidWidth + 2)}\u255d';
    }

    print(top);
    print(header);
    print(
        '\u2560${"=" * 9}${"=" * nameWidth}${"=" * (sizeWidth + 2)}${detailed ? "=" * (dateWidth + 2) : ""}${"=" * (uuidWidth + 2)}\u2563');

    int folderCount = 0;
    int fileCount = 0;

    for (var i in items) {
      final type = i['type'] == 'folder' ? '\ud83d\udcc1' : '\ud83d\udcc4';
      if (i['type'] == 'folder')
        folderCount++;
      else
        fileCount++;

      var name = i['name'] ?? 'Unknown';
      if (name.length > nameWidth)
        name = name.substring(0, nameWidth - 3) + '...';
      name = name.padRight(nameWidth);

      final size =
          (i['type'] == 'folder' ? '<DIR>' : formatSize(i['size'] ?? 0))
              .padLeft(sizeWidth);
      final itemUuid = i['uuid'] ?? 'N/A';
      final uuidDisplay =
          (showFullUUIDs ? itemUuid : '${itemUuid.substring(0, 8)}...')
              .padRight(uuidWidth);

      if (detailed) {
        final modified = i['lastModified'] ?? i['timestamp'];
        final dateDisplay = formatDate(modified).padLeft(dateWidth);
        print('\u2551  $type  $name  $size  $dateDisplay  $uuidDisplay \u2551');
      } else {
        print('\u2551  $type  $name  $size  $uuidDisplay \u2551');
      }
    }

    print(footer);
    print(
        '\n\ud83d\udcca Total: ${items.length} items ($folderCount folders, $fileCount files)');
  }

  Future<void> handleMkdir(String arg) async {
    await _prepareClient();
    print('\ud83d\udcc2 Creating "$arg"...');
    try {
      await client.createFolderRecursive(arg);
      print('\u2705 Folder created.');
    } catch (e) {
      _exit('Mkdir failed: $e');
    }
  }

  Future<void> handleVerify(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.length < 2) {
      stderr.writeln('\u274c Usage: verify <file-uuid-or-path> <local-file>');
      exit(1);
    }

    try {
      final creds = await config.readCredentials();
      if (creds == null) {
        stderr.writeln('\u274c Not logged in.');
        exit(1);
      }
      client.setAuth(creds);

      final input = args[0];
      final localPath = args[1];
      final localFile = File(localPath);

      if (!await localFile.exists()) {
        stderr.writeln('\u274c Local file not found: $localPath');
        exit(1);
      }

      final isUuid = RegExp(
              r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
              caseSensitive: false)
          .hasMatch(input);

      String fileUuid;
      if (isUuid) {
        fileUuid = input;
        print('\ud83d\udd0d Verifying upload by UUID');
        print('   Remote UUID: $fileUuid');
        print('   Local file: $localPath\n');
      } else {
        print('\ud83d\udd0d Resolving remote path: $input');
        final resolved = await client.resolvePath(input);
        if (resolved['type'] != 'file') {
          stderr.writeln('\u274c "$input" is not a file');
          exit(1);
        }
        fileUuid = resolved['uuid'];
        print('   \u2705 Resolved to UUID: $fileUuid');
        print('   Local file: $localPath\n');
      }

      final match = await client.verifyUploadMetadata(fileUuid, localFile);
      exit(match ? 0 : 1);
    } catch (e) {
      stderr.writeln('\u274c Verification failed: $e');
      exit(1);
    }
  }

  Future<void> handleUpload(ArgResults argResults) async {
    final sources = argResults.rest.sublist(1);
    if (sources.isEmpty) _exit('No source files specified');

    await _prepareClient();

    String targetPath = '/';
    List<String> actualSources = sources;

    if (argResults.wasParsed('target')) {
      targetPath = argResults['target'] as String;
    } else if (sources.length > 1) {
      final lastArg = sources.last;
      if (lastArg.startsWith('/') || !lastArg.contains('*')) {
        targetPath = lastArg;
        actualSources = sources.sublist(0, sources.length - 1);
      }
    }

    final recursive = argResults['recursive'] as bool;
    final onConflict = argResults['on-conflict'] as String;
    final preserveTimestamps = argResults['preserve-timestamps'] as bool;
    final include = argResults['include'] as List<String>;
    final exclude = argResults['exclude'] as List<String>;

    final batchId = config.generateBatchId('upload', actualSources, targetPath);
    print("\ud83d\udd04 Batch ID: $batchId");
    print("\ud83c\udfaf Target: $targetPath");
    var batchState = await config.loadBatchState(batchId);

    try {
      await client.upload(
        actualSources,
        targetPath,
        recursive: recursive,
        onConflict: onConflict,
        preserveTimestamps: preserveTimestamps,
        include: include,
        exclude: exclude,
        batchId: batchId,
        initialBatchState: batchState,
        saveStateCallback: (state) => config.saveBatchState(batchId, state),
      );

      await config.deleteBatchState(batchId);
      print("\u2705 Upload batch completed.");
    } catch (e) {
      _exit('Upload failed: $e');
    }
  }

  Future<void> handleDownload(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: dl <file-uuid-or-path>');

    await _prepareClient();
    final input = args[0];
    final onConflict = argResults['on-conflict'] as String;

    final isUuid = RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
            caseSensitive: false)
        .hasMatch(input);

    if (isUuid) {
      print('\ud83d\udce5 Downloading file by UUID: $input');
      try {
        final result = await client.downloadFile(input);
        final data = result['data'] as Uint8List;
        final filename = result['filename'] as String;
        final file = File(filename);

        if (await file.exists() && onConflict == 'skip' && !force) {
          print('\u23ed\ufe0f  Skipping: $filename (exists)');
          return;
        }

        await file.writeAsBytes(data);
        print('\u2705 Downloaded: $filename (${formatSize(data.length)})');
      } catch (e) {
        _exit('Download failed: $e');
      }
    } else {
      print('\ud83d\udd0d Resolving path: $input');
      try {
        final resolved = await client.resolvePath(input);
        if (resolved['type'] != 'file') {
          _exit("'$input' is not a file. Use 'download-path -r' for folders.");
        }
        final fileUuid = resolved['uuid'];
        final filename = p.basename(input);

        print('\ud83d\udce5 Downloading: $filename');
        await client.downloadFile(fileUuid, savePath: filename);
        print('\u2705 Downloaded: $filename');
      } catch (e) {
        _exit('Download failed: $e');
      }
    }
  }

  Future<void> handleDownloadPath(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: download-path <path>');

    await _prepareClient();

    final remotePath = args[0];
    final localDestination = argResults['target'] as String?;
    final recursive = argResults['recursive'] as bool;
    final onConflict = argResults['on-conflict'] as String;
    final preserveTimestamps = argResults['preserve-timestamps'] as bool;
    final include = argResults['include'] as List<String>;
    final exclude = argResults['exclude'] as List<String>;

    final batchId = config.generateBatchId(
        'download', [remotePath], localDestination ?? '.');
    print("\ud83d\udd04 Batch ID: $batchId");
    var batchState = await config.loadBatchState(batchId);

    try {
      await client.downloadPath(
        remotePath,
        localDestination: localDestination,
        recursive: recursive,
        onConflict: onConflict,
        preserveTimestamps: preserveTimestamps,
        include: include,
        exclude: exclude,
        batchId: batchId,
        initialBatchState: batchState,
        saveStateCallback: (state) => config.saveBatchState(batchId, state),
      );

      await config.deleteBatchState(batchId);
      print("\u2705 Download batch completed.");
    } catch (e) {
      _exit('Download failed: $e');
    }
  }

  /// Pure move/rename decision (no I/O).
  ///
  /// When the destination is an existing folder the item keeps its own name
  /// (a plain move); otherwise the destination's basename becomes the new
  /// name (a move-and-rename).
  static ({String destName, bool isRename}) planMove({
    required String srcPath,
    required String destPath,
    required bool destIsExistingFolder,
  }) =>
      destIsExistingFolder
          ? (destName: p.basename(srcPath), isRename: false)
          : (destName: p.basename(destPath), isRename: true);

  Future<void> handleMove(String srcPath, String destPath) async {
    await _prepareClient();
    final src = await client.resolvePath(srcPath);

    Map<String, dynamic>? destParent;
    String destName;
    bool isRename;

    try {
      final destObj = await client.resolvePath(destPath);
      if (destObj['type'] == 'folder') {
        destParent = destObj;
      } else {
        _exit('Destination exists as a file.');
      }
      final plan = planMove(
          srcPath: srcPath, destPath: destPath, destIsExistingFolder: true);
      destName = plan.destName;
      isRename = plan.isRename;
    } catch (_) {
      final parentDir = p.dirname(destPath);
      try {
        destParent =
            await client.resolvePath(parentDir == '.' ? '/' : parentDir);
        if (destParent['type'] != 'folder') throw Exception('Parent not dir');
      } catch (e) {
        _exit('Destination parent not found.');
      }
      final plan = planMove(
          srcPath: srcPath, destPath: destPath, destIsExistingFolder: false);
      destName = plan.destName;
      isRename = plan.isRename;
    }

    print(
        '\ud83d\ude9a Moving "${src['path']}" to "${destParent['path']}/$destName"...');

    if (src['parent'] != destParent['uuid']) {
      await client.moveItem(src['uuid'], destParent['uuid'], src['type']);
    }

    final currentName = p.basename(src['path']!);
    if (isRename && destName != currentName) {
      await client.renameItem(src['uuid'], destName, src['type']);
    }

    print('\u2705 Done.');
  }

  Future<void> handleCopy(String srcPath, String destPath) async {
    await _prepareClient();
    final src = await client.resolvePath(srcPath);
    if (src['type'] == 'folder') _exit('Folder copy not yet supported.');

    Map<String, dynamic>? destFolder;
    String targetName;

    try {
      final destObj = await client.resolvePath(destPath);
      if (destObj['type'] == 'folder') {
        destFolder = destObj;
        targetName = p.basename(srcPath);
      } else {
        if (!force) _exit('Destination exists. Use -f to overwrite.');
        final parentPath = p.dirname(destPath);
        destFolder =
            await client.resolvePath(parentPath == '.' ? '/' : parentPath);
        targetName = p.basename(destPath);
      }
    } catch (_) {
      final parentPath = p.dirname(destPath);
      try {
        destFolder =
            await client.resolvePath(parentPath == '.' ? '/' : parentPath);
      } catch (e) {
        _exit('Destination parent not found.');
      }
      targetName = p.basename(destPath);
    }

    print(
        '\ud83d\udccb Copying "${src['path']}" to "${destFolder['path']}/$targetName"...');

    final tempDir = Directory.systemTemp.createTempSync('filen_cli_cp_');
    final tempFile = File(p.join(tempDir.path, targetName));

    try {
      stdout.write('   1/2 Downloading...  \r');
      await client.downloadFile(src['uuid'], savePath: tempFile.path);

      stdout.write('   2/2 Uploading...    \r');
      await client.uploadFile(tempFile, destFolder['uuid']);

      print('\n\u2705 Copy complete.');
    } catch (e) {
      print('');
      _exit('Copy failed: $e');
    } finally {
      if (tempFile.existsSync()) tempFile.deleteSync();
      if (tempDir.existsSync()) tempDir.deleteSync();
    }
  }

  Future<void> handleRename(String path, String newName) async {
    await _prepareClient();
    final src = await client.resolvePath(path);
    print('\u270f\ufe0f Renaming "${src['path']}" to "$newName"...');
    try {
      await client.renameItem(src['uuid'], newName, src['type']);
      print('\u2705 Renamed.');
    } catch (e) {
      _exit('Rename failed: $e');
    }
  }

  Future<void> handleTrash(ArgResults argResults, String path) async {
    await _prepareClient();
    final src = await client.resolvePath(path);
    final forceFlag = argResults['force'] as bool;

    if (!forceFlag) {
      if (!_confirmAction('\u2753 Move ${src['type']} "$path" to trash?')) {
        print("\u274c Cancelled");
        return;
      }
    }

    print('\ud83d\uddd1\ufe0f Moving "${src['path']}" to trash...');
    try {
      await client.trashItem(src['uuid'], src['type']);
      print('\u2705 Trashed.');
    } catch (e) {
      _exit('Trash failed: $e');
    }
  }

  Future<void> handleDeletePath(ArgResults argResults, String path) async {
    await _prepareClient();
    final src = await client.resolvePath(path);
    final forceFlag = argResults['force'] as bool;

    print('\u26a0\ufe0f WARNING: This will PERMANENTLY delete the item!');
    if (!forceFlag) {
      if (!_confirmAction(
          '\u2753 Permanently delete ${src['type']} "$path"?')) {
        print("\u274c Cancelled");
        return;
      }
    }

    print('\ud83d\uddd1\ufe0f Deleting "${src['path']}"...');
    try {
      await client.deletePermanently(src['uuid'], src['type']);
      print('\u2705 Permanently deleted.');
    } catch (e) {
      _exit('Delete failed: $e');
    }
  }

  Future<void> handleListTrash(ArgResults argResults) async {
    await _prepareClient();
    final bool showFullUUIDs = argResults['uuids'];

    print('\ud83d\uddd1\ufe0f Listing trash contents...\n');
    final trashItems = await client.getTrashContent();

    if (trashItems.isEmpty) {
      print('\ud83d\udced Trash is empty');
      return;
    }

    for (var item in trashItems) {
      final type = item['type'] == 'folder' ? '\ud83d\udcc1' : '\ud83d\udcc4';
      final uuid = item['uuid'] ?? 'N/A';
      final uuidDisplay = showFullUUIDs ? uuid : '${uuid.substring(0, 8)}...';
      final size =
          item['type'] == 'folder' ? '<DIR>' : formatSize(item['size'] ?? 0);
      print('  $type  ${item['name']}  ($size)  [$uuidDisplay]');
    }

    print('\n\ud83d\udcca Total: ${trashItems.length} items');
  }

  Future<void> handleRestoreUuid(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: restore-uuid <uuid>');

    await _prepareClient();
    final itemUuid = args[0];
    final forceFlag = argResults['force'] as bool;

    if (!forceFlag) {
      if (!_confirmAction(
          '\u2753 Restore item "$itemUuid" to original location?')) {
        print("\u274c Cancelled");
        return;
      }
    }

    print("\ud83d\ude80 Restoring item...");
    try {
      try {
        await client.restoreItem(itemUuid, 'file');
        print("\u2705 Restored (file).");
      } catch (_) {
        await client.restoreItem(itemUuid, 'folder');
        print("\u2705 Restored (folder).");
      }
    } catch (e) {
      _exit("Failed to restore: $e");
    }
  }

  Future<void> handleRestorePath(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: restore-path <name>');

    await _prepareClient();
    final itemName = args[0];
    final forceFlag = argResults['force'] as bool;

    print("\ud83d\udd0d Finding '$itemName' in trash...");
    final trashItems = await client.getTrashContent();
    final matches = trashItems.where((i) => i['name'] == itemName).toList();

    if (matches.isEmpty) _exit("Item '$itemName' not found in trash.");
    if (matches.length > 1) {
      stderr.writeln("\u274c Multiple items named '$itemName' found in trash.");
      stderr.writeln("   Use 'restore-uuid' with one of these UUIDs:");
      for (var m in matches) {
        stderr.writeln("   - ${m['type']} ${m['uuid']}");
      }
      exit(1);
    }

    final item = matches.first;
    if (!forceFlag) {
      if (!_confirmAction('\u2753 Restore ${item['type']} "$itemName"?')) {
        print("\u274c Cancelled");
        return;
      }
    }

    print("\ud83d\ude80 Restoring item...");
    try {
      await client.restoreItem(item['uuid'], item['type']);
      print("\u2705 Restored.");
    } catch (e) {
      _exit("Restore failed: $e");
    }
  }

  Future<void> handleResolve(String path) async {
    await _prepareClient();
    print("\ud83d\udd0d Resolving path: $path");
    final resolved = await client.resolvePath(path);
    print("\n\u2705 Path resolved!");
    print("=" * 40);
    print("  Type: ${resolved['type']?.toString().toUpperCase()}");
    print("  UUID: ${resolved['uuid']}");
    print("  Path: ${resolved['path']}");
    if (resolved['metadata'] != null) {
      print("\n  Metadata:");
      (resolved['metadata'] as Map).forEach((k, v) {
        print("    $k: $v");
      });
    }
    print("=" * 40);
  }

  Future<void> handleSearch(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.isEmpty) _exit('Usage: search <query>');

    await _prepareClient();
    final query = args[0];
    final detailed = argResults['uuids'];

    print("\ud83d\udd0d Searching for '$query'...");
    final results = await client.search(query, detailed: detailed);
    final folders = results['folders']!;
    final files = results['files']!;

    if (folders.isEmpty && files.isEmpty) {
      print("\n\ud83d\udced No results found.");
      return;
    }

    print("\n" + "=" * 60);
    if (files.isNotEmpty) {
      print("\ud83d\udcc4 Files (${files.length}):");
      for (var f in files) {
        final displayName = f['fullPath'] ?? f['name'];
        print("  \ud83d\udcc4 $displayName (${f['uuid'].substring(0, 8)}...)");
      }
    }
    print("=" * 60);
  }

  Future<void> handleFind(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    if (args.length < 2) _exit('Usage: find <path> <pattern>');

    await _prepareClient();
    final path = args[0];
    final pattern = args[1];
    final maxDepth = int.tryParse(argResults['maxdepth'] ?? '-1') ?? -1;

    print("\ud83d\udd0d Finding files matching '$pattern' in '$path'...");
    final results = await client.findFiles(path, pattern, maxDepth: maxDepth);

    if (results.isEmpty) {
      print("\n\ud83d\udced No results found.");
      return;
    }

    print("\n" + "=" * 60);
    print("\ud83d\udcc4 Found Files (${results.length}):");
    for (var file in results) {
      final size = formatSize(file['size'] ?? 0);
      print("  ${file['fullPath']}  ($size)");
    }
    print("=" * 60);
  }

  Future<void> handleTree(ArgResults argResults) async {
    final args = argResults.rest.sublist(1);
    final path = args.isNotEmpty ? args[0] : '/';
    final maxDepth = int.tryParse(argResults['depth'] ?? '3') ?? 3;

    await _prepareClient();
    print("\n\ud83c\udf33 Folder tree: $path");
    print("=" * 60);
    print(path == '/' ? '\ud83d\udcc1 /' : '\ud83d\udcc1 ${p.basename(path)}');
    await client.printTree(path, (line) => print(line), maxDepth: maxDepth);
    print("\n(Showing max $maxDepth levels deep)");
  }

  Future<void> handleWhoami() async {
    final creds = await _requireAuth();
    print('\ud83d\udce7 Email: ${creds['email']}');
    print('\ud83c\udd94 User ID: ${creds['userId']}');
    print('\ud83d\udcc1 Root: ${creds['baseFolderUUID']}');
    final keys = (creds['masterKeys'] ?? '').toString().split('|');
    print('\ud83d\udd11 Master Keys: ${keys.length}');
  }

  Future<void> handleLogout() async {
    await config.clearCredentials();
    print('\u2705 Logged out');
  }

  Future<void> handleConfig() async {
    print('\ud83d\udcc1 Config dir: ${config.configDir}');
    print('\ud83d\udd10 Credentials: ${config.credentialsFile}');
    print('\ud83d\udd04 Batch states: ${config.batchStateDir}');
    print('\n\ud83c\udf10 API Endpoints:');
    print('   Gateway: ${FilenClient.apiUrl}');
    print('   Ingest: https://ingest.filen.io');
    print('   Egest: https://egest.filen.io');
  }

  Future<void> handleQuota() async {
    await _prepareClient();
    try {
      final response = await client.api.makeRequest(
        'GET',
        Uri.parse('${FilenClient.apiUrl}/v3/user/info'),
      );
      final data = json.decode(response.body);
      if (data['status'] == true && data['data'] != null) {
        final info = data['data'];
        final used = info['storageUsed'] ?? 0;
        final max = info['maxStorage'] ?? 0;
        final pct = max > 0 ? (used / max * 100).toStringAsFixed(1) : '?';
        print('\ud83d\udcca Storage Quota:');
        print('   Used:  ${formatSize(used)}');
        print('   Total: ${formatSize(max)}');
        print('   Usage: $pct%');
      } else {
        print('\u274c Could not fetch quota info');
      }
    } catch (e) {
      _exit('Quota failed: $e');
    }
  }

  // --- WebDAV ---

  Future<void> handleWebdavStart(ArgResults argResults) async {
    final bool background = argResults['background'] ?? false;
    final bool isDaemon = argResults['daemon'] ?? false;
    final int port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;

    if (isDaemon) {
      await handleMount(argResults);
      return;
    }

    final existingPid = await config.readWebdavPid();
    if (existingPid != null) {
      final isRunning = await _isProcessRunning(existingPid);
      if (isRunning) {
        stderr.writeln(
            '\u274c WebDAV server is already running (PID: $existingPid).');
        exit(1);
      } else {
        await config.clearWebdavPid();
      }
    }

    if (background) {
      print('\ud83d\ude80 Starting WebDAV server in background...');
      try {
        final process = await Process.start(
          Platform.executable,
          [
            Platform.script.toFilePath(),
            'webdav-start',
            '--daemon',
            '--port=$port'
          ],
          mode: ProcessStartMode.detached,
        );
        await Future.delayed(Duration(milliseconds: 1000));

        final isRunning = await _isProcessRunning(process.pid);
        if (!isRunning) {
          stderr.writeln('\u274c Failed to start background process');
          await config.clearWebdavPid();
          exit(1);
        }

        await config.saveWebdavPid(process.pid);
        print('\u2705 WebDAV server started (PID: ${process.pid})');
        print('   URL: http://localhost:$port/');
        print('   User: filen / Pass: filen-webdav');
        exit(0);
      } catch (e) {
        stderr.writeln('\u274c Failed to start background process: $e');
        exit(1);
      }
    }

    print('\ud83d\ude80 Starting WebDAV server in foreground...');
    print('   (Press Ctrl+C to stop)');
    await handleMount(argResults);
  }

  Future<void> handleWebdavStop(ArgResults argResults) async {
    print('\ud83d\uded1 Stopping WebDAV server...');
    final pid = await config.readWebdavPid();
    if (pid == null) {
      print('\u274c Server does not appear to be running.');
      exit(1);
    }

    try {
      final exists = await _isProcessRunning(pid);
      if (!exists) {
        print('\u26a0\ufe0f Process is not running. Cleaning up.');
        await config.clearWebdavPid();
        exit(0);
      }

      Process.killPid(pid, ProcessSignal.sigterm);
      await Future.delayed(Duration(milliseconds: 500));

      if (await _isProcessRunning(pid)) {
        Process.killPid(pid, ProcessSignal.sigkill);
        await Future.delayed(Duration(milliseconds: 200));
      }

      print('\u2705 Server stopped (PID: $pid).');
    } catch (e) {
      print('\u26a0\ufe0f Error terminating process: $e');
    }

    await config.clearWebdavPid();
  }

  Future<void> handleWebdavStatus(ArgResults argResults) async {
    final pid = await config.readWebdavPid();
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;

    if (pid == null) {
      print('\u274c WebDAV server is not running.');
      exit(1);
    }

    if (!await _isProcessRunning(pid)) {
      print(
          '\u274c WebDAV server PID file exists but process is not running (PID: $pid).');
      exit(1);
    }

    print('\u2705 WebDAV server is running (PID: $pid)');
    print('   URL: http://localhost:$port/');
    print('   User: filen / Pass: filen-webdav');
  }

  Future<void> handleWebdavTest(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final url = Uri.parse('http://localhost:$port/');
    print('\ud83e\uddea Testing WebDAV server at $url ...');

    final basicAuth =
        'Basic ${base64Encode(utf8.encode('filen:filen-webdav'))}';

    try {
      final request = http.Request('PROPFIND', url)
        ..headers['Authorization'] = basicAuth
        ..headers['Depth'] = '0'
        ..headers['Content-Type'] = 'application/xml'
        ..body =
            '<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/></D:prop></D:propfind>';

      final response =
          await http.Client().send(request).timeout(Duration(seconds: 10));
      await response.stream.drain<void>();

      if (response.statusCode == 207) {
        print('\u2705 Connection successful! (207 Multi-Status)');
      } else {
        print('\u274c Connection failed (${response.statusCode})');
      }
    } catch (e) {
      if (e is SocketException) {
        print('\u274c Server not reachable at $url');
      } else if (e is TimeoutException) {
        print('\u274c Connection timed out');
      } else {
        print('\u274c Connection test failed: $e');
      }
    }
  }

  Future<void> handleWebdavMount(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final url = 'http://localhost:$port/';

    print('\ud83d\uddc2\ufe0f  Mount Instructions');
    print('=' * 50);
    print('Server URL: $url');
    print('Username:   filen');
    print('Password:   filen-webdav');
    print('\n--- Linux (davfs2) ---');
    print('sudo mount -t davfs $url /mnt/filen');
    print('\n--- macOS (Finder) ---');
    print('Cmd+K > $url');
    print('\n--- Windows ---');
    print('net use Z: $url /user:filen filen-webdav');
  }

  Future<void> handleWebdavConfig(ArgResults argResults) async {
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    print('\u2699\ufe0f  WebDAV Server Configuration');
    print('   Host: localhost');
    print('   Port: $port');
    print('   User: filen / Pass: filen-webdav');
    print('   Protocol: http');
    print('   PID File: ${config.webdavPidFile}');
  }

  Future<void> handleMount(ArgResults argResults) async {
    await _prepareClient();
    final port = int.tryParse(argResults['port'] ?? '8080') ?? 8080;
    final sslCertPath = argResults['ssl-cert'] as String?;
    final sslKeyPath = argResults['ssl-key'] as String?;
    final useSSL = sslCertPath != null && sslKeyPath != null;

    print('\ud83d\udd10 User: ${client.email}');
    print(
        '\ud83c\udf10 Starting WebDAV server on port $port${useSSL ? " (HTTPS)" : ""}...\n');

    try {
      final filenFS = FilenFileSystem(client: client);

      final davConfig = DAVConfig(
        root: filenFS.directory('/'),
        prefix: '/',
        authenticationProvider: BasicAuthenticationProvider.plaintext(
          realm: 'Filen WebDAV',
          users: {'filen': 'filen-webdav'},
        ),
        authorizationProvider: RoleBasedAuthorizationProvider(
          readWriteUsers: {'filen'},
          allowAnonymousRead: false,
        ),
        enableLocking: true,
      );

      final dav = ShelfDAV.withConfig(davConfig);

      HttpServer server;
      if (useSSL) {
        final context = SecurityContext()
          ..useCertificateChain(sslCertPath)
          ..usePrivateKey(sslKeyPath);
        server = await shelf_io.serve(
          dav.handler,
          '0.0.0.0',
          port,
          securityContext: context,
        );
      } else {
        server = await shelf_io.serve(dav.handler, '0.0.0.0', port);
      }

      final protocol = useSSL ? 'https' : 'http';
      print('\u2705 WebDAV server started!');
      print('\ud83d\udce1 URL: $protocol://localhost:$port/');
      print(
          '\ud83d\udce1 Network: $protocol://${await _getLocalIpAddress()}:$port/');
      print('\ud83d\udd10 Auth: filen / filen-webdav');
      if (useSSL) print('\ud83d\udd12 SSL: enabled');
      print('\n\ud83d\uded1 Press Ctrl+C to stop\n');

      ProcessSignal.sigint.watch().listen((_) async {
        print('\n\ud83d\uded1 Shutting down...');
        await server.close(force: true);
        await config.clearWebdavPid();
        print('\u2705 Server stopped.');
        exit(0);
      });

      ProcessSignal.sigterm.watch().listen((_) async {
        await server.close(force: true);
        await config.clearWebdavPid();
        exit(0);
      });
    } catch (e, stackTrace) {
      stderr.writeln('\u274c Failed to start WebDAV server: $e');
      if (debugMode) stderr.writeln(stackTrace);
      await config.clearWebdavPid();
      exit(1);
    }
  }

  // --- Helpers ---

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return 'localhost';
  }

  Future<void> _prepareClient() async {
    final c = await config.readCredentials();
    if (c == null) _exit('Not logged in');
    client.setAuth(c);
    if (client.baseFolderUUID.isEmpty) {
      try {
        client.baseFolderUUID = await client.fetchBaseFolderUUID();
        c['baseFolderUUID'] = client.baseFolderUUID;
        await config.saveCredentials(c);
      } catch (_) {
        _exit('Could not fetch root UUID');
      }
    }
  }

  Future<Map<String, dynamic>> _requireAuth() async {
    final creds = await config.readCredentials();
    if (creds == null) _exit('Not logged in. Run "login" first.');
    return creds;
  }

  bool _confirmAction(String prompt) {
    stdout.write('$prompt [y/N]: ');
    final response = stdin.readLineSync()?.toLowerCase().trim();
    return response == 'y' || response == 'yes';
  }

  Future<bool> _isProcessRunning(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'PID eq $pid']);
        return result.stdout.toString().contains(pid.toString());
      } else {
        final result = await Process.run('ps', ['-p', pid.toString()]);
        return result.exitCode == 0;
      }
    } catch (e) {
      return false;
    }
  }

  Never _exit(String m) {
    stderr.writeln('\u274c $m');
    exit(1);
  }
}
