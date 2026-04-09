import 'dart:typed_data';

import 'emergency_profile.dart';
import '../services/ble_mesh_exceptions.dart';

/// SOS 广告载荷 — 统一为 14 字节格式（与 BlePayloadEncoder 和扫描端一致）
///
/// 布局（不含 Company ID）：
///   [0]     uint8   — 协议版本（0x01）/ SOS 标志
///   [1]     uint8   — 血型代码
///   [2-5]   float32 — 纬度
///   [6-9]   float32 — 经度
///   [10-13] uint32  — Unix 时间戳（秒）
///
/// 加上 Company ID (2字节) 后总长度为 16 字节（rawManufacturerData）
class SosAdvertisementPayload {
  const SosAdvertisementPayload({
    required this.companyId,
    required this.longitude,
    required this.latitude,
    required this.bloodType,
    required this.sosFlag,
    this.timestamp,
  });

  final int companyId;
  final double longitude;
  final double latitude;
  final BloodType bloodType;
  final bool sosFlag;
  final DateTime? timestamp;

  static const int protocolVersion = 0x01;

  /// 制造商载荷（14 字节，不含 Company ID）
  List<int> get manufacturerPayload {
    _validate();
    final data = ByteData(14);
    data.setUint8(0, sosFlag ? protocolVersion : 0);
    data.setUint8(1, bloodType.code);
    data.setFloat32(2, latitude, Endian.little);
    data.setFloat32(6, longitude, Endian.little);
    final ts =
        (timestamp ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    data.setUint32(10, ts, Endian.little);
    return data.buffer.asUint8List();
  }

  /// 完整制造商数据（含 Company ID，共 16 字节）
  List<int> get rawManufacturerData {
    final data = ByteData(16);
    data.setUint16(0, companyId, Endian.little);
    final payload = manufacturerPayload;
    for (var i = 0; i < payload.length; i++) {
      data.setUint8(i + 2, payload[i]);
    }
    return data.buffer.asUint8List();
  }

  void _validate() {
    if (companyId < 0 || companyId > 0xFFFF) {
      throw const BleMeshInvalidPayloadException('公司 ID 必须落在 2 字节范围内。');
    }
    if (latitude < -90 || latitude > 90) {
      throw const BleMeshInvalidPayloadException('纬度必须位于 -90 到 90 之间。');
    }
    if (longitude < -180 || longitude > 180) {
      throw const BleMeshInvalidPayloadException('经度必须位于 -180 到 180 之间。');
    }
  }
}
