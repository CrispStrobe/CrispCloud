import '../services/auth_sync_notice.dart';
import 'auth_sync_notice_strings.dart';
import 'provider_workflow_strings.dart';
import 'package:flutter/widgets.dart';
import '../services/web_file_failure.dart';
import 'web_file_error_strings.dart';
import '../services/terminal_mount_failure.dart';
import 'terminal_mount_error_strings.dart';
import '../services/azure_hetzner_failure.dart';
import 'azure_hetzner_strings.dart';
import 'remote_transport_strings.dart';

import '../services/nextcloud_operation_failure.dart';
import '../services/b2_operation_failure.dart';
import '../services/filen_operation_failure.dart';
import '../services/internxt_operation_failure.dart';
import '../services/ftp_operation_failure.dart';
import '../services/sftp_operation_failure.dart';
import '../services/smb_operation_failure.dart';
import '../services/webdav_operation_failure.dart';
import '../services/gdrive_operation_failure.dart';
import '../services/dropbox_operation_failure.dart';
import '../services/onedrive_operation_failure.dart';
import '../services/pcloud_operation_failure.dart';
import '../services/s3_operation_failure.dart';
import 'nextcloud_operation_strings.dart';
import 'b2_operation_strings.dart';
import 'filen_operation_strings.dart';
import 'internxt_operation_strings.dart';
import 'ftp_operation_strings.dart';
import 'sftp_operation_strings.dart';
import 'smb_operation_strings.dart';
import 'webdav_operation_strings.dart';
import 'gdrive_operation_strings.dart';
import 'dropbox_operation_strings.dart';
import 'onedrive_operation_strings.dart';
import 'pcloud_operation_strings.dart';
import 's3_operation_strings.dart';

/// Returns null for unknown errors so each caller can retain its fallback.
String? localizedKnownProviderError(BuildContext context, Object error) =>
    localizedProviderWorkflowError(context, error) ??
    localizedKnownProviderErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String? localizedKnownProviderErrorForLanguage(String language, Object error) {
  final workflow = localizedProviderWorkflowErrorForLanguage(language, error);
  if (workflow != null) return workflow;
  if (error is AuthSyncNotice) return localizedAuthSyncNotice(language, error);
  if (error is WebFileFailure) return localizedWebFileErrorForLanguage(language, error);
  if (error is TerminalMountFailure)
    return localizedTerminalMountErrorForLanguage(language, error);
  if (error is AzureHetznerFailure)
    return localizedAzureHetznerErrorForLanguage(language, error);
  final transport = localizedRemoteTransportErrorForLanguage(language, error);
  if (transport != null) return transport;
  if (error is SftpOperationFailure) {
    return localizedSftpOperationErrorForLanguage(language, error);
  }
  if (error is SmbOperationFailure) {
    return localizedSmbErrorForLanguage(language, error);
  }
  if (error is FtpOperationFailure) {
    return localizedFtpErrorForLanguage(language, error);
  }
  if (error is WebDavOperationFailure) {
    return localizedWebDavErrorForLanguage(language, error);
  }
  if (error is FilenOperationFailure) {
    return localizedFilenErrorForLanguage(language, error);
  }
  if (error is InternxtOperationFailure) {
    return localizedInternxtErrorForLanguage(language, error);
  }
  if (error is B2OperationFailure) {
    return localizedB2ErrorForLanguage(language, error);
  }
  if (error is NextcloudOperationFailure) {
    return localizedNextcloudErrorForLanguage(language, error);
  }
  if (error is OneDriveOperationFailure) {
    return localizedOneDriveErrorForLanguage(language, error);
  }
  if (error is S3OperationFailure) return localizedS3ErrorForLanguage(language, error);
  if (error is PCloudOperationFailure) {
    return localizedPCloudErrorForLanguage(language, error);
  }
  if (error is GDriveOperationFailure) {
    return localizedGDriveErrorForLanguage(language, error);
  }
  if (error is DropboxOperationFailure) {
    return localizedDropboxErrorForLanguage(language, error);
  }
  return null;
}

/// Localizes recognized provider errors and preserves all other details.
String localizedProviderError(BuildContext context, Object error) =>
    localizedKnownProviderError(context, error) ?? error.toString();

/// Localizes provider errors without requiring a widget tree.
String localizedProviderErrorForLanguage(String language, Object error) =>
    localizedKnownProviderErrorForLanguage(language, error) ?? error.toString();
