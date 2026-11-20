import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'analysis.dart';
import 'backend.dart';
import 'bundle.dart';
import 'macho_code_identity.dart';
import 'source_text.dart';

typedef _VersionNative = Uint32 Function();
typedef _VersionDart = int Function();
typedef _SetEnabledNative = Uint32 Function(Uint32);
typedef _SetEnabledDart = int Function(int);
typedef _CapabilitiesNative = Uint32 Function(Pointer<Void>);
typedef _CapabilitiesDart = int Function(Pointer<Void>);
typedef _CreateNative =
    Pointer<Void> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      Size,
    );
typedef _CreateDart =
    Pointer<Void> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
    );
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _AnalyzeNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Size,
      Pointer<Pointer<Void>>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Uint8>,
      Size,
    );
typedef _AnalyzeDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      Pointer<Pointer<Void>>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Uint8>,
      int,
    );
typedef _CountNative = Size Function(Pointer<Void>);
typedef _CountDart = int Function(Pointer<Void>);
typedef _AnalyzedNative = Int32 Function(Pointer<Void>);
typedef _AnalyzedDart = int Function(Pointer<Void>);
typedef _TokenNative = Int32 Function(Pointer<Void>, Size, Pointer<_TokenView>);
typedef _AttachNerNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      Size,
    );
typedef _AttachNerDart =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Uint8>,
      int,
    );
typedef _EntityNative =
    Int32 Function(Pointer<Void>, Size, Pointer<_EntityView>);
typedef _EntityDart = int Function(Pointer<Void>, int, Pointer<_EntityView>);
typedef _TokenDart = int Function(Pointer<Void>, int, Pointer<_TokenView>);

final class _TextView extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int length;
}

/// Field-for-field layout of CrispEmbed's text ABI 1. The existing source
/// header, not ffigen conventions or guessed packed layouts, owns this ABI.
final class _TokenView extends Struct {
  external _TextView text;
  external _TextView norm;
  external _TextView prefix;
  external _TextView suffix;
  external _TextView shape;
  external _TextView lemma;
  external _TextView tag;
  external _TextView pos;
  external _TextView morph;
  external _TextView dependency;
  @Size()
  external int byteStart;
  @Size()
  external int byteEnd;
  @Size()
  external int scalarStart;
  @Size()
  external int scalarEnd;
  @Size()
  external int utf16Start;
  @Size()
  external int utf16End;
  @Uint64()
  external int orthId;
  @Array(6)
  external Array<Uint64> features;
  @Int32()
  external int head;
  @Uint32()
  external int flags;
}

/// Field-for-field layout of `crispembed_spacy_entity_view` (runtime PR #240).
final class _EntityView extends Struct {
  external _TextView label;
  @Size()
  external int tokenStart;
  @Size()
  external int tokenEnd;
  @Size()
  external int byteStart;
  @Size()
  external int byteEnd;
  @Size()
  external int scalarStart;
  @Size()
  external int scalarEnd;
  @Size()
  external int utf16Start;
  @Size()
  external int utf16End;
}

/// Context capability bit reported when NER is attached.
const spacyEntitiesCapability = 16;

/// Sendable configuration; call open only inside the owned worker isolate.
///
/// The installed library must live in a directory named by its trusted SHA-256
/// (for example `<hash>/libcrispembed-spacy.so`), immutably for the process
/// lifetime. This prevents a reused dynamic-loader path naming a different
/// version after worker replacement. Model files must be immutable while open
/// verifies and native copies them. All five bundle files, including notices,
/// are authenticated before native code loads. No download or subprocess runs.
///
/// The host explicitly sets CRISPEMBED_SPACY=1 before process start, or calls
/// [enableSpacyNativeGateForProcess] after an explicit user opt-in. Opening
/// never changes the process environment itself. Recorded qualification is
/// per exact library digest (see the distribution catalog); mobile, Windows
/// and Wasm remain unavailable here.
final class SpacyNativeBackendFactory implements SpacyBackendFactory {
  SpacyNativeBackendFactory({
    required this.bundleDirectory,
    required this.libraryPath,
    required this.librarySha256,
    this.nerPath,
    this.nerSha256,
    this.hostBundled = false,
  }) {
    if ((nerPath == null) != (nerSha256 == null) ||
        (nerPath != null &&
            (nerPath!.isEmpty ||
                nerPath!.contains('\u0000') ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(nerSha256!)))) {
      throw ArgumentError('Invalid optional NER configuration.');
    }
    if (bundleDirectory.isEmpty ||
        libraryPath.isEmpty ||
        bundleDirectory.contains('\u0000') ||
        libraryPath.contains('\u0000') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(librarySha256)) {
      throw ArgumentError('Invalid native spaCy installation configuration.');
    }
  }
  final String bundleDirectory;
  final String libraryPath;
  final String librarySha256;

