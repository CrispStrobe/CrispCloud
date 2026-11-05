import 'transfer_spool_contract.dart';
import 'internxt_transfer_platform_stub.dart'
    if (dart.library.io) 'internxt_transfer_platform_io.dart'
    if (dart.library.html) 'internxt_transfer_platform_web.dart'
    as platform;

/// A view of an existing private spool, never a whole-part memory copy. The
/// original spool owns its storage and must outlive all of its slices.
TransferSpool sliceInternxtSpool(TransferSpool spool, int start, int end) {
  if (start < 0 || end < start || end > spool.length) {
    throw RangeError('Invalid private upload slice.');
  }
  return platform.sliceSpool(spool, start, end);
}

Future<void> saveInternxtDownload(
  Stream<List<int>> source,
  String path, {
  required void Function() checkCurrent,
}) => platform.saveDownload(source, path, checkCurrent: checkCurrent);
