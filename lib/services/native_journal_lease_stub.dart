class NativeJournalLease {
  void close() {}
}

Future<NativeJournalLease?> tryAcquireNativeJournalLease(String path) async =>
    throw UnsupportedError('Background journal leases require native storage.');
