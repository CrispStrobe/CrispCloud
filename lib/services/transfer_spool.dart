import 'transfer_spool_contract.dart';
import 'transfer_spool_stub.dart'
    if (dart.library.io) 'transfer_spool_io.dart'
    if (dart.library.html) 'transfer_spool_web.dart'
    as impl;

export 'transfer_spool_contract.dart';

/// Materialize a stream in private disk/browser storage, never in a growing
/// memory buffer. Used when an upload API needs a size the source cannot give.
Future<TransferSpool> createTransferSpool(
  Stream<List<int>> source, {
  int? expectedLength,
  int? maxBytes,
  Future<void> Function()? checkpoint,
}) => impl.createTransferSpool(
  source,
  expectedLength: expectedLength,
  maxBytes: maxBytes,
  checkpoint: checkpoint,
);
