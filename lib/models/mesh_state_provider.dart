import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/sos_payload.dart';
import '../services/rssi_ranging_engine.dart';

part 'mesh_state_provider.g.dart';

/// 设备发现记录，包含 SOS 负载和元数据
@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.macAddress,
    required this.payload,
    required this.rssi,
    required this.firstDiscoveredAt,
    required this.lastUpdatedAt,
    this.rangingResult,
  });

  final String macAddress;
  final SosPayload payload;
  final int rssi;
  final DateTime firstDiscoveredAt;
  final DateTime lastUpdatedAt;

  /// RSSI 测距结果（含卡尔曼滤波和置信度）
  final RangingResult? rangingResult;

  /// 估算距离（米）— 使用统一测距引擎
  double get estimatedDistance => rangingResult?.estimatedDistance ?? 0;

  /// 距离置信度（0.0 - 1.0）
  double get distanceConfidence => rangingResult?.confidence ?? 0;

  /// 置信度标签
  String get confidenceLabel => rangingResult?.confidenceLabel ?? '未知';

  /// 距离描述
  String get distanceDescription => rangingResult?.distanceDescription ?? '未知';

  DiscoveredDevice copyWith({
    String? macAddress,
    SosPayload? payload,
    int? rssi,
    DateTime? firstDiscoveredAt,
    DateTime? lastUpdatedAt,
    RangingResult? rangingResult,
  }) {
    return DiscoveredDevice(
      macAddress: macAddress ?? this.macAddress,
      payload: payload ?? this.payload,
      rssi: rssi ?? this.rssi,
      firstDiscoveredAt: firstDiscoveredAt ?? this.firstDiscoveredAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      rangingResult: rangingResult ?? this.rangingResult,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DiscoveredDevice &&
        other.macAddress == macAddress &&
        other.payload == payload &&
        other.rssi == rssi &&
        other.firstDiscoveredAt == firstDiscoveredAt &&
        other.lastUpdatedAt == lastUpdatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(macAddress, payload, rssi, firstDiscoveredAt, lastUpdatedAt);
}

/// 网格网络状态
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

  /// 获取按最后更新时间排序的设备列表
  List<DiscoveredDevice> get sortedDevices =>
      discoveredDevices.values.toList()
        ..sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));

  /// 获取最近 30 秒内活跃的设备
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
    if (identical(this, other)) return true;
    return other is MeshState &&
        other.discoveredDevices == discoveredDevices &&
        other.lastScanTime == lastScanTime &&
        other.isScanning == isScanning;
  }

  @override
  int get hashCode => Object.hash(discoveredDevices, lastScanTime, isScanning);
}

/// Mesh 状态通知器
@riverpod
class MeshStateNotifier extends _$MeshStateNotifier {
  @override
  MeshState build() {
    return const MeshState(discoveredDevices: {}, isScanning: false);
  }

  /// 添加或更新设备
  ///
  /// 核心优化逻辑：
  /// 1. 通过 MAC 地址去重
  /// 2. 只有当设备是新的，或者时间戳/信号强度有显著变化时才更新
  /// 3. 使用统一 RSSI 测距引擎（含卡尔曼滤波）
  /// 4. 避免无效的频繁重绘
  void addOrUpdateDevice(String macAddress, SosPayload payload, int rssi) {
    final now = DateTime.now();
    final currentState = state;
    final existingDevice = currentState.discoveredDevices[macAddress];

    // 使用统一测距引擎计算距离
    final rangingEngine = RssiRangingEngine.instance();
    final rangingResult = rangingEngine.estimateDistance(rssi);

    // 如果设备已存在，检查是否需要更新
    if (existingDevice != null) {
      // 只有当时间戳更新或 RSSI 变化超过阈值时才更新
      final hasNewerTimestamp =
          payload.timestamp > existingDevice.payload.timestamp;
      final hasSignificantRssiChange = (existingDevice.rssi - rssi).abs() > 5;

      if (!hasNewerTimestamp && !hasSignificantRssiChange) {
        // 无需更新，避免触发不必要的重建
        return;
      }

      // 更新现有设备
      final updatedDevice = existingDevice.copyWith(
        payload: payload,
        rssi: rssi,
        lastUpdatedAt: now,
        rangingResult: rangingResult,
      );

      state = currentState.copyWith(
        discoveredDevices: {
          ...currentState.discoveredDevices,
          macAddress: updatedDevice,
        },
        lastScanTime: now,
      );
    } else {
      // 添加新设备
      final newDevice = DiscoveredDevice(
        macAddress: macAddress,
        payload: payload,
        rssi: rssi,
        firstDiscoveredAt: now,
        lastUpdatedAt: now,
        rangingResult: rangingResult,
      );

      state = currentState.copyWith(
        discoveredDevices: {
          ...currentState.discoveredDevices,
          macAddress: newDevice,
        },
        lastScanTime: now,
      );
    }
  }

  /// 清除所有发现的设备
  void clearDevices() {
    state = state.copyWith(discoveredDevices: {}, lastScanTime: DateTime.now());
  }

  /// 注入测试数据（用于开发调试）
  void injectTestData() {
    final now = DateTime.now();
    // 以深圳某地为测试中心点
    const centerLat = 22.547;
    const centerLng = 114.065;

    final testData = [
      // 设备1：强信号，近距离
      (
        mac: 'AA:BB:CC:00:00:01',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 1, // A型血
          latitude: centerLat + 0.001,
          longitude: centerLng + 0.001,
          timestamp: now.millisecondsSinceEpoch ~/ 1000,
        ),
        rssi: -45,
      ),
      // 设备2：中等信号
      (
        mac: 'AA:BB:CC:00:00:02',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 2, // B型血
          latitude: centerLat - 0.002,
          longitude: centerLng + 0.003,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 10,
        ),
        rssi: -65,
      ),
      // 设备3：弱信号，远距离
      (
        mac: 'AA:BB:CC:00:00:03',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 3, // AB型血
          latitude: centerLat + 0.005,
          longitude: centerLng - 0.004,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 20,
        ),
        rssi: -85,
      ),
      // 设备4：O型血，中等距离
      (
        mac: 'AA:BB:CC:00:00:04',
        payload: SosPayload(
          protocolVersion: 1,
          bloodType: 0, // O型血
          latitude: centerLat - 0.003,
          longitude: centerLng - 0.002,
          timestamp: now.millisecondsSinceEpoch ~/ 1000 - 5,
        ),
        rssi: -70,
      ),
    ];

    for (final data in testData) {
      addOrUpdateDevice(data.mac, data.payload, data.rssi);
    }
  }

  /// 设置扫描状态
  void setScanning(bool scanning) {
    state = state.copyWith(isScanning: scanning);
  }

  /// 移除过期设备（超过指定秒数未更新）
  void removeStaleDevices(int staleThresholdSeconds) {
    final now = DateTime.now();
    final activeDevices = <String, DiscoveredDevice>{};

    for (final entry in state.discoveredDevices.entries) {
      final age = now.difference(entry.value.lastUpdatedAt).inSeconds;
      if (age <= staleThresholdSeconds) {
        activeDevices[entry.key] = entry.value;
      }
    }

    if (activeDevices.length != state.discoveredDevices.length) {
      state = state.copyWith(
        discoveredDevices: activeDevices,
        lastScanTime: now,
      );
    }
  }
}
