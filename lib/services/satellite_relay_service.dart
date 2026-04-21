import '../models/emergency_profile.dart';

enum SatelliteRelayStatus {
  reserved,
  sent,
  failed,
}

class SatelliteRelayRequest {
  const SatelliteRelayRequest({
    required this.messageId,
    required this.latitude,
    required this.longitude,
    required this.bloodType,
    required this.senderMac,
    required this.timestamp,
  });

  final int messageId;
  final double latitude;
  final double longitude;
  final BloodType bloodType;
  final String senderMac;
  final DateTime timestamp;
}

class SatelliteRelayResult {
  const SatelliteRelayResult({
    required this.status,
    required this.message,
  });

  const SatelliteRelayResult.reserved()
    : status = SatelliteRelayStatus.reserved,
      message =
          'Satellite relay interface is reserved for future Beidou short-message integration.';

  const SatelliteRelayResult.sent({this.message = 'Satellite relay accepted the SOS payload.'})
    : status = SatelliteRelayStatus.sent;

  const SatelliteRelayResult.failed(String error)
    : status = SatelliteRelayStatus.failed,
      message = error;

  final SatelliteRelayStatus status;
  final String message;
}

abstract class SatelliteRelayService {
  Future<SatelliteRelayResult> relaySos(SatelliteRelayRequest request);
}

class NoopSatelliteRelayService implements SatelliteRelayService {
  const NoopSatelliteRelayService();

  @override
  Future<SatelliteRelayResult> relaySos(SatelliteRelayRequest request) async {
    return const SatelliteRelayResult.reserved();
  }
}

const SatelliteRelayService satelliteRelayService = NoopSatelliteRelayService();
