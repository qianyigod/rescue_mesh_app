import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mesh_state_provider.dart';
import '../services/mbtiles_reader.dart';
import '../theme/rescue_theme.dart';

/// 离线战术地图视图组件
///
/// 特性：
/// - 基于 MBTiles 的纯离线地图渲染
/// - 在线瓦片自动降级（OpenStreetMap）
/// - 实时同步 meshStateProvider 中的求救者位置
/// - 动态红色闪烁标靶标记
/// - 网络状态自动检测
class OfflineTacticalMapView extends ConsumerStatefulWidget {
  const OfflineTacticalMapView({super.key});

  @override
  ConsumerState<OfflineTacticalMapView> createState() =>
      _OfflineTacticalMapViewState();
}

class _OfflineTacticalMapViewState extends ConsumerState<OfflineTacticalMapView>
    with TickerProviderStateMixin {
  late final AnimationController _markerPulseController;
  bool _useOnlineFallback = false;
  bool _isLoading = true;
  String? _mapFilePath;
  LatLng? _currentPosition;
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initMapFile();
    _checkNetworkStatus();
    _getCurrentLocation();
    _startPositionTracking();
  }

  @override
  void dispose() {
    _markerPulseController.dispose();
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  /// 检查网络连接状态
  Future<void> _checkNetworkStatus() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      // 网络状态用于日志记录和调试
      debugPrint(
        '网络状态: ${connectivityResult != ConnectivityResult.none ? "已连接" : "无连接"}',
      );
    } catch (e) {
      debugPrint('网络状态检查失败: $e');
    }
  }

  /// 获取用户当前位置
  Future<void> _getCurrentLocation({bool moveToCurrent = true}) async {
    if (_isLocating) return;

    try {
      setState(() {
        _isLocating = true;
      });

      // 检查并请求位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('位置权限被拒绝');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('需要位置权限才能定位')));
          }
          return;
        }
      }

      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('位置服务未启用');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先开启位置服务')));
        }
        return;
      }

      // 获取当前位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (mounted) {
        final newPosition = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = newPosition;
        });

        // 移动地图到当前位置
        if (moveToCurrent) {
          try {
            _mapController.move(newPosition, 15.0);
          } catch (e) {
            debugPrint('移动地图失败: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('获取当前位置失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('定位失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  /// 开始持续位置跟踪
  void _startPositionTracking() {
    _positionStreamSubscription?.cancel();

    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // 每移动 10 米更新一次
          ),
        ).listen(
          (Position position) {
            if (!mounted) return;

            final newPosition = LatLng(position.latitude, position.longitude);
            setState(() {
              _currentPosition = newPosition;
            });
          },
          onError: (error) {
            debugPrint('位置跟踪错误: $error');
          },
        );
  }

  /// 初始化地图文件路径并验证存在性
  Future<void> _initMapFile() async {
    try {
      // 优先从本地存储加载 MBTiles 文件
      final appDir = await getApplicationDocumentsDirectory();
      final mapsDir = Directory('${appDir.path}/maps');

      if (!await mapsDir.exists()) {
        await mapsDir.create(recursive: true);
      }

      final localMapFile = File('${mapsDir.path}/tactical.mbtiles');

      // 检查本地是否存在 MBTiles 文件
      if (await localMapFile.exists()) {
        // 验证文件是否可以正常打开
        try {
          final reader = MbtilesReader(filePath: localMapFile.path);
          await reader.open();
          reader.close();

          setState(() {
            _mapFilePath = localMapFile.path;
            _useOnlineFallback = false;
            _isLoading = false;
          });
          return;
        } catch (e) {
          debugPrint('MBTiles 文件损坏，将在在线模式下运行: $e');
        }
      }

      // MBTiles 不存在时，尝试从 assets/maps/ 复制
      await _copyMbtilesFromAssets(localMapFile);
    } catch (e) {
      debugPrint('地图初始化失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _useOnlineFallback = false;
        });
      }
    }
  }

  /// 从 assets/maps/ 复制 MBTiles 文件到本地存储
  Future<void> _copyMbtilesFromAssets(File targetFile) async {
    try {
      // 从 assets/maps/tactical.mbtiles 读取并写入本地存储
      final byteData = await rootBundle.load('assets/maps/tactical.mbtiles');
      final buffer = byteData.buffer.asUint8List();
      await targetFile.writeAsBytes(buffer);

      // 验证复制后的文件
      final reader = MbtilesReader(filePath: targetFile.path);
      await reader.open();
      reader.close();

      setState(() {
        _mapFilePath = targetFile.path;
        _useOnlineFallback = false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('从 assets 复制 MBTiles 失败: $e');
      // 复制失败，检查网络状态决定是否使用在线瓦片
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasNetwork = connectivityResult != ConnectivityResult.none;

      setState(() {
        _useOnlineFallback = hasNetwork;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 mesh 状态
    final meshState = ref.watch(meshStateProvider);
    final discoveredDevices = meshState.discoveredDevices.values;

    // 加载中状态
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(RescuePalette.accent),
        ),
      );
    }

    // 完全降级：无网络且无离线瓦片
    if (!_useOnlineFallback && _mapFilePath == null) {
      return _buildFallbackWidget();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // 地图主体
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentPosition ?? const LatLng(39.9042, 116.4074),
              initialZoom: _currentPosition != null ? 15.0 : 13.0,
              minZoom: 10.0,
              maxZoom: _useOnlineFallback ? 19.0 : 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // 瓦片图层：离线 MBTiles 或在线 OSM
              if (_useOnlineFallback)
                _buildOnlineTileLayer()
              else
                TileLayer(
                  tileProvider: MbTilesTileProvider(filePath: _mapFilePath!),
                  urlTemplate: 'mbtiles://{z}/{x}/{y}',
                  zoomOffset: 0,
                  maxZoom: 18,
                ),

              // 当前位置标记
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: RescuePalette.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: RescuePalette.accent.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

              // 动态求救者标记层
              MarkerLayer(markers: _buildRescueMarkers(discoveredDevices)),
            ],
          ),

          // 地图信息覆盖层
          Positioned(
            top: 12,
            right: 12,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _useOnlineFallback ? Icons.cloud : Icons.cloud_off,
                        size: 14,
                        color: _useOnlineFallback
                            ? RescuePalette.success
                            : RescuePalette.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _useOnlineFallback ? '在线地图' : '离线战术地图',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 定位按钮
                GestureDetector(
                  onTap: () => _getCurrentLocation(moveToCurrent: true),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLocating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                RescuePalette.accent,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.my_location,
                            size: 18,
                            color: _currentPosition != null
                                ? RescuePalette.accent
                                : Colors.white70,
                          ),
                  ),
                ),
              ],
            ),
          ),

          // 地图出处标注
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _useOnlineFallback
                    ? '© 高德地图 | © OpenStreetMap contributors'
                    : '© 离线战术地图 | MBTiles',
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建在线瓦片图层（降级方案）
  /// 使用高德地图作为国内瓦片源，解决 OpenStreetMap 在国内访问受限导致灰屏的问题
  Widget _buildOnlineTileLayer() {
    return TileLayer(
      // 高德地图瓦片源（支持中文标注，国内访问稳定）
      // s 参数为子域名 {1,2,3,4}，用于负载均衡
      urlTemplate:
          'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
      subdomains: const ['1', '2', '3', '4'],
      userAgentPackageName: 'com.rescuemesh.app',
      maxZoom: 18,
      tileProvider: NetworkTileProvider(),
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
              '请维持雷达模式或检查网络连接',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: RescuePalette.textMuted),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '提示：将 tactical.mbtiles 放置于 assets/maps/ 目录以启用离线模式',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: RescuePalette.textMuted),
                textAlign: TextAlign.center,
              ),
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
