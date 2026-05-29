// lib/services/sync_database_connection_web.dart
//
// Web fallback: drift supports WebDatabase via sql.js wasm.
// For now, use in-memory database (sync state is ephemeral on web).
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openSyncDatabase() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'crispcloud_sync',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
