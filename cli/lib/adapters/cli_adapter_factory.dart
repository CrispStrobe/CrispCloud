// lib/adapters/cli_adapter_factory.dart
//
// Creates provider adapter instances from a CLI config map.
// Supported providers:
//   - S3  (http + crypto)
//   - SFTP (dartssh2)
//   - SMB (crisp_storage: libsmb2 or the Rust engine)
//   - WebDAV (http)
//   - Filen, Internxt (crisp_storage Rust engine, rust_cloud/)

import '../config/cli_config.dart';
import 'cli_storage_client.dart';
import 'rust_cloud_adapter.dart';
import 's3_adapter.dart';
import 'smb_adapter.dart';
import 'sftp_adapter.dart';
import 'webdav_adapter.dart';

/// Create a [CliStorageClient] for the named provider.
///
/// [config] is the raw provider map from the CLI config file.
/// Throws [CliConfigException] for unknown or misconfigured providers.
CliStorageClient createAdapter(
  String providerName,
  Map<String, dynamic> config,
) {
  final type = config['type'] as String?;
  if (type == null) {
    throw CliConfigException(
      'Provider "$providerName" has no "type" field in config.',
    );
  }

  switch (type.toLowerCase()) {
    case 'smb':
      return SmbCliAdapter.fromConfig(config);
    case 's3':
      return S3CliAdapter.fromConfig(config);
    case 'sftp':
      return SftpCliAdapter.fromConfig(config);
    case 'webdav':
      return WebDavCliAdapter.fromConfig(config);
    case 'filen':
    case 'internxt':
      return RustCloudCliAdapter.fromConfig(type.toLowerCase(), config);
    default:
      throw CliConfigException(
        'Unsupported provider type "$type". '
        'Supported types: s3, sftp, smb, webdav, filen, internxt.',
      );
  }
}
