import 'package:crisp_storage/src/cloud/internxt_streaming_transfer.dart'
    as core;

import 'transfer_spool.dart';
import 'internxt_transfer_platform.dart';
import 'spooled_http_upload.dart';

export 'package:crisp_storage/src/cloud/internxt_streaming_transfer.dart'
    show InternxtPathNotFound, InternxtTransferSession;

/// Preserve the GUI's browser/OPFS integrations while using the shared protocol.
class InternxtStreamingTransfer extends core.InternxtStreamingTransfer {
  const InternxtStreamingTransfer({
    int multipartMinimum = 100 * 1024 * 1024,
    int preferredPartSize = 30 * 1024 * 1024,
  }) : super(
         multipartMinimum: multipartMinimum,
         preferredPartSize: preferredPartSize,
         createSpool: createTransferSpool,
         sliceSpool: sliceInternxtSpool,
         uploadBrowser: uploadSpooledHttpBody,
       );
  static const chunkSize = core.InternxtStreamingTransfer.chunkSize;
  static const maxUploadSize = core.InternxtStreamingTransfer.maxUploadSize;
  static const maxParts = core.InternxtStreamingTransfer.maxParts;
}
