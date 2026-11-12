import 'archive_publication_lease.dart';

Future<ArchivePublicationLease?> acquireArchivePublicationLease(
  String id,
) async => throw UnsupportedError(
  'Archive publication requires a process-lifetime lease. Browser publication is unavailable.',
);
