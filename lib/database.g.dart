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

class $MedicalProfilesTable extends MedicalProfiles
    with TableInfo<$MedicalProfilesTable, MedicalProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MedicalProfilesTable(this.attachedDatabase, [this._alias]);
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
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ageMeta = const VerificationMeta('age');
  @override
  late final GeneratedColumn<String> age = GeneratedColumn<String>(
    'age',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bloodTypeMeta = const VerificationMeta(
    'bloodType',
  );
  @override
  late final GeneratedColumn<int> bloodType = GeneratedColumn<int>(
    'blood_type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _medicalHistoryMeta = const VerificationMeta(
    'medicalHistory',
  );
  @override
  late final GeneratedColumn<String> medicalHistory = GeneratedColumn<String>(
    'medical_history',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _allergiesMeta = const VerificationMeta(
    'allergies',
  );
  @override
  late final GeneratedColumn<String> allergies = GeneratedColumn<String>(
    'allergies',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _emergencyContactMeta = const VerificationMeta(
    'emergencyContact',
  );
  @override
  late final GeneratedColumn<String> emergencyContact = GeneratedColumn<String>(
    'emergency_contact',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    age,
    bloodType,
    medicalHistory,
    allergies,
    emergencyContact,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'medical_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<MedicalProfile> instance, {
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
    }
    if (data.containsKey('age')) {
      context.handle(
        _ageMeta,
        age.isAcceptableOrUnknown(data['age']!, _ageMeta),
      );
    }
    if (data.containsKey('blood_type')) {
      context.handle(
        _bloodTypeMeta,
        bloodType.isAcceptableOrUnknown(data['blood_type']!, _bloodTypeMeta),
      );
    }
    if (data.containsKey('medical_history')) {
      context.handle(
        _medicalHistoryMeta,
        medicalHistory.isAcceptableOrUnknown(
          data['medical_history']!,
          _medicalHistoryMeta,
        ),
      );
    }
    if (data.containsKey('allergies')) {
      context.handle(
        _allergiesMeta,
        allergies.isAcceptableOrUnknown(data['allergies']!, _allergiesMeta),
      );
    }
    if (data.containsKey('emergency_contact')) {
      context.handle(
        _emergencyContactMeta,
        emergencyContact.isAcceptableOrUnknown(
          data['emergency_contact']!,
          _emergencyContactMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MedicalProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MedicalProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      age: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age'],
      )!,
      bloodType: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}blood_type'],
      )!,
      medicalHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}medical_history'],
      )!,
      allergies: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}allergies'],
      )!,
      emergencyContact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emergency_contact'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MedicalProfilesTable createAlias(String alias) {
    return $MedicalProfilesTable(attachedDatabase, alias);
  }
}

class MedicalProfile extends DataClass implements Insertable<MedicalProfile> {
  final int id;
  final String name;
  final String age;
  final int bloodType;
  final String medicalHistory;
  final String allergies;
  final String emergencyContact;
  final DateTime updatedAt;
  const MedicalProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.bloodType,
    required this.medicalHistory,
    required this.allergies,
    required this.emergencyContact,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['age'] = Variable<String>(age);
    map['blood_type'] = Variable<int>(bloodType);
    map['medical_history'] = Variable<String>(medicalHistory);
    map['allergies'] = Variable<String>(allergies);
    map['emergency_contact'] = Variable<String>(emergencyContact);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MedicalProfilesCompanion toCompanion(bool nullToAbsent) {
    return MedicalProfilesCompanion(
      id: Value(id),
      name: Value(name),
      age: Value(age),
      bloodType: Value(bloodType),
      medicalHistory: Value(medicalHistory),
      allergies: Value(allergies),
      emergencyContact: Value(emergencyContact),
      updatedAt: Value(updatedAt),
    );
  }

