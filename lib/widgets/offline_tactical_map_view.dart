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
class OfflineTacticalMapView extends ConsumerStatefulWidget {
  const OfflineTacticalMapView({super.key});

  @override
  ConsumerState<OfflineTacticalMapView> createState() =>
      _OfflineTacticalMapViewState();
}

class _OfflineTacticalMapViewState extends ConsumerState<OfflineTacticalMapView>
    with TickerProviderStateMixin {
  static const String _expectedOfflineMapName = 'Rescue Mesh Tactical Grid';
  static const String _tiandituApiKey = 'd9f8596e7de371267b98dd849fa6321a';
  static const String _tiandituSourceLabel = '地图来源：国家地理信息公共服务平台（天地图）';
  static const String _tiandituApprovalLabel = '审图号：GS（2025）1508号';

  late final AnimationController _markerPulseController;
  bool _useOnlineFallback = false;
  bool _isLoading = true;
  String? _mapFilePath;
  LatLng? _offlineMapCenter;
  double _offlineInitialZoom = 13.0;
  double _offlineMinZoom = 10.0;
  double _offlineMaxZoom = 16.0;
  double _offlineMinNativeZoom = 10.0;
  double _offlineMaxNativeZoom = 16.0;
  String _mapAttributionLabel = '地图来源待识别';
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
      final hasNetwork = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );
      // 网络状态仅用于日志记录和调试
      debugPrint('网络状态: ${hasNetwork ? "已连接" : "无连接"}');
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

  /// 初始化地图文件路径并验证可用性
  Future<void> _initMapFile() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasNetwork = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );

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
          if (!_isExpectedOfflineMap(reader)) {
            reader.close();
            await _copyMbtilesFromAssets(localMapFile);
            return;
          }
          final center = reader.center;
          final minZoom = reader.minZoom;
          final maxZoom = reader.maxZoom;
          final attribution = _offlineAttributionForReader(reader);
          reader.close();

          setState(() {
            _mapFilePath = localMapFile.path;
            _offlineMapCenter = center;
            _offlineMinNativeZoom = minZoom.toDouble();
            _offlineMaxNativeZoom = maxZoom.toDouble();
            _offlineMinZoom = (minZoom - 1).clamp(1, minZoom).toDouble();
            _offlineMaxZoom = (maxZoom + 2).toDouble();
            _offlineInitialZoom = maxZoom >= 15 ? 15.0 : maxZoom.toDouble();
            _mapAttributionLabel = attribution;
            _useOnlineFallback = hasNetwork && _hasTiandituApiKey;
            _isLoading = false;
          });
          _moveToOfflineCenterIfNeeded();
          return;
        } catch (e) {
          debugPrint('MBTiles 文件损坏，将切换到在线模式: $e');
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
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasNetwork = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );

      // 从 assets/maps/tactical.mbtiles 读取并写入本地存储
      final byteData = await rootBundle.load('assets/maps/tactical.mbtiles');
      final buffer = byteData.buffer.asUint8List();
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await targetFile.writeAsBytes(buffer);

      // 验证复制后的文件
      final reader = MbtilesReader(filePath: targetFile.path);
      await reader.open();
      final center = reader.center;
      final minZoom = reader.minZoom;
      final maxZoom = reader.maxZoom;
      final attribution = _offlineAttributionForReader(reader);
      reader.close();

      setState(() {
        _mapFilePath = targetFile.path;
        _offlineMapCenter = center;
        _offlineMinNativeZoom = minZoom.toDouble();
        _offlineMaxNativeZoom = maxZoom.toDouble();
        _offlineMinZoom = (minZoom - 1).clamp(1, minZoom).toDouble();
        _offlineMaxZoom = (maxZoom + 2).toDouble();
        _offlineInitialZoom = maxZoom >= 15 ? 15.0 : maxZoom.toDouble();
        _mapAttributionLabel = attribution;
        _useOnlineFallback = hasNetwork && _hasTiandituApiKey;
        _isLoading = false;
      });
      _moveToOfflineCenterIfNeeded();
    } catch (e) {
      debugPrint('从 assets 复制 MBTiles 失败: $e');
      // 复制失败后，检查网络状态决定是否使用在线瓦片
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasNetwork = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );

      setState(() {
        _useOnlineFallback = hasNetwork && _hasTiandituApiKey;
        _mapAttributionLabel = _onlineAttributionLabel();
        _isLoading = false;
      });
    }
  }

  String _offlineAttributionForReader(MbtilesReader reader) {
    final rawAttribution = reader.attribution?.trim();
    if (rawAttribution != null && rawAttribution.isNotEmpty) {
      if (rawAttribution.contains('Tianditu') ||
          rawAttribution.contains('Map source: Tianditu')) {
        return '$_tiandituSourceLabel\n$_tiandituApprovalLabel';
      }
      return rawAttribution;
    }

    final mapName = reader.name?.trim();
    if (mapName != null && mapName.isNotEmpty) {
      return '$mapName\n$_tiandituSourceLabel\n$_tiandituApprovalLabel';
    }

    return '$_tiandituSourceLabel\n$_tiandituApprovalLabel';
  }

  String _onlineAttributionLabel() {
    return '$_tiandituSourceLabel\n$_tiandituApprovalLabel';
  }

  bool _isExpectedOfflineMap(MbtilesReader reader) {
    final mapName = reader.name?.trim();
    if (mapName == _expectedOfflineMapName) {
      return true;
    }

    final attribution = reader.attribution ?? '';
    return attribution.contains('Tianditu') ||
        attribution.contains('国家地理信息公共服务平台');
  }

  bool get _hasTiandituApiKey => _tiandituApiKey.trim().isNotEmpty;

  void _moveToOfflineCenterIfNeeded() {
    if (_currentPosition != null || _offlineMapCenter == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _offlineMapCenter == null) {
        return;
      }

      try {
        _mapController.move(_offlineMapCenter!, _offlineInitialZoom);
      } catch (e) {
        debugPrint('移动到离线地图中心失败: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final meshState = ref.watch(meshStateProvider);
    final discoveredDevices = meshState.discoveredDevices.values;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(RescuePalette.accent),
        ),
      );
    }

    if (!_useOnlineFallback && _mapFilePath == null) {
      return _buildFallbackWidget();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  _currentPosition ??
                  _offlineMapCenter ??
                  const LatLng(20.02, 110.35),
              initialZoom: _currentPosition != null
                  ? 15.0
                  : _offlineInitialZoom,
              minZoom: _useOnlineFallback ? 3.0 : _offlineMinZoom,
              maxZoom: _useOnlineFallback ? 19.0 : _offlineMaxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              if (_useOnlineFallback)
                ..._buildOnlineTileLayers()
              else
                TileLayer(
                  tileProvider: MbTilesTileProvider(filePath: _mapFilePath!),
                  urlTemplate: 'mbtiles://{z}/{x}/{y}',
                  zoomOffset: 0,
                  minZoom: _offlineMinZoom,
                  maxZoom: _offlineMaxZoom,
                  minNativeZoom: _offlineMinNativeZoom.toInt(),
                  maxNativeZoom: _offlineMaxNativeZoom.toInt(),
                ),

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

              MarkerLayer(markers: _buildRescueMarkers(discoveredDevices)),
            ],
          ),

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
                        _useOnlineFallback ? '在线地图' : '离线地图',
                        style: const TextStyle(
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
            left: 10,
            right: 10,
            bottom: 10,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 2),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 320),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _useOnlineFallback
                        ? _onlineAttributionLabel()
                        : _mapAttributionLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOnlineTileLayers() {
    if (!_hasTiandituApiKey) {
      return const <Widget>[];
    }

    return <Widget>[
      _buildTiandituLayer(layerId: 'vec', layerGroup: 'vec_w', zIndex: 1),
      _buildTiandituLayer(layerId: 'cva', layerGroup: 'cva_w', zIndex: 2),
    ];
  }

  Widget _buildTiandituLayer({
    required String layerId,
    required String layerGroup,
    required int zIndex,
  }) {
    return TileLayer(
      urlTemplate:
          'https://t{s}.tianditu.gov.cn/$layerGroup/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
          '&LAYER=$layerId&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
          '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$_tiandituApiKey',
      subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
      userAgentPackageName: 'com.rescuemesh.app',
      maxZoom: 18,
      tileProvider: NetworkTileProvider(),
      panBuffer: 0,
      additionalOptions: <String, String>{'zIndex': '$zIndex'},
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
        border: const Border.fromBorderSide(
          BorderSide(color: RescuePalette.border),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.map_outlined,
              size: 64,
              color: RescuePalette.warning,
            ),
            const SizedBox(height: 16),
            Text(
              _hasTiandituApiKey ? '离线瓦片未就绪' : '未配置天地图 Key',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: RescuePalette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _hasTiandituApiKey
                  ? '请先准备离线地图包，或在联网状态下使用天地图在线底图。'
                  : '启动时请通过 --dart-define=TIANDITU_API_KEY=你的天地图Key 配置在线底图。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RescuePalette.textMuted,
                height: 1.5,
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

    // 根据 RSSI 计算颜色，信号越强越偏绿，越弱越偏红。
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
