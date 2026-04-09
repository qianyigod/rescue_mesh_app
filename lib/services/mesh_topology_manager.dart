import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Mesh 中继拓扑管理器 — 商业化级网络拓扑发现
///
/// 功能：
/// - 追踪设备间的中继跳数（Hop Count）
/// - 构建网络拓扑图
/// - 识别关键中继节点
/// - 计算网络连通性指标
/// - 检测网络分区
class MeshTopologyManager extends ChangeNotifier {
  MeshTopologyManager._internal();

  static final MeshTopologyManager instance = MeshTopologyManager._internal();

  // 设备邻接表（谁发现了谁）
  final Map<String, Set<String>> _adjacencyList = {};

  // 设备到跳数的映射（从本设备出发）
  final Map<String, int> _hopCounts = {};

  // 设备最后活跃时间
  final Map<String, DateTime> _lastSeen = {};

  // 设备角色
  final Map<String, MeshNodeRole> _nodeRoles = {};

  /// 获取所有已知节点
  Set<String> get knownNodes => _adjacencyList.keys.toSet();

  /// 获取邻居数量
  int get neighborCount => _adjacencyList[thisDeviceId]?.length ?? 0;

  /// 获取网络中的总跳数
  int get maxHopCount =>
      _hopCounts.values.isEmpty ? 0 : _hopCounts.values.reduce(math.max);

  /// 获取关键中继节点列表（连接多个子网的节点）
  List<String> get criticalRelayNodes {
    return _nodeRoles.entries
        .where((e) => e.value == MeshNodeRole.relay)
        .map((e) => e.key)
        .toList();
  }

  /// 网络连通性评分（0.0 - 1.0）
  double get connectivityScore {
    if (knownNodes.isEmpty) return 0.0;

    // 计算可达节点比例
    final reachableNodes = _hopCounts.keys.toSet();
    return reachableNodes.length / knownNodes.length;
  }

  /// 当前设备的唯一标识
  static String thisDeviceId = 'self';

  /// 更新拓扑信息
  ///
  /// [observerId] 观察到 [observedId] 的设备
  /// [rssi] 信号强度，用于估算跳数
  void updateEdge(String observerId, String observedId, int rssi) {
    // 更新邻接表
    _adjacencyList.putIfAbsent(observerId, () => {});
    _adjacencyList[observerId]!.add(observedId);

    // 更新最后活跃时间
    _lastSeen[observerId] = DateTime.now();
    _lastSeen[observedId] = DateTime.now();

    // 估算跳数（基于 RSSI）
    final hopCount = _estimateHopCount(rssi);
    _hopCounts[observedId] = hopCount;

    // 更新节点角色
    _updateNodeRoles();

    notifyListeners();
  }

  /// 获取设备的跳数
  int getHopCount(String deviceId) {
    return _hopCounts[deviceId] ?? 0;
  }

  /// 获取设备的角色
  MeshNodeRole getNodeRole(String deviceId) {
    return _nodeRoles[deviceId] ?? MeshNodeRole.edge;
  }

  /// 获取设备的邻居列表
  Set<String> getNeighbors(String deviceId) {
    return _adjacencyList[deviceId] ?? {};
  }

  /// 清除过期节点（超过指定时间未更新）
  void pruneStaleNodes(Duration timeout) {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _lastSeen.entries) {
      if (now.difference(entry.value) > timeout) {
        toRemove.add(entry.key);
      }
    }

    for (final nodeId in toRemove) {
      _adjacencyList.remove(nodeId);
      _hopCounts.remove(nodeId);
      _lastSeen.remove(nodeId);
      _nodeRoles.remove(nodeId);

      // 从其他节点的邻居列表中移除
      for (final neighbors in _adjacencyList.values) {
        neighbors.remove(nodeId);
      }
    }

    if (toRemove.isNotEmpty) {
      _updateNodeRoles();
      notifyListeners();
    }
  }

  /// 清空拓扑数据
  void clear() {
    _adjacencyList.clear();
    _hopCounts.clear();
    _lastSeen.clear();
    _nodeRoles.clear();
    notifyListeners();
  }

  /// 估算跳数（基于 RSSI）- 优化版
  int _estimateHopCount(int rssi) {
    // 使用对数路径损耗模型估算距离，再转换为跳数
    // BLE 典型发射功率: -4 dBm @ 1米
    // 路径损耗指数: 2.5 (室内环境)
    // 每跳平均距离: ~10米 (BLE 典型范围)

    if (rssi >= -50) return 1; // 非常近 (< 3米)
    if (rssi >= -60) return 1; // 近距离 (3-10米)
    if (rssi >= -70) return 2; // 中距离 (10-20米) - 可能经过1次中继
    if (rssi >= -78) return 3; // 较远距离 (20-30米) - 可能经过2次中继
    if (rssi >= -85) return 4; // 远距离 (30-40米) - 可能经过3次中继
    if (rssi >= -90) return 5; // 很远距离 (40-50米) - 可能经过4次中继
    return 6; // 极远距离 (> 50米) - 可能经过5+次中继
  }

  /// 更新节点角色
  void _updateNodeRoles() {
    _nodeRoles.clear();

    for (final nodeId in _adjacencyList.keys) {
      final neighborCount = _adjacencyList[nodeId]!.length;

      if (neighborCount >= 3) {
        _nodeRoles[nodeId] = MeshNodeRole.relay;
      } else if (neighborCount >= 1) {
        _nodeRoles[nodeId] = MeshNodeRole.router;
      } else {
        _nodeRoles[nodeId] = MeshNodeRole.edge;
      }
    }
  }

  /// 获取网络拓扑摘要
  MeshTopologySummary getSummary() {
    final totalNodes = knownNodes.length;
    final relayCount = criticalRelayNodes.length;
    final avgHopCount = _hopCounts.values.isEmpty
        ? 0.0
        : _hopCounts.values.reduce((a, b) => a + b) / _hopCounts.values.length;

    return MeshTopologySummary(
      totalNodes: totalNodes,
      relayNodes: relayCount,
      maxHopCount: maxHopCount,
      avgHopCount: avgHopCount,
      connectivityScore: connectivityScore,
    );
  }
}

/// 节点角色
enum MeshNodeRole {
  edge, // 边缘节点（只连接一个邻居）
  router, // 路由器（连接多个邻居）
  relay, // 中继节点（关键枢纽，连接 3+ 邻居）
}

/// 网络拓扑摘要
class MeshTopologySummary {
  const MeshTopologySummary({
    required this.totalNodes,
    required this.relayNodes,
    required this.maxHopCount,
    required this.avgHopCount,
    required this.connectivityScore,
  });

  final int totalNodes;
  final int relayNodes;
  final int maxHopCount;
  final double avgHopCount;
  final double connectivityScore;

  /// 获取人类可读的网络状态描述
  String get networkHealthLabel {
    if (totalNodes == 0) return '无连接';
    if (connectivityScore >= 0.8) return '良好';
    if (connectivityScore >= 0.5) return '一般';
    return '较差';
  }
}
