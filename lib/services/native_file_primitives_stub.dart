bool get supportsNativeExclusiveRename => false;

Future<bool> moveNativeNoReplace(String source, String destination) async =>
    false;

bool get supportsNativePreallocation => false;
bool get supportsNativeCopyOnWrite => false;
bool get supportsNativePermissions => false;
Future<bool> preallocateNativeFile(String path, int length) async => false;
Future<bool> cloneNativeFile(String source, String destination) async => false;
Future<void> setNativeFileMode(String path, int mode) async =>
    throw UnsupportedError('Native permissions are unavailable.');
