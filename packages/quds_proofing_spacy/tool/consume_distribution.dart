// W7 developer-only installed-package operational consumer.
// No shipped application/default changes. Save locally checked source before native use.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

const manifestSha =
    'e043af51e247368931f23fa0d9b931453e174f105b021fe2053e8e3029fd3d8d';
const librarySha =
    'ea89842ebf22c08508aff1cfbf18d78a107118af320523009616ff62b6e42977';
const prefix = 'prefix🙂: ';
const timeout = Duration(seconds: 60);
const forbiddenLoaderEnvironment = [
  'LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT', 'LD_ORIGIN_PATH',
];

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void checkLoaderEnvironment(Map<String, String> environment) {
  require(!forbiddenLoaderEnvironment.any(environment.containsKey),
      'Loader environment overrides are not admitted, including empty values.');
}

Map<String, Object?> readMap(Object? value, String label) {
  if (value is! Map<String, Object?>) throw FormatException('$label must be an object.');
  return value;
}

List<Object?> readList(Object? value, String label) {
  if (value is! List<Object?>) throw FormatException('$label must be a list.');
  return value;
}

String readString(Object? value, String label) {
  if (value is! String) throw FormatException('$label must be a string.');
  return value;
}

int readInt(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer.');
  return value;
}

bool validHash(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
String digest(List<int> bytes) => sha256.convert(bytes).toString();
bool safeMember(String value) =>
    value.isNotEmpty &&
    !value.startsWith('/') &&
    !value.contains('\\') &&
    !value.contains(':') &&
    value.split('/').every((p) => p.isNotEmpty && p != '.' && p != '..');

Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<List<int>> authenticate(File file, String sha, int maximum,
    {int? exact, int? mode}) async {
  require(validHash(sha), 'Invalid externally trusted SHA-256.');
  require(await FileSystemEntity.type(file.path, followLinks: false) ==
      FileSystemEntityType.file, 'Artifact is missing, linked or non-regular.');
  final before = await file.stat();
  require(before.size > 0 && before.size <= maximum &&
      (exact == null || before.size == exact), 'Artifact byte bound failed.');
  if (mode != null) require(before.mode & 0x1ff == mode, 'Artifact mode changed.');
  final bytes = await file.readAsBytes();
  final after = await file.stat();
  require(bytes.length == before.size && before.size == after.size &&
      before.modified == after.modified && before.changed == after.changed &&
      digest(bytes) == sha, 'Artifact changed or failed its trusted hash.');
  return bytes;
}

Future<void> directAncestors(String path) async {
  var directory = File(path).absolute.parent;
  while (true) {
    require(await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.directory, 'Linked artifact ancestor.');
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
}

Future<Map<String, Object?>> installed(String rootPath, String archiveSha) async {
  final root = Directory(rootPath).absolute;
  await directAncestors('${root.path}/distribution.json');
  require(root.uri.pathSegments.where((p) => p.isNotEmpty).last == archiveSha,
      'Installation name differs from trusted archive identity.');
  require((await root.stat()).mode & 0x1ff == 0x16d, 'Installation is not 0555.');
  final bytes = await authenticate(File('${root.path}/distribution.json'),
      manifestSha, 65536, mode: 0x124);
  final manifest = readMap(jsonDecode(utf8.decode(bytes)), 'manifest');
  require(manifest['schema'] == 'crispembed.spacy.distribution.v1', 'Wrong manifest.');
  final pins = readMap(manifest['files'], 'manifest.files');
  require(pins.length == 20, 'Incomplete installed payload.');
  final directories = <String>{};
  for (final entry in pins.entries) {
    require(safeMember(entry.key), 'Unsafe pinned member.');
    final parts = entry.key.split('/');
    for (var i = 1; i < parts.length; i++) directories.add(parts.take(i).join('/'));
    final pin = readMap(entry.value, 'payload pin');
    final size = readInt(pin['size_bytes'], 'payload size');
    await authenticate(File('${root.path}/${entry.key}'),
        readString(pin['sha256'], 'payload hash'), size, exact: size, mode: 0x124);
  }
  final seenFiles = <String>{}, seenDirectories = <String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(root.path.length + 1);
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      require(directories.contains(relative) &&
          (await entity.stat()).mode & 0x1ff == 0x16d, 'Unexpected installation directory.');
      seenDirectories.add(relative);
    } else {
      require(type == FileSystemEntityType.file &&
          (pins.containsKey(relative) || relative == 'distribution.json'),
          'Unlisted or linked installed payload.');
      seenFiles.add(relative);
    }
  }
  require(seenFiles.length == 21 && seenDirectories.length == directories.length,
      'Installed tree is incomplete.');
  final native = readMap(manifest['native'], 'manifest.native');
  require(native['library_sha256'] == librarySha &&
      manifest['bundle_manifest_sha256'] == spacyBundleManifestSha256,
      'Native/model identity changed.');
  return manifest;
}

