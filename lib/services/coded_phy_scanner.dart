import 'dart:async';

import 'package:flutter/services.dart';

/// Coded PHY 扫描服务 — 用于接收 BLE Long Range (300m) 信号
///
/// 当设备支持 Bluetooth 5.0+ 时，优先使用 Coded PHY 扫描；
/// 否则自动回退到传统 1M PHY 扫描。
class CodedPhyScanner {
  CodedPhyScanner._();

  static const MethodChannel _methodChannel = MethodChannel(
    'rescue_mesh/advertiser',
  );
  static const EventChannel _scanEventChannel = EventChannel(
    'rescue_mesh/coded_phy_scanner',
  );

  static StreamSubscription? _scanSubscription;

  /// 检查设备是否支持 Coded PHY (Bluetooth 5.0+)
  static Future<bool> supportsCodedPhy() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'supportsCodedPhy',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 开始 Coded PHY 扫描
  ///
  /// 返回扫描结果流
  static Stream<CodedPhyScanResult> startScan() {
    final controller = StreamController<CodedPhyScanResult>.broadcast();

    _scanSubscription = _scanEventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          final result = CodedPhyScanResult.fromMap(
            Map<String, dynamic>.from(event),
          );
          controller.add(result);
        }
      },
      onError: (error) {
        controller.addError(error);
      },
    );

    _methodChannel.invokeMethod('startCodedPhyScan').catchError((e) {
      controller.addError(e);
    });

    return controller.stream;
  }

  /// 停止 Coded PHY 扫描
  static Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await _methodChannel.invokeMethod('stopCodedPhyScan');
    } catch (e) {
      // 忽略停止扫描时的错误
    }
  }

  /// 检查是否正在扫描
  static Future<bool> isScanning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isCodedPhyScanning',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 设置SOS密集广播模式
  static Future<void> setSosMode(bool enabled) async {
    try {
      await _methodChannel.invokeMethod('setSosMode', {'isSos': enabled});
    } catch (e) {
      // 忽略错误
    }
  }

  /// 获取累积的信号（经过积分处理的弱信号）
  static Future<List<AccumulatedSignal>> getAccumulatedSignals() async {
    try {
      final result = await _methodChannel.invokeMethod<List>(
        'getAccumulatedSignals',
      );
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((e) => AccumulatedSignal.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// Coded PHY 扫描结果
class CodedPhyScanResult {
  final String address;
  final String name;
  final int rssi;
  final int phy; // 0=1M, 1=2M, 3=CODED
  final Map<String, dynamic>? msd; // Manufacturer Specific Data
  final int timestampNanos;
  // 累积信号相关字段
  final int? accumCount; // 累积检测次数
  final int? accumMaxRssi; // 累积最大RSSI
  final int? accumAvgRssi; // 累积平均RSSI
  final bool isAccumulated; // 是否是累积信号

  CodedPhyScanResult({
    required this.address,
    required this.name,
    required this.rssi,
    required this.phy,
    this.msd,
    required this.timestampNanos,
    this.accumCount,
    this.accumMaxRssi,
    this.accumAvgRssi,
    this.isAccumulated = false,
  });

  factory CodedPhyScanResult.fromMap(Map<String, dynamic> map) {
    return CodedPhyScanResult(
      address: map['address'] as String? ?? '',
      name: map['name'] as String? ?? '',
      rssi: map['rssi'] as int? ?? -100,
      phy: map['phy'] as int? ?? 0,
      msd: map['msd'] as Map<String, dynamic>?,
      timestampNanos: map['timestampNanos'] as int? ?? 0,
      accumCount: map['accumCount'] as int?,
      accumMaxRssi: map['accumMaxRssi'] as int?,
      accumAvgRssi: map['accumAvgRssi'] as int?,
      isAccumulated: map['isAccumulated'] as bool? ?? false,
    );
  }

  /// 是否是 Coded PHY 信号
  bool get isCodedPhy => phy == 3; // PHY_LE_CODED = 3

  @override
  String toString() {
    return 'CodedPhyScanResult(address: $address, name: $name, rssi: $rssi, phy: $phy, isCoded: $isCodedPhy, accumulated: $isAccumulated)';
  }
}

/// 累积信号结果（经过积分处理的弱信号）
class AccumulatedSignal {
  final String address;
  final String name;
  final int count; // 检测次数
  final int avgRssi; // 平均RSSI
  final int maxRssi; // 最大RSSI
  final int phy;
  final Map<String, dynamic>? msd;

  AccumulatedSignal({
    required this.address,
    required this.name,
    required this.count,
    required this.avgRssi,
    required this.maxRssi,
    required this.phy,
    this.msd,
  });

  factory AccumulatedSignal.fromMap(Map<String, dynamic> map) {
    return AccumulatedSignal(
      address: map['address'] as String? ?? '',
      name: map['name'] as String? ?? '',
      count: map['count'] as int? ?? 0,
      avgRssi: map['avgRssi'] as int? ?? -100,
      maxRssi: map['maxRssi'] as int? ?? -100,
      phy: map['phy'] as int? ?? 0,
      msd: map['msd'] as Map<String, dynamic>?,
    );
  }

  /// 是否是远距离弱信号（RSSI < -80 但被多次检测到）
  bool get isWeakButConfirmed => count >= 2 && avgRssi < -80;

  @override
  String toString() {
    return 'AccumulatedSignal(address: $address, count: $count, avgRssi: $avgRssi, maxRssi: $maxRssi)';
  }
}
