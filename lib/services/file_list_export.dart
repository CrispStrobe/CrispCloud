import 'file_list_export_native.dart'
    if (dart.library.html) 'file_list_export_web.dart'
    as platform;

/// Save/download a UTF-8 list. Null means the native save dialog was cancelled.
Future<String?> exportFileListText(String text) =>
    platform.exportFileListText(text);
