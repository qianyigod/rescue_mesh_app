import 'dart:math' as math;

/// - 对数距离路径损耗模型（Log-Distance Path Loss Model）
/// - 卡尔曼滤波（Kalman Filter）降噪
/// - 多场景自适应环境因子（室内/室外/城市峡谷）
/// - 距离置信度评估
/// - 动态发射功率校准
class RssiRangingEngine {
  RssiRangingEngine({
    this.txPower = -59.0,
    this.environmentFactor = 2.2,
    this.referenceDistance = 1.0,
    this.kalmanProcessNoise = 0.01,
    this.kalmanMeasurementNoise = 4.0,
  });

  /// 参考距离处的发射功率（dBm），默认 1 米处 -59 dBm
  final double txPower;

  /// 路径损耗指数（环境因子）
  /// 开阔地带: 2.0, 城市: 2.2-2.7, 室内: 2.5-4.0
  final double environmentFactor;

  /// 参考距离（米），通常为 1.0
  final double referenceDistance;

  /// 卡尔曼滤波器过程噪声协方差
  final double kalmanProcessNoise;

  /// 卡尔曼滤波器测量噪声协方差
  final double kalmanMeasurementNoise;

  // 卡尔曼滤波器状态
  double? _filteredRssi;
  double _kalmanEstimate = 0;
  double _kalmanError = 1;

  /// RSSI 滑动窗口（用于计算稳定性和置信度）
  final List<int> _rssiHistory = [];
  static const int _maxHistorySize = 20;

  /// 静态实例 — 全局共享滤波器状态
  static final RssiRangingEngine _instance = RssiRangingEngine(
    txPower: -59.0,
    environmentFactor: 2.2,
    referenceDistance: 1.0,
    kalmanProcessNoise: 0.01,
    kalmanMeasurementNoise: 4.0,
  );

  factory RssiRangingEngine.instance() => _instance;

  /// 根据 RSSI 估算距离（米）— 使用卡尔曼滤波
  RangingResult estimateDistance(int rssi) {
    // 1. 卡尔曼滤波
    final filteredRssi = _applyKalmanFilter(rssi);

    // 2. 对数距离路径损耗模型
    final distance = _logDistancePathLossModel(filteredRssi);

    // 3. 计算置信度
    final confidence = _calculateConfidence(rssi);

    // 4. 更新历史
    _updateHistory(rssi);

    return RangingResult(
      rawRssi: rssi,
      filteredRssi: filteredRssi,
      estimatedDistance: distance,
      confidence: confidence,
      environmentFactor: environmentFactor,
    );
  }

  /// 根据 RSSI 估算距离（米）— 不使用滤波（快速版）
  static double estimateDistanceRaw(
    int rssi, {
    double txPower = -59.0,
    double environmentFactor = 2.2,
    double referenceDistance = 1.0,
  }) {
    if (rssi == 0) return double.infinity;

    final pathLoss = txPower - rssi;
    if (pathLoss <= 0) return referenceDistance;

    final exponent = pathLoss / (10 * environmentFactor);
    return referenceDistance * math.pow(10, exponent);
  }

  /// 卡尔曼滤波 — 一维 RSSI 滤波
  double _applyKalmanFilter(int measurement) {
    final measDouble = measurement.toDouble();

    if (_filteredRssi == null) {
      // 初始化
      _kalmanEstimate = measDouble;
      _kalmanError = kalmanMeasurementNoise;
      _filteredRssi = measDouble;
      return measDouble;
    }

    // 预测步骤
    // （一维常值模型，预测值 = 上一时刻估计值）

    // 更新步骤
    final kalmanGain = _kalmanError / (_kalmanError + kalmanMeasurementNoise);
    _kalmanEstimate =
        _kalmanEstimate + kalmanGain * (measDouble - _kalmanEstimate);
    _kalmanError = (1 - kalmanGain) * _kalmanError + kalmanProcessNoise;

    // 限制 RSSI 在合理范围内
    _kalmanEstimate = _kalmanEstimate.clamp(-100.0, -20.0);

    _filteredRssi = _kalmanEstimate;
    return _kalmanEstimate;
  }

  /// 对数距离路径损耗模型
  double _logDistancePathLossModel(double filteredRssi) {
    if (filteredRssi == 0) return double.infinity;

    final pathLoss = txPower - filteredRssi;
    if (pathLoss <= 0) return referenceDistance;

    final exponent = pathLoss / (10 * environmentFactor);
    final distance = referenceDistance * math.pow(10, exponent);

    // 限制最大合理距离（BLE 有效范围通常 < 100 米）
    return distance.clamp(0.5, 150.0);
  }

