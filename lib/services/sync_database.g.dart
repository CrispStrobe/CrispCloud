// GENERATED CODE - DO NOT MODIFY BY HAND
// Run `dart run build_runner build` to regenerate.

part of 'sync_database.dart';

class $SyncPairsTable extends SyncPairs with TableInfo<$SyncPairsTable, SyncPair> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPairsTable(this.attachedDatabase, [this._alias]);

  static const VerificationMeta _idMeta = VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>('id', aliasedName, false,
      hasAutoIncrement: true, type: DriftSqlType.int, defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>('name', aliasedName, false,
      additionalChecks: GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 255), type: DriftSqlType.string);
  static const VerificationMeta _localPathMeta = VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>('local_path', aliasedName, false, type: DriftSqlType.string);
  static const VerificationMeta _remotePathMeta = VerificationMeta('remotePath');
  @override
  late final GeneratedColumn<String> remotePath = GeneratedColumn<String>('remote_path', aliasedName, false, type: DriftSqlType.string);
  static const VerificationMeta _providerMeta = VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>('provider', aliasedName, false, type: DriftSqlType.string);
  static const VerificationMeta _conflictPolicyMeta = VerificationMeta('conflictPolicy');
  @override
  late final GeneratedColumn<String> conflictPolicy = GeneratedColumn<String>('conflict_policy', aliasedName, false,
      type: DriftSqlType.string, defaultValue: const Constant('newestWins'));
  static const VerificationMeta _directionMeta = VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>('direction', aliasedName, false,
      type: DriftSqlType.string, defaultValue: const Constant('twoWay'));
  static const VerificationMeta _enabledMeta = VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>('enabled', aliasedName, false,
      type: DriftSqlType.bool, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'), defaultValue: const Constant(true));
  static const VerificationMeta _lastSyncAtMeta = VerificationMeta('lastSyncAt');
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>('last_sync_at', aliasedName, true, type: DriftSqlType.dateTime);
  static const VerificationMeta _createdAtMeta = VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>('created_at', aliasedName, false,
      type: DriftSqlType.dateTime, defaultValue: currentDateAndTime);

  static const VerificationMeta _includePatternsMeta = VerificationMeta('includePatterns');
  @override
  late final GeneratedColumn<String> includePatterns = GeneratedColumn<String>('include_patterns', aliasedName, false,
      type: DriftSqlType.string, defaultValue: const Constant(''));
  static const VerificationMeta _excludePatternsMeta = VerificationMeta('excludePatterns');
  @override
  late final GeneratedColumn<String> excludePatterns = GeneratedColumn<String>('exclude_patterns', aliasedName, false,
      type: DriftSqlType.string, defaultValue: const Constant(''));
  static const VerificationMeta _usePlaceholdersMeta = VerificationMeta('usePlaceholders');
  @override
  late final GeneratedColumn<bool> usePlaceholders = GeneratedColumn<bool>('use_placeholders', aliasedName, false,
      type: DriftSqlType.bool, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("use_placeholders" IN (0, 1))'), defaultValue: const Constant(false));

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pairs';
  @override
  VerificationContext validateIntegrity(Insertable<SyncPair> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta, localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('remote_path')) {
      context.handle(_remotePathMeta, remotePath.isAcceptableOrUnknown(data['remote_path']!, _remotePathMeta));
    } else if (isInserting) {
      context.missing(_remotePathMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta, provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('conflict_policy')) context.handle(_conflictPolicyMeta, conflictPolicy.isAcceptableOrUnknown(data['conflict_policy']!, _conflictPolicyMeta));
    if (data.containsKey('direction')) context.handle(_directionMeta, direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    if (data.containsKey('enabled')) context.handle(_enabledMeta, enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    if (data.containsKey('last_sync_at')) context.handle(_lastSyncAtMeta, lastSyncAt.isAcceptableOrUnknown(data['last_sync_at']!, _lastSyncAtMeta));
    if (data.containsKey('created_at')) context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    if (data.containsKey('include_patterns')) context.handle(_includePatternsMeta, includePatterns.isAcceptableOrUnknown(data['include_patterns']!, _includePatternsMeta));
    if (data.containsKey('exclude_patterns')) context.handle(_excludePatternsMeta, excludePatterns.isAcceptableOrUnknown(data['exclude_patterns']!, _excludePatternsMeta));
    if (data.containsKey('use_placeholders')) context.handle(_usePlaceholdersMeta, usePlaceholders.isAcceptableOrUnknown(data['use_placeholders']!, _usePlaceholdersMeta));
    return context;
  }

  @override
  List<GeneratedColumn> get $columns => [id, name, localPath, remotePath, provider, conflictPolicy, direction, enabled, lastSyncAt, createdAt, includePatterns, excludePatterns, usePlaceholders];
  @override
  SyncPair map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPair(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      localPath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      remotePath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}remote_path'])!,
      provider: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      conflictPolicy: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}conflict_policy'])!,
      direction: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      enabled: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      lastSyncAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}last_sync_at']),
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      includePatterns: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}include_patterns'])!,
      excludePatterns: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}exclude_patterns'])!,
      usePlaceholders: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}use_placeholders'])!,
    );
  }

  @override
  $SyncPairsTable createAlias(String alias) => $SyncPairsTable(attachedDatabase, alias);
}