  /// Optional separate NER model (`ner.gguf`) and its trusted SHA-256. The
  /// library must export the NER ABI and the process must enable
  /// `CRISPEMBED_SPACY_NER=1`; otherwise opening fails rather than silently
  /// dropping entities.
  final String? nerPath;
  final String? nerSha256;

  /// The library ships inside the host's own code-signed app bundle (for
  /// example `Contents/Frameworks` of a sandboxed macOS app), so it cannot
  /// live in a SHA-256-named directory. The code signature seals it for the
  /// lifetime of the process; [librarySha256] is still verified before load.
  final bool hostBundled;

  @override
  Future<SpacyBackend> open(SpacyBundle bundle) async {
    // Loading is limited to targets with a built library. What an exact
    // build is qualified for is recorded per library digest in the
    // distribution catalog, never inferred from the ABI.
    if (!_loadableAbis.contains(Abi.current())) {
      throw const SpacyUnavailableException(
        'Native spaCy analysis is available only for Linux (x86-64, arm64), '
        'macOS arm64, Windows x86-64, iOS arm64 and Android (arm64, x86-64) '
        'libraries.',
      );
    }
    if (nerPath != null && bundle.formatVersion != 1) {
      throw const SpacyUnavailableException(
        'A separate NER model applies to the German bundle only; English and '
        'French entities come from their own model.',
      );
    }
    final String directory;
    final String library;
    try {
      directory = await Directory(bundleDirectory).resolveSymbolicLinks();
      library = await File(libraryPath).resolveSymbolicLinks();
    } on FileSystemException {
      throw const SpacyUnavailableException(
        'The explicit spaCy library or model directory is unavailable.',
      );
    }
    final parent = File(
      library,
    ).parent.uri.pathSegments.lastWhere((part) => part.isNotEmpty);
    if (!hostBundled && parent != librarySha256) {
      throw const SpacyUnavailableException(
        'Install the native spaCy library in its SHA-256 directory.',
      );
    }
    await _verifyBundle(directory, bundle);
    // A host-bundled library also yields its signature-independent code
    // digest, measured from the very bytes whose SHA-256 was just verified.
    final codeSha256 = hostBundled
        ? await _verifyHostBundledLibrary(File(library), librarySha256)
        : null;
    if (!hostBundled) {
      await _verifyFile(
        File(library),
        librarySha256,
        maximumBytes: 128 * 1024 * 1024,
      );
    }
    final bindings = _loadBindings(library, librarySha256);
    _enable(bindings, namedEntities: nerPath != null);
    final allocations = Arena();
    Pointer<Void> context = nullptr;
    late final _NativeBackend backend;
    try {
      if (bindings.abiVersion() != 1 ||
          bindings.textAbiVersion() != 1 ||
          bindings.legacyCapabilities() != 3) {
        throw const SpacyUnavailableException(
          'The library has an incompatible spaCy ABI or capability profile.',
        );
      }
      final error = allocations<Uint8>(_errorCapacity);
      error.asTypedList(_errorCapacity).fillRange(0, _errorCapacity, 0);
      context = bindings.create(
        '$directory/model.gguf'.toNativeUtf8(allocator: allocations),
        bundle.modelFile.sha256.toNativeUtf8(allocator: allocations),
        '$directory/resources.json'.toNativeUtf8(allocator: allocations),
        bundle.resourcesFile.sha256.toNativeUtf8(allocator: allocations),
        error,
        _errorCapacity,
      );
      if (context == nullptr) {
        throw SpacyUnavailableException(
          _diagnostic(error, 'The native spaCy model could not be admitted.'),
        );
      }
      final ner = nerPath;
      if (ner != null) {
        final attach = bindings.attachNer;
        if (attach == null || bindings.entity == null) {
          throw const SpacyUnavailableException(
            'This native spaCy library has no named-entity support.',
          );
        }
        await _verifyFile(
          File(ner),
          nerSha256!,
          maximumBytes: 64 * 1024 * 1024,
        );
        error.asTypedList(_errorCapacity).fillRange(0, _errorCapacity, 0);
        if (attach(
              context,
              ner.toNativeUtf8(allocator: allocations),
              nerSha256!.toNativeUtf8(allocator: allocations),
              error,
              _errorCapacity,
            ) !=
            0) {
          throw SpacyUnavailableException(
            _diagnostic(error, 'The optional NER model could not be attached.'),
          );
        }
      }
      final identity = SpacyBackendIdentity.forBundle(
        bundle,
        librarySha256: librarySha256,
        capabilityMask: bindings.contextCapabilities(context),
        codeSha256: codeSha256,
      );
      identity.validate(bundle);
      backend = _NativeBackend(bindings, context, identity, bundle);
      context = nullptr; // Finalization owns the handle before another await.
    } finally {
      if (context != nullptr) bindings.free(context);
      allocations.releaseAll();
    }
    try {
      // Detect ordinary installation replacement during opening. The install
      // contract still requires immutability; hashes do not lock pathnames.
      await _verifyBundle(directory, bundle);
      await _verifyFile(
        File(library),
        librarySha256,
        maximumBytes: 128 * 1024 * 1024,
      );
      return backend;
    } on Object {
      await backend.dispose();
      rethrow;
    }
  }
}

