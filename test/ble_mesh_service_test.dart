import 'package:flutter_test/flutter_test.dart';
import 'package:life_network/models/sos_message.dart';
import 'package:life_network/services/ble_mesh_service.dart';

void main() {
  group('BleMeshService relay queue', () {
    test('deduplicates identical payloads from different relays', () {
      final service = BleMeshService();
      final messageA = SosMessage(
        companyId: 0xFFFF,
        remoteId: 'relay-a',
        deviceName: 'Relay A',
        sosFlag: true,
        latitude: 30.0,
        longitude: 120.0,
        bloodTypeCode: 1,
        rssi: -70,
        receivedAt: DateTime.utc(2026, 4, 9, 12, 0, 0),
        rawPayload: const [1, 0x81, 1, 2, 3, 4, 5, 6],
      );
      final messageB = SosMessage(
        companyId: 0xFFFF,
        remoteId: 'relay-b',
        deviceName: 'Relay B',
        sosFlag: true,
        latitude: 30.0,
        longitude: 120.0,
        bloodTypeCode: 1,
        rssi: -62,
        receivedAt: DateTime.utc(2026, 4, 9, 12, 0, 2),
        rawPayload: const [1, 0x81, 1, 2, 3, 4, 5, 6],
      );

      service.addRelayMessage(messageA);
      service.addRelayMessage(messageB);

      expect(service.queueLength, 1);
    });

    test('caps realtime relay queue size', () {
      final service = BleMeshService();

      for (var i = 0; i < 20; i++) {
        service.addRelayMessage(
          SosMessage(
            companyId: 0xFFFF,
            remoteId: 'relay-$i',
            deviceName: 'Relay $i',
            sosFlag: true,
            latitude: 30.0 + i,
            longitude: 120.0 + i,
            bloodTypeCode: i % 4,
            rssi: -80 + i,
            receivedAt: DateTime.utc(2026, 4, 9, 12, 0, i),
            rawPayload: [1, 0x81, i, i + 1, i + 2, i + 3, i + 4, i + 5],
          ),
        );
      }

      expect(service.queueLength, lessThanOrEqualTo(15));
    });
  });
}
