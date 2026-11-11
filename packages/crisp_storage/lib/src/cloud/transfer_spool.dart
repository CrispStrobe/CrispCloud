import 'transfer_spool_stub.dart'
    if (dart.library.io) 'transfer_spool_io.dart'
    as impl;
export 'transfer_spool_contract.dart';
import 'transfer_spool_contract.dart';

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
