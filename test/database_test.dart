import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_network/database.dart';
import 'package:life_network/models/sos_message.dart';

void main() {
  group('AppDatabase SOS storage', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('saveIncomingSos deduplicates same sender within 5 minutes', () async {
      final first = SosMessage(
        companyId: 0xFFFF,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'rescuer',
        sosFlag: true,
        latitude: 31.2304,
        longitude: 121.4737,
        bloodTypeCode: 4,
        rssi: -60,
        receivedAt: DateTime(2026, 3, 20, 10, 0, 0),
        rawPayload: const [1, 0, 0, 0, 0, 0, 0, 0, 0, 4],
      );
      final second = SosMessage(
        companyId: 0xFFFF,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'rescuer',
        sosFlag: true,
        latitude: 31.2310,
        longitude: 121.4740,
        bloodTypeCode: 3,
        rssi: -58,
        receivedAt: DateTime(2026, 3, 20, 10, 3, 0),
        rawPayload: const [1, 0, 0, 0, 0, 0, 0, 0, 0, 3],
      );

      final firstId = await database.saveIncomingSos(first);
      final secondId = await database.saveIncomingSos(second);

      final pending = await database.getPendingUploads();
      expect(firstId, secondId);
      expect(pending.length, 1);
      expect(pending.single.latitude, 31.2310);
      expect(pending.single.longitude, 121.4740);
      expect(pending.single.bloodType, 3);
    });

    test('markAsUploaded updates pending records', () async {
      final message = SosMessage(
        companyId: 0xFFFF,
        remoteId: '11:22:33:44:55:66',
        deviceName: 'sender',
        sosFlag: true,
        latitude: 30.0,
        longitude: 120.0,
        bloodTypeCode: 1,
        rssi: -50,
        receivedAt: DateTime(2026, 3, 20, 12, 0, 0),
        rawPayload: const [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
      );

      final id = await database.saveIncomingSos(message);
      expect((await database.getPendingUploads()).length, 1);

      await database.markAsUploaded([id]);

      expect(await database.getPendingUploads(), isEmpty);
    });
  });
}
