import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/sos_payload.dart';
import '../services/rssi_ranging_engine.dart';

part 'mesh_state_provider.g.dart';

@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.deviceId,
    required this.sourceAddress,
    required this.payload,
    required this.rssi,
    required this.firstDiscoveredAt,
    required this.lastUpdatedAt,
    this.rangingResult,
  });

  final String deviceId;
  final String sourceAddress;
  final SosPayload payload;
  final int rssi;
  final DateTime firstDiscoveredAt;
  final DateTime lastUpdatedAt;
  final RangingResult? rangingResult;

  double get estimatedDistance => rangingResult?.estimatedDistance ?? 0;

  double get distanceConfidence => rangingResult?.confidence ?? 0;

  String get confidenceLabel => rangingResult?.confidenceLabel ?? '未知';

  String get distanceDescription => rangingResult?.distanceDescription ?? '未知';

  DiscoveredDevice copyWith({
    String? deviceId,
    String? sourceAddress,
    SosPayload? payload,
    int? rssi,
    DateTime? firstDiscoveredAt,
    DateTime? lastUpdatedAt,
    RangingResult? rangingResult,
  }) {
    return DiscoveredDevice(
      deviceId: deviceId ?? this.deviceId,
      sourceAddress: sourceAddress ?? this.sourceAddress,
      payload: payload ?? this.payload,
      rssi: rssi ?? this.rssi,
      firstDiscoveredAt: firstDiscoveredAt ?? this.firstDiscoveredAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      rangingResult: rangingResult ?? this.rangingResult,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is DiscoveredDevice &&
        other.deviceId == deviceId &&
        other.sourceAddress == sourceAddress &&
        other.payload == payload &&
        other.rssi == rssi &&
        other.firstDiscoveredAt == firstDiscoveredAt &&
        other.lastUpdatedAt == lastUpdatedAt &&
        other.rangingResult == rangingResult;
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    sourceAddress,
    payload,
    rssi,
    firstDiscoveredAt,
    lastUpdatedAt,
    rangingResult,
  );
}

@immutable
class MeshState {
  const MeshState({
    required this.discoveredDevices,
    this.lastScanTime,
    this.isScanning = false,
  });

  final Map<String, DiscoveredDevice> discoveredDevices;
  final DateTime? lastScanTime;
  final bool isScanning;

  List<DiscoveredDevice> get sortedDevices =>
      discoveredDevices.values.toList()
        ..sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));

  List<DiscoveredDevice> get activeDevices {
    final now = DateTime.now();
    return discoveredDevices.values.where((device) {
      return now.difference(device.lastUpdatedAt).inSeconds <= 30;
    }).toList();
  }

  MeshState copyWith({
    Map<String, DiscoveredDevice>? discoveredDevices,
    DateTime? lastScanTime,
    bool? isScanning,
  }) {
    return MeshState(
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      isScanning: isScanning ?? this.isScanning,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is MeshState &&
        mapEquals(other.discoveredDevices, discoveredDevices) &&
        other.lastScanTime == lastScanTime &&
        other.isScanning == isScanning;
  }

  @override
  int get hashCode => Object.hash(discoveredDevices, lastScanTime, isScanning);
}

@riverpod
class MeshStateNotifier extends _$MeshStateNotifier {
  final Map<String, RssiRangingEngine> _rangingEngines =
      <String, RssiRangingEngine>{};

  @override
  MeshState build() {
    return const MeshState(discoveredDevices: {}, isScanning: false);
  }

