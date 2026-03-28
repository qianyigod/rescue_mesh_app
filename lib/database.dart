import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models/sos_message.dart';

part 'database.g.dart';

class SosRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get latitude => text()();
  TextColumn get longitude => text()();
  TextColumn get status => text().withDefault(const Constant('准备广播'))();
  DateTimeColumn get createTime => dateTime().withDefault(currentDateAndTime)();
}

class MedicalProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get age => text().withDefault(const Constant(''))();
  IntColumn get bloodType => integer().withDefault(const Constant(-1))();
  TextColumn get medicalHistory => text().withDefault(const Constant(''))();
  TextColumn get allergies => text().withDefault(const Constant(''))();
  TextColumn get emergencyContact => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class SosMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get senderMac => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get bloodType => integer()();
  DateTimeColumn get timestamp => dateTime()();
  BoolColumn get isUploaded => boolean().withDefault(const Constant(false))();
}

class StoredSosMessage {
  const StoredSosMessage({
    required this.id,
    required this.senderMac,
    required this.latitude,
    required this.longitude,
    required this.bloodType,
    required this.timestamp,
    required this.isUploaded,
  });

  final int id;
  final String senderMac;
  final double latitude;
  final double longitude;
  final int bloodType;
  final DateTime timestamp;
  final bool isUploaded;
}