Future<Map<String, Object?>> cpuPreflight(Map<String, Object?> protocol) async {
  require(Platform.isLinux && Abi.current() == Abi.linuxX64, 'Linux x86-64 required.');
  final platform = readMap(protocol['platform'], 'protocol.platform');
  require(platform['system'] == 'Linux' && platform['machine'] == 'x86_64',
      'Protocol target differs from the accepted platform.');
  final required = readList(platform['required_cpu_flags'], 'CPU flags')
      .map((value) => readString(value, 'CPU flag')).toList();
  require(required.toSet().containsAll(['avx', 'avx2', 'bmi2', 'f16c', 'fma', 'sse4_2']),
      'Protocol weakens the accepted CPU baseline.');
  final cpu = await File('/proc/cpuinfo').readAsString();
  final rows = RegExp(r'^flags\s*:\s*(.*)$', multiLine: true).allMatches(cpu).toList();
  require(rows.isNotEmpty && rows.every((row) {
    final flags = row.group(1)!.split(RegExp(r'\s+')).toSet();
    return required.every(flags.contains);
  }), 'CPU lacks the frozen native baseline.');
  return <String, Object?>{'abi': Abi.current().toString(), 'processor_flag_rows': rows.length,
    'required_flags': required, 'all_processor_rows_pass': true};
}

Future<List<Map<String, Object?>>> dependencyPreflight(
    String library, Map<String, Object?> manifest) async {
  // Developer harness only: ldd reads the already-authenticated candidate.
  final result = await Process.run('/usr/bin/ldd', [library]).timeout(timeout);
  require(result.exitCode == 0, 'ldd dependency resolution failed.');
  final resolved = <String, String>{};
  for (final line in readString(result.stdout, 'ldd stdout').split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 3 && parts[1] == '=>') resolved[parts[0]] = parts[2];
    if (parts.first.startsWith('/')) resolved[parts.first.split('/').last] = parts.first;
  }
  final rows = <Map<String, Object?>>[];
  final system = readMap(manifest['system_dependencies'], 'system dependencies');
  for (final raw in readList(system['qualified_resolved_files'], 'qualified files')) {
    final pin = readMap(raw, 'dependency pin');
    final name = readString(pin['soname'], 'dependency soname');
    require(resolved.containsKey(name), 'A qualified dependency was not resolved.');
    final path = await File(resolved[name]!).resolveSymbolicLinks();
    final hash = readString(pin['sha256'], 'dependency hash');
    final size = readInt(pin['bytes'], 'dependency size');
    await authenticate(File(path), hash, size, exact: size);
    rows.add(<String, Object?>{'soname': name, 'path': path, 'sha256': hash, 'bytes': size});
  }
  require(rows.length == 6, 'Qualified dependency closure is incomplete.');
  return rows;
}

