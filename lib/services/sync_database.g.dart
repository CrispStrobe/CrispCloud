// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_database.dart';

// ignore_for_file: type=lint
class $SyncPairsTable extends SyncPairs
    with TableInfo<$SyncPairsTable, SyncPair> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPairsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remotePathMeta = const VerificationMeta(
    'remotePath',
  );
  @override
  late final GeneratedColumn<String> remotePath = GeneratedColumn<String>(
    'remote_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceBindingMeta = const VerificationMeta(
    'sourceBinding',
  );
  @override
  late final GeneratedColumn<String> sourceBinding = GeneratedColumn<String>(
    'source_binding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conflictPolicyMeta = const VerificationMeta(
    'conflictPolicy',
  );
  @override
  late final GeneratedColumn<String> conflictPolicy = GeneratedColumn<String>(
    'conflict_policy',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('newestWins'),
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('twoWay'),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _includePatternsMeta = const VerificationMeta(
    'includePatterns',
  );
  @override
  late final GeneratedColumn<String> includePatterns = GeneratedColumn<String>(
    'include_patterns',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _excludePatternsMeta = const VerificationMeta(
    'excludePatterns',
  );
  @override
  late final GeneratedColumn<String> excludePatterns = GeneratedColumn<String>(
    'exclude_patterns',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _usePlaceholdersMeta = const VerificationMeta(
    'usePlaceholders',
  );
  @override
  late final GeneratedColumn<bool> usePlaceholders = GeneratedColumn<bool>(
    'use_placeholders',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_placeholders" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    localPath,
    remotePath,
    provider,
    sourceBinding,
    conflictPolicy,
    direction,
    enabled,
    lastSyncAt,
    createdAt,
    includePatterns,
    excludePatterns,
    usePlaceholders,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pairs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPair> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('remote_path')) {
      context.handle(
        _remotePathMeta,
        remotePath.isAcceptableOrUnknown(data['remote_path']!, _remotePathMeta),
      );
    } else if (isInserting) {
      context.missing(_remotePathMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('source_binding')) {
      context.handle(
        _sourceBindingMeta,
        sourceBinding.isAcceptableOrUnknown(
          data['source_binding']!,
          _sourceBindingMeta,
        ),
      );
    }
    if (data.containsKey('conflict_policy')) {
      context.handle(
        _conflictPolicyMeta,
        conflictPolicy.isAcceptableOrUnknown(
          data['conflict_policy']!,
          _conflictPolicyMeta,
        ),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('include_patterns')) {
      context.handle(
        _includePatternsMeta,
        includePatterns.isAcceptableOrUnknown(
          data['include_patterns']!,
          _includePatternsMeta,
        ),
      );
    }
    if (data.containsKey('exclude_patterns')) {
      context.handle(
        _excludePatternsMeta,
        excludePatterns.isAcceptableOrUnknown(
          data['exclude_patterns']!,
          _excludePatternsMeta,
        ),
      );
    }
    if (data.containsKey('use_placeholders')) {
      context.handle(
        _usePlaceholdersMeta,
        usePlaceholders.isAcceptableOrUnknown(
          data['use_placeholders']!,
          _usePlaceholdersMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncPair map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPair(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      remotePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_path'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      sourceBinding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_binding'],
      ),
      conflictPolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_policy'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      includePatterns: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}include_patterns'],
      )!,
      excludePatterns: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exclude_patterns'],
      )!,
      usePlaceholders: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_placeholders'],
      )!,
    );
  }

  @override
  $SyncPairsTable createAlias(String alias) {
    return $SyncPairsTable(attachedDatabase, alias);
  }
}

class SyncPair extends DataClass implements Insertable<SyncPair> {
  final int id;
  final String name;
  final String localPath;
  final String remotePath;
  final String provider;

  /// Versioned local installation + remote account/root references. Legacy
  /// rows remain unbound until the user explicitly reviews their sources.
  final String? sourceBinding;
  final String conflictPolicy;
  final String direction;
  final bool enabled;
  final DateTime? lastSyncAt;
  final DateTime createdAt;

  /// Comma-separated glob patterns to include (empty = include all).
  /// Example: "*.dart,*.yaml,lib/**"
  final String includePatterns;

  /// Comma-separated glob patterns to exclude.
  /// Example: ".git/**,*.tmp,node_modules/**"
  final String excludePatterns;

