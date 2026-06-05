// lib/services/sync_database_connection_web.dart
//
// Web fallback: use in-memory database. Sync state is ephemeral on web
// since sqlite3.wasm and drift_worker.js are not bundled in the web build.
import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openSyncDatabase() {
  return WebDatabase('crispcloud_sync');
}
