import 'dart:io';

import 'package:crisp_cloud/services/native_journal_lease.dart';

Future<void> main(List<String> args) async {
  final lease = await tryAcquireNativeJournalLease(args.single);
  if (lease == null) exit(2);
  stdout.writeln('leased');
  await stdout.flush();
  await stdin.drain<void>();
  lease.close();
}
