// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SosRecordsTable extends SosRecords
    with TableInfo<$SosRecordsTable, SosRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SosRecordsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<String> latitude = GeneratedColumn<String>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<String> longitude = GeneratedColumn<String>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('准备广播'),
  );
  static const VerificationMeta _createTimeMeta = const VerificationMeta(
    'createTime',
  );
  @override
  late final GeneratedColumn<DateTime> createTime = GeneratedColumn<DateTime>(
    'create_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    latitude,
    longitude,
    status,
    createTime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sos_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SosRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('create_time')) {
      context.handle(
        _createTimeMeta,
        createTime.isAcceptableOrUnknown(data['create_time']!, _createTimeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SosRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SosRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}longitude'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}create_time'],
      )!,
    );
  }

  @override
  $SosRecordsTable createAlias(String alias) {
    return $SosRecordsTable(attachedDatabase, alias);
  }
}

class SosRecord extends DataClass implements Insertable<SosRecord> {
  final int id;
  final String latitude;
  final String longitude;
  final String status;
  final DateTime createTime;
  const SosRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.createTime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['latitude'] = Variable<String>(latitude);
    map['longitude'] = Variable<String>(longitude);
    map['status'] = Variable<String>(status);
    map['create_time'] = Variable<DateTime>(createTime);
    return map;
  }

  SosRecordsCompanion toCompanion(bool nullToAbsent) {
    return SosRecordsCompanion(
      id: Value(id),
      latitude: Value(latitude),
      longitude: Value(longitude),
      status: Value(status),
      createTime: Value(createTime),
    );
  }

  factory SosRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SosRecord(
      id: serializer.fromJson<int>(json['id']),
      latitude: serializer.fromJson<String>(json['latitude']),
      longitude: serializer.fromJson<String>(json['longitude']),
      status: serializer.fromJson<String>(json['status']),
      createTime: serializer.fromJson<DateTime>(json['createTime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'latitude': serializer.toJson<String>(latitude),
      'longitude': serializer.toJson<String>(longitude),
      'status': serializer.toJson<String>(status),
      'createTime': serializer.toJson<DateTime>(createTime),
    };
  }

  SosRecord copyWith({
    int? id,
    String? latitude,
    String? longitude,
    String? status,
    DateTime? createTime,
  }) => SosRecord(
    id: id ?? this.id,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    status: status ?? this.status,
    createTime: createTime ?? this.createTime,
  );
  SosRecord copyWithCompanion(SosRecordsCompanion data) {
    return SosRecord(
      id: data.id.present ? data.id.value : this.id,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      status: data.status.present ? data.status.value : this.status,
      createTime: data.createTime.present
          ? data.createTime.value
          : this.createTime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SosRecord(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('status: $status, ')
          ..write('createTime: $createTime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, latitude, longitude, status, createTime);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SosRecord &&
          other.id == this.id &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.status == this.status &&
          other.createTime == this.createTime);
}

class SosRecordsCompanion extends UpdateCompanion<SosRecord> {
  final Value<int> id;
  final Value<String> latitude;
  final Value<String> longitude;
  final Value<String> status;
  final Value<DateTime> createTime;
  const SosRecordsCompanion({
    this.id = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.status = const Value.absent(),
    this.createTime = const Value.absent(),
  });
  SosRecordsCompanion.insert({
    this.id = const Value.absent(),
    required String latitude,
    required String longitude,
    this.status = const Value.absent(),
    this.createTime = const Value.absent(),
  }) : latitude = Value(latitude),
       longitude = Value(longitude);
  static Insertable<SosRecord> custom({
    Expression<int>? id,
    Expression<String>? latitude,
    Expression<String>? longitude,
    Expression<String>? status,
    Expression<DateTime>? createTime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (status != null) 'status': status,
      if (createTime != null) 'create_time': createTime,
    });
  }

  SosRecordsCompanion copyWith({
    Value<int>? id,
    Value<String>? latitude,
    Value<String>? longitude,
    Value<String>? status,
    Value<DateTime>? createTime,
  }) {
    return SosRecordsCompanion(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      createTime: createTime ?? this.createTime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<String>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<String>(longitude.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createTime.present) {
      map['create_time'] = Variable<DateTime>(createTime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SosRecordsCompanion(')
          ..write('id: $id, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('status: $status, ')
          ..write('createTime: $createTime')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SosRecordsTable sosRecords = $SosRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [sosRecords];
}

typedef $$SosRecordsTableCreateCompanionBuilder =
    SosRecordsCompanion Function({
      Value<int> id,
      required String latitude,
      required String longitude,
      Value<String> status,
      Value<DateTime> createTime,
    });
typedef $$SosRecordsTableUpdateCompanionBuilder =
    SosRecordsCompanion Function({
      Value<int> id,
      Value<String> latitude,
      Value<String> longitude,
      Value<String> status,
      Value<DateTime> createTime,
    });

class $$SosRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $SosRecordsTable> {
  $$SosRecordsTableFilterComposer({
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

  ColumnFilters<String> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createTime => $composableBuilder(
    column: $table.createTime,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SosRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $SosRecordsTable> {
  $$SosRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createTime => $composableBuilder(
    column: $table.createTime,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SosRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SosRecordsTable> {
  $$SosRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<String> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createTime => $composableBuilder(
    column: $table.createTime,
    builder: (column) => column,
  );
}

class $$SosRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SosRecordsTable,
          SosRecord,
          $$SosRecordsTableFilterComposer,
          $$SosRecordsTableOrderingComposer,
          $$SosRecordsTableAnnotationComposer,
          $$SosRecordsTableCreateCompanionBuilder,
          $$SosRecordsTableUpdateCompanionBuilder,
          (
            SosRecord,
            BaseReferences<_$AppDatabase, $SosRecordsTable, SosRecord>,
          ),
          SosRecord,
          PrefetchHooks Function()
        > {
  $$SosRecordsTableTableManager(_$AppDatabase db, $SosRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SosRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SosRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SosRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> latitude = const Value.absent(),
                Value<String> longitude = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createTime = const Value.absent(),
              }) => SosRecordsCompanion(
                id: id,
                latitude: latitude,
                longitude: longitude,
                status: status,
                createTime: createTime,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String latitude,
                required String longitude,
                Value<String> status = const Value.absent(),
                Value<DateTime> createTime = const Value.absent(),
              }) => SosRecordsCompanion.insert(
                id: id,
                latitude: latitude,
                longitude: longitude,
                status: status,
                createTime: createTime,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SosRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SosRecordsTable,
      SosRecord,
      $$SosRecordsTableFilterComposer,
      $$SosRecordsTableOrderingComposer,
      $$SosRecordsTableAnnotationComposer,
      $$SosRecordsTableCreateCompanionBuilder,
      $$SosRecordsTableUpdateCompanionBuilder,
      (SosRecord, BaseReferences<_$AppDatabase, $SosRecordsTable, SosRecord>),
      SosRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SosRecordsTableTableManager get sosRecords =>
      $$SosRecordsTableTableManager(_db, _db.sosRecords);
}
