import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../utils/async_lock.dart';
import 'archive_creation_service.dart';
import 'archive_external_packer_types.dart';
import 'file_operation_service.dart';
import 'archive_external_packer_stub.dart'
    if (dart.library.io) 'archive_external_packer_io.dart'
    as packer_platform;

export 'archive_external_packer_types.dart';

abstract interface class ArchiveExternalPackerPreferences {
  Future<ArchiveExternalPackerConfiguration?> load();
  Future<void> save(ArchiveExternalPackerConfiguration configuration);
  Future<void> reset();
}

/// Preferences contain only a platform, engine kind and executable path.
/// They are intentionally separate from provider credentials and sync config.
class ArchiveExternalPackerStore implements ArchiveExternalPackerPreferences {
  ArchiveExternalPackerStore(this.platform);
  final String platform;
  static final AsyncLock _lock = AsyncLock();
  String get _key => 'archive_external_packer_v1_$platform';

  @override
  Future<ArchiveExternalPackerConfiguration?> load() =>
      _lock.synchronized(() async {
        final raw = (await SharedPreferences.getInstance()).getString(_key);
        if (raw == null) return null;
        try {
          if (raw.length > 16384) throw const FormatException();
          final configuration = ArchiveExternalPackerConfiguration.fromJson(
            jsonDecode(raw),
          );
          if (configuration.platform != platform) throw const FormatException();
          return configuration;
        } catch (_) {
          throw const ArchiveExternalPackerException(
            ArchiveExternalPackerFailure.invalidConfiguration,
          );
        }
      });

  @override
  Future<void> save(ArchiveExternalPackerConfiguration configuration) =>
      _lock.synchronized(() async {
        configuration.validate();
        if (configuration.platform != platform) {
          throw const ArchiveExternalPackerException(
            ArchiveExternalPackerFailure.invalidConfiguration,
          );
        }
        if (!await (await SharedPreferences.getInstance()).setString(
          _key,
          jsonEncode(configuration.toJson()),
        )) {
          throw const ArchiveExternalPackerException(
            ArchiveExternalPackerFailure.saveFailed,
          );
        }
      });

  @override
  Future<void> reset() => _lock.synchronized(() async {
    if (!await (await SharedPreferences.getInstance()).remove(_key)) {
      throw const ArchiveExternalPackerException(
        ArchiveExternalPackerFailure.saveFailed,
      );
    }
  });
}

/// Optional installed engines produce candidates for the normal creation
/// pipeline. They never receive source-provider paths or the destination path,
/// never publish files, and never establish permission to rewrite an archive.
class ArchiveExternalPackerService {
  ArchiveExternalPackerService({
    ArchiveExternalPackerEngine? engine,
    this.creator = const ArchiveCreationService(),
  }) : engine = engine ?? packer_platform.createArchiveExternalPackerEngine();
  final ArchiveExternalPackerEngine engine;
  final ArchiveCreationService creator;
  String? get platform => engine.platform;

  Future<List<ArchiveExternalPackerConfiguration>> discover() =>
      engine.discover();
  Future<ArchiveExternalPackerInstallation> probe(
    ArchiveExternalPackerConfiguration configuration, {
    ArchiveExternalSevenZipProfile sevenZipProfile =
        const ArchiveExternalSevenZipProfile(),
    bool Function()? isCancelled,
  }) => engine.probe(
    configuration,
    sevenZipProfile: sevenZipProfile,
    isCancelled: isCancelled,
  );

  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) {
    if (platform == null) {
      throw const ArchiveExternalPackerException(
        ArchiveExternalPackerFailure.unsupportedPlatform,
      );
    }
    if (installation.configuration.platform != platform) {
      throw const ArchiveExternalPackerException(
        ArchiveExternalPackerFailure.unsupportedFormat,
      );
    }
    installation.validateOptions(options);
    final format = switch (options.format) {
      ArchiveExternalPackerFormat.zip => ArchiveCreationFormat.zip,
      ArchiveExternalPackerFormat.sevenZip => ArchiveCreationFormat.sevenZip,
      ArchiveExternalPackerFormat.rar => ArchiveCreationFormat.rar,
    };
    return creator.create(
      source: source,
      destination: destination,
      files: files,
      destinationDirectory: destinationDirectory,
      options: ArchiveCreationOptions(
        name: options.name,
        format: format,
        // The fixed external adapter owns its compression choice. These are
        // valid built-in options only for shared name/time validation.
        compression: format == ArchiveCreationFormat.rar
            ? ArchiveCreationCompression.none
            : format == ArchiveCreationFormat.sevenZip
            ? ArchiveCreationCompression.lzma2
            : ArchiveCreationCompression.normal,
      ),
      writer:
          ({
            required entries,
            required sink,
            required maxOutputBytes,
            isCancelled,
          }) => engine.write(
            installation: installation,
            options: options,
            entries: entries,
            sink: sink,
            maxOutputBytes: maxOutputBytes,
            isCancelled: isCancelled,
          ),
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }
}