@DriftDatabase(tables: [SosRecords, MedicalProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  static const String _sosMessagesTableName = 'sos_messages';
  static const Duration _dedupeWindow = Duration(minutes: 5);
  final StreamController<List<StoredSosMessage>> _storedMessagesController =
      StreamController<List<StoredSosMessage>>.broadcast();

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createSosMessagesTable();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _createSosMessagesTable();
      }
      if (from < 3) {
        await m.create(medicalProfiles);
      }
    },
    beforeOpen: (details) async {
      await _createSosMessagesTable();
    },
  );

  Future<int> addRecord(SosRecordsCompanion entry) {
    return into(sosRecords).insert(entry);
  }

  Future<List<SosRecord>> getAllRecords() {
    return select(sosRecords).get();
  }

  // Medical Profile methods
  Future<int> saveMedicalProfile({
    required String name,
    required String age,
    required int bloodType,
    required String medicalHistory,
    required String allergies,
    required String emergencyContact,
  }) async {
    final existing = await getAllMedicalProfiles();
    if (existing.isNotEmpty) {
      final id = existing.first.id;
      await update(medicalProfiles).write(
        MedicalProfilesCompanion(
          id: Value(id),
          name: Value(name),
          age: Value(age),
          bloodType: Value(bloodType),
          medicalHistory: Value(medicalHistory),
          allergies: Value(allergies),
          emergencyContact: Value(emergencyContact),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return id;
    } else {
      return into(medicalProfiles).insert(
        MedicalProfilesCompanion.insert(
          name: Value(name),
          age: Value(age),
          bloodType: Value(bloodType),
          medicalHistory: Value(medicalHistory),
          allergies: Value(allergies),
          emergencyContact: Value(emergencyContact),
        ),
      );
    }
  }

  Future<List<MedicalProfileData>> getAllMedicalProfiles() async {
    final query = select(medicalProfiles);
    query.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => MedicalProfileData(
            id: row.id,
            name: row.name,
            age: row.age,
            bloodType: row.bloodType,
            medicalHistory: row.medicalHistory,
            allergies: row.allergies,
            emergencyContact: row.emergencyContact,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  Future<MedicalProfileData?> getCurrentMedicalProfile() async {
    final profiles = await getAllMedicalProfiles();
    return profiles.isNotEmpty ? profiles.first : null;
  }

  Future<int> saveIncomingSos(SosMessage message) async {
    final threshold = message.receivedAt.subtract(_dedupeWindow);
    final existing = await customSelect(
      '''
      SELECT id, sender_mac, latitude, longitude, blood_type, timestamp, is_uploaded
      FROM $_sosMessagesTableName
      WHERE sender_mac = ? AND timestamp >= ?
      ORDER BY timestamp DESC
      LIMIT 1
      ''',
      variables: [
        Variable<String>(message.remoteId),
        Variable<DateTime>(threshold),
      ],
      readsFrom: const {},
    ).getSingleOrNull();

    if (existing != null) {
      final existingId = existing.read<int>('id');
      await customUpdate(
        '''
        UPDATE $_sosMessagesTableName
        SET latitude = ?, longitude = ?, blood_type = ?, timestamp = ?, is_uploaded = 0
        WHERE id = ?
        ''',
        variables: [
          Variable<double>(message.latitude),
          Variable<double>(message.longitude),
          Variable<int>(message.bloodTypeCode),
          Variable<DateTime>(message.receivedAt),
          Variable<int>(existingId),
        ],
        updates: const {},
      );
      unawaited(_notifyStoredMessagesChanged());
      return existingId;
    }

    await customInsert(
      '''
      INSERT INTO $_sosMessagesTableName
        (sender_mac, latitude, longitude, blood_type, timestamp, is_uploaded)
      VALUES (?, ?, ?, ?, ?, 0)
      ''',
      variables: [
        Variable<String>(message.remoteId),
        Variable<double>(message.latitude),
        Variable<double>(message.longitude),
        Variable<int>(message.bloodTypeCode),
        Variable<DateTime>(message.receivedAt),
      ],
      updates: const {},
    );

    final inserted = await customSelect(
      'SELECT last_insert_rowid() AS id',
      readsFrom: const {},
    ).getSingle();
    unawaited(_notifyStoredMessagesChanged());
    return inserted.read<int>('id');
  }

  Future<List<StoredSosMessage>> getAllStoredSosMessages() async {
    final rows = await customSelect('''
      SELECT id, sender_mac, latitude, longitude, blood_type, timestamp, is_uploaded
      FROM $_sosMessagesTableName
      ORDER BY timestamp DESC
      ''', readsFrom: const {}).get();

    return rows.map(_mapStoredSosMessage).toList(growable: false);
  }

  Stream<List<StoredSosMessage>> watchStoredSosMessages() async* {
    yield await getAllStoredSosMessages();
    yield* _storedMessagesController.stream;
  }

  Future<List<StoredSosMessage>> getPendingUploads() async {
    final rows = await customSelect('''
      SELECT id, sender_mac, latitude, longitude, blood_type, timestamp, is_uploaded
      FROM $_sosMessagesTableName
      WHERE is_uploaded = 0
      ORDER BY timestamp ASC
      ''', readsFrom: const {}).get();

    return rows.map(_mapStoredSosMessage).toList(growable: false);
  }

  Future<void> markAsUploaded(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final placeholders = List.filled(ids.length, '?').join(', ');
    await customUpdate(
      '''
      UPDATE $_sosMessagesTableName
      SET is_uploaded = 1
      WHERE id IN ($placeholders)
      ''',
      variables: ids.map((id) => Variable<int>(id)).toList(growable: false),
      updates: const {},
    );
    unawaited(_notifyStoredMessagesChanged());
  }

  Future<void> _createSosMessagesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS $_sosMessagesTableName (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        sender_mac TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        blood_type INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        is_uploaded INTEGER NOT NULL DEFAULT 0
      )
      ''');
  }

  StoredSosMessage _mapStoredSosMessage(QueryRow row) {
    return StoredSosMessage(
      id: row.read<int>('id'),
      senderMac: row.read<String>('sender_mac'),
      latitude: row.read<double>('latitude'),
      longitude: row.read<double>('longitude'),
      bloodType: row.read<int>('blood_type'),
      timestamp: row.read<DateTime>('timestamp'),
      isUploaded: row.read<bool>('is_uploaded'),
    );
  }

  Future<void> _notifyStoredMessagesChanged() async {
    if (_storedMessagesController.isClosed) {
      return;
    }
    final records = await getAllStoredSosMessages();
    _storedMessagesController.add(records);
  }

  @override
  Future<void> close() async {
    await _storedMessagesController.close();
    await super.close();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'mesh_rescue.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final appDb = AppDatabase();

/// Medical Profile Data class
class MedicalProfileData {
  const MedicalProfileData({
    required this.id,
    required this.name,
    required this.age,
    required this.bloodType,
    required this.medicalHistory,
    required this.allergies,
    required this.emergencyContact,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String age;
  final int bloodType;
  final String medicalHistory;
  final String allergies;
  final String emergencyContact;
  final DateTime updatedAt;
}
