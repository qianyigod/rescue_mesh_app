import 'dart:async';

import 'package:location/location.dart';

import '../database.dart';
import '../models/emergency_profile.dart';
import 'ble_mesh_exceptions.dart';
import 'ble_mesh_service.dart';
import 'network_sync_service.dart';
import 'domestic_location_service.dart';
import 'power_saving_manager.dart';

typedef DomesticFixProvider =
    Future<DomesticLocationFix?> Function(Duration timeout);
typedef SosLocationClientFactory = SosLocationClient Function();
typedef SosMessagePersister =
    Future<int> Function({
      required String senderMac,
      required double latitude,
      required double longitude,
      required int bloodType,
    });

abstract class SosLocationClient {
  Future<bool> serviceEnabled();

  Future<bool> requestService();

  Future<PermissionStatus> hasPermission();

  Future<PermissionStatus> requestPermission();

  Future<void> changeSettings({
    required LocationAccuracy accuracy,
    required int interval,
    required double distanceFilter,
  });

  Future<LocationData> getLocation();
}

class PluginSosLocationClient implements SosLocationClient {
  PluginSosLocationClient({Location? location}) : _location = location ?? Location();

  final Location _location;

  @override
  Future<void> changeSettings({
    required LocationAccuracy accuracy,
    required int interval,
    required double distanceFilter,
  }) {
    return _location.changeSettings(
      accuracy: accuracy,
      interval: interval,
      distanceFilter: distanceFilter,
    );
  }

  @override
  Future<LocationData> getLocation() => _location.getLocation();

  @override
  Future<PermissionStatus> hasPermission() => _location.hasPermission();

  @override
  Future<PermissionStatus> requestPermission() => _location.requestPermission();

  @override
  Future<bool> requestService() => _location.requestService();

  @override
  Future<bool> serviceEnabled() => _location.serviceEnabled();
}

class SosLocationResolution {
  const SosLocationResolution._({
    required this.latitude,
    required this.longitude,
    required this.requiresCacheConfirmation,
    this.cachedAt,
    this.failureReason,
  });

  const SosLocationResolution.ready({
    required double latitude,
    required double longitude,
  }) : this._(
         latitude: latitude,
         longitude: longitude,
         requiresCacheConfirmation: false,
       );

  const SosLocationResolution.requiresCacheConfirmation({
    required double latitude,
    required double longitude,
    required DateTime cachedAt,
    required String failureReason,
  }) : this._(
         latitude: latitude,
         longitude: longitude,
         requiresCacheConfirmation: true,
         cachedAt: cachedAt,
         failureReason: failureReason,
       );

  final double latitude;
  final double longitude;
  final bool requiresCacheConfirmation;
  final DateTime? cachedAt;
  final String? failureReason;
}

class SosTriggerResult {
  const SosTriggerResult({
    required this.messageId,
    required this.latitude,
    required this.longitude,
    required this.uploadedCount,
    this.bleError,
    this.syncError,
  });

  final int messageId;
  final double latitude;
  final double longitude;
  final int uploadedCount;
  final String? bleError;
  final String? syncError;

  bool get broadcastStarted => bleError == null;
  bool get uploadedToCommandCenter => uploadedCount > 0 && syncError == null;
}

class SosTriggerService {
  SosTriggerService({
    AppDatabase? database,
    NetworkSyncService? networkSyncServiceOverride,
    PowerSavingManager? powerSavingManagerOverride,
    DomesticFixProvider? domesticFixProvider,
    SosLocationClientFactory? locationClientFactory,
    SosMessagePersister? sosMessagePersister,
  }) : _database = database ?? appDb,
        _networkSyncService =
            networkSyncServiceOverride ?? networkSyncService,
        _powerSavingManager =
            powerSavingManagerOverride ?? powerSavingManager,
        _domesticFixProvider =
            domesticFixProvider ??
            ((timeout) => domesticLocationService.getCurrentFix(timeout: timeout)),
        _locationClientFactory =
            locationClientFactory ?? (() => PluginSosLocationClient()),
        _sosMessagePersister = sosMessagePersister;

  final AppDatabase _database;
  final NetworkSyncService _networkSyncService;
  final PowerSavingManager _powerSavingManager;
  final DomesticFixProvider _domesticFixProvider;
  final SosLocationClientFactory _locationClientFactory;
  final SosMessagePersister? _sosMessagePersister;

  static const Duration _domesticLocationTimeout = Duration(seconds: 4);
  static const Duration _locationAcquireTimeout = Duration(seconds: 10);
  static const Duration _locationFallbackCacheMaxAge = Duration(minutes: 15);

