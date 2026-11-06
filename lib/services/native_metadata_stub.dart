import 'storage_transfer_contract.dart';

bool get supportsNativeMetadata => false;
bool get supportsNativeOwnership => false;
bool get supportsNativeExtendedAttributes => false;
bool get supportsNativeAccessControlLists => false;

Future<TransferMetadata> readNativeMetadata(
  String path, {
  bool ownership = true,
  bool extendedAttributes = true,
  bool acl = true,
}) async => throw UnsupportedError('Native metadata is unavailable.');

Future<void> writeNativeMetadata(
  String path,
  TransferMetadata metadata,
) async => throw UnsupportedError('Native metadata is unavailable.');
