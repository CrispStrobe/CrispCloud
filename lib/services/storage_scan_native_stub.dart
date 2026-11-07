import '../models/storage_analysis.dart';

Future<StorageScanDirectory> readNativeStorageScanDirectory(String path) =>
    throw UnsupportedError('Native metadata scanning is unavailable.');

class NativeStorageScanWorker {
  NativeStorageScanWorker._();

  static Future<NativeStorageScanWorker> start() =>
      throw UnsupportedError('Native metadata scanning is unavailable.');

  Future<StorageScanDirectory> readDirectory(String path) =>
      throw UnsupportedError('Native metadata scanning is unavailable.');

  Future<void> close() async {}
}