  void addOrUpdateDevice(
    String deviceId,
    String sourceAddress,
    SosPayload payload,
    int rssi,
  ) {
    final now = DateTime.now();
    final currentState = state;
    final existingDevice = currentState.discoveredDevices[deviceId];

    final rangingEngine = _rangingEngines.putIfAbsent(
      deviceId,
      () => RssiRangingEngine(),
    );
    final rangingResult = rangingEngine.estimateDistance(rssi);

    if (existingDevice != null) {
      final hasNewerTimestamp =
          payload.timestamp > existingDevice.payload.timestamp;
      final hasSignificantRssiChange = (existingDevice.rssi - rssi).abs() > 5;

      final stableSourceAddress = existingDevice.sourceAddress.isNotEmpty
          ? existingDevice.sourceAddress
          : sourceAddress;

      if (!hasNewerTimestamp && !hasSignificantRssiChange) {
        final refreshedDevice = existingDevice.copyWith(
          sourceAddress: stableSourceAddress,
          lastUpdatedAt: now,
        );

        state = currentState.copyWith(
          discoveredDevices: {
            ...currentState.discoveredDevices,
            deviceId: refreshedDevice,
          },
          lastScanTime: now,
        );
        return;
      }

      final updatedDevice = existingDevice.copyWith(
        sourceAddress: stableSourceAddress,
        payload: payload,
        rssi: rssi,
        lastUpdatedAt: now,
        rangingResult: rangingResult,
      );

      state = currentState.copyWith(
        discoveredDevices: {
          ...currentState.discoveredDevices,
          deviceId: updatedDevice,
        },
        lastScanTime: now,
      );
      return;
    }

    final newDevice = DiscoveredDevice(
      deviceId: deviceId,
      sourceAddress: sourceAddress,
      payload: payload,
      rssi: rssi,
      firstDiscoveredAt: now,
      lastUpdatedAt: now,
      rangingResult: rangingResult,
    );

    state = currentState.copyWith(
      discoveredDevices: {
        ...currentState.discoveredDevices,
        deviceId: newDevice,
      },
      lastScanTime: now,
    );
  }

  void clearDevices() {
    for (final engine in _rangingEngines.values) {
      engine.reset();
    }
    _rangingEngines.clear();
    state = state.copyWith(discoveredDevices: {}, lastScanTime: DateTime.now());
  }

  void injectTestData() {
    final now = DateTime.now();
    const centerLat = 22.547;
    const centerLng = 114.065;

    final testData = [
      (
        mac: 'AA:BB:CC:00:00:01',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 1,
          latitude: centerLat + 0.001,
          longitude: centerLng + 0.001,
          timestamp: now.millisecondsSinceEpoch ~/ 1000,
        ),
        rssi: -45,
      ),
      (
        mac: 'AA:BB:CC:00:00:02',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 2,
          latitude: centerLat - 0.002,
          longitude: centerLng + 0.003,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 10,
        ),
        rssi: -65,
      ),
      (
        mac: 'AA:BB:CC:00:00:03',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 3,
          latitude: centerLat + 0.005,
          longitude: centerLng - 0.004,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 20,
        ),
        rssi: -85,
      ),
      (
        mac: 'AA:BB:CC:00:00:04',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 0,
          latitude: centerLat - 0.003,
          longitude: centerLng - 0.002,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 5,
        ),
        rssi: -70,
      ),
    ];

    for (final data in testData) {
      addOrUpdateDevice(data.mac, data.mac, data.payload, data.rssi);
    }
  }

  void setScanning(bool scanning) {
    state = state.copyWith(isScanning: scanning);
  }

  void removeStaleDevices(int staleThresholdSeconds) {
    final now = DateTime.now();
    final activeDevices = <String, DiscoveredDevice>{};
    final staleKeys = <String>[];

    for (final entry in state.discoveredDevices.entries) {
      final age = now.difference(entry.value.lastUpdatedAt).inSeconds;
      if (age <= staleThresholdSeconds) {
        activeDevices[entry.key] = entry.value;
      } else {
        staleKeys.add(entry.key);
      }
    }

    for (final key in staleKeys) {
      _rangingEngines.remove(key)?.reset();
    }

    if (activeDevices.length != state.discoveredDevices.length) {
      state = state.copyWith(
        discoveredDevices: activeDevices,
        lastScanTime: now,
      );
    }
  }
}
