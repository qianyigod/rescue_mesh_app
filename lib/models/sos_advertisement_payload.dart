import 'dart:typed_data';

import 'emergency_profile.dart';
import '../services/ble_mesh_exceptions.dart';

class SosAdvertisementPayload {
  const SosAdvertisementPayload({
    required this.companyId,
    required this.longitude,
    required this.latitude,
    required this.bloodType,
    required this.sosFlag,
  });

  final int companyId;
  final double longitude;
  final double latitude;
  final BloodType bloodType;
  final bool sosFlag;

  List<int> get manufacturerPayload {
    _validate();
    final data = ByteData(10);
    data.setUint8(0, sosFlag ? 1 : 0);
    data.setInt32(1, _encodeCoordinate(latitude), Endian.little);
    data.setInt32(5, _encodeCoordinate(longitude), Endian.little);
    data.setUint8(9, bloodType.code);
    return data.buffer.asUint8List();
  }

  List<int> get rawManufacturerData {
    final data = ByteData(12);
    data.setUint16(0, companyId, Endian.little);
    final payload = manufacturerPayload;
    for (var i = 0; i < payload.length; i++) {
      data.setUint8(i + 2, payload[i]);
    }
    return data.buffer.asUint8List();
  }

  static int _encodeCoordinate(double value) {
    return (value * 1000000).round();
  }

  void _validate() {
    if (companyId < 0 || companyId > 0xFFFF) {
      throw const BleMeshInvalidPayloadException(
        '公司 ID 必须落在 2 字节范围内。',
      );
    }
    if (latitude < -90 || latitude > 90) {
      throw const BleMeshInvalidPayloadException(
        '纬度必须位于 -90 到 90 之间。',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw const BleMeshInvalidPayloadException(
        '经度必须位于 -180 到 180 之间。',
      );
    }
  }
}