class SyncPair extends DataClass implements Insertable<SyncPair> {
  final int id;
  final String name;
  final String localPath;
  final String remotePath;
  final String provider;
  final String conflictPolicy;
  final String direction;
  final bool enabled;
  final DateTime? lastSyncAt;
  final DateTime createdAt;
  final String includePatterns;
  final String excludePatterns;
  final bool usePlaceholders;

  const SyncPair({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remotePath,
    required this.provider,
    required this.conflictPolicy,
    required this.direction,
    required this.enabled,
    this.lastSyncAt,
    required this.createdAt,
    this.includePatterns = '',
    this.excludePatterns = '',
    this.usePlaceholders = false,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['local_path'] = Variable<String>(localPath);
    map['remote_path'] = Variable<String>(remotePath);
    map['provider'] = Variable<String>(provider);
    map['conflict_policy'] = Variable<String>(conflictPolicy);
    map['direction'] = Variable<String>(direction);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastSyncAt != null) map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['include_patterns'] = Variable<String>(includePatterns);
    map['exclude_patterns'] = Variable<String>(excludePatterns);
    map['use_placeholders'] = Variable<bool>(usePlaceholders);
    return map;
  }

  SyncPairsCompanion toCompanion(bool nullToAbsent) {
    return SyncPairsCompanion(
      id: Value(id),
      name: Value(name),
      localPath: Value(localPath),
      remotePath: Value(remotePath),
      provider: Value(provider),
      conflictPolicy: Value(conflictPolicy),
      direction: Value(direction),
      enabled: Value(enabled),
      lastSyncAt: lastSyncAt == null && nullToAbsent ? const Value.absent() : Value(lastSyncAt),
      createdAt: Value(createdAt),
      includePatterns: Value(includePatterns),
      excludePatterns: Value(excludePatterns),
      usePlaceholders: Value(usePlaceholders),
    );
  }

  SyncPair copyWith({int? id, String? name, String? localPath, String? remotePath, String? provider, String? conflictPolicy, String? direction, bool? enabled, Value<DateTime?>? lastSyncAt, DateTime? createdAt, String? includePatterns, String? excludePatterns, bool? usePlaceholders}) {
    return SyncPair(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      provider: provider ?? this.provider,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      direction: direction ?? this.direction,
      enabled: enabled ?? this.enabled,
      lastSyncAt: lastSyncAt == null ? this.lastSyncAt : lastSyncAt.value,
      createdAt: createdAt ?? this.createdAt,
      includePatterns: includePatterns ?? this.includePatterns,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      usePlaceholders: usePlaceholders ?? this.usePlaceholders,
    );
  }

  @override
  String toString() => 'SyncPair(id: $id, name: $name, localPath: $localPath, remotePath: $remotePath, provider: $provider)';

  @override
  int get hashCode => Object.hash(id, name, localPath, remotePath, provider);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SyncPair && other.id == id);

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) => {
    'id': id, 'name': name, 'localPath': localPath, 'remotePath': remotePath,
    'provider': provider, 'conflictPolicy': conflictPolicy, 'direction': direction,
    'enabled': enabled, 'lastSyncAt': lastSyncAt?.toIso8601String(), 'createdAt': createdAt.toIso8601String(),
    'includePatterns': includePatterns, 'excludePatterns': excludePatterns, 'usePlaceholders': usePlaceholders,
  };
}

