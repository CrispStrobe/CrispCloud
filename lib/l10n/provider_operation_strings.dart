import 'package:flutter/widgets.dart';

import '../services/nextcloud_operation_failure.dart';
import '../services/b2_operation_failure.dart';
import '../services/ftp_operation_failure.dart';
import '../services/webdav_operation_failure.dart';
import '../services/gdrive_operation_failure.dart';
import '../services/dropbox_operation_failure.dart';
import '../services/onedrive_operation_failure.dart';
import '../services/pcloud_operation_failure.dart';
import '../services/s3_operation_failure.dart';
import 'nextcloud_operation_strings.dart';
import 'b2_operation_strings.dart';
import 'ftp_operation_strings.dart';
import 'webdav_operation_strings.dart';
import 'gdrive_operation_strings.dart';
import 'dropbox_operation_strings.dart';
import 'onedrive_operation_strings.dart';
import 'pcloud_operation_strings.dart';
import 's3_operation_strings.dart';

/// Returns null for unknown errors so each caller can retain its fallback.
String? localizedKnownProviderError(BuildContext context, Object error) {
  if (error is FtpOperationFailure) {
    return localizedFtpError(context, error);
  }
  if (error is WebDavOperationFailure) {
    return localizedWebDavError(context, error);
  }
  if (error is B2OperationFailure) {
    return localizedB2Error(context, error);
  }
  if (error is NextcloudOperationFailure) {
    return localizedNextcloudError(context, error);
  }
  if (error is OneDriveOperationFailure) {
    return localizedOneDriveError(context, error);
  }
  if (error is S3OperationFailure) return localizedS3Error(context, error);
  if (error is PCloudOperationFailure) {
    return localizedPCloudError(context, error);
  }
  if (error is GDriveOperationFailure) {
    return localizedGDriveError(context, error);
  }
  if (error is DropboxOperationFailure) {
    return localizedDropboxError(context, error);
  }
  return null;
}

/// Localizes recognized provider errors and preserves all other details.
String localizedProviderError(BuildContext context, Object error) =>
    localizedKnownProviderError(context, error) ?? error.toString();
