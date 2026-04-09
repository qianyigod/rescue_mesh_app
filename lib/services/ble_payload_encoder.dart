import 'dart:typed_data';

import '../models/sos_payload.dart';

class BlePayloadEncoder {
  BlePayloadEncoder._();

  static const int protocolVersion = 0x01;
  static const int payloadLength = 14; // 标准格式
  static const int compactPayloadLength = 8; // 紧凑格式（用于远距离传输）
  static const Endian byteOrder = Endian.little;

  // 紧凑格式坐标缩放因子
  // 纬度: -90~90 → int16 (-32768~32767), 精度 ~0.0027° ≈ 300m
  // 经度: -180~180 → int16 (-32768~32767), 精度 ~0.0055° ≈ 550m
  static const double _latScale = 32767.0 / 90.0;
  static const double _lonScale = 32767.0 / 180.0;

  static List<int> encodeSosData({
    required double lat,
    required double lon,
    required int bloodType,
    required DateTime time,
  }) {
    _validateCoordinate(lat, isLatitude: true);
    _validateCoordinate(lon, isLatitude: false);

    if (bloodType < 0 || bloodType > 0xFF) {
      throw RangeError.range(bloodType, 0, 0xFF, 'bloodType');
    }

    final timestamp = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (timestamp < 0 || timestamp > 0xFFFFFFFF) {
      throw RangeError.range(timestamp, 0, 0xFFFFFFFF, 'time');
    }

    final byteData = ByteData(payloadLength);
    byteData.setUint8(0, protocolVersion);
    byteData.setUint8(1, bloodType);
    byteData.setFloat32(2, lat, byteOrder);
    byteData.setFloat32(6, lon, byteOrder);
    byteData.setUint32(10, timestamp, byteOrder);

    return byteData.buffer.asUint8List();
  }

  static SosPayload? decodeSosData(List<int> rawBytes) {
    if (rawBytes.length != payloadLength) {
      throw FormatException(
        'Invalid BLE SOS payload length: expected $payloadLength bytes, got '
        '${rawBytes.length}.',
      );
    }

    final bytes = Uint8List.fromList(rawBytes);
    final byteData = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final version = byteData.getUint8(0);
    if (version != protocolVersion) {
      return null;
    }

    final bloodType = byteData.getUint8(1);
    final latitude = byteData.getFloat32(2, byteOrder);
    final longitude = byteData.getFloat32(6, byteOrder);
    final timestamp = byteData.getUint32(10, byteOrder);

    _validateCoordinate(latitude, isLatitude: true);
    _validateCoordinate(longitude, isLatitude: false);

    return SosPayload(
      protocolVersion: version,
      bloodType: bloodType,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
    );
  }

  static void _validateCoordinate(double value, {required bool isLatitude}) {
    if (!value.isFinite) {
      throw FormatException(
        isLatitude ? 'Latitude is not finite.' : 'Longitude is not finite.',
      );
    }

    final isValid = isLatitude
        ? value >= -90.0 && value <= 90.0
        : value >= -180.0 && value <= 180.0;
    if (!isValid) {
      throw RangeError.value(
        value,
        isLatitude ? 'lat' : 'lon',
        isLatitude
            ? 'Latitude must be between -90 and 90 degrees.'
            : 'Longitude must be between -180 and 180 degrees.',
      );
    }
  }

  // ===== 紧凑格式编解码 (8字节) =====
  // 格式: [version(1)][flags(1)][lat_int16(2)][lon_int16(2)][timestamp_u16(2)]
  // 总长度: 8字节（比标准格式减少43%）

  static List<int> encodeCompactSosData({
    required double lat,
    required double lon,
    required int bloodType,
    required DateTime time,
    int sosFlag = 1,
  }) {
    _validateCoordinate(lat, isLatitude: true);
    _validateCoordinate(lon, isLatitude: false);

    // 将浮点坐标压缩为 int16
    final latInt = (lat * _latScale).clamp(-32768, 32767).toInt();
    final lonInt = (lon * _lonScale).clamp(-32768, 32767).toInt();

    // 时间戳压缩为相对值（相对于2024-01-01的秒数，uint16最大65535秒≈18小时）
    final baseTime = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch ~/ 1000;
    final timestamp = (time.toUtc().millisecondsSinceEpoch ~/ 1000) - baseTime;
    final timestampClamped = timestamp.clamp(0, 0xFFFF).toInt();

    final byteData = ByteData(compactPayloadLength);
    byteData.setUint8(0, protocolVersion);
    // flags: bit0=sosFlag, bit7=compact标志
    byteData.setUint8(1, (sosFlag & 0x01) | 0x80);
    byteData.setInt16(2, latInt, byteOrder);
    byteData.setInt16(4, lonInt, byteOrder);
    byteData.setUint16(6, timestampClamped, byteOrder);

    return byteData.buffer.asUint8List();
  }

  static SosPayload? decodeCompactSosData(List<int> rawBytes) {
    if (rawBytes.length != compactPayloadLength) {
      return null;
    }

    final bytes = Uint8List.fromList(rawBytes);
    final byteData = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );

    final version = byteData.getUint8(0);
    if (version != protocolVersion) {
      return null;
    }

    final flags = byteData.getUint8(1);
    // 检查紧凑格式标志 (bit7)
    if ((flags & 0x80) == 0) {
      return null; // 不是紧凑格式
    }

    final sosFlag = flags & 0x01;
    final latInt = byteData.getInt16(2, byteOrder);
    final lonInt = byteData.getInt16(4, byteOrder);
    final timestampOffset = byteData.getUint16(6, byteOrder);

    // 解压缩坐标
    final latitude = latInt / _latScale;
    final longitude = lonInt / _lonScale;

    // 恢复时间戳
    final baseTime = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch ~/ 1000;
    final timestamp = baseTime + timestampOffset;

    return SosPayload(
      protocolVersion: version,
      bloodType: 0, // 紧凑格式不包含血型
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
    );
  }
}
