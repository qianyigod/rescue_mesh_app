import 'emergency_profile.dart';

class SosMessage {
  const SosMessage({
    required this.companyId,
    required this.remoteId,
    required this.deviceName,
    required this.sosFlag,
    required this.latitude,
    required this.longitude,
    required this.bloodTypeCode,
    required this.rssi,
    required this.receivedAt,
    required this.rawPayload,
  });

  final int companyId;
  final String remoteId;
  final String deviceName;
  final bool sosFlag;
  final double latitude;
  final double longitude;
  final int bloodTypeCode;
  final int rssi;
  final DateTime receivedAt;
  final List<int> rawPayload;

  String get signalId {
    final payloadHex = rawPayload
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$companyId:$payloadHex';
  }

  BloodType get bloodType {
    for (final type in BloodType.values) {
      if (type.code == bloodTypeCode) {
        return type;
      }
    }
    return BloodType.unknown;
  }
}