class SyncPairsCompanion extends UpdateCompanion<SyncPair> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> localPath;
  final Value<String> remotePath;
  final Value<String> provider;
  final Value<String> conflictPolicy;
  final Value<String> direction;
  final Value<bool> enabled;
  final Value<DateTime?> lastSyncAt;
  final Value<DateTime> createdAt;
  final Value<String> includePatterns;
  final Value<String> excludePatterns;
  final Value<bool> usePlaceholders;

  const SyncPairsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.localPath = const Value.absent(),
    this.remotePath = const Value.absent(),
    this.provider = const Value.absent(),
    this.conflictPolicy = const Value.absent(),
    this.direction = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.includePatterns = const Value.absent(),
    this.excludePatterns = const Value.absent(),
    this.usePlaceholders = const Value.absent(),
  });

  SyncPairsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String localPath,
    required String remotePath,
    required String provider,
    this.conflictPolicy = const Value.absent(),
    this.direction = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.includePatterns = const Value.absent(),
    this.excludePatterns = const Value.absent(),
    this.usePlaceholders = const Value.absent(),
  })  : name = Value(name),
        localPath = Value(localPath),
        remotePath = Value(remotePath),
        provider = Value(provider);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<int>(id.value);
    if (name.present) map['name'] = Variable<String>(name.value);
    if (localPath.present) map['local_path'] = Variable<String>(localPath.value);
    if (remotePath.present) map['remote_path'] = Variable<String>(remotePath.value);
    if (provider.present) map['provider'] = Variable<String>(provider.value);
    if (conflictPolicy.present) map['conflict_policy'] = Variable<String>(conflictPolicy.value);
    if (direction.present) map['direction'] = Variable<String>(direction.value);
    if (enabled.present) map['enabled'] = Variable<bool>(enabled.value);
    if (lastSyncAt.present) map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    if (createdAt.present) map['created_at'] = Variable<DateTime>(createdAt.value);
    if (includePatterns.present) map['include_patterns'] = Variable<String>(includePatterns.value);
    if (excludePatterns.present) map['exclude_patterns'] = Variable<String>(excludePatterns.value);
    if (usePlaceholders.present) map['use_placeholders'] = Variable<bool>(usePlaceholders.value);
    return map;
  }

  @override
  String toString() => 'SyncPairsCompanion(name: $name, localPath: $localPath, remotePath: $remotePath)';
}

// --- SyncEntries ---

class $SyncEntriesTable extends SyncEntries with TableInfo<$SyncEntriesTable, SyncEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncEntriesTable(this.attachedDatabase, [this._alias]);

  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>('id', aliasedName, false,
      hasAutoIncrement: true, type: DriftSqlType.int, defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  late final GeneratedColumn<int> pairId = GeneratedColumn<int>('pair_id', aliasedName, false, type: DriftSqlType.int);
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>('relative_path', aliasedName, false, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<String> localHash = GeneratedColumn<String>('local_hash', aliasedName, true, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<String> remoteHash = GeneratedColumn<String>('remote_hash', aliasedName, true, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<DateTime> localModified = GeneratedColumn<DateTime>('local_modified', aliasedName, true, type: DriftSqlType.dateTime);
  @override
  late final GeneratedColumn<DateTime> remoteModified = GeneratedColumn<DateTime>('remote_modified', aliasedName, true, type: DriftSqlType.dateTime);
  @override
  late final GeneratedColumn<int> localSize = GeneratedColumn<int>('local_size', aliasedName, false, type: DriftSqlType.int, defaultValue: const Constant(0));
  @override
  late final GeneratedColumn<int> remoteSize = GeneratedColumn<int>('remote_size', aliasedName, false, type: DriftSqlType.int, defaultValue: const Constant(0));
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>('status', aliasedName, false, type: DriftSqlType.string, defaultValue: const Constant('synced'));
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>('error', aliasedName, true, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<bool> isFolder = GeneratedColumn<bool>('is_folder', aliasedName, false,
      type: DriftSqlType.bool, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_folder" IN (0, 1))'), defaultValue: const Constant(false));
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>('last_sync_at', aliasedName, true, type: DriftSqlType.dateTime);

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [{pairId, relativePath}];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_entries';
  @override
  VerificationContext validateIntegrity(Insertable<SyncEntry> instance, {bool isInserting = false}) => VerificationContext();

  @override
  List<GeneratedColumn> get $columns => [id, pairId, relativePath, localHash, remoteHash, localModified, remoteModified, localSize, remoteSize, status, error, isFolder, lastSyncAt];
  @override
  SyncEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncEntry(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      pairId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}pair_id'])!,
      relativePath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}relative_path'])!,
      localHash: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}local_hash']),
      remoteHash: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}remote_hash']),
      localModified: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}local_modified']),
      remoteModified: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}remote_modified']),
      localSize: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}local_size'])!,
      remoteSize: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}remote_size'])!,
      status: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      error: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}error']),
      isFolder: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_folder'])!,
      lastSyncAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}last_sync_at']),
    );
  }

  @override
  $SyncEntriesTable createAlias(String alias) => $SyncEntriesTable(attachedDatabase, alias);
}