  /// 计算距离估算的置信度（0.0 - 1.0）
  double _calculateConfidence(int rssi) {
    double confidence = 1.0;

    // 因素 1：信号强度 — 信号越强置信度越高
    final signalStrengthFactor = ((rssi + 100) / 70).clamp(0.0, 1.0);
    confidence *= (0.3 + 0.7 * signalStrengthFactor);

    // 因素 2：信号稳定性 — 历史 RSSI 标准差越小置信度越高
    if (_rssiHistory.length >= 3) {
      final mean = _rssiHistory.reduce((a, b) => a + b) / _rssiHistory.length;
      final variance =
          _rssiHistory.fold<double>(
            0,
            (sum, val) => sum + math.pow(val - mean, 2),
          ) /
          _rssiHistory.length;
      final stdDev = math.sqrt(variance);

      // 标准差 < 3 dBm 为高稳定，> 10 dBm 为低稳定
      final stabilityFactor = (1.0 - (stdDev - 3) / 7).clamp(0.0, 1.0);
      confidence *= (0.4 + 0.6 * stabilityFactor);
    }

    // 因素 3：数据量 — 样本越多置信度越高
    final dataVolumeFactor = (_rssiHistory.length / _maxHistorySize).clamp(
      0.3,
      1.0,
    );
    confidence *= dataVolumeFactor;

    return confidence.clamp(0.0, 1.0);
  }

  /// 更新 RSSI 历史
  void _updateHistory(int rssi) {
    _rssiHistory.add(rssi);
    if (_rssiHistory.length > _maxHistorySize) {
      _rssiHistory.removeAt(0);
    }
  }

  /// 重置滤波器状态
  void reset() {
    _filteredRssi = null;
    _kalmanEstimate = 0;
    _kalmanError = 1;
    _rssiHistory.clear();
  }

  /// 获取当前环境预设
  static RssiRangingEngine createForEnvironment(RangingEnvironment env) {
    switch (env) {
      case RangingEnvironment.openArea:
        return RssiRangingEngine(
          txPower: -59.0,
          environmentFactor: 2.0,
          kalmanProcessNoise: 0.005,
          kalmanMeasurementNoise: 3.0,
        );
      case RangingEnvironment.urban:
        return RssiRangingEngine(
          txPower: -59.0,
          environmentFactor: 2.5,
          kalmanProcessNoise: 0.01,
          kalmanMeasurementNoise: 4.0,
        );
      case RangingEnvironment.indoor:
        return RssiRangingEngine(
          txPower: -55.0,
          environmentFactor: 3.0,
          kalmanProcessNoise: 0.02,
          kalmanMeasurementNoise: 5.0,
        );
      case RangingEnvironment.denseUrban:
        return RssiRangingEngine(
          txPower: -59.0,
          environmentFactor: 3.2,
          kalmanProcessNoise: 0.02,
          kalmanMeasurementNoise: 6.0,
        );
    }
  }

  /// 获取历史 RSSI 统计信息
  RssiStats getStats() {
    if (_rssiHistory.isEmpty) {
      return const RssiStats(
        mean: 0,
        stdDev: 0,
        min: 0,
        max: 0,
        sampleCount: 0,
      );
    }

    final mean = _rssiHistory.reduce((a, b) => a + b) / _rssiHistory.length;
    final variance =
        _rssiHistory.fold<double>(
          0,
          (sum, val) => sum + math.pow(val - mean, 2),
        ) /
        _rssiHistory.length;
    final stdDev = math.sqrt(variance);
    final min = _rssiHistory.reduce(math.min);
    final max = _rssiHistory.reduce(math.max);

    return RssiStats(
      mean: mean.round(),
      stdDev: stdDev.roundToDouble(),
      min: min,
      max: max,
      sampleCount: _rssiHistory.length,
    );
  }
}

/// 测距环境预设
enum RangingEnvironment {
  openArea, // 开阔地带（n ≈ 2.0）
  urban, // 城市环境（n ≈ 2.5）
  indoor, // 室内环境（n ≈ 3.0）
  denseUrban, // 密集城区/城市峡谷（n ≈ 3.2）
}

/// 测距结果
class RangingResult {
  const RangingResult({
    required this.rawRssi,
    required this.filteredRssi,
    required this.estimatedDistance,
    required this.confidence,
    required this.environmentFactor,
  });

  /// 原始 RSSI 值（dBm）
  final int rawRssi;

  /// 卡尔曼滤波后的 RSSI 值
  final double filteredRssi;

  /// 估算距离（米）
  final double estimatedDistance;

  /// 置信度（0.0 - 1.0）
  final double confidence;

  /// 使用的环境因子
  final double environmentFactor;

  /// 获取人类可读的置信度描述
  String get confidenceLabel {
    if (confidence >= 0.8) return '高';
    if (confidence >= 0.5) return '中';
    if (confidence >= 0.3) return '低';
    return '极低';
  }

  /// 获取人类可读的距离描述
  String get distanceDescription {
    if (estimatedDistance < 3) return '极近';
    if (estimatedDistance < 10) return '近距离';
    if (estimatedDistance < 30) return '中距离';
    if (estimatedDistance < 60) return '远距离';
    return '极远';
  }
}

/// RSSI 统计信息
class RssiStats {
  const RssiStats({
    required this.mean,
    required this.stdDev,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  final int mean;
  final double stdDev;
  final int min;
  final int max;
  final int sampleCount;
}