Future<List<Map<String, Object?>>> mappedDependencies(
    List<Map<String, Object?>> rows, String library) async {
  final mapped = <String>{};
  for (final line in await File('/proc/self/maps').readAsLines()) {
    final match = RegExp(r'^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(/.*)$').firstMatch(line);
    if (match != null) mapped.add(match.group(1)!);
  }
  require(mapped.contains(await File(library).resolveSymbolicLinks()), 'Native library not mapped.');
  for (final row in rows) {
    final path = readString(row['path'], 'mapped path');
    final soname = readString(row['soname'], 'mapped soname');
    require(mapped.contains(path), 'A preflight dependency is not mapped.');
    require(await fileHash(File(path)) == row['sha256'], 'Mapped dependency bytes changed.');
    require(!mapped.any((other) {
      final name = other.split('/').last;
      return other != path && (name == soname || name.startsWith('$soname.'));
    }), 'A conflicting dependency image is also mapped.');
  }
  return rows.map((row) => <String, Object?>{...row, 'mapped': true}).toList();
}

String relativeSourcePath(String rootPath, String filePath) {
  var normalizedRoot = rootPath;
  while (normalizedRoot.endsWith(Platform.pathSeparator)) {
    normalizedRoot = normalizedRoot.substring(
        0, normalizedRoot.length - Platform.pathSeparator.length);
  }
  final prefix = '$normalizedRoot${Platform.pathSeparator}';
  require(filePath.startsWith(prefix), 'Source file is outside its recorded root.');
  final relative = filePath.substring(prefix.length);
  require(safeMember(relative), 'Unsafe source inventory path.');
  return relative;
}

Future<Map<String, String>> sourceHashes() async {
  final sources = <String, String>{};
  Future<void> collect(Directory root, String label) async {
    final files = await root.list(recursive: true, followLinks: false)
        .where((e) => e is File && e.path.endsWith('.dart')).cast<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      sources['$label/${relativeSourcePath(root.path, file.path)}'] = await fileHash(file);
    }
  }
  await collect(Directory.fromUri(Platform.script.resolve('../lib/')), 'quds_proofing_spacy/lib');
  for (final name in ['crypto', 'ffi', 'typed_data']) {
    final uri = await Isolate.resolvePackageUri(Uri.parse('package:$name/$name.dart'));
    require(uri != null, 'Missing pinned Dart dependency.');
    await collect(File.fromUri(uri!).parent, '$name/lib');
  }
  sources['consume_distribution.dart'] = await fileHash(File.fromUri(Platform.script));
  final config = await Isolate.packageConfig;
  require(config != null, 'Missing external package configuration.');
  sources['package_config.json'] = await fileHash(File.fromUri(config!));
  return sources;
}

LinguisticAnalysisRequest request(String id, String text, {String locale = 'de-DE'}) =>
    LinguisticAnalysisRequest(text: text, documentId: 'w7-installed-package', blockId: id,
        revision: 1, locale: locale, startOffset: prefix.length,
        configurationId: manifestSha, generation: 1);

Map<String, Object?> validateResult(LinguisticAnalysisResult result,
    LinguisticAnalysisRequest input) {
  require(result.isSuccess && result.request.sameSnapshot(input), 'Analysis/snapshot failed.');
  require(result.identity?.librarySha256 == librarySha, 'Worker identity changed.');
  final bytes = utf8.encode(input.text), scalars = input.text.runes.toList();
  final paragraph = '$prefix${input.text} suffix';
  final ranges = <Map<String, int>>[];
  for (final token in result.tokens) {
    require(input.text.substring(token.start, token.end) == token.text &&
        utf8.decode(bytes.sublist(token.byteStart, token.byteEnd)) == token.text &&
        String.fromCharCodes(scalars.sublist(token.scalarStart, token.scalarEnd)) == token.text &&
        utf8.encode(input.text.substring(0, token.start)).length == token.byteStart &&
        input.text.substring(0, token.start).runes.length == token.scalarStart,
        'Independent original-source coordinate check failed.');
    final start = input.startOffset + token.start, end = input.startOffset + token.end;
    require(paragraph.substring(start, end) == token.text, 'Nonzero-origin mapping failed.');
    ranges.add(<String, int>{'start': start, 'end': end});
  }
  return <String, Object?>{'id': input.blockId, 'utf8_sha256': digest(bytes),
    'utf16_origin': input.startOffset, 'absolute_token_ranges': ranges,
    'result': result.toJson(), 'coordinate_checks_passed': true};
}