class SyncEntry extends DataClass implements Insertable<SyncEntry> {
  final int id;
  final int pairId;
  final String relativePath;
  final String? localHash;
  final String? remoteHash;
  final DateTime? localModified;
  final DateTime? remoteModified;
  final int localSize;
  final int remoteSize;
  final String status;
  final String? error;
  final bool isFolder;
  final DateTime? lastSyncAt;

  const SyncEntry({
    required this.id,
    required this.pairId,
    required this.relativePath,
    this.localHash,
    this.remoteHash,
    this.localModified,
    this.remoteModified,
    required this.localSize,
    required this.remoteSize,
    required this.status,
    this.error,
    required this.isFolder,
    this.lastSyncAt,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['pair_id'] = Variable<int>(pairId);
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || localHash != null) map['local_hash'] = Variable<String>(localHash);
    if (!nullToAbsent || remoteHash != null) map['remote_hash'] = Variable<String>(remoteHash);
    if (!nullToAbsent || localModified != null) map['local_modified'] = Variable<DateTime>(localModified);
    if (!nullToAbsent || remoteModified != null) map['remote_modified'] = Variable<DateTime>(remoteModified);
    map['local_size'] = Variable<int>(localSize);
    map['remote_size'] = Variable<int>(remoteSize);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) map['error'] = Variable<String>(error);
    map['is_folder'] = Variable<bool>(isFolder);
    if (!nullToAbsent || lastSyncAt != null) map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    return map;
  }

  @override
  String toString() => 'SyncEntry(id: $id, pairId: $pairId, relativePath: $relativePath, status: $status)';

  @override
  int get hashCode => Object.hash(id, pairId, relativePath);

  @override
  bool operator ==(Object other) => identical(this, other) || (other is SyncEntry && other.id == id);

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) => {
    'id': id, 'pairId': pairId, 'relativePath': relativePath, 'status': status,
    'localHash': localHash, 'remoteHash': remoteHash, 'isFolder': isFolder,
  };
}

class SyncEntriesCompanion extends UpdateCompanion<SyncEntry> {
  final Value<int> id;
  final Value<int> pairId;
  final Value<String> relativePath;
  final Value<String?> localHash;
  final Value<String?> remoteHash;
  final Value<DateTime?> localModified;
  final Value<DateTime?> remoteModified;
  final Value<int> localSize;
  final Value<int> remoteSize;
  final Value<String> status;
  final Value<String?> error;
  final Value<bool> isFolder;
  final Value<DateTime?> lastSyncAt;

  const SyncEntriesCompanion({
    this.id = const Value.absent(),
    this.pairId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.localHash = const Value.absent(),
    this.remoteHash = const Value.absent(),
    this.localModified = const Value.absent(),
    this.remoteModified = const Value.absent(),
    this.localSize = const Value.absent(),
    this.remoteSize = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.isFolder = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
  });

  SyncEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int pairId,
    required String relativePath,
    this.localHash = const Value.absent(),
    this.remoteHash = const Value.absent(),
    this.localModified = const Value.absent(),
    this.remoteModified = const Value.absent(),
    this.localSize = const Value.absent(),
    this.remoteSize = const Value.absent(),
    this.status = const Value.absent(),
    this.error = const Value.absent(),
    this.isFolder = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
  })  : pairId = Value(pairId),
        relativePath = Value(relativePath);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<int>(id.value);
    if (pairId.present) map['pair_id'] = Variable<int>(pairId.value);
    if (relativePath.present) map['relative_path'] = Variable<String>(relativePath.value);
    if (localHash.present) map['local_hash'] = Variable<String>(localHash.value);
    if (remoteHash.present) map['remote_hash'] = Variable<String>(remoteHash.value);
    if (localModified.present) map['local_modified'] = Variable<DateTime>(localModified.value);
    if (remoteModified.present) map['remote_modified'] = Variable<DateTime>(remoteModified.value);
    if (localSize.present) map['local_size'] = Variable<int>(localSize.value);
    if (remoteSize.present) map['remote_size'] = Variable<int>(remoteSize.value);
    if (status.present) map['status'] = Variable<String>(status.value);
    if (error.present) map['error'] = Variable<String>(error.value);
    if (isFolder.present) map['is_folder'] = Variable<bool>(isFolder.value);
    if (lastSyncAt.present) map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    return map;
  }
}