  factory MedicalProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MedicalProfile(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      age: serializer.fromJson<String>(json['age']),
      bloodType: serializer.fromJson<int>(json['bloodType']),
      medicalHistory: serializer.fromJson<String>(json['medicalHistory']),
      allergies: serializer.fromJson<String>(json['allergies']),
      emergencyContact: serializer.fromJson<String>(json['emergencyContact']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'age': serializer.toJson<String>(age),
      'bloodType': serializer.toJson<int>(bloodType),
      'medicalHistory': serializer.toJson<String>(medicalHistory),
      'allergies': serializer.toJson<String>(allergies),
      'emergencyContact': serializer.toJson<String>(emergencyContact),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MedicalProfile copyWith({
    int? id,
    String? name,
    String? age,
    int? bloodType,
    String? medicalHistory,
    String? allergies,
    String? emergencyContact,
    DateTime? updatedAt,
  }) => MedicalProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    age: age ?? this.age,
    bloodType: bloodType ?? this.bloodType,
    medicalHistory: medicalHistory ?? this.medicalHistory,
    allergies: allergies ?? this.allergies,
    emergencyContact: emergencyContact ?? this.emergencyContact,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MedicalProfile copyWithCompanion(MedicalProfilesCompanion data) {
    return MedicalProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      age: data.age.present ? data.age.value : this.age,
      bloodType: data.bloodType.present ? data.bloodType.value : this.bloodType,
      medicalHistory: data.medicalHistory.present
          ? data.medicalHistory.value
          : this.medicalHistory,
      allergies: data.allergies.present ? data.allergies.value : this.allergies,
      emergencyContact: data.emergencyContact.present
          ? data.emergencyContact.value
          : this.emergencyContact,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MedicalProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('age: $age, ')
          ..write('bloodType: $bloodType, ')
          ..write('medicalHistory: $medicalHistory, ')
          ..write('allergies: $allergies, ')
          ..write('emergencyContact: $emergencyContact, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    age,
    bloodType,
    medicalHistory,
    allergies,
    emergencyContact,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MedicalProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.age == this.age &&
          other.bloodType == this.bloodType &&
          other.medicalHistory == this.medicalHistory &&
          other.allergies == this.allergies &&
          other.emergencyContact == this.emergencyContact &&
          other.updatedAt == this.updatedAt);
}

class MedicalProfilesCompanion extends UpdateCompanion<MedicalProfile> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> age;
  final Value<int> bloodType;
  final Value<String> medicalHistory;
  final Value<String> allergies;
  final Value<String> emergencyContact;
  final Value<DateTime> updatedAt;
  const MedicalProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.age = const Value.absent(),
    this.bloodType = const Value.absent(),
    this.medicalHistory = const Value.absent(),
    this.allergies = const Value.absent(),
    this.emergencyContact = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MedicalProfilesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.age = const Value.absent(),
    this.bloodType = const Value.absent(),
    this.medicalHistory = const Value.absent(),
    this.allergies = const Value.absent(),
    this.emergencyContact = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<MedicalProfile> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? age,
    Expression<int>? bloodType,
    Expression<String>? medicalHistory,
    Expression<String>? allergies,
    Expression<String>? emergencyContact,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (age != null) 'age': age,
      if (bloodType != null) 'blood_type': bloodType,
      if (medicalHistory != null) 'medical_history': medicalHistory,
      if (allergies != null) 'allergies': allergies,
      if (emergencyContact != null) 'emergency_contact': emergencyContact,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  MedicalProfilesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? age,
    Value<int>? bloodType,
    Value<String>? medicalHistory,
    Value<String>? allergies,
    Value<String>? emergencyContact,
    Value<DateTime>? updatedAt,
  }) {
    return MedicalProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      bloodType: bloodType ?? this.bloodType,
      medicalHistory: medicalHistory ?? this.medicalHistory,
      allergies: allergies ?? this.allergies,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (age.present) {
      map['age'] = Variable<String>(age.value);
    }
    if (bloodType.present) {
      map['blood_type'] = Variable<int>(bloodType.value);
    }
    if (medicalHistory.present) {
      map['medical_history'] = Variable<String>(medicalHistory.value);
    }
    if (allergies.present) {
      map['allergies'] = Variable<String>(allergies.value);
    }
    if (emergencyContact.present) {
      map['emergency_contact'] = Variable<String>(emergencyContact.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MedicalProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('age: $age, ')
          ..write('bloodType: $bloodType, ')
          ..write('medicalHistory: $medicalHistory, ')
          ..write('allergies: $allergies, ')
          ..write('emergencyContact: $emergencyContact, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SosRecordsTable sosRecords = $SosRecordsTable(this);
  late final $MedicalProfilesTable medicalProfiles = $MedicalProfilesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sosRecords,
    medicalProfiles,
  ];
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
typedef $$MedicalProfilesTableCreateCompanionBuilder =
    MedicalProfilesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> age,
      Value<int> bloodType,
      Value<String> medicalHistory,
      Value<String> allergies,
      Value<String> emergencyContact,
      Value<DateTime> updatedAt,
    });
typedef $$MedicalProfilesTableUpdateCompanionBuilder =
    MedicalProfilesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> age,
      Value<int> bloodType,
      Value<String> medicalHistory,
      Value<String> allergies,
      Value<String> emergencyContact,
      Value<DateTime> updatedAt,
    });

