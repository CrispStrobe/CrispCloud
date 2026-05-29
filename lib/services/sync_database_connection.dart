// lib/services/sync_database_connection.dart
//
// Platform-conditional database connection.
// Uses NativeDatabase on desktop/mobile, in-memory fallback on web.

export 'sync_database_connection_native.dart'
    if (dart.library.html) 'sync_database_connection_web.dart';