// --- OfflineQueue ---

class $OfflineQueueTable extends OfflineQueue with TableInfo<$OfflineQueueTable, OfflineQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineQueueTable(this.attachedDatabase, [this._alias]);

  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>('id', aliasedName, false,
      hasAutoIncrement: true, type: DriftSqlType.int, defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  late final GeneratedColumn<int> pairId = GeneratedColumn<int>('pair_id', aliasedName, false, type: DriftSqlType.int);
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>('operation', aliasedName, false, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>('path', aliasedName, false, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<String> targetPath = GeneratedColumn<String>('target_path', aliasedName, true, type: DriftSqlType.string);
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>('created_at', aliasedName, false,
      type: DriftSqlType.dateTime, defaultValue: currentDateAndTime);
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>('completed', aliasedName, false,
      type: DriftSqlType.bool, defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'), defaultValue: const Constant(false));
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>('error', aliasedName, true, type: DriftSqlType.string);

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_queue';
  @override
  VerificationContext validateIntegrity(Insertable<OfflineQueueEntry> instance, {bool isInserting = false}) => VerificationContext();
  @override
  List<GeneratedColumn> get $columns => [id, pairId, operation, path, targetPath, createdAt, completed, error];
  @override
  OfflineQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineQueueEntry(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      pairId: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}pair_id'])!,
      operation: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}operation'])!,
      path: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      targetPath: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}target_path']),
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      completed: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
      error: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}error']),
    );
  }
  @override
  $OfflineQueueTable createAlias(String alias) => $OfflineQueueTable(attachedDatabase, alias);
}

class OfflineQueueEntry extends DataClass implements Insertable<OfflineQueueEntry> {
  final int id;
  final int pairId;
  final String operation;
  final String path;
  final String? targetPath;
  final DateTime createdAt;
  final bool completed;
  final String? error;

  const OfflineQueueEntry({
    required this.id,
    required this.pairId,
    required this.operation,
    required this.path,
    this.targetPath,
    required this.createdAt,
    required this.completed,
    this.error,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['pair_id'] = Variable<int>(pairId);
    map['operation'] = Variable<String>(operation);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || targetPath != null) map['target_path'] = Variable<String>(targetPath);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || error != null) map['error'] = Variable<String>(error);
    return map;
  }

  @override
  String toString() => 'OfflineQueueEntry(id: $id, operation: $operation, path: $path)';

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) => {
    'id': id, 'pairId': pairId, 'operation': operation, 'path': path,
    'targetPath': targetPath, 'completed': completed,
  };
}

class OfflineQueueCompanion extends UpdateCompanion<OfflineQueueEntry> {
  final Value<int> id;
  final Value<int> pairId;
  final Value<String> operation;
  final Value<String> path;
  final Value<String?> targetPath;
  final Value<DateTime> createdAt;
  final Value<bool> completed;
  final Value<String?> error;

  const OfflineQueueCompanion({
    this.id = const Value.absent(),
    this.pairId = const Value.absent(),
    this.operation = const Value.absent(),
    this.path = const Value.absent(),
    this.targetPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completed = const Value.absent(),
    this.error = const Value.absent(),
  });

  OfflineQueueCompanion.insert({
    this.id = const Value.absent(),
    required int pairId,
    required String operation,
    required String path,
    this.targetPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completed = const Value.absent(),
    this.error = const Value.absent(),
  })  : pairId = Value(pairId),
        operation = Value(operation),
        path = Value(path);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) map['id'] = Variable<int>(id.value);
    if (pairId.present) map['pair_id'] = Variable<int>(pairId.value);
    if (operation.present) map['operation'] = Variable<String>(operation.value);
    if (path.present) map['path'] = Variable<String>(path.value);
    if (targetPath.present) map['target_path'] = Variable<String>(targetPath.value);
    if (createdAt.present) map['created_at'] = Variable<DateTime>(createdAt.value);
    if (completed.present) map['completed'] = Variable<bool>(completed.value);
    if (error.present) map['error'] = Variable<String>(error.value);
    return map;
  }
}

// --- Database class ---

abstract class _$SyncDatabase extends GeneratedDatabase {
  _$SyncDatabase(QueryExecutor e) : super(e);

  late final $SyncPairsTable syncPairs = $SyncPairsTable(this);
  late final $SyncEntriesTable syncEntries = $SyncEntriesTable(this);
  late final $OfflineQueueTable offlineQueue = $OfflineQueueTable(this);

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [syncPairs, syncEntries, offlineQueue];
}
