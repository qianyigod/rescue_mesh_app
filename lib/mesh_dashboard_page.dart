import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location/location.dart';

import 'ar_rescue_compass_page.dart';
import 'models/emergency_profile.dart';
import 'models/mesh_state_provider.dart';
import 'models/sos_message.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/power_saving_manager.dart';
import 'theme/rescue_theme.dart';
import 'widgets/offline_tactical_map_view.dart';
import 'widgets/sonar_radar_widget.dart';

class MeshDashboardPage extends StatefulWidget {
  MeshDashboardPage({
    super.key,
    BleMeshService? sosService,
    BleScannerService? scannerService,
  }) : sosService = sosService ?? bleMeshService,
       scannerService = scannerService ?? bleScannerService;

  final BleMeshService sosService;
  final BleScannerService scannerService;

  @override
  State<MeshDashboardPage> createState() => _MeshDashboardPageState();
}

class _MeshDashboardPageState extends State<MeshDashboardPage>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _radarController;
  late final Listenable _servicesListenable;

  String? _actionStatus;
  Stream<SosMessage>? _sosStream;

  // [新增] 视图模式切换：false = 雷达模式，true = 地图模式
  bool _isMapView = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _servicesListenable = Listenable.merge([
      widget.sosService,
      widget.scannerService,
    ]);
    _sosStream = widget.scannerService.sosMessageStream;

    widget.sosService.init().catchError((_) {});
    widget.scannerService.init().catchError((_) {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _toggleSosBroadcast() async {
    if (widget.sosService.isBroadcastingNow) {
      try {
        await widget.sosService.stopSosBroadcast();
        if (!mounted) {
          return;
        }
        setState(() {
          _actionStatus = 'SOS 广播已停止。';
        });
      } on BleMeshException catch (error) {
        _showError(error.message);
      }
      return;
    }

    try {
      setState(() {
        _actionStatus = '正在获取定位并准备发起 SOS 广播...';
      });

      final location = Location();
      var serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          throw const BleMeshPlatformException(
            platformCode: 'location_service_disabled',
            message: '定位服务未开启，无法广播当前位置。',
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
          message: '定位权限未授予，无法发起带坐标的 SOS 广播。',
        );
      }

      final locationData = await powerSavingManager.acquireLocationFix(
        location: location,
      );
      final latitude = locationData.latitude;
      final longitude = locationData.longitude;
      if (latitude == null || longitude == null) {
        throw const BleMeshPlatformException(
          platformCode: 'location_unavailable',
          message: '当前定位结果不可用，请稍后再试。',
        );
      }

      await widget.sosService.startSosBroadcast(
        latitude: latitude,
        longitude: longitude,
        bloodType: EmergencyProfile.current.bloodType,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _actionStatus =
            'SOS 广播已发出。纬度 ${latitude.toStringAsFixed(5)}，经度 ${longitude.toStringAsFixed(5)}。';
      });
    } on BleMeshException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('发起 SOS 广播失败：$error');
    }
  }

  Future<void> _toggleRadarScanning() async {
    if (widget.scannerService.isScanning) {
      try {
        await widget.scannerService.stopScanning();
        if (!mounted) {
          return;
        }
        setState(() {
          _actionStatus = '雷达扫描已停止。';
        });
      } on BleMeshException catch (error) {
        _showError(error.message);
      }
      return;
    }

    try {
      await widget.scannerService.startScanning();
      if (!mounted) {
        return;
      }
      setState(() {
        _actionStatus = '雷达扫描已启动，正在监听附近的 SOS 信标。';
      });
    } on BleMeshException catch (error) {
      _showError(error.message);
    }
  }

  void _openArRescueCompass() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArRescueCompassPage(
          targetLatitude: 0.0,
          targetLongitude: 0.0,
          targetName: 'AR 导航',
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _actionStatus = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: RescuePalette.critical, content: Text(message)),
    );
  }

  double _estimateDistanceMeters(int rssi) {
    const txPower = -59.0;
    const pathLoss = 2.2;
    final ratio = (txPower - rssi) / (10 * pathLoss);
    return math.pow(10, ratio).toDouble();
  }

  String _formatDistance(int rssi) {
    final meters = _estimateDistanceMeters(rssi);
    if (!meters.isFinite || meters <= 0) {
      return '距离未知';
    }
    if (meters < 1) {
      return '约 ${(meters * 100).round()} 厘米';
    }
    if (meters < 1000) {
      return '约 ${meters.toStringAsFixed(1)} 米';
    }
    return '约 ${(meters / 1000).toStringAsFixed(2)} 公里';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _servicesListenable,
      builder: (context, _) {
        final bluetoothReady =
            widget.sosService.isAdapterReady ||
            widget.scannerService.isAdapterReady;
        final permissionsReady =
            widget.sosService.permissionsGranted &&
            widget.scannerService.permissionsGranted;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7FAFC), Color(0xFFF0F5F7), Color(0xFFE7EEF2)],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: RescuePalette.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: RescuePalette.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: bluetoothReady
                                  ? RescuePalette.success
                                  : RescuePalette.critical,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '救援系统现场终端',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatusPill(
                            label: '蓝牙',
                            value: bluetoothReady ? '已开启' : '未开启',
                            tone: bluetoothReady
                                ? RescuePalette.success
                                : RescuePalette.critical,
                          ),
                          _StatusPill(
                            label: '权限',
                            value: permissionsReady ? '已就绪' : '未完成',
                            tone: permissionsReady
                                ? RescuePalette.success
                                : RescuePalette.critical,
                          ),
                          _StatusPill(
                            label: '广播',
                            value: widget.sosService.isBroadcastingNow
                                ? '呼救中'
                                : '待命',
                            tone: widget.sosService.isBroadcastingNow
                                ? RescuePalette.critical
                                : RescuePalette.textMuted,
                          ),
                          _StatusPill(
                            label: '雷达',
                            value: widget.scannerService.isScanning
                                ? '扫描中'
                                : '静默',
                            tone: widget.scannerService.isScanning
                                ? RescuePalette.success
                                : RescuePalette.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                StreamBuilder<SosMessage>(
                  stream: _sosStream,
                  builder: (context, snapshot) {
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: RescuePalette.panel,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: snapshot.hasData
                              ? RescuePalette.critical
                              : RescuePalette.border,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '雷达监测区',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                ),
                              ),
                              // [新增] 视图切换按钮
                              IconButton(
                                icon: Icon(
                                  _isMapView ? Icons.radar : Icons.map,
                                  color: _isMapView
                                      ? RescuePalette.accent
                                      : RescuePalette.success,
                                ),
                                tooltip: _isMapView ? '切换到雷达模式' : '切换到地图模式',
                                onPressed: () {
                                  setState(() {
                                    _isMapView = !_isMapView;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_isMapView)
                            // [新增] 地图模式
                            SizedBox(
                              height: 280,
                              child: OfflineTacticalMapView(),
                            )
                          else
                            // [原有] 雷达模式
                            StreamBuilder<SosMessage>(
                              stream: _sosStream,
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return _RadarSilentPanel(
                                    controller: _radarController,
                                    isScanning:
                                        widget.scannerService.isScanning,
                                  );
                                } else {
                                  return _SosAlertCard(
                                    message: snapshot.data!,
                                    distanceText: _formatDistance(
                                      snapshot.data!.rssi,
                                    ),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                if (_actionStatus != null ||
                    widget.sosService.lastError != null ||
                    widget.scannerService.lastError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: RescuePalette.panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: RescuePalette.border),
                    ),
                    child: Text(
                      _actionStatus ??
                          widget.sosService.lastError ??
                          widget.scannerService.lastError ??
                          '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RescuePalette.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        controller: _pulseController,
                        icon: Icons.sos,
                        title: widget.sosService.isBroadcastingNow
                            ? '正在呼救...'
                            : '发起 SOS 广播',
                        subtitle: widget.sosService.isBroadcastingNow
                            ? '点击停止广播'
                            : '向附近终端发出求救信标',
                        active: widget.sosService.isBroadcastingNow,
                        activeColor: RescuePalette.critical,
                        idleBackground: RescuePalette.criticalSoft,
                        iconColor: RescuePalette.critical,
                        onTap: _toggleSosBroadcast,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ActionButton(
                        controller: _pulseController,
                        icon: Icons.radar,
                        title: widget.scannerService.isScanning
                            ? '扫描中...'
                            : '开启雷达扫描',
                        subtitle: widget.scannerService.isScanning
                            ? '点击停止扫描'
                            : '发现附近求救者信标',
                        active: widget.scannerService.isScanning,
                        activeColor: RescuePalette.success,
                        idleBackground: RescuePalette.successSoft,
                        iconColor: RescuePalette.success,
                        onTap: _toggleRadarScanning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        controller: _pulseController,
                        icon: Icons.explore,
                        title: 'AR 救援罗盘',
                        subtitle: '使用 AR 技术导航至求救者位置',
                        active: false,
                        activeColor: RescuePalette.accent,
                        idleBackground: RescuePalette.accentSoft,
                        iconColor: RescuePalette.accent,
                        onTap: _openArRescueCompass,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: RescuePalette.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RescuePalette.border),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: RescuePalette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: tone, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarSilentPanel extends StatelessWidget {
  const _RadarSilentPanel({required this.controller, required this.isScanning});

  final AnimationController controller;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 280,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final progress = controller.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final base in [0.2, 0.45, 0.7])
                    Transform.scale(
                      scale: 0.6 + ((progress + base) % 1.0) * 0.9,
                      child: Opacity(
                        opacity: 0.10 + (1 - ((progress + base) % 1.0)) * 0.18,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: RescuePalette.success.withValues(
                                alpha: 0.32,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF6FBF8),
                      border: Border.all(color: RescuePalette.border),
                    ),
                  ),
                  Transform.rotate(
                    angle: progress * math.pi * 2,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            RescuePalette.success.withValues(alpha: 0.0),
                            RescuePalette.success.withValues(alpha: 0.0),
                            RescuePalette.success.withValues(alpha: 0.12),
                            RescuePalette.success.withValues(alpha: 0.42),
                          ],
                          stops: const [0.0, 0.55, 0.82, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: RescuePalette.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Text(
          isScanning ? '雷达静默，周边安全' : '雷达待机，点击下方按钮开始扫描',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: isScanning ? RescuePalette.success : RescuePalette.textMuted,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isScanning ? '正在扫描周边区域，等待求救信号...' : '扫描启动后，这里会实时显示附近的求救卡片',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: RescuePalette.textMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SosAlertCard extends StatelessWidget {
  const _SosAlertCard({required this.message, required this.distanceText});

  final SosMessage message;
  final String distanceText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCE9EA), Color(0xFFF7D7D9), Color(0xFFF2C6CA)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RescuePalette.critical),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: RescuePalette.critical,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '发现附近有人求救！',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: RescuePalette.critical,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AlertMetric(label: '距离估算', value: distanceText),
              _AlertMetric(label: 'RSSI', value: '${message.rssi} dBm'),
              _AlertMetric(label: '血型', value: message.bloodType.label),
              _AlertMetric(
                label: '坐标',
                value:
                    '${message.latitude.toStringAsFixed(5)}, ${message.longitude.toStringAsFixed(5)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '设备 ID：${message.remoteId}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: RescuePalette.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            '接收时间：${message.receivedAt.toLocal()}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: RescuePalette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AlertMetric extends StatelessWidget {
  const _AlertMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RescuePalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: RescuePalette.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: RescuePalette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.controller,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.activeColor,
    required this.idleBackground,
    required this.iconColor,
    required this.onTap,
  });

  final AnimationController controller;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final Color activeColor;
  final Color idleBackground;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final glow = active ? 0.14 + (controller.value * 0.14) : 0.0;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              height: 164,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withValues(alpha: 0.16)
                    : idleBackground,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: active ? activeColor : RescuePalette.border,
                  width: active ? 1.6 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withValues(alpha: glow),
                    blurRadius: active ? 24 : 0,
                    spreadRadius: active ? 2 : 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: active ? activeColor : iconColor, size: 34),
                  const Spacer(),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: RescuePalette.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RescuePalette.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
