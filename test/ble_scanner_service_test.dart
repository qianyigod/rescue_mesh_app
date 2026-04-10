import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_network/services/ble_scanner_service.dart';

void main() {
  group('BleScannerService.decodeSosPayload', () {
    test('decodes float32 payload', () {
      final byteData = ByteData(10);
      byteData.setUint8(0, 1);
      byteData.setFloat32(1, 31.2304, Endian.little);
      byteData.setFloat32(5, 121.4737, Endian.little);
      byteData.setUint8(9, 4);

      final service = BleScannerService();
      final message = service.decodeSosPayload(
        byteData.buffer.asUint8List(),
        remoteId: 'device-a',
        rssi: -55,
      );

      expect(message.sosFlag, isTrue);
      expect(message.latitude, closeTo(31.2304, 0.0001));
      expect(message.longitude, closeTo(121.4737, 0.0001));
      expect(message.bloodTypeCode, 4);
      expect(message.remoteId, 'device-a');
    });

    test('falls back to int32 micro-degree payload', () {
      final byteData = ByteData(10);
      byteData.setUint8(0, 1);
      byteData.setInt32(1, 31230400, Endian.little);
      byteData.setInt32(5, 121473700, Endian.little);
      byteData.setUint8(9, 4);

      final service = BleScannerService();
      final message = service.decodeSosPayload(
        byteData.buffer.asUint8List(),
        remoteId: 'device-b',
        rssi: -48,
      );

      expect(message.latitude, closeTo(31.2304, 0.000001));
      expect(message.longitude, closeTo(121.4737, 0.000001));
      expect(message.bloodTypeCode, 4);
    });
  });
}
