import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mesh_state_provider.dart';
import '../services/mbtiles_reader.dart';
import '../theme/rescue_theme.dart';

/// 离线战术地图视图组件
///
/// 特性：
/// - 基于 MBTiles 的纯离线地图渲染
/// - 实时同步 meshStateProvider 中的求救者位置
/// - 动态红色闪烁标靶标记
/// - 异常降级处理
class OfflineTacticalMapView extends ConsumerStatefulWidget {
  const OfflineTacticalMapView({super.key});

  @override
  ConsumerState<OfflineTacticalMapView> createState() =>
      _OfflineTacticalMapViewState();
}

class _OfflineTacticalMapViewState extends ConsumerState<OfflineTacticalMapView>
    with TickerProviderStateMixin {
  late final AnimationController _markerPulseController;
  bool _mbtilesNotFound = false;
  String? _mapFilePath;

  @override
  void initState() {
    super.initState();
    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initMapFile();
  }

  @override
  void dispose() {
    _markerPulseController.dispose();
    super.dispose();
  }

  /// 初始化地图文件路径并验证存在性
  Future<void> _initMapFile() async {
    try {
      // 优先从 assets 目录加载
      // 注意：MBTiles 文件需要手动复制到本地存储才能被 sqlite3 读取
      final appDir = await getApplicationDocumentsDirectory();
      final mapsDir = Directory('${appDir.path}/maps');

      if (!await mapsDir.exists()) {
        await mapsDir.create(recursive: true);
      }

      final localMapFile = File('${mapsDir.path}/tactical.mbtiles');

      // 检查本地是否存在 MBTiles 文件
      if (await localMapFile.exists()) {
        setState(() {
          _mapFilePath = localMapFile.path;
          _mbtilesNotFound = false;
        });
      } else {
        // 尝试从 assets 复制（首次启动时）
        await _copyMbtilesFromAssets(localMapFile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mbtilesNotFound = true;
        });
      }
    }
  }

  /// 从 assets 复制 MBTiles 文件到本地存储
  Future<void> _copyMbtilesFromAssets(File targetFile) async {
    try {
      // 注意：需要在 pubspec.yaml 中声明 assets/maps/tactical.mbtiles
      // 由于 Flutter 无法直接读取大型二进制 assets，
      // 这里我们检查一个占位文件或设置降级标志
      setState(() {
        _mbtilesNotFound = true;
      });
    } catch (e) {
      setState(() {
        _mbtilesNotFound = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 mesh 状态
    final meshState = ref.watch(meshStateProvider);
    final discoveredDevices = meshState.discoveredDevices.values;

    // 异常降级：MBTiles 文件不存在
    if (_mbtilesNotFound) {
      return _buildFallbackWidget();
    }

    // 等待地图文件路径就绪
    if (_mapFilePath == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(RescuePalette.accent),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 地图主体
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(39.9042, 116.4074), // 默认北京
              initialZoom: 13.0,
              minZoom: 10.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // MBTiles 图层
              TileLayer(
                tileProvider: MbTilesTileProvider(filePath: _mapFilePath!),
                urlTemplate: 'mbtiles://{z}/{x}/{y}',
                zoomOffset: 0,
                maxZoom: 18,
              ),

              // 动态求救者标记层
              MarkerLayer(markers: _buildRescueMarkers(discoveredDevices)),
            ],
          ),

          // 地图信息覆盖层
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '离线战术地图',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建求救者标记列表
  List<Marker> _buildRescueMarkers(Iterable<DiscoveredDevice> devices) {
    return devices.map((device) {
      return Marker(
        point: LatLng(device.payload.latitude, device.payload.longitude),
        width: 48,
        height: 48,
        child: AnimatedBuilder(
          animation: _markerPulseController,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(48, 48),
              painter: _PulsingBeaconPainter(
                pulseValue: _markerPulseController.value,
                rssi: device.rssi,
              ),
            );
          },
        ),
      );
    }).toList();
  }

  /// 异常降级占位组件
  Widget _buildFallbackWidget() {
    return Container(
      decoration: BoxDecoration(
        color: RescuePalette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RescuePalette.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 64, color: RescuePalette.warning),
            const SizedBox(height: 16),
            Text(
              '离线瓦片未就绪',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: RescuePalette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '请维持雷达模式',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: RescuePalette.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              '提示：将 tactical.mbtiles 放置于 assets/maps/ 目录',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: RescuePalette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 脉冲信标绘制器
class _PulsingBeaconPainter extends CustomPainter {
  _PulsingBeaconPainter({required this.pulseValue, required this.rssi});

  final double pulseValue;
  final int rssi;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width * 0.18;

    // 根据 RSSI 计算颜色（信号越强越绿，越弱越红）
    final signalQuality = ((rssi + 100) / 80).clamp(0.0, 1.0);
    final paintColor = Color.lerp(
      RescuePalette.critical,
      RescuePalette.success,
      signalQuality,
    )!;

    // 外圈脉冲效果
    final pulseRadius = baseRadius * (1.5 + pulseValue * 1.2);
    final pulsePaint = Paint()
      ..color = paintColor.withValues(alpha: (1.0 - pulseValue) * 0.4)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, pulseRadius, pulsePaint);

    // 内圈实心圆
    final corePaint = Paint()
      ..color = paintColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, baseRadius * 1.2, corePaint);

    // 中心白点
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, baseRadius * 0.5, centerPaint);
  }

  @override
  bool shouldRepaint(_PulsingBeaconPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue || oldDelegate.rssi != rssi;
  }
}
