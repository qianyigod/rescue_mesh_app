import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_network/services/ble_payload_encoder.dart';

void main() {
  group('BlePayloadEncoder', () {
    test('encodes SOS data into the 14-byte payload layout', () {
      final time = DateTime.utc(2026, 3, 26, 12, 34, 56);

      final payload = BlePayloadEncoder.encodeSosData(
        lat: 31.2304,
        lon: 121.4737,
        bloodType: 4,
        time: time,
      );

      final byteData = ByteData.view(Uint8List.fromList(payload).buffer);

      expect(payload, hasLength(BlePayloadEncoder.payloadLength));
      expect(byteData.getUint8(0), BlePayloadEncoder.protocolVersion);
      expect(byteData.getUint8(1), 4);
      expect(byteData.getFloat32(2, Endian.little), closeTo(31.2304, 0.0001));
      expect(byteData.getFloat32(6, Endian.little), closeTo(121.4737, 0.0001));
      expect(
        byteData.getUint32(10, Endian.little),
        time.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('decodes SOS data from the 14-byte payload layout', () {
      final time = DateTime.utc(2026, 3, 26, 12, 34, 56);

      final payload = BlePayloadEncoder.encodeSosData(
        lat: 31.2304,
        lon: 121.4737,
        bloodType: 4,
        time: time,
      );

      final decoded = BlePayloadEncoder.decodeSosData(payload);

      expect(decoded, isNotNull);
      expect(decoded!.protocolVersion, BlePayloadEncoder.protocolVersion);
      expect(decoded.bloodType, 4);
      expect(decoded.latitude, closeTo(31.2304, 0.0001));
      expect(decoded.longitude, closeTo(121.4737, 0.0001));
      expect(decoded.timestamp, time.millisecondsSinceEpoch ~/ 1000);
      expect(decoded.time, time);
    });

    test('throws when payload length is not 14 bytes', () {
      expect(
        () => BlePayloadEncoder.decodeSosData(const <int>[1, 2, 3]),
        throwsA(isA<FormatException>()),
      );
    });

    test('returns null when protocol version does not match', () {
      final byteData = ByteData(BlePayloadEncoder.payloadLength);
      byteData.setUint8(0, 0x02);
      byteData.setUint8(1, 4);
      byteData.setFloat32(2, 31.2304, Endian.little);
      byteData.setFloat32(6, 121.4737, Endian.little);
      byteData.setUint32(10, 1, Endian.little);

      final decoded = BlePayloadEncoder.decodeSosData(
        byteData.buffer.asUint8List(),
      );

      expect(decoded, isNull);
    });
  });
}