const _loadableAbis = {
  Abi.linuxX64,
  Abi.linuxArm64,
  Abi.macosArm64,
  Abi.windowsX64,
  // Mobile apps ship the library inside the signed app only (hostBundled);
  // each exact mobile binary still needs its own recorded qualification.
  Abi.iosArm64,
  Abi.androidArm64,
  Abi.androidX64,
};

/// Enables the opened library for this process after the host's explicit
/// opt-in (a factory exists only then). Libraries exporting
/// `crispembed_spacy_set_enabled` are enabled through it, without touching
/// the process environment; flags are only ever added, so a worker for one
/// language never disables another worker's gates. Older libraries without
/// that export fall back to [enableSpacyNativeGateForProcess] (POSIX only).
void _enable(_Bindings bindings, {required bool namedEntities}) {
  final wanted = 1 | (namedEntities ? 2 : 0);
  final setEnabled = bindings.setEnabled;
  if (setEnabled != null) {
    final previous = setEnabled(wanted);
    if (previous | wanted != wanted) setEnabled(previous | wanted);
    return;
  }
  if (!enableSpacyNativeGateForProcess(namedEntities: namedEntities)) {
    throw const SpacyUnavailableException(
      'Native analysis cannot be enabled with this library on this platform.',
    );
  }
}

typedef _SetEnvNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32);
typedef _SetEnvDart = int Function(Pointer<Utf8>, Pointer<Utf8>, int);

/// Sets `CRISPEMBED_SPACY=1` (and `CRISPEMBED_SPACY_NER=1` when
/// [namedEntities]) for this process so the native library admits work. Hosts call this only after the user explicitly enabled local German
/// analysis, before starting a worker. Returns false where unsupported.
///
/// `Platform.environment` is a startup snapshot and does not reflect this.
bool enableSpacyNativeGateForProcess({bool namedEntities = false}) {
  if (!_loadableAbis.contains(Abi.current()) || Platform.isWindows) {
    return false;
  }
  final setenv = DynamicLibrary.process()
      .lookupFunction<_SetEnvNative, _SetEnvDart>('setenv');
  final allocations = Arena();
  try {
    bool set(String name) =>
        setenv(
          name.toNativeUtf8(allocator: allocations),
          '1'.toNativeUtf8(allocator: allocations),
          1,
        ) ==
        0;
    return set('CRISPEMBED_SPACY') &&
        (!namedEntities || set('CRISPEMBED_SPACY_NER'));
  } finally {
    allocations.releaseAll();
  }
}

const _errorCapacity = 1024;
const _maximumOutputStringBytes = 32 * 1024 * 1024;
final Map<String, ({String hash, _Bindings bindings})> _libraries = {};

