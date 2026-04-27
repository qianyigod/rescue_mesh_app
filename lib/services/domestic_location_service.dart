import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DomesticLocationFix {
  const DomesticLocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    this.bearing,
    required this.provider,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final double? bearing;
  final String provider;
}

class DomesticLocationService {
  DomesticLocationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'cn.rescuemesh.location/domestic';

  final MethodChannel _channel;

  Future<DomesticLocationFix?> getCurrentFix({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (kIsWeb) {
      return null;
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'getCurrentFix',
        <String, dynamic>{'timeoutMs': timeout.inMilliseconds},
      );
      if (response == null) {
        return null;
      }

      final latitude = (response['latitude'] as num?)?.toDouble();
      final longitude = (response['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) {
        return null;
      }

      return DomesticLocationFix(
        latitude: latitude,
        longitude: longitude,
        accuracy: (response['accuracy'] as num?)?.toDouble(),
        altitude: (response['altitude'] as num?)?.toDouble(),
        speed: (response['speed'] as num?)?.toDouble(),
        bearing: (response['bearing'] as num?)?.toDouble(),
        provider: (response['provider'] as String?) ?? 'domestic_sdk',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}

final domesticLocationService = DomesticLocationService();
