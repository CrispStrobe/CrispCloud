Future<T> withWindowsCredentialStoreLock<T>(Future<T> Function() operation) =>
    operation();