_Bindings _loadBindings(String path, String hash) {
  final existing = _libraries[path];
  if (existing != null) {
    if (existing.hash != hash) {
      throw const SpacyUnavailableException(
        'A loaded spaCy library path cannot be reused for a different hash.',
      );
    }
    return existing.bindings;
  }
  try {
    final bindings = _Bindings(DynamicLibrary.open(path));
    _libraries[path] = (hash: hash, bindings: bindings);
    return bindings;
  } on Object {
    throw const SpacyUnavailableException(
      'The verified spaCy library cannot load or lacks its required C ABI.',
    );
  }
}

Future<void> _verifyBundle(String directory, SpacyBundle bundle) async {
  for (final artifact in bundle.pinnedFiles) {
    await _verifyFile(
      File('$directory/${artifact.file}'),
      artifact.sha256,
      expectedBytes: artifact.bytes,
      maximumBytes: artifact.bytes,
    );
  }
}

Future<void> _verifyFile(
  File file,
  String hash, {
  int? expectedBytes,
  required int maximumBytes,
}) async {
  try {
    // Fixed bundle names and no symlink members prevent path escape.
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact is missing, linked or not a regular file.',
      );
    }
    final length = await file.length();
    if (length < 1 ||
        length > maximumBytes ||
        (expectedBytes != null && expectedBytes != length)) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact has the wrong size.',
      );
    }
    final digest = await sha256.bind(file.openRead(0, length)).first;
    if (digest.toString() != hash || await file.length() != length) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact failed SHA-256 verification.',
      );
    }
  } on FileSystemException {
    throw const SpacyUnavailableException(
      'Cannot read a pinned spaCy artifact.',
    );
  }
}

/// Verifies a host-bundled library like [_verifyFile] and returns its
/// [machOCodeSha256] computed from the same bytes (null for non-Mach-O or
/// unsigned files, which then carry no code identity).
Future<String?> _verifyHostBundledLibrary(File file, String hash) async {
  try {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact is missing, linked or not a regular file.',
      );
    }
    final length = await file.length();
    if (length < 1 || length > 128 * 1024 * 1024) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact has the wrong size.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != length ||
        sha256.convert(bytes).toString() != hash ||
        await file.length() != length) {
      throw const SpacyUnavailableException(
        'A pinned spaCy artifact failed SHA-256 verification.',
      );
    }
    return machOCodeSha256(bytes);
  } on FileSystemException {
    throw const SpacyUnavailableException(
      'Cannot read a pinned spaCy artifact.',
    );
  }
}

String _diagnostic(Pointer<Uint8> error, String fallback) {
  final bytes = error.asTypedList(_errorCapacity);
  final nul = bytes.indexOf(0);
  final message = utf8.decode(
    bytes.sublist(0, nul < 0 ? bytes.length : nul),
    allowMalformed: true,
  );
  return message.isEmpty ? fallback : message;
}

final class _Bindings {
  _Bindings(this.library) {
    abiVersion = library.lookupFunction<_VersionNative, _VersionDart>(
      'crispembed_spacy_abi_version',
    );
    textAbiVersion = library.lookupFunction<_VersionNative, _VersionDart>(
      'crispembed_spacy_text_abi_version',
    );
    legacyCapabilities = library.lookupFunction<_VersionNative, _VersionDart>(
      'crispembed_spacy_capabilities',
    );
    if (library.providesSymbol('crispembed_spacy_set_enabled')) {
      setEnabled = library.lookupFunction<_SetEnabledNative, _SetEnabledDart>(
        'crispembed_spacy_set_enabled',
      );
    }
    contextCapabilities = library
        .lookupFunction<_CapabilitiesNative, _CapabilitiesDart>(
          'crispembed_spacy_context_capabilities',
        );
    create = library.lookupFunction<_CreateNative, _CreateDart>(
      'crispembed_spacy_create_with_resources',
    );
    freePointer = library.lookup<NativeFunction<_FreeNative>>(
      'crispembed_spacy_free',
    );
    free = freePointer.asFunction<_FreeDart>();
    finalizer = NativeFinalizer(freePointer);
    analyze = library.lookupFunction<_AnalyzeNative, _AnalyzeDart>(
      'crispembed_spacy_analyze_utf8',
    );
    tokenCount = library.lookupFunction<_CountNative, _CountDart>(
      'crispembed_spacy_document_token_count',
    );
    isAnalyzed = library.lookupFunction<_AnalyzedNative, _AnalyzedDart>(
      'crispembed_spacy_document_is_analyzed',
    );
    token = library.lookupFunction<_TokenNative, _TokenDart>(
      'crispembed_spacy_document_token',
    );
    if (library.providesSymbol('crispembed_spacy_attach_ner') &&
        library.providesSymbol('crispembed_spacy_document_entity_count') &&
        library.providesSymbol('crispembed_spacy_document_entity')) {
      attachNer = library.lookupFunction<_AttachNerNative, _AttachNerDart>(
        'crispembed_spacy_attach_ner',
      );
      entityCount = library.lookupFunction<_CountNative, _CountDart>(
        'crispembed_spacy_document_entity_count',
      );
      entity = library.lookupFunction<_EntityNative, _EntityDart>(
        'crispembed_spacy_document_entity',
      );
    }
    documentFree = library.lookupFunction<_FreeNative, _FreeDart>(
      'crispembed_spacy_document_free',
    );
  }
  final DynamicLibrary library;
  late final _VersionDart abiVersion;
  late final _VersionDart textAbiVersion;
  late final _VersionDart legacyCapabilities;
  late final _CapabilitiesDart contextCapabilities;

