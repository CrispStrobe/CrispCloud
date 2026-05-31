# ADR 004: Drift/SQLite for Sync Metadata

**Status**: Accepted

---

## Context

The sync engine (Phase 4) needs to maintain persistent state across app restarts for:

- **Sync pairs**: local folder path, remote provider + path, sync direction, include/exclude patterns, conflict policy, bandwidth schedule.
- **File state**: per-file record of last-known local modification time, last-known remote modification time, remote content hash (where available), and local hash — needed for delta sync.
- **Offline queue**: operations (upload, delete, rename, move, create folder) queued while offline, stored in chronological order for replay on reconnect.
- **File cache index**: LRU metadata for the offline file cache — path, size, last-accessed time, local cache path — used for eviction decisions.

We needed a persistent, queryable store. The candidates were:

**`shared_preferences`**: key-value only. Storing structured data requires JSON serialization per-key with no query capability. Querying the offline queue or the file state table (e.g., "all files in sync pair X not accessed in 30 days") requires loading everything into memory. Rejected.

**Hive / Isar**: NoSQL embedded stores. Schema migrations require custom code; complex queries require collection scanning. Isar has strong Flutter integration but does not support Web targets via WebAssembly. Rejected.

**`sqflite`**: the most common Flutter SQLite package. Works on Android/iOS/macOS/Windows/Linux. Does not support Web. Rejected because CrispCloud targets Web (PWA) as a first-class platform.

**drift** (formerly `moor`): a type-safe SQLite abstraction for Dart. Uses `sqflite` on native and `sql.js` (SQLite compiled to WebAssembly) on the Web. Schema is declared in Dart; the code generator produces type-safe query classes and data classes. Migrations are first-class with version tracking.

---

## Decision

Use **drift** (`pub.dev/packages/drift`) as the local database for all sync-related persistent state.

### Tables

```dart
// Sync pairs: one row per configured sync relationship
class SyncPairs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localPath => text()();
  TextColumn get remoteProvider => text()();
  TextColumn get remotePath => text()();
  TextColumn get direction => text()();        // 'both', 'local_to_remote', 'remote_to_local'
  TextColumn get conflictPolicy => text()();
  TextColumn get includeGlobs => text().nullable()();  // JSON array
  TextColumn get excludeGlobs => text().nullable()();
  BoolColumn get syncOnlyOnWifi => boolean().withDefault(const Constant(false))();
  TextColumn get syncHours => text().nullable()();     // "22:00-06:00" or null
  BoolColumn get placeholdersEnabled => boolean().withDefault(const Constant(false))();
}

// Per-file sync state
class SyncedFiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get syncPairId => integer().references(SyncPairs, #id)();
  TextColumn get relativePath => text()();
  DateTimeColumn get localModified => dateTime().nullable()();
  DateTimeColumn get remoteModified => dateTime().nullable()();
  TextColumn get localHash => text().nullable()();
  TextColumn get remoteHash => text().nullable()();
  DateTimeColumn get lastSeen => dateTime()();
}

// Offline operation queue
class OfflineQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get syncPairId => integer().references(SyncPairs, #id)();
  TextColumn get operation => text()();   // 'upload', 'delete', 'rename', 'move', 'createFolder'
  TextColumn get sourcePath => text()();
  TextColumn get targetPath => text().nullable()();
  DateTimeColumn get queuedAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();
}

// LRU file cache index
class FileCacheEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteProvider => text()();
  TextColumn get remotePath => text()();
  TextColumn get localCachePath => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get lastAccessed => dateTime()();
}
```

### Web Support

On the Web target, drift uses `sql.js` (SQLite compiled to WASM) with an OPFS (Origin Private File System) backend for persistence. The same Dart query code works on all platforms with no platform-specific branches.

### Why SQL Over NoSQL

The offline queue replay requires ordered queries with status filtering: `SELECT * FROM offline_queue WHERE status = 'pending' ORDER BY queued_at ASC`. The sync state requires join queries: files in a specific sync pair that have changed since a given timestamp. The file cache eviction requires: files ordered by last_accessed, scanning until cumulative size exceeds the eviction threshold. These are natural SQL expressions and awkward in key-value or document stores.

---

## Consequences

**Positive:**

- Schema is declared in Dart; the code generator creates type-safe insert/select/update/delete classes. Typos in column names are compile-time errors.
- Schema migrations are versioned with the `MigrationStrategy` class. Adding a column in a future version is a two-line change.
- The WASM backend means the same database code runs in the browser PWA — no platform forks.
- Complex sync queries (delta detection, LRU eviction, queue replay) are expressed as type-safe Dart fluent query builders that compile to optimized SQL.

**Negative / Trade-offs:**

- Build-time code generation: developers must run `dart run build_runner build` after schema changes. If the generated files are out of date, the build fails with confusing errors. The CI pipeline runs `build_runner` before `flutter test`.
- The `sql.js` WASM file adds ~1.5 MB to the web build. This is acceptable for a desktop-class web app but notable.
- drift is a larger dependency than `sqflite` alone. However, the type safety and web support justify the added complexity.
- Database file location varies per platform: `~/.local/share/crispcloud/crispcloud.db` on Linux, `%APPDATA%\crispcloud\crispcloud.db` on Windows, `~/Library/Application Support/crispcloud/crispcloud.db` on macOS, app-private storage on Android/iOS, OPFS on Web.