  /// When true, new remote files are created as lightweight placeholders
  /// instead of being fully downloaded. Users can hydrate on demand.
  final bool usePlaceholders;
  const SyncPair({
    required this.id,
    required this.name,
    required this.localPath,
    required this.remotePath,
    required this.provider,
    this.sourceBinding,
    required this.conflictPolicy,
    required this.direction,
    required this.enabled,
    this.lastSyncAt,
    required this.createdAt,
    required this.includePatterns,
    required this.excludePatterns,
    required this.usePlaceholders,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['local_path'] = Variable<String>(localPath);
    map['remote_path'] = Variable<String>(remotePath);
    map['provider'] = Variable<String>(provider);
    if (!nullToAbsent || sourceBinding != null) {
      map['source_binding'] = Variable<String>(sourceBinding);
    }
    map['conflict_policy'] = Variable<String>(conflictPolicy);
    map['direction'] = Variable<String>(direction);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
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
      sourceBinding: sourceBinding == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceBinding),
      conflictPolicy: Value(conflictPolicy),
      direction: Value(direction),
      enabled: Value(enabled),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      createdAt: Value(createdAt),
      includePatterns: Value(includePatterns),
      excludePatterns: Value(excludePatterns),
      usePlaceholders: Value(usePlaceholders),
    );
  }

  factory SyncPair.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPair(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      localPath: serializer.fromJson<String>(json['localPath']),
      remotePath: serializer.fromJson<String>(json['remotePath']),
      provider: serializer.fromJson<String>(json['provider']),
      sourceBinding: serializer.fromJson<String?>(json['sourceBinding']),
      conflictPolicy: serializer.fromJson<String>(json['conflictPolicy']),
      direction: serializer.fromJson<String>(json['direction']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      includePatterns: serializer.fromJson<String>(json['includePatterns']),
      excludePatterns: serializer.fromJson<String>(json['excludePatterns']),
      usePlaceholders: serializer.fromJson<bool>(json['usePlaceholders']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'localPath': serializer.toJson<String>(localPath),
      'remotePath': serializer.toJson<String>(remotePath),
      'provider': serializer.toJson<String>(provider),
      'sourceBinding': serializer.toJson<String?>(sourceBinding),
      'conflictPolicy': serializer.toJson<String>(conflictPolicy),
      'direction': serializer.toJson<String>(direction),
      'enabled': serializer.toJson<bool>(enabled),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'includePatterns': serializer.toJson<String>(includePatterns),
      'excludePatterns': serializer.toJson<String>(excludePatterns),
      'usePlaceholders': serializer.toJson<bool>(usePlaceholders),
    };
  }

  SyncPair copyWith({
    int? id,
    String? name,
    String? localPath,
    String? remotePath,
    String? provider,
    Value<String?> sourceBinding = const Value.absent(),
    String? conflictPolicy,
    String? direction,
    bool? enabled,
    Value<DateTime?> lastSyncAt = const Value.absent(),
    DateTime? createdAt,
    String? includePatterns,
    String? excludePatterns,
    bool? usePlaceholders,
  }) => SyncPair(
    id: id ?? this.id,
    name: name ?? this.name,
    localPath: localPath ?? this.localPath,
    remotePath: remotePath ?? this.remotePath,
    provider: provider ?? this.provider,
    sourceBinding: sourceBinding.present
        ? sourceBinding.value
        : this.sourceBinding,
    conflictPolicy: conflictPolicy ?? this.conflictPolicy,
    direction: direction ?? this.direction,
    enabled: enabled ?? this.enabled,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    createdAt: createdAt ?? this.createdAt,
    includePatterns: includePatterns ?? this.includePatterns,
    excludePatterns: excludePatterns ?? this.excludePatterns,
    usePlaceholders: usePlaceholders ?? this.usePlaceholders,
  );
  SyncPair copyWithCompanion(SyncPairsCompanion data) {
    return SyncPair(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      remotePath: data.remotePath.present
          ? data.remotePath.value
          : this.remotePath,
      provider: data.provider.present ? data.provider.value : this.provider,
      sourceBinding: data.sourceBinding.present
          ? data.sourceBinding.value
          : this.sourceBinding,
      conflictPolicy: data.conflictPolicy.present
          ? data.conflictPolicy.value
          : this.conflictPolicy,
      direction: data.direction.present ? data.direction.value : this.direction,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      includePatterns: data.includePatterns.present
          ? data.includePatterns.value
          : this.includePatterns,
      excludePatterns: data.excludePatterns.present
          ? data.excludePatterns.value
          : this.excludePatterns,
      usePlaceholders: data.usePlaceholders.present
          ? data.usePlaceholders.value
          : this.usePlaceholders,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPair(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('localPath: $localPath, ')
          ..write('remotePath: $remotePath, ')
          ..write('provider: $provider, ')
          ..write('sourceBinding: $sourceBinding, ')
          ..write('conflictPolicy: $conflictPolicy, ')
          ..write('direction: $direction, ')
          ..write('enabled: $enabled, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('includePatterns: $includePatterns, ')
          ..write('excludePatterns: $excludePatterns, ')
          ..write('usePlaceholders: $usePlaceholders')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    localPath,
    remotePath,
    provider,
    sourceBinding,
    conflictPolicy,
    direction,
    enabled,
    lastSyncAt,
    createdAt,
    includePatterns,
    excludePatterns,
    usePlaceholders,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPair &&
          other.id == this.id &&
          other.name == this.name &&
          other.localPath == this.localPath &&
          other.remotePath == this.remotePath &&
          other.provider == this.provider &&
          other.sourceBinding == this.sourceBinding &&
          other.conflictPolicy == this.conflictPolicy &&
          other.direction == this.direction &&
          other.enabled == this.enabled &&
          other.lastSyncAt == this.lastSyncAt &&
          other.createdAt == this.createdAt &&
          other.includePatterns == this.includePatterns &&
          other.excludePatterns == this.excludePatterns &&
          other.usePlaceholders == this.usePlaceholders);
}

class SyncPairsCompanion extends UpdateCompanion<SyncPair> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> localPath;
  final Value<String> remotePath;
  final Value<String> provider;
  final Value<String?> sourceBinding;
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
    this.sourceBinding = const Value.absent(),
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
    this.sourceBinding = const Value.absent(),
    this.conflictPolicy = const Value.absent(),
    this.direction = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.includePatterns = const Value.absent(),
    this.excludePatterns = const Value.absent(),
    this.usePlaceholders = const Value.absent(),
  }) : name = Value(name),
       localPath = Value(localPath),
       remotePath = Value(remotePath),
       provider = Value(provider);
  static Insertable<SyncPair> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? localPath,
    Expression<String>? remotePath,
    Expression<String>? provider,
    Expression<String>? sourceBinding,
    Expression<String>? conflictPolicy,
    Expression<String>? direction,
    Expression<bool>? enabled,
    Expression<DateTime>? lastSyncAt,
    Expression<DateTime>? createdAt,
    Expression<String>? includePatterns,
    Expression<String>? excludePatterns,
    Expression<bool>? usePlaceholders,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (localPath != null) 'local_path': localPath,
      if (remotePath != null) 'remote_path': remotePath,
      if (provider != null) 'provider': provider,
      if (sourceBinding != null) 'source_binding': sourceBinding,
      if (conflictPolicy != null) 'conflict_policy': conflictPolicy,
      if (direction != null) 'direction': direction,
      if (enabled != null) 'enabled': enabled,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (createdAt != null) 'created_at': createdAt,
      if (includePatterns != null) 'include_patterns': includePatterns,
      if (excludePatterns != null) 'exclude_patterns': excludePatterns,
      if (usePlaceholders != null) 'use_placeholders': usePlaceholders,
    });
  }

  SyncPairsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? localPath,
    Value<String>? remotePath,
    Value<String>? provider,
    Value<String?>? sourceBinding,
    Value<String>? conflictPolicy,
    Value<String>? direction,
    Value<bool>? enabled,
    Value<DateTime?>? lastSyncAt,
    Value<DateTime>? createdAt,
    Value<String>? includePatterns,
    Value<String>? excludePatterns,
    Value<bool>? usePlaceholders,
  }) {
    return SyncPairsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      localPath: localPath ?? this.localPath,
      remotePath: remotePath ?? this.remotePath,
      provider: provider ?? this.provider,
      sourceBinding: sourceBinding ?? this.sourceBinding,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      direction: direction ?? this.direction,
      enabled: enabled ?? this.enabled,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      createdAt: createdAt ?? this.createdAt,
      includePatterns: includePatterns ?? this.includePatterns,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      usePlaceholders: usePlaceholders ?? this.usePlaceholders,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (remotePath.present) {
      map['remote_path'] = Variable<String>(remotePath.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (sourceBinding.present) {
      map['source_binding'] = Variable<String>(sourceBinding.value);
    }
    if (conflictPolicy.present) {
      map['conflict_policy'] = Variable<String>(conflictPolicy.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (includePatterns.present) {
      map['include_patterns'] = Variable<String>(includePatterns.value);
    }
    if (excludePatterns.present) {
      map['exclude_patterns'] = Variable<String>(excludePatterns.value);
    }
    if (usePlaceholders.present) {
      map['use_placeholders'] = Variable<bool>(usePlaceholders.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPairsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('localPath: $localPath, ')
          ..write('remotePath: $remotePath, ')
          ..write('provider: $provider, ')
          ..write('sourceBinding: $sourceBinding, ')
          ..write('conflictPolicy: $conflictPolicy, ')
          ..write('direction: $direction, ')
          ..write('enabled: $enabled, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('includePatterns: $includePatterns, ')
          ..write('excludePatterns: $excludePatterns, ')
          ..write('usePlaceholders: $usePlaceholders')
          ..write(')'))
        .toString();
  }
}

class $SyncEntriesTable extends SyncEntries
    with TableInfo<$SyncEntriesTable, SyncEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<int> pairId = GeneratedColumn<int>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sync_pairs (id)',
    ),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localHashMeta = const VerificationMeta(
    'localHash',
  );
  @override
  late final GeneratedColumn<String> localHash = GeneratedColumn<String>(
    'local_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteHashMeta = const VerificationMeta(
    'remoteHash',
  );
  @override
  late final GeneratedColumn<String> remoteHash = GeneratedColumn<String>(
    'remote_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localModifiedMeta = const VerificationMeta(
    'localModified',
  );
  @override
  late final GeneratedColumn<DateTime> localModified =
      GeneratedColumn<DateTime>(
        'local_modified',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remoteModifiedMeta = const VerificationMeta(
    'remoteModified',
  );
  @override
  late final GeneratedColumn<DateTime> remoteModified =
      GeneratedColumn<DateTime>(
        'remote_modified',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _localSizeMeta = const VerificationMeta(
    'localSize',
  );
  @override
  late final GeneratedColumn<int> localSize = GeneratedColumn<int>(
    'local_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteSizeMeta = const VerificationMeta(
    'remoteSize',
  );
  @override
  late final GeneratedColumn<int> remoteSize = GeneratedColumn<int>(
    'remote_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFolderMeta = const VerificationMeta(
    'isFolder',
  );
  @override
  late final GeneratedColumn<bool> isFolder = GeneratedColumn<bool>(
    'is_folder',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_folder" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pairId,
    relativePath,
    localHash,
    remoteHash,
    localModified,
    remoteModified,
    localSize,
    remoteSize,
    status,
    error,
    isFolder,
    lastSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('local_hash')) {
      context.handle(
        _localHashMeta,
        localHash.isAcceptableOrUnknown(data['local_hash']!, _localHashMeta),
      );
    }
    if (data.containsKey('remote_hash')) {
      context.handle(
        _remoteHashMeta,
        remoteHash.isAcceptableOrUnknown(data['remote_hash']!, _remoteHashMeta),
      );
    }
    if (data.containsKey('local_modified')) {
      context.handle(
        _localModifiedMeta,
        localModified.isAcceptableOrUnknown(
          data['local_modified']!,
          _localModifiedMeta,
        ),
      );
    }
    if (data.containsKey('remote_modified')) {
      context.handle(
        _remoteModifiedMeta,
        remoteModified.isAcceptableOrUnknown(
          data['remote_modified']!,
          _remoteModifiedMeta,
        ),
      );
    }
    if (data.containsKey('local_size')) {
      context.handle(
        _localSizeMeta,
        localSize.isAcceptableOrUnknown(data['local_size']!, _localSizeMeta),
      );
    }
    if (data.containsKey('remote_size')) {
      context.handle(
        _remoteSizeMeta,
        remoteSize.isAcceptableOrUnknown(data['remote_size']!, _remoteSizeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('is_folder')) {
      context.handle(
        _isFolderMeta,
        isFolder.isAcceptableOrUnknown(data['is_folder']!, _isFolderMeta),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {pairId, relativePath},
  ];
  @override
  SyncEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pair_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      localHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_hash'],
      ),
      remoteHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_hash'],
      ),
      localModified: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}local_modified'],
      ),
      remoteModified: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remote_modified'],
      ),
      localSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_size'],
      )!,
      remoteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_size'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      isFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_folder'],
      )!,
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
    );
  }

  @override
  $SyncEntriesTable createAlias(String alias) {
    return $SyncEntriesTable(attachedDatabase, alias);
  }
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
    if (!nullToAbsent || localHash != null) {
      map['local_hash'] = Variable<String>(localHash);
    }
    if (!nullToAbsent || remoteHash != null) {
      map['remote_hash'] = Variable<String>(remoteHash);
    }
    if (!nullToAbsent || localModified != null) {
      map['local_modified'] = Variable<DateTime>(localModified);
    }
    if (!nullToAbsent || remoteModified != null) {
      map['remote_modified'] = Variable<DateTime>(remoteModified);
    }
    map['local_size'] = Variable<int>(localSize);
    map['remote_size'] = Variable<int>(remoteSize);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['is_folder'] = Variable<bool>(isFolder);
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    return map;
  }

  SyncEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncEntriesCompanion(
      id: Value(id),
      pairId: Value(pairId),
      relativePath: Value(relativePath),
      localHash: localHash == null && nullToAbsent
          ? const Value.absent()
          : Value(localHash),
      remoteHash: remoteHash == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteHash),
      localModified: localModified == null && nullToAbsent
          ? const Value.absent()
          : Value(localModified),
      remoteModified: remoteModified == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteModified),
      localSize: Value(localSize),
      remoteSize: Value(remoteSize),
      status: Value(status),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      isFolder: Value(isFolder),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
    );
  }

  factory SyncEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncEntry(
      id: serializer.fromJson<int>(json['id']),
      pairId: serializer.fromJson<int>(json['pairId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      localHash: serializer.fromJson<String?>(json['localHash']),
      remoteHash: serializer.fromJson<String?>(json['remoteHash']),
      localModified: serializer.fromJson<DateTime?>(json['localModified']),
      remoteModified: serializer.fromJson<DateTime?>(json['remoteModified']),
      localSize: serializer.fromJson<int>(json['localSize']),
      remoteSize: serializer.fromJson<int>(json['remoteSize']),
      status: serializer.fromJson<String>(json['status']),
      error: serializer.fromJson<String?>(json['error']),
      isFolder: serializer.fromJson<bool>(json['isFolder']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pairId': serializer.toJson<int>(pairId),
      'relativePath': serializer.toJson<String>(relativePath),
      'localHash': serializer.toJson<String?>(localHash),
      'remoteHash': serializer.toJson<String?>(remoteHash),
      'localModified': serializer.toJson<DateTime?>(localModified),
      'remoteModified': serializer.toJson<DateTime?>(remoteModified),
      'localSize': serializer.toJson<int>(localSize),
      'remoteSize': serializer.toJson<int>(remoteSize),
      'status': serializer.toJson<String>(status),
      'error': serializer.toJson<String?>(error),
      'isFolder': serializer.toJson<bool>(isFolder),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
    };
  }

  SyncEntry copyWith({
    int? id,
    int? pairId,
    String? relativePath,
    Value<String?> localHash = const Value.absent(),
    Value<String?> remoteHash = const Value.absent(),
    Value<DateTime?> localModified = const Value.absent(),
    Value<DateTime?> remoteModified = const Value.absent(),
    int? localSize,
    int? remoteSize,
    String? status,
    Value<String?> error = const Value.absent(),
    bool? isFolder,
    Value<DateTime?> lastSyncAt = const Value.absent(),
  }) => SyncEntry(
    id: id ?? this.id,
    pairId: pairId ?? this.pairId,
    relativePath: relativePath ?? this.relativePath,
    localHash: localHash.present ? localHash.value : this.localHash,
    remoteHash: remoteHash.present ? remoteHash.value : this.remoteHash,
    localModified: localModified.present
        ? localModified.value
        : this.localModified,
    remoteModified: remoteModified.present
        ? remoteModified.value
        : this.remoteModified,
    localSize: localSize ?? this.localSize,
    remoteSize: remoteSize ?? this.remoteSize,
    status: status ?? this.status,
    error: error.present ? error.value : this.error,
    isFolder: isFolder ?? this.isFolder,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
  );
  SyncEntry copyWithCompanion(SyncEntriesCompanion data) {
    return SyncEntry(
      id: data.id.present ? data.id.value : this.id,
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      localHash: data.localHash.present ? data.localHash.value : this.localHash,
      remoteHash: data.remoteHash.present
          ? data.remoteHash.value
          : this.remoteHash,
      localModified: data.localModified.present
          ? data.localModified.value
          : this.localModified,
      remoteModified: data.remoteModified.present
          ? data.remoteModified.value
          : this.remoteModified,
      localSize: data.localSize.present ? data.localSize.value : this.localSize,
      remoteSize: data.remoteSize.present
          ? data.remoteSize.value
          : this.remoteSize,
      status: data.status.present ? data.status.value : this.status,
      error: data.error.present ? data.error.value : this.error,
      isFolder: data.isFolder.present ? data.isFolder.value : this.isFolder,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntry(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('relativePath: $relativePath, ')
          ..write('localHash: $localHash, ')
          ..write('remoteHash: $remoteHash, ')
          ..write('localModified: $localModified, ')
          ..write('remoteModified: $remoteModified, ')
          ..write('localSize: $localSize, ')
          ..write('remoteSize: $remoteSize, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('isFolder: $isFolder, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pairId,
    relativePath,
    localHash,
    remoteHash,
    localModified,
    remoteModified,
    localSize,
    remoteSize,
    status,
    error,
    isFolder,
    lastSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncEntry &&
          other.id == this.id &&
          other.pairId == this.pairId &&
          other.relativePath == this.relativePath &&
          other.localHash == this.localHash &&
          other.remoteHash == this.remoteHash &&
          other.localModified == this.localModified &&
          other.remoteModified == this.remoteModified &&
          other.localSize == this.localSize &&
          other.remoteSize == this.remoteSize &&
          other.status == this.status &&
          other.error == this.error &&
          other.isFolder == this.isFolder &&
          other.lastSyncAt == this.lastSyncAt);
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
  }) : pairId = Value(pairId),
       relativePath = Value(relativePath);
  static Insertable<SyncEntry> custom({
    Expression<int>? id,
    Expression<int>? pairId,
    Expression<String>? relativePath,
    Expression<String>? localHash,
    Expression<String>? remoteHash,
    Expression<DateTime>? localModified,
    Expression<DateTime>? remoteModified,
    Expression<int>? localSize,
    Expression<int>? remoteSize,
    Expression<String>? status,
    Expression<String>? error,
    Expression<bool>? isFolder,
    Expression<DateTime>? lastSyncAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pairId != null) 'pair_id': pairId,
      if (relativePath != null) 'relative_path': relativePath,
      if (localHash != null) 'local_hash': localHash,
      if (remoteHash != null) 'remote_hash': remoteHash,
      if (localModified != null) 'local_modified': localModified,
      if (remoteModified != null) 'remote_modified': remoteModified,
      if (localSize != null) 'local_size': localSize,
      if (remoteSize != null) 'remote_size': remoteSize,
      if (status != null) 'status': status,
      if (error != null) 'error': error,
      if (isFolder != null) 'is_folder': isFolder,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
    });
  }

  SyncEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? pairId,
    Value<String>? relativePath,
    Value<String?>? localHash,
    Value<String?>? remoteHash,
    Value<DateTime?>? localModified,
    Value<DateTime?>? remoteModified,
    Value<int>? localSize,
    Value<int>? remoteSize,
    Value<String>? status,
    Value<String?>? error,
    Value<bool>? isFolder,
    Value<DateTime?>? lastSyncAt,
  }) {
    return SyncEntriesCompanion(
      id: id ?? this.id,
      pairId: pairId ?? this.pairId,
      relativePath: relativePath ?? this.relativePath,
      localHash: localHash ?? this.localHash,
      remoteHash: remoteHash ?? this.remoteHash,
      localModified: localModified ?? this.localModified,
      remoteModified: remoteModified ?? this.remoteModified,
      localSize: localSize ?? this.localSize,
      remoteSize: remoteSize ?? this.remoteSize,
      status: status ?? this.status,
      error: error ?? this.error,
      isFolder: isFolder ?? this.isFolder,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pairId.present) {
      map['pair_id'] = Variable<int>(pairId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (localHash.present) {
      map['local_hash'] = Variable<String>(localHash.value);
    }
    if (remoteHash.present) {
      map['remote_hash'] = Variable<String>(remoteHash.value);
    }
    if (localModified.present) {
      map['local_modified'] = Variable<DateTime>(localModified.value);
    }
    if (remoteModified.present) {
      map['remote_modified'] = Variable<DateTime>(remoteModified.value);
    }
    if (localSize.present) {
      map['local_size'] = Variable<int>(localSize.value);
    }
    if (remoteSize.present) {
      map['remote_size'] = Variable<int>(remoteSize.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (isFolder.present) {
      map['is_folder'] = Variable<bool>(isFolder.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncEntriesCompanion(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('relativePath: $relativePath, ')
          ..write('localHash: $localHash, ')
          ..write('remoteHash: $remoteHash, ')
          ..write('localModified: $localModified, ')
          ..write('remoteModified: $remoteModified, ')
          ..write('localSize: $localSize, ')
          ..write('remoteSize: $remoteSize, ')
          ..write('status: $status, ')
          ..write('error: $error, ')
          ..write('isFolder: $isFolder, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }
}

class $OfflineQueueTable extends OfflineQueue
    with TableInfo<$OfflineQueueTable, OfflineQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pairIdMeta = const VerificationMeta('pairId');
  @override
  late final GeneratedColumn<int> pairId = GeneratedColumn<int>(
    'pair_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sync_pairs (id)',
    ),
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetPathMeta = const VerificationMeta(
    'targetPath',
  );
  @override
  late final GeneratedColumn<String> targetPath = GeneratedColumn<String>(
    'target_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceBindingMeta = const VerificationMeta(
    'sourceBinding',
  );
  @override
  late final GeneratedColumn<String> sourceBinding = GeneratedColumn<String>(
    'source_binding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pairId,
    operation,
    path,
    targetPath,
    sourceBinding,
    createdAt,
    completed,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pair_id')) {
      context.handle(
        _pairIdMeta,
        pairId.isAcceptableOrUnknown(data['pair_id']!, _pairIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pairIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('target_path')) {
      context.handle(
        _targetPathMeta,
        targetPath.isAcceptableOrUnknown(data['target_path']!, _targetPathMeta),
      );
    }
    if (data.containsKey('source_binding')) {
      context.handle(
        _sourceBindingMeta,
        sourceBinding.isAcceptableOrUnknown(
          data['source_binding']!,
          _sourceBindingMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineQueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pairId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pair_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      targetPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_path'],
      ),
      sourceBinding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_binding'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  $OfflineQueueTable createAlias(String alias) {
    return $OfflineQueueTable(attachedDatabase, alias);
  }
}

class OfflineQueueEntry extends DataClass
    implements Insertable<OfflineQueueEntry> {
  final int id;
  final int pairId;
  final String operation;
  final String path;
  final String? targetPath;

  /// Exact binding in effect when queued; never inherited after a rebind.
  final String? sourceBinding;
  final DateTime createdAt;
  final bool completed;
  final String? error;
  const OfflineQueueEntry({
    required this.id,
    required this.pairId,
    required this.operation,
    required this.path,
    this.targetPath,
    this.sourceBinding,
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
    if (!nullToAbsent || targetPath != null) {
      map['target_path'] = Variable<String>(targetPath);
    }
    if (!nullToAbsent || sourceBinding != null) {
      map['source_binding'] = Variable<String>(sourceBinding);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  OfflineQueueCompanion toCompanion(bool nullToAbsent) {
    return OfflineQueueCompanion(
      id: Value(id),
      pairId: Value(pairId),
      operation: Value(operation),
      path: Value(path),
      targetPath: targetPath == null && nullToAbsent
          ? const Value.absent()
          : Value(targetPath),
      sourceBinding: sourceBinding == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceBinding),
      createdAt: Value(createdAt),
      completed: Value(completed),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory OfflineQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineQueueEntry(
      id: serializer.fromJson<int>(json['id']),
      pairId: serializer.fromJson<int>(json['pairId']),
      operation: serializer.fromJson<String>(json['operation']),
      path: serializer.fromJson<String>(json['path']),
      targetPath: serializer.fromJson<String?>(json['targetPath']),
      sourceBinding: serializer.fromJson<String?>(json['sourceBinding']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      completed: serializer.fromJson<bool>(json['completed']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pairId': serializer.toJson<int>(pairId),
      'operation': serializer.toJson<String>(operation),
      'path': serializer.toJson<String>(path),
      'targetPath': serializer.toJson<String?>(targetPath),
      'sourceBinding': serializer.toJson<String?>(sourceBinding),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'completed': serializer.toJson<bool>(completed),
      'error': serializer.toJson<String?>(error),
    };
  }

  OfflineQueueEntry copyWith({
    int? id,
    int? pairId,
    String? operation,
    String? path,
    Value<String?> targetPath = const Value.absent(),
    Value<String?> sourceBinding = const Value.absent(),
    DateTime? createdAt,
    bool? completed,
    Value<String?> error = const Value.absent(),
  }) => OfflineQueueEntry(
    id: id ?? this.id,
    pairId: pairId ?? this.pairId,
    operation: operation ?? this.operation,
    path: path ?? this.path,
    targetPath: targetPath.present ? targetPath.value : this.targetPath,
    sourceBinding: sourceBinding.present
        ? sourceBinding.value
        : this.sourceBinding,
    createdAt: createdAt ?? this.createdAt,
    completed: completed ?? this.completed,
    error: error.present ? error.value : this.error,
  );
  OfflineQueueEntry copyWithCompanion(OfflineQueueCompanion data) {
    return OfflineQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      pairId: data.pairId.present ? data.pairId.value : this.pairId,
      operation: data.operation.present ? data.operation.value : this.operation,
      path: data.path.present ? data.path.value : this.path,
      targetPath: data.targetPath.present
          ? data.targetPath.value
          : this.targetPath,
      sourceBinding: data.sourceBinding.present
          ? data.sourceBinding.value
          : this.sourceBinding,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      completed: data.completed.present ? data.completed.value : this.completed,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueEntry(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('operation: $operation, ')
          ..write('path: $path, ')
          ..write('targetPath: $targetPath, ')
          ..write('sourceBinding: $sourceBinding, ')
          ..write('createdAt: $createdAt, ')
          ..write('completed: $completed, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pairId,
    operation,
    path,
    targetPath,
    sourceBinding,
    createdAt,
    completed,
    error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineQueueEntry &&
          other.id == this.id &&
          other.pairId == this.pairId &&
          other.operation == this.operation &&
          other.path == this.path &&
          other.targetPath == this.targetPath &&
          other.sourceBinding == this.sourceBinding &&
          other.createdAt == this.createdAt &&
          other.completed == this.completed &&
          other.error == this.error);
}

class OfflineQueueCompanion extends UpdateCompanion<OfflineQueueEntry> {
  final Value<int> id;
  final Value<int> pairId;
  final Value<String> operation;
  final Value<String> path;
  final Value<String?> targetPath;
  final Value<String?> sourceBinding;
  final Value<DateTime> createdAt;
  final Value<bool> completed;
  final Value<String?> error;
  const OfflineQueueCompanion({
    this.id = const Value.absent(),
    this.pairId = const Value.absent(),
    this.operation = const Value.absent(),
    this.path = const Value.absent(),
    this.targetPath = const Value.absent(),
    this.sourceBinding = const Value.absent(),
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
    this.sourceBinding = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completed = const Value.absent(),
    this.error = const Value.absent(),
  }) : pairId = Value(pairId),
       operation = Value(operation),
       path = Value(path);
  static Insertable<OfflineQueueEntry> custom({
    Expression<int>? id,
    Expression<int>? pairId,
    Expression<String>? operation,
    Expression<String>? path,
    Expression<String>? targetPath,
    Expression<String>? sourceBinding,
    Expression<DateTime>? createdAt,
    Expression<bool>? completed,
    Expression<String>? error,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pairId != null) 'pair_id': pairId,
      if (operation != null) 'operation': operation,
      if (path != null) 'path': path,
      if (targetPath != null) 'target_path': targetPath,
      if (sourceBinding != null) 'source_binding': sourceBinding,
      if (createdAt != null) 'created_at': createdAt,
      if (completed != null) 'completed': completed,
      if (error != null) 'error': error,
    });
  }

  OfflineQueueCompanion copyWith({
    Value<int>? id,
    Value<int>? pairId,
    Value<String>? operation,
    Value<String>? path,
    Value<String?>? targetPath,
    Value<String?>? sourceBinding,
    Value<DateTime>? createdAt,
    Value<bool>? completed,
    Value<String?>? error,
  }) {
    return OfflineQueueCompanion(
      id: id ?? this.id,
      pairId: pairId ?? this.pairId,
      operation: operation ?? this.operation,
      path: path ?? this.path,
      targetPath: targetPath ?? this.targetPath,
      sourceBinding: sourceBinding ?? this.sourceBinding,
      createdAt: createdAt ?? this.createdAt,
      completed: completed ?? this.completed,
      error: error ?? this.error,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pairId.present) {
      map['pair_id'] = Variable<int>(pairId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (targetPath.present) {
      map['target_path'] = Variable<String>(targetPath.value);
    }
    if (sourceBinding.present) {
      map['source_binding'] = Variable<String>(sourceBinding.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueCompanion(')
          ..write('id: $id, ')
          ..write('pairId: $pairId, ')
          ..write('operation: $operation, ')
          ..write('path: $path, ')
          ..write('targetPath: $targetPath, ')
          ..write('sourceBinding: $sourceBinding, ')
          ..write('createdAt: $createdAt, ')
          ..write('completed: $completed, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }
}

abstract class _$SyncDatabase extends GeneratedDatabase {
  _$SyncDatabase(QueryExecutor e) : super(e);
  $SyncDatabaseManager get managers => $SyncDatabaseManager(this);
  late final $SyncPairsTable syncPairs = $SyncPairsTable(this);
  late final $SyncEntriesTable syncEntries = $SyncEntriesTable(this);
  late final $OfflineQueueTable offlineQueue = $OfflineQueueTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    syncPairs,
    syncEntries,
    offlineQueue,
  ];
}

typedef $$SyncPairsTableCreateCompanionBuilder =
    SyncPairsCompanion Function({
      Value<int> id,
      required String name,
      required String localPath,
      required String remotePath,
      required String provider,
      Value<String?> sourceBinding,
      Value<String> conflictPolicy,
      Value<String> direction,
      Value<bool> enabled,
      Value<DateTime?> lastSyncAt,
      Value<DateTime> createdAt,
      Value<String> includePatterns,
      Value<String> excludePatterns,
      Value<bool> usePlaceholders,
    });
typedef $$SyncPairsTableUpdateCompanionBuilder =
    SyncPairsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> localPath,
      Value<String> remotePath,
      Value<String> provider,
      Value<String?> sourceBinding,
      Value<String> conflictPolicy,
      Value<String> direction,
      Value<bool> enabled,
      Value<DateTime?> lastSyncAt,
      Value<DateTime> createdAt,
      Value<String> includePatterns,
      Value<String> excludePatterns,
      Value<bool> usePlaceholders,
    });

final class $$SyncPairsTableReferences
    extends BaseReferences<_$SyncDatabase, $SyncPairsTable, SyncPair> {
  $$SyncPairsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SyncEntriesTable, List<SyncEntry>>
  _syncEntriesRefsTable(_$SyncDatabase db) => MultiTypedResultKey.fromTable(
    db.syncEntries,
    aliasName: 'sync_pairs__id__sync_entries__pair_id',
  );

  $$SyncEntriesTableProcessedTableManager get syncEntriesRefs {
    final manager = $$SyncEntriesTableTableManager(
      $_db,
      $_db.syncEntries,
    ).filter((f) => f.pairId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_syncEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OfflineQueueTable, List<OfflineQueueEntry>>
  _offlineQueueRefsTable(_$SyncDatabase db) => MultiTypedResultKey.fromTable(
    db.offlineQueue,
    aliasName: 'sync_pairs__id__offline_queue__pair_id',
  );

  $$OfflineQueueTableProcessedTableManager get offlineQueueRefs {
    final manager = $$OfflineQueueTableTableManager(
      $_db,
      $_db.offlineQueue,
    ).filter((f) => f.pairId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_offlineQueueRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SyncPairsTableFilterComposer
    extends Composer<_$SyncDatabase, $SyncPairsTable> {
  $$SyncPairsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictPolicy => $composableBuilder(
    column: $table.conflictPolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get includePatterns => $composableBuilder(
    column: $table.includePatterns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excludePatterns => $composableBuilder(
    column: $table.excludePatterns,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usePlaceholders => $composableBuilder(
    column: $table.usePlaceholders,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> syncEntriesRefs(
    Expression<bool> Function($$SyncEntriesTableFilterComposer f) f,
  ) {
    final $$SyncEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncEntries,
      getReferencedColumn: (t) => t.pairId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncEntriesTableFilterComposer(
            $db: $db,
            $table: $db.syncEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> offlineQueueRefs(
    Expression<bool> Function($$OfflineQueueTableFilterComposer f) f,
  ) {
    final $$OfflineQueueTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.offlineQueue,
      getReferencedColumn: (t) => t.pairId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OfflineQueueTableFilterComposer(
            $db: $db,
            $table: $db.offlineQueue,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SyncPairsTableOrderingComposer
    extends Composer<_$SyncDatabase, $SyncPairsTable> {
  $$SyncPairsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictPolicy => $composableBuilder(
    column: $table.conflictPolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get includePatterns => $composableBuilder(
    column: $table.includePatterns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excludePatterns => $composableBuilder(
    column: $table.excludePatterns,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usePlaceholders => $composableBuilder(
    column: $table.usePlaceholders,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncPairsTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SyncPairsTable> {
  $$SyncPairsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conflictPolicy => $composableBuilder(
    column: $table.conflictPolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get includePatterns => $composableBuilder(
    column: $table.includePatterns,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excludePatterns => $composableBuilder(
    column: $table.excludePatterns,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get usePlaceholders => $composableBuilder(
    column: $table.usePlaceholders,
    builder: (column) => column,
  );

  Expression<T> syncEntriesRefs<T extends Object>(
    Expression<T> Function($$SyncEntriesTableAnnotationComposer a) f,
  ) {
    final $$SyncEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncEntries,
      getReferencedColumn: (t) => t.pairId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.syncEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> offlineQueueRefs<T extends Object>(
    Expression<T> Function($$OfflineQueueTableAnnotationComposer a) f,
  ) {
    final $$OfflineQueueTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.offlineQueue,
      getReferencedColumn: (t) => t.pairId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OfflineQueueTableAnnotationComposer(
            $db: $db,
            $table: $db.offlineQueue,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SyncPairsTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $SyncPairsTable,
          SyncPair,
          $$SyncPairsTableFilterComposer,
          $$SyncPairsTableOrderingComposer,
          $$SyncPairsTableAnnotationComposer,
          $$SyncPairsTableCreateCompanionBuilder,
          $$SyncPairsTableUpdateCompanionBuilder,
          (SyncPair, $$SyncPairsTableReferences),
          SyncPair,
          PrefetchHooks Function({bool syncEntriesRefs, bool offlineQueueRefs})
        > {
  $$SyncPairsTableTableManager(_$SyncDatabase db, $SyncPairsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPairsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPairsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPairsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String> remotePath = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String?> sourceBinding = const Value.absent(),
                Value<String> conflictPolicy = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> includePatterns = const Value.absent(),
                Value<String> excludePatterns = const Value.absent(),
                Value<bool> usePlaceholders = const Value.absent(),
              }) => SyncPairsCompanion(
                id: id,
                name: name,
                localPath: localPath,
                remotePath: remotePath,
                provider: provider,
                sourceBinding: sourceBinding,
                conflictPolicy: conflictPolicy,
                direction: direction,
                enabled: enabled,
                lastSyncAt: lastSyncAt,
                createdAt: createdAt,
                includePatterns: includePatterns,
                excludePatterns: excludePatterns,
                usePlaceholders: usePlaceholders,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String localPath,
                required String remotePath,
                required String provider,
                Value<String?> sourceBinding = const Value.absent(),
                Value<String> conflictPolicy = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> includePatterns = const Value.absent(),
                Value<String> excludePatterns = const Value.absent(),
                Value<bool> usePlaceholders = const Value.absent(),
              }) => SyncPairsCompanion.insert(
                id: id,
                name: name,
                localPath: localPath,
                remotePath: remotePath,
                provider: provider,
                sourceBinding: sourceBinding,
                conflictPolicy: conflictPolicy,
                direction: direction,
                enabled: enabled,
                lastSyncAt: lastSyncAt,
                createdAt: createdAt,
                includePatterns: includePatterns,
                excludePatterns: excludePatterns,
                usePlaceholders: usePlaceholders,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SyncPairsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({syncEntriesRefs = false, offlineQueueRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (syncEntriesRefs) db.syncEntries,
                    if (offlineQueueRefs) db.offlineQueue,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (syncEntriesRefs)
                        await $_getPrefetchedData<
                          SyncPair,
                          $SyncPairsTable,
                          SyncEntry
                        >(
                          currentTable: table,
                          referencedTable: $$SyncPairsTableReferences
                              ._syncEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SyncPairsTableReferences(
                                db,
                                table,
                                p0,
                              ).syncEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.pairId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (offlineQueueRefs)
                        await $_getPrefetchedData<
                          SyncPair,
                          $SyncPairsTable,
                          OfflineQueueEntry
                        >(
                          currentTable: table,
                          referencedTable: $$SyncPairsTableReferences
                              ._offlineQueueRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SyncPairsTableReferences(
                                db,
                                table,
                                p0,
                              ).offlineQueueRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.pairId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SyncPairsTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $SyncPairsTable,
      SyncPair,
      $$SyncPairsTableFilterComposer,
      $$SyncPairsTableOrderingComposer,
      $$SyncPairsTableAnnotationComposer,
      $$SyncPairsTableCreateCompanionBuilder,
      $$SyncPairsTableUpdateCompanionBuilder,
      (SyncPair, $$SyncPairsTableReferences),
      SyncPair,
      PrefetchHooks Function({bool syncEntriesRefs, bool offlineQueueRefs})
    >;
typedef $$SyncEntriesTableCreateCompanionBuilder =
    SyncEntriesCompanion Function({
      Value<int> id,
      required int pairId,
      required String relativePath,
      Value<String?> localHash,
      Value<String?> remoteHash,
      Value<DateTime?> localModified,
      Value<DateTime?> remoteModified,
      Value<int> localSize,
      Value<int> remoteSize,
      Value<String> status,
      Value<String?> error,
      Value<bool> isFolder,
      Value<DateTime?> lastSyncAt,
    });
typedef $$SyncEntriesTableUpdateCompanionBuilder =
    SyncEntriesCompanion Function({
      Value<int> id,
      Value<int> pairId,
      Value<String> relativePath,
      Value<String?> localHash,
      Value<String?> remoteHash,
      Value<DateTime?> localModified,
      Value<DateTime?> remoteModified,
      Value<int> localSize,
      Value<int> remoteSize,
      Value<String> status,
      Value<String?> error,
      Value<bool> isFolder,
      Value<DateTime?> lastSyncAt,
    });

final class $$SyncEntriesTableReferences
    extends BaseReferences<_$SyncDatabase, $SyncEntriesTable, SyncEntry> {
  $$SyncEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SyncPairsTable _pairIdTable(_$SyncDatabase db) =>
      db.syncPairs.createAlias('sync_entries__pair_id__sync_pairs__id');

  $$SyncPairsTableProcessedTableManager get pairId {
    final $_column = $_itemColumn<int>('pair_id')!;

    final manager = $$SyncPairsTableTableManager(
      $_db,
      $_db.syncPairs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_pairIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SyncEntriesTableFilterComposer
    extends Composer<_$SyncDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localHash => $composableBuilder(
    column: $table.localHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteHash => $composableBuilder(
    column: $table.remoteHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get localModified => $composableBuilder(
    column: $table.localModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remoteModified => $composableBuilder(
    column: $table.remoteModified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSize => $composableBuilder(
    column: $table.localSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteSize => $composableBuilder(
    column: $table.remoteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  $$SyncPairsTableFilterComposer get pairId {
    final $$SyncPairsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableFilterComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncEntriesTableOrderingComposer
    extends Composer<_$SyncDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localHash => $composableBuilder(
    column: $table.localHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteHash => $composableBuilder(
    column: $table.remoteHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get localModified => $composableBuilder(
    column: $table.localModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remoteModified => $composableBuilder(
    column: $table.remoteModified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSize => $composableBuilder(
    column: $table.localSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteSize => $composableBuilder(
    column: $table.remoteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$SyncPairsTableOrderingComposer get pairId {
    final $$SyncPairsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableOrderingComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncEntriesTableAnnotationComposer
    extends Composer<_$SyncDatabase, $SyncEntriesTable> {
  $$SyncEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localHash =>
      $composableBuilder(column: $table.localHash, builder: (column) => column);

  GeneratedColumn<String> get remoteHash => $composableBuilder(
    column: $table.remoteHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get localModified => $composableBuilder(
    column: $table.localModified,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remoteModified => $composableBuilder(
    column: $table.remoteModified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localSize =>
      $composableBuilder(column: $table.localSize, builder: (column) => column);

  GeneratedColumn<int> get remoteSize => $composableBuilder(
    column: $table.remoteSize,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<bool> get isFolder =>
      $composableBuilder(column: $table.isFolder, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  $$SyncPairsTableAnnotationComposer get pairId {
    final $$SyncPairsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableAnnotationComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncEntriesTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $SyncEntriesTable,
          SyncEntry,
          $$SyncEntriesTableFilterComposer,
          $$SyncEntriesTableOrderingComposer,
          $$SyncEntriesTableAnnotationComposer,
          $$SyncEntriesTableCreateCompanionBuilder,
          $$SyncEntriesTableUpdateCompanionBuilder,
          (SyncEntry, $$SyncEntriesTableReferences),
          SyncEntry,
          PrefetchHooks Function({bool pairId})
        > {
  $$SyncEntriesTableTableManager(_$SyncDatabase db, $SyncEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> pairId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String?> localHash = const Value.absent(),
                Value<String?> remoteHash = const Value.absent(),
                Value<DateTime?> localModified = const Value.absent(),
                Value<DateTime?> remoteModified = const Value.absent(),
                Value<int> localSize = const Value.absent(),
                Value<int> remoteSize = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<bool> isFolder = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
              }) => SyncEntriesCompanion(
                id: id,
                pairId: pairId,
                relativePath: relativePath,
                localHash: localHash,
                remoteHash: remoteHash,
                localModified: localModified,
                remoteModified: remoteModified,
                localSize: localSize,
                remoteSize: remoteSize,
                status: status,
                error: error,
                isFolder: isFolder,
                lastSyncAt: lastSyncAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int pairId,
                required String relativePath,
                Value<String?> localHash = const Value.absent(),
                Value<String?> remoteHash = const Value.absent(),
                Value<DateTime?> localModified = const Value.absent(),
                Value<DateTime?> remoteModified = const Value.absent(),
                Value<int> localSize = const Value.absent(),
                Value<int> remoteSize = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<bool> isFolder = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
              }) => SyncEntriesCompanion.insert(
                id: id,
                pairId: pairId,
                relativePath: relativePath,
                localHash: localHash,
                remoteHash: remoteHash,
                localModified: localModified,
                remoteModified: remoteModified,
                localSize: localSize,
                remoteSize: remoteSize,
                status: status,
                error: error,
                isFolder: isFolder,
                lastSyncAt: lastSyncAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SyncEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pairId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (pairId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.pairId,
                                referencedTable: $$SyncEntriesTableReferences
                                    ._pairIdTable(db),
                                referencedColumn: $$SyncEntriesTableReferences
                                    ._pairIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SyncEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $SyncEntriesTable,
      SyncEntry,
      $$SyncEntriesTableFilterComposer,
      $$SyncEntriesTableOrderingComposer,
      $$SyncEntriesTableAnnotationComposer,
      $$SyncEntriesTableCreateCompanionBuilder,
      $$SyncEntriesTableUpdateCompanionBuilder,
      (SyncEntry, $$SyncEntriesTableReferences),
      SyncEntry,
      PrefetchHooks Function({bool pairId})
    >;
typedef $$OfflineQueueTableCreateCompanionBuilder =
    OfflineQueueCompanion Function({
      Value<int> id,
      required int pairId,
      required String operation,
      required String path,
      Value<String?> targetPath,
      Value<String?> sourceBinding,
      Value<DateTime> createdAt,
      Value<bool> completed,
      Value<String?> error,
    });
typedef $$OfflineQueueTableUpdateCompanionBuilder =
    OfflineQueueCompanion Function({
      Value<int> id,
      Value<int> pairId,
      Value<String> operation,
      Value<String> path,
      Value<String?> targetPath,
      Value<String?> sourceBinding,
      Value<DateTime> createdAt,
      Value<bool> completed,
      Value<String?> error,
    });

final class $$OfflineQueueTableReferences
    extends
        BaseReferences<_$SyncDatabase, $OfflineQueueTable, OfflineQueueEntry> {
  $$OfflineQueueTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SyncPairsTable _pairIdTable(_$SyncDatabase db) =>
      db.syncPairs.createAlias('offline_queue__pair_id__sync_pairs__id');

  $$SyncPairsTableProcessedTableManager get pairId {
    final $_column = $_itemColumn<int>('pair_id')!;

    final manager = $$SyncPairsTableTableManager(
      $_db,
      $_db.syncPairs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_pairIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OfflineQueueTableFilterComposer
    extends Composer<_$SyncDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  $$SyncPairsTableFilterComposer get pairId {
    final $$SyncPairsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableFilterComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OfflineQueueTableOrderingComposer
    extends Composer<_$SyncDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  $$SyncPairsTableOrderingComposer get pairId {
    final $$SyncPairsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableOrderingComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OfflineQueueTableAnnotationComposer
    extends Composer<_$SyncDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceBinding => $composableBuilder(
    column: $table.sourceBinding,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  $$SyncPairsTableAnnotationComposer get pairId {
    final $$SyncPairsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pairId,
      referencedTable: $db.syncPairs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncPairsTableAnnotationComposer(
            $db: $db,
            $table: $db.syncPairs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OfflineQueueTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $OfflineQueueTable,
          OfflineQueueEntry,
          $$OfflineQueueTableFilterComposer,
          $$OfflineQueueTableOrderingComposer,
          $$OfflineQueueTableAnnotationComposer,
          $$OfflineQueueTableCreateCompanionBuilder,
          $$OfflineQueueTableUpdateCompanionBuilder,
          (OfflineQueueEntry, $$OfflineQueueTableReferences),
          OfflineQueueEntry,
          PrefetchHooks Function({bool pairId})
        > {
  $$OfflineQueueTableTableManager(_$SyncDatabase db, $OfflineQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> pairId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String?> targetPath = const Value.absent(),
                Value<String?> sourceBinding = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => OfflineQueueCompanion(
                id: id,
                pairId: pairId,
                operation: operation,
                path: path,
                targetPath: targetPath,
                sourceBinding: sourceBinding,
                createdAt: createdAt,
                completed: completed,
                error: error,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int pairId,
                required String operation,
                required String path,
                Value<String?> targetPath = const Value.absent(),
                Value<String?> sourceBinding = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => OfflineQueueCompanion.insert(
                id: id,
                pairId: pairId,
                operation: operation,
                path: path,
                targetPath: targetPath,
                sourceBinding: sourceBinding,
                createdAt: createdAt,
                completed: completed,
                error: error,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OfflineQueueTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({pairId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (pairId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.pairId,
                                referencedTable: $$OfflineQueueTableReferences
                                    ._pairIdTable(db),
                                referencedColumn: $$OfflineQueueTableReferences
                                    ._pairIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OfflineQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $OfflineQueueTable,
      OfflineQueueEntry,
      $$OfflineQueueTableFilterComposer,
      $$OfflineQueueTableOrderingComposer,
      $$OfflineQueueTableAnnotationComposer,
      $$OfflineQueueTableCreateCompanionBuilder,
      $$OfflineQueueTableUpdateCompanionBuilder,
      (OfflineQueueEntry, $$OfflineQueueTableReferences),
      OfflineQueueEntry,
      PrefetchHooks Function({bool pairId})
    >;

class $SyncDatabaseManager {
  final _$SyncDatabase _db;
  $SyncDatabaseManager(this._db);
  $$SyncPairsTableTableManager get syncPairs =>
      $$SyncPairsTableTableManager(_db, _db.syncPairs);
  $$SyncEntriesTableTableManager get syncEntries =>
      $$SyncEntriesTableTableManager(_db, _db.syncEntries);
  $$OfflineQueueTableTableManager get offlineQueue =>
      $$OfflineQueueTableTableManager(_db, _db.offlineQueue);
}