  /// Null for libraries built before the process-wide enable API.
  _SetEnabledDart? setEnabled;
  _AttachNerDart? attachNer;
  _CountDart? entityCount;
  _EntityDart? entity;
  late final _CreateDart create;
  late final Pointer<NativeFunction<_FreeNative>> freePointer;
  late final _FreeDart free;
  late final NativeFinalizer finalizer;
  late final _AnalyzeDart analyze;
  late final _CountDart tokenCount;
  late final _AnalyzedDart isAnalyzed;
  late final _TokenDart token;
  late final _FreeDart documentFree;
}

final class _NativeBackend implements SpacyBackend, Finalizable {
  _NativeBackend(this._bindings, this._context, this.identity, this._bundle) {
    _bindings.finalizer.attach(this, _context, detach: this);
  }
  final _Bindings _bindings;
  final SpacyBundle _bundle;
  Pointer<Void> _context;
  @override
  final SpacyBackendIdentity identity;

  @override
  Future<LinguisticAnalysisResult> analyze(
    LinguisticAnalysisRequest request,
  ) async {
    LinguisticAnalysisResult failure(
      LinguisticAnalysisStatus status,
      String message,
    ) => LinguisticAnalysisResult.failure(
      request: request,
      status: status,
      message: message,
      identity: identity,
    );
    if (_context == nullptr) {
      return failure(
        LinguisticAnalysisStatus.unavailable,
        'The native spaCy context is disposed.',
      );
    }
    if (!_bundle.acceptsLocale(request.locale)) {
      return failure(
        LinguisticAnalysisStatus.unsupported,
        _bundle.language == SpacyLanguage.german
            ? 'This analysis profile supports de-DE only.'
            : 'This analysis profile supports '
                  '${_bundle.language.displayName} text only.',
      );
    }
    final allocations = Arena();
    Pointer<Void> document = nullptr;
    try {
      final source = SpacySourceText(request.text);
      final input = allocations<Uint8>(
        source.bytes.isEmpty ? 1 : source.bytes.length,
      );
      input.asTypedList(source.bytes.length).setAll(0, source.bytes);
      final output = allocations<Pointer<Void>>()..value = nullptr;
      final error = allocations<Uint8>(_errorCapacity);
      error.asTypedList(_errorCapacity).fillRange(0, _errorCapacity, 0);
      final status = _bindings.analyze(
        _context,
        input,
        source.bytes.length,
        output,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        error,
        _errorCapacity,
      );
      document = output.value;
      if (status != 0) {
        return failure(
          status == 6
              ? LinguisticAnalysisStatus.cancelled
              : status == 1
              ? LinguisticAnalysisStatus.unavailable
              : LinguisticAnalysisStatus.failed,
          _diagnostic(error, 'Native spaCy analysis failed (status $status).'),
        );
      }
      if (document == nullptr || _bindings.isAnalyzed(document) != 1) {
        throw const FormatException(
          'Native analysis returned no complete document.',
        );
      }
      final count = _bindings.tokenCount(document);
      if (count < 0 || count > spacyMaximumTokens) {
        throw const FormatException(
          'Native analysis returned excessive tokens.',
        );
      }
      final view = allocations<_TokenView>();
      final tokens = <LinguisticToken>[];
      var outputBytes = 0;
      String copy(_TextView text, {int maximum = spacyMaximumTextBytes}) {
        if (text.length < 0 ||
            text.length > maximum ||
            (text.length > 0 && text.data == nullptr)) {
          throw const FormatException('Invalid native counted UTF-8 field.');
        }
        outputBytes += text.length;
        if (outputBytes > _maximumOutputStringBytes) {
          throw const FormatException('Native text output exceeds its bound.');
        }
        return text.length == 0
            ? ''
            : utf8.decode(text.data.asTypedList(text.length));
      }

      for (var i = 0; i < count; i++) {
        if (_bindings.token(document, i, view) != 0) {
          throw const FormatException('Native token view is unavailable.');
        }
        final token = view.ref;
        if (token.flags & ~15 != 0) {
          throw const FormatException('Unknown native token flags.');
        }
        tokens.add(
          LinguisticToken(
            index: i,
            text: copy(token.text),
            norm: copy(token.norm),
            prefix: copy(token.prefix),
            suffix: copy(token.suffix),
            shape: copy(token.shape),
            lemma: copy(token.lemma),
            tag: copy(token.tag, maximum: 4096),
            pos: copy(token.pos, maximum: 4096),
            morphology: copy(token.morph, maximum: 65536),
            dependency: copy(token.dependency, maximum: 4096),
            head: token.head,
            byteStart: token.byteStart,
            byteEnd: token.byteEnd,
            scalarStart: token.scalarStart,
            scalarEnd: token.scalarEnd,
            start: token.utf16Start,
            end: token.utf16End,
            spaceAfter: token.flags & 1 != 0,
            isSpace: token.flags & 2 != 0,
            sentenceStart: token.flags & 4 != 0,
            sentenceEnd: token.flags & 8 != 0,
          ),
        );
      }
      List<LinguisticEntity>? entities;
      final readEntity = _bindings.entity;
      final countEntities = _bindings.entityCount;
      if (identity.capabilityMask & spacyEntitiesCapability != 0 &&
          readEntity != null &&
          countEntities != null) {
        final entityCount = countEntities(document);
        if (entityCount < 0 || entityCount > tokens.length) {
          throw const FormatException(
            'Native analysis returned excessive entities.',
          );
        }
        final entityView = allocations<_EntityView>();
        entities = [];
        for (var i = 0; i < entityCount; i++) {
          if (readEntity(document, i, entityView) != 0) {
            throw const FormatException('Native entity view is unavailable.');
          }
          final item = entityView.ref;
          if (item.tokenStart >= item.tokenEnd ||
              item.tokenEnd > tokens.length ||
              item.byteStart != tokens[item.tokenStart].byteStart ||
              item.byteEnd != tokens[item.tokenEnd - 1].byteEnd ||
              item.scalarStart != tokens[item.tokenStart].scalarStart ||
              item.scalarEnd != tokens[item.tokenEnd - 1].scalarEnd ||
              item.utf16End > request.text.length) {
            throw const FormatException('Invalid native entity span.');
          }
          entities.add(
            LinguisticEntity(
              startToken: item.tokenStart,
              endToken: item.tokenEnd,
              start: item.utf16Start,
              end: item.utf16End,
              label: copy(item.label, maximum: 64),
              text: request.text.substring(item.utf16Start, item.utf16End),
            ),
          );
        }
      }
      return LinguisticAnalysisResult.success(
        request: request,
        identity: identity,
        tokens: tokens,
        entities: entities,
      );
    } on FormatException catch (error) {
      return failure(LinguisticAnalysisStatus.failed, error.message);
    } on Object {
      return failure(
        LinguisticAnalysisStatus.failed,
        'The native spaCy analysis could not be completed.',
      );
    } finally {
      // Free even malformed or error-returned non-null documents. All strings
      // above were copied before the final view and document expire.
      if (document != nullptr) _bindings.documentFree(document);
      allocations.releaseAll();
    }
  }

  @override
  Future<void> dispose() async {
    if (_context != nullptr) {
      _bindings.finalizer.detach(this);
      _bindings.free(_context);
      _context = nullptr;
    }
  }
}
