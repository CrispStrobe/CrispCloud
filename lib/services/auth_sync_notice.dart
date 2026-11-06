/// App-authored notices kept as data until the UI chooses its locale.
enum AuthSyncNoticeCode {
  sessionExpired,
  syncPair,
  sync,
  download,
  freeSpace,
  downloadAll,
}

class AuthSyncNotice {
  const AuthSyncNotice(this.code, {this.cause, this.pairName});
  final AuthSyncNoticeCode code;
  final Object? cause;
  final String? pairName;
}
