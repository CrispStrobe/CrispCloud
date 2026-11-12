import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'archive_publication_lease.dart';
import 'native_journal_lease.dart';

Future<ArchivePublicationLease?> acquireArchivePublicationLease(
  String id,
) async {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return MemoryArchivePublicationLease.acquire(id);
  }
  final directory = Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'archive_publication_leases',
    ),
  );
  await directory.create(recursive: true);
  return acquireNativeArchivePublicationLease(
    p.join(directory.path, '$id.lock'),
  );
}

Future<ArchivePublicationLease?> acquireNativeArchivePublicationLease(
  String path,
) async {
  final lease = await tryAcquireNativeJournalLease(path);
  return lease == null ? null : _NativeArchiveLease(lease);
}

class _NativeArchiveLease implements ArchivePublicationLease {
  _NativeArchiveLease(this._lease);
  NativeJournalLease? _lease;
  @override
  bool get isHeld => _lease != null;
  @override
  void close() {
    _lease?.close();
    _lease = null;
  }
}