class $$MedicalProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $MedicalProfilesTable> {
  $$MedicalProfilesTableFilterComposer({
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

  ColumnFilters<String> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bloodType => $composableBuilder(
    column: $table.bloodType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get medicalHistory => $composableBuilder(
    column: $table.medicalHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get allergies => $composableBuilder(
    column: $table.allergies,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MedicalProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $MedicalProfilesTable> {
  $$MedicalProfilesTableOrderingComposer({
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

  ColumnOrderings<String> get age => $composableBuilder(
    column: $table.age,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bloodType => $composableBuilder(
    column: $table.bloodType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get medicalHistory => $composableBuilder(
    column: $table.medicalHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get allergies => $composableBuilder(
    column: $table.allergies,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MedicalProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MedicalProfilesTable> {
  $$MedicalProfilesTableAnnotationComposer({
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

  GeneratedColumn<String> get age =>
      $composableBuilder(column: $table.age, builder: (column) => column);

  GeneratedColumn<int> get bloodType =>
      $composableBuilder(column: $table.bloodType, builder: (column) => column);

  GeneratedColumn<String> get medicalHistory => $composableBuilder(
    column: $table.medicalHistory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get allergies =>
      $composableBuilder(column: $table.allergies, builder: (column) => column);

  GeneratedColumn<String> get emergencyContact => $composableBuilder(
    column: $table.emergencyContact,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MedicalProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MedicalProfilesTable,
          MedicalProfile,
          $$MedicalProfilesTableFilterComposer,
          $$MedicalProfilesTableOrderingComposer,
          $$MedicalProfilesTableAnnotationComposer,
          $$MedicalProfilesTableCreateCompanionBuilder,
          $$MedicalProfilesTableUpdateCompanionBuilder,
          (
            MedicalProfile,
            BaseReferences<
              _$AppDatabase,
              $MedicalProfilesTable,
              MedicalProfile
            >,
          ),
          MedicalProfile,
          PrefetchHooks Function()
        > {
  $$MedicalProfilesTableTableManager(
    _$AppDatabase db,
    $MedicalProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MedicalProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MedicalProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MedicalProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> age = const Value.absent(),
                Value<int> bloodType = const Value.absent(),
                Value<String> medicalHistory = const Value.absent(),
                Value<String> allergies = const Value.absent(),
                Value<String> emergencyContact = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => MedicalProfilesCompanion(
                id: id,
                name: name,
                age: age,
                bloodType: bloodType,
                medicalHistory: medicalHistory,
                allergies: allergies,
                emergencyContact: emergencyContact,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> age = const Value.absent(),
                Value<int> bloodType = const Value.absent(),
                Value<String> medicalHistory = const Value.absent(),
                Value<String> allergies = const Value.absent(),
                Value<String> emergencyContact = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => MedicalProfilesCompanion.insert(
                id: id,
                name: name,
                age: age,
                bloodType: bloodType,
                medicalHistory: medicalHistory,
                allergies: allergies,
                emergencyContact: emergencyContact,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MedicalProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MedicalProfilesTable,
      MedicalProfile,
      $$MedicalProfilesTableFilterComposer,
      $$MedicalProfilesTableOrderingComposer,
      $$MedicalProfilesTableAnnotationComposer,
      $$MedicalProfilesTableCreateCompanionBuilder,
      $$MedicalProfilesTableUpdateCompanionBuilder,
      (
        MedicalProfile,
        BaseReferences<_$AppDatabase, $MedicalProfilesTable, MedicalProfile>,
      ),
      MedicalProfile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SosRecordsTableTableManager get sosRecords =>
      $$SosRecordsTableTableManager(_db, _db.sosRecords);
  $$MedicalProfilesTableTableManager get medicalProfiles =>
      $$MedicalProfilesTableTableManager(_db, _db.medicalProfiles);
}