  Future<SosLocationResolution> resolveLocationForSos() async {
    final locationClient = _locationClientFactory();
    await _ensureLocationAccess(locationClient);

    final domesticFix = await _domesticFixProvider(_domesticLocationTimeout);
    if (domesticFix != null) {
      final freshLocation = LocationData.fromMap({
        'latitude': domesticFix.latitude,
        'longitude': domesticFix.longitude,
        'accuracy': domesticFix.accuracy,
        'altitude': domesticFix.altitude,
        'speed': domesticFix.speed,
        'heading': domesticFix.bearing,
        'provider': domesticFix.provider,
        'time': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
      _powerSavingManager.cacheLocationFix(freshLocation);
      return SosLocationResolution.ready(
        latitude: domesticFix.latitude,
        longitude: domesticFix.longitude,
      );
    }

    try {
      await locationClient.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 0,
      );
      final freshLocation = await locationClient
          .getLocation()
          .timeout(_locationAcquireTimeout);
      final latitude = freshLocation.latitude;
      final longitude = freshLocation.longitude;
      if (latitude == null || longitude == null) {
        return _resolveCachedFallback('当前实时定位结果不可用。');
      }

      _powerSavingManager.cacheLocationFix(freshLocation);
      return SosLocationResolution.ready(
        latitude: latitude,
        longitude: longitude,
      );
    } on TimeoutException {
      return _resolveCachedFallback('实时定位超时。');
    } catch (_) {
      return _resolveCachedFallback('实时定位失败。');
    }
  }

  Future<SosTriggerResult> triggerSos({
    required BleMeshService bleService,
    required BloodType bloodType,
    String senderMac = 'SELF',
  }) async {
    final resolution = await resolveLocationForSos();
    if (resolution.requiresCacheConfirmation) {
      throw BleMeshPlatformException(
        platformCode: 'location_confirmation_required',
        message: resolution.failureReason ?? '需要确认是否使用缓存坐标发送 SOS。',
        details: {
          'latitude': resolution.latitude,
          'longitude': resolution.longitude,
          'cachedAt': resolution.cachedAt?.toIso8601String(),
        },
      );
    }

    return sendResolvedSos(
      bleService: bleService,
      bloodType: bloodType,
      senderMac: senderMac,
      resolution: resolution,
    );
  }

  Future<SosTriggerResult> sendResolvedSos({
    required BleMeshService bleService,
    required BloodType bloodType,
    required SosLocationResolution resolution,
    String senderMac = 'SELF',
  }) async {
    final latitude = resolution.latitude;
    final longitude = resolution.longitude;
    if (!latitude.isFinite || !longitude.isFinite) {
      throw const BleMeshPlatformException(
        platformCode: 'location_unavailable',
        message: '当前定位结果不可用，无法发送 SOS。',
      );
    }

    final messageId =
        await _sosMessagePersister?.call(
          senderMac: senderMac,
          latitude: latitude,
          longitude: longitude,
          bloodType: bloodType.code,
        ) ??
        await _database.addSosMessage(
          senderMac: senderMac,
          latitude: latitude,
          longitude: longitude,
          bloodType: bloodType.code,
        );

    String? bleError;
    try {
      await bleService.startSosBroadcast(
        latitude: latitude,
        longitude: longitude,
        bloodType: bloodType,
      );
    } on BleMeshException catch (error) {
      bleError = error.message;
    } catch (error) {
      bleError = error.toString();
    }

    unawaited(
      _networkSyncService.syncNow().catchError((Object error) {
        return 0;
      }),
    );

    return SosTriggerResult(
      messageId: messageId,
      latitude: latitude,
      longitude: longitude,
      uploadedCount: 0,
      bleError: bleError,
      syncError: null,
    );
  }

  Future<void> _ensureLocationAccess(SosLocationClient locationClient) async {
    var serviceEnabled = await locationClient.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await locationClient.requestService();
      if (!serviceEnabled) {
        throw const BleMeshPlatformException(
          platformCode: 'location_service_disabled',
          message: '定位服务未开启，无法发送 SOS 坐标。',
        );
      }
    }

    var permissionGranted = await locationClient.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await locationClient.requestPermission();
    }
    if (permissionGranted != PermissionStatus.granted) {
      throw const BleMeshPlatformException(
        platformCode: 'location_permission_denied',
        message: '定位权限未授予，无法发送 SOS 坐标。',
      );
    }
  }

  SosLocationResolution _resolveCachedFallback(String failureReason) {
    final fallbackLocation = _powerSavingManager.getCachedLocation(
      maxAge: _locationFallbackCacheMaxAge,
    );
    final cachedAt = _powerSavingManager.cachedLocationUpdatedAt;
    final latitude = fallbackLocation?.latitude;
    final longitude = fallbackLocation?.longitude;
    if (fallbackLocation != null &&
        cachedAt != null &&
        latitude != null &&
        longitude != null) {
      return SosLocationResolution.requiresCacheConfirmation(
        latitude: latitude,
        longitude: longitude,
        cachedAt: cachedAt,
        failureReason: '$failureReason 可改用最近一次缓存坐标继续发送。',
      );
    }

    throw const BleMeshPlatformException(
      platformCode: 'location_timeout',
      message: '定位超时，且没有可用的最近缓存坐标。请靠近窗边后重试。',
    );
  }
}

final sosTriggerService = SosTriggerService();
