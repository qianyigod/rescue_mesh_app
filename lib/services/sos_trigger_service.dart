import 'package:location/location.dart';

import '../database.dart';
import '../models/emergency_profile.dart';
import 'ble_mesh_exceptions.dart';
import 'ble_mesh_service.dart';
import 'network_sync_service.dart';
import 'power_saving_manager.dart';

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
  }) : _database = database ?? appDb,
       _networkSyncService =
           networkSyncServiceOverride ?? networkSyncService,
       _powerSavingManager =
           powerSavingManagerOverride ?? powerSavingManager;

  final AppDatabase _database;
  final NetworkSyncService _networkSyncService;
  final PowerSavingManager _powerSavingManager;

  Future<SosTriggerResult> triggerSos({
    required BleMeshService bleService,
    required BloodType bloodType,
    String senderMac = 'SELF',
  }) async {
    final location = Location();

    var serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        throw const BleMeshPlatformException(
          platformCode: 'location_service_disabled',
          message: '定位服务未开启，无法发送 SOS 坐标。',
        );
      }
    }

    var permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
    }
    if (permissionGranted != PermissionStatus.granted) {
      throw const BleMeshPlatformException(
        platformCode: 'location_permission_denied',
        message: '定位权限未授予，无法发送 SOS 坐标。',
      );
    }

    final locationData = await _powerSavingManager.acquireLocationFix(
      location: location,
    );
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null) {
      throw const BleMeshPlatformException(
        platformCode: 'location_unavailable',
        message: '当前定位结果不可用，请稍后重试。',
      );
    }

    final messageId = await _database.addSosMessage(
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

    String? syncError;
    var uploadedCount = 0;
    try {
      uploadedCount = await _networkSyncService.syncNow();
      if (uploadedCount == 0 && _networkSyncService.lastError != null) {
        syncError = _networkSyncService.lastError;
      }
    } catch (error) {
      syncError = error.toString();
    }

    return SosTriggerResult(
      messageId: messageId,
      latitude: latitude,
      longitude: longitude,
      uploadedCount: uploadedCount,
      bleError: bleError,
      syncError: syncError,
    );
  }
}

final sosTriggerService = SosTriggerService();
