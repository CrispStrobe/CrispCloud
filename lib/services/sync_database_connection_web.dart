// lib/services/sync_database_connection_web.dart
//
// Web stub: sync database is not functional on web.
// Returns a LazyDatabase that throws on first access, but since
// sync features are disabled on web, it's never actually opened.
import 'package:drift/drift.dart';
import 'package:drift/backends.dart';

QueryExecutor openSyncDatabase() {
  // Return a no-op executor. Sync is not supported on web.
  // The SyncNotifier creates the database but sync operations
  // are guarded by kIsWeb checks elsewhere.
  return LazyDatabase(() async {
    return _NoOpQueryExecutor();
  });
}

/// A minimal QueryExecutor that does nothing — used on web where
/// drift/sqlite is not available.
class _NoOpQueryExecutor extends QueryExecutor {
  @override
  TransactionExecutor beginTransaction() => _NoOpTransactionExecutor();

  @override
  TransactionExecutor beginExclusive() => _NoOpTransactionExecutor();

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<void> runBatched(BatchedStatements statements) async {}

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {}

  @override
  Future<int> runDelete(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(String statement, List<Object?> args) async => [];

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => 0;

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<void> close() async {}
}

class _NoOpTransactionExecutor extends TransactionExecutor {
  @override
  TransactionExecutor beginTransaction() => this;

  @override
  TransactionExecutor beginExclusive() => this;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<void> runBatched(BatchedStatements statements) async {}

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {}

  @override
  Future<int> runDelete(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(String statement, List<Object?> args) async => [];

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => 0;

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<void> close() async {}

  @override
  Future<void> send() async {}

  @override
  Future<void> rollback() async {}

  @override
  bool get supportsNestedTransactions => false;
}
