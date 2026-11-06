import 'storage_transfer_contract.dart';

bool get supportsNativeMetadata => false;
bool get supportsNativeOwnership => false;
bool get supportsNativeExtendedAttributes => false;
bool get supportsNativeAccessControlLists => false;
bool get supportsNativeWindowsAttributes => false;
bool get supportsNativeCreatedTime => false;

Future<TransferMetadata> readNativeMetadata(
  String path, {
  bool ownership = true,
  bool extendedAttributes = true,
  bool acl = true,
  bool created = true,
  bool windowsAttributes = true,
}) async => throw UnsupportedError('Native metadata is unavailable.');

Future<void> writeNativeMetadata(
  String path,
  TransferMetadata metadata,
) async => throw UnsupportedError('Native metadata is unavailable.');
