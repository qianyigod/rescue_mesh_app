import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_mesh_app/models/emergency_profile.dart';
import 'package:rescue_mesh_app/models/sos_advertisement_payload.dart';

void main() {
  test(
    'SOS manufacturer data encodes company id, flag, lat, lon, and blood type (14-byte payload)',
    () {
      const payload = SosAdvertisementPayload(
        companyId: 0xFFFF,
        longitude: 121.4737,
        latitude: 31.2304,
        bloodType: BloodType.o,
        sosFlag: true,
      );

      // 完整制造商数据：2 字节 Company ID + 14 字节载荷 = 16 字节
      expect(payload.rawManufacturerData.length, 16);
      expect(payload.rawManufacturerData[0], 0xFF);
      expect(payload.rawManufacturerData[1], 0xFF);

      // 制造商载荷（不含 Company ID）：14 字节
      expect(payload.manufacturerPayload.length, 14);
      expect(payload.manufacturerPayload[0], 0x01); // 协议版本 + SOS 标志
      expect(payload.manufacturerPayload[1], BloodType.o.code);

      // 验证坐标编码（float32）
      final byteData = ByteData.sublistView(
        Uint8List.fromList(payload.manufacturerPayload),
      );
      final latitude = byteData.getFloat32(2, Endian.little);
      final longitude = byteData.getFloat32(6, Endian.little);
      expect(latitude, closeTo(31.2304, 0.0001));
      expect(longitude, closeTo(121.4737, 0.0001));
    },
  );

  test('SOS flag off uses protocol version 0', () {
    const payload = SosAdvertisementPayload(
      companyId: 0xFFFF,
      longitude: 121.4737,
      latitude: 31.2304,
      bloodType: BloodType.a,
      sosFlag: false,
    );

    expect(payload.manufacturerPayload[0], 0); // SOS 关闭
  });
}