// Request IDs are checked by sameSnapshot separately. Freeze annotations only;
// result.toJson currently omits requests, and token.toJson omits sentenceEnd.
String annotationSnapshot(LinguisticAnalysisResult result) =>
    jsonEncode(<String, Object?>{
      'tokens': result.tokens.map((token) => <String, Object?>{
        ...token.toJson(), 'sentence_end': token.sentenceEnd,
      }).toList(),
      'sentences': result.sentences.map((sentence) => sentence.toJson()).toList(),
    });

Future<void> save(File target, Map<String, Object?> report) async {
  final temporary = File('${target.path}.pending-$pid');
  await temporary.create(exclusive: true);
  try {
    await temporary.writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n', flush: true);
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<void> selfTest() async {
  require(digest(utf8.encode('abc')) ==
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'Hash control failed.');
  require(safeMember('bundle/model.gguf') &&
      ['../x', '/x', 'a//x', 'a/./x', 'a\\x', 'C:/x'].every((p) => !safeMember(p)),
      'Path controls failed.');
  final input = request('synthetic', '🙂x\u0000');
  require(input.startOffset == 10 && input.text.length == 4 &&
      utf8.encode(input.text).length == 6 && input.text.runes.length == 3,
      'UTF-16/source control failed.');
  checkLoaderEnvironment(const {'PATH': '/unused', 'CRISPEMBED_SPACY': '1'});
  var rejectedLoaderOverrides = 0;
  for (final name in forbiddenLoaderEnvironment) {
    for (final value in ['', 'test-override']) {
      var rejected = false;
      try { checkLoaderEnvironment({name: value}); }
      on StateError { rejected = true; }
      require(rejected, 'A loader override was admitted: $name.');
      rejectedLoaderOverrides++;
    }
  }
  var sourcePathControls = 0;
  for (final root in ['/package/lib', '/package/lib/']) {
    for (final relative in ['src/analysis.dart', 'quds_proofing_spacy.dart']) {
      require(relativeSourcePath(root, '/package/lib/$relative') == relative,
          'Source label loses characters at a directory boundary.');
      sourcePathControls++;
    }
  }
  var outsideRootRejected = false;
  try { relativeSourcePath('/package/lib/', '/package/library/file.dart'); }
  on StateError { outsideRootRejected = true; }
  require(outsideRootRejected, 'Sibling source directory was admitted.');
  sourcePathControls++;
  print(jsonEncode(<String, Object?>{'status': 'passed', 'model_free_controls': 17,
    'loader_environment_clean_cases': 1,
    'loader_environment_rejection_cases': rejectedLoaderOverrides,
    'source_path_controls': sourcePathControls,
    'source_hashes': await sourceHashes(),
    'native_library_loaded': false, 'native_inference_executions': 0}));
}

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--self-test') { await selfTest(); return; }
  const names = {'--archive', '--sha256', '--installed', '--protocol', '--protocol-sha256', '--report'};
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length || !names.contains(args[i]) || options.containsKey(args[i])) {
      throw ArgumentError('Expected unique --archive --sha256 --installed --protocol --protocol-sha256 --report values.');
    }
    options[args[i]] = args[i + 1];
  }
  if (options.length != names.length) throw ArgumentError('All six named arguments are required.');
  final output = File(options['--report']!).absolute;
  await output.create(exclusive: true);
  final caseReports = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'schema': 'quds.spacy.w7.installed_worker_consumer.v1', 'status': 'running',
    'started_utc': DateTime.now().toUtc().toIso8601String(),
    'scope': 'Dart worker operational package consumption; no quality score or native resource-cycle replication',
    'dart_version': Platform.version, 'os': Platform.operatingSystem,
    'archive_sha256': options['--sha256'], 'manifest_sha256': manifestSha,
    'protocol_sha256': options['--protocol-sha256'],
    'native_acceptance_rerun': false, 'grammar_qualification_rerun': false,
    'cases': caseReports, 'github_actions_queries_waits_reruns': 0,
    'typing_or_ui_activation_observed': false,
    'ui_scope': 'CLI invokes analyze explicitly; no Flutter editor or typing observation is claimed.',
  };
  SpacyTransport? worker;
  try {
    await save(output, report);
    checkLoaderEnvironment(Platform.environment);
    report['loader_overrides_absent'] = true;
    await directAncestors(options['--archive']!);
    await authenticate(File(options['--archive']!), options['--sha256']!, 16 * 1024 * 1024);
    final manifest = await installed(options['--installed']!, options['--sha256']!);
    final protocolBytes = await authenticate(File(options['--protocol']!), options['--protocol-sha256']!, 65536);
    final protocol = readMap(jsonDecode(utf8.decode(protocolBytes)), 'protocol');
    require(protocol['schema'] == 'crispembed.spacy.w7.consumer_protocol.v1', 'Wrong protocol.');
    final cases = readList(protocol['cases'], 'protocol.cases')
        .map((value) => readMap(value, 'operational case')).toList();
    require(cases.length == 8, 'Expected eight frozen operational inputs.');
    for (final item in cases) {
      readString(item['id'], 'case id');
      require(digest(utf8.encode(readString(item['text'], 'case text'))) ==
          readString(item['utf8_sha256'], 'case hash'), 'Protocol input hash mismatch.');
    }
    final cycleText = readString(protocol['cycle_text'], 'cycle text');
    require(digest(utf8.encode(cycleText)) ==
        readString(protocol['cycle_utf8_sha256'], 'cycle hash'), 'Protocol cycle input hash mismatch.');
    report['cpu_preflight'] = await cpuPreflight(protocol);
    require(Platform.environment['CRISPEMBED_SPACY'] == '1', 'Explicit CRISPEMBED_SPACY=1 is required.');
    final root = Directory(options['--installed']!).absolute.path;
    final entrypoints = readMap(manifest['entrypoints'], 'manifest.entrypoints');
    final libraryMember = readString(entrypoints['library'], 'library entrypoint');
    final bundleMember = readString(entrypoints['bundle'], 'bundle entrypoint');
    require(safeMember(libraryMember) && safeMember(bundleMember), 'Unsafe entrypoint.');
    final library = '$root/$libraryMember';
    final dependencies = await dependencyPreflight(library, manifest);
    report['dependency_preflight'] = dependencies;
    final before = await sourceHashes();
    report['sources_before'] = before;
    report['dart_executable_sha256'] = await fileHash(File(Platform.resolvedExecutable));
    final factory = SpacyNativeBackendFactory(bundleDirectory: '$root/$bundleMember',
        libraryPath: library, librarySha256: librarySha);
    Future<SpacyTransport> open() => startSpacyWorker(bundle: const SpacyBundle.germanF32(),
        backendFactory: factory, startupTimeout: timeout, requestTimeout: timeout);
    final startup = Stopwatch()..start();
    worker = await open();
    report['startup_elapsed_microseconds'] = startup.elapsedMicroseconds;
    report['mapped_dependencies'] = await mappedDependencies(dependencies, library);
    final retained = <LinguisticAnalysisResult>[];
    for (final item in cases) {
      final input = request(readString(item['id'], 'case id'), readString(item['text'], 'case text'));
      final watch = Stopwatch()..start();
      final result = await worker.analyze(input);
      retained.add(result);
      caseReports.add(<String, Object?>{...validateResult(result, input),
        'elapsed_microseconds': watch.elapsedMicroseconds});
      await save(output, report);
    }
    final unicodeCase = cases[1];
    require(unicodeCase['id'] == 'unicode_emoji', 'Frozen Unicode case moved.');
    final unicodeText = readString(unicodeCase['text'], 'Unicode case text');
    final repeatInput = request('repeat-unicode', unicodeText);
    final repeat = await worker.analyze(repeatInput);
    validateResult(repeat, repeatInput);
    require(annotationSnapshot(repeat) == annotationSnapshot(retained[1]), 'Repeated copied output changed.');
    report['same_worker_repeat_exact'] = true;
    final unsupported = await worker.analyze(request('unsupported', unicodeText, locale: 'de-AT'));
    require(unsupported.status == LinguisticAnalysisStatus.unsupported, 'Unsupported locale was not explicit.');
    report['unsupported_de_AT'] = unsupported.status.name;
    final cancelInput = request('cancel', cycleText);
    final pending = worker.analyze(cancelInput);
    worker.cancel(cancelInput.key);
    final cancelled = await pending;
    require(cancelled.status == LinguisticAnalysisStatus.cancelled, 'Caller cancellation failed.');
    report['cancellation'] = <String, Object?>{'status': cancelled.status.name,
      'scope': 'Synchronous caller cancellation after dispatch; physical compute start/interruption is not observed.'};
    final ownedBefore = retained.map((r) => jsonEncode(r.toJson())).toList();
    final shutdown = Stopwatch()..start();
    await worker.dispose().timeout(timeout);
    await worker.dispose().timeout(timeout);
    final closed = await worker.analyze(cancelInput);
    require(closed.status == LinguisticAnalysisStatus.unavailable, 'Disposed worker accepted work.');
    report['shutdown_elapsed_microseconds'] = shutdown.elapsedMicroseconds;
    report['shutdown_awaited_and_idempotent'] = true;
    worker = null;
    require(ownedBefore.asMap().entries.every((e) => e.value == jsonEncode(retained[e.key].toJson())), 'Owned results changed after disposal.');
    var immutable = false;
    try { retained[1].tokens.clear(); } on UnsupportedError { immutable = true; }
    require(immutable, 'Returned token collection is mutable.');
    report['copied_results_stable_after_disposal'] = true;
    report['returned_token_collection_immutable'] = immutable;
    worker = await open();
    final reopened = await worker.analyze(repeatInput);
    validateResult(reopened, repeatInput);
    require(annotationSnapshot(reopened) == annotationSnapshot(retained[1]), 'Reopened worker output changed.');
    report['reopened_worker_repeat_exact'] = true;
    await worker.dispose().timeout(timeout);
    worker = null;
    report['dependencies_after'] = await mappedDependencies(dependencies, library);
    await installed(options['--installed']!, options['--sha256']!);
    final after = await sourceHashes();
    report['sources_after'] = after;
    require(jsonEncode(before) == jsonEncode(after), 'Consumer source/configuration changed.');
    report['status'] = 'passed';
    report['completed_operational_cases'] = retained.length;
    report['additional_control_requests'] = 5;
    report['additional_control_request_labels'] = [
      'same-worker-repeat', 'unsupported-locale', 'cancelled-caller',
      'disposed-worker-rejection', 'reopened-worker-repeat',
    ];
  } on Object catch (error, stack) {
    report['status'] = 'failed'; report['error'] = error.toString();
    report['stack'] = stack.toString(); exitCode = 1;
  } finally {
    if (worker != null) {
      try { await worker.dispose().timeout(timeout); report['failure_cleanup_awaited'] = true; }
      on Object catch (error) { report['failure_cleanup_error'] = error.toString(); exitCode = 1; }
    }
    report['finished_utc'] = DateTime.now().toUtc().toIso8601String();
    await save(output, report);
  }
  print(jsonEncode(<String, Object?>{'status': report['status'], 'report': output.path,
    'completed_operational_cases': report['completed_operational_cases']}));
}
