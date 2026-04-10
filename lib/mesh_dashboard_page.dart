import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ar_rescue_compass_page.dart';
import 'models/emergency_profile.dart';
import 'models/sos_message.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/sos_trigger_service.dart';
import 'services/rssi_ranging_engine.dart';
import 'theme/rescue_theme.dart';
import 'widgets/offline_tactical_map_view.dart';

class MeshDashboardPage extends StatefulWidget {
  MeshDashboardPage({
    super.key,
    BleMeshService? sosService,
    BleScannerService? scannerService,
    this.onRadarRequested,
  }) : sosService = sosService ?? bleMeshService,
       scannerService = scannerService ?? bleScannerService;

  final BleMeshService sosService;
  final BleScannerService scannerService;
  final Future<void> Function()? onRadarRequested;

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

      final result = await sosTriggerService.triggerSos(
        bleService: widget.sosService,
        bloodType: EmergencyProfile.current.bloodType,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        if (result.uploadedToCommandCenter && result.broadcastStarted) {
          _actionStatus =
              'SOS 已广播并成功上传到指挥中心。纬度 ${result.latitude.toStringAsFixed(5)}，经度 ${result.longitude.toStringAsFixed(5)}。';
        } else if (result.uploadedToCommandCenter && result.bleError != null) {
          _actionStatus = 'SOS 已上传到指挥中心，但本地 BLE 广播失败：${result.bleError}';
        } else if (result.syncError != null && result.broadcastStarted) {
          _actionStatus =
              'SOS 已广播，但联网上传失败：${result.syncError}。数据已保存，恢复联网后会自动重试。';
        } else if (result.syncError != null && result.bleError != null) {
          _actionStatus =
              'SOS 已保存到本地，但 BLE 广播和联网上传都失败了。BLE：${result.bleError}；网络：${result.syncError}';
        } else {
          _actionStatus =
              'SOS 已保存。纬度 ${result.latitude.toStringAsFixed(5)}，经度 ${result.longitude.toStringAsFixed(5)}。';
        }
      });
    } on BleMeshException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('发起 SOS 广播失败：$error');
    }
  }

  Future<void> _toggleRadarScanning() async {
    if (widget.onRadarRequested != null) {
      await widget.onRadarRequested!.call();
      if (!mounted) {
        return;
      }
      setState(() {
        _actionStatus = widget.scannerService.isScanning
            ? '雷达页已打开，扫描正在运行。'
            : '雷达扫描已停止，请检查蓝牙与权限状态后重新启动。';
      });
      return;
    }

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

  void _openArRescueCompass({
    double? targetLatitude,
    double? targetLongitude,
    String? targetName,
    int? targetRssi,
  }) {
    if (targetLatitude == null || targetLongitude == null) {
      _showError('请先在雷达列表中选择带坐标的目标，再打开 AR 搜救罗盘。');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArRescueCompassPage(
          targetLatitude: targetLatitude,
          targetLongitude: targetLongitude,
          targetName: targetName ?? 'AR 导航',
          targetRssi: targetRssi ?? -70,
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

  String _formatDistance(int rssi) {
    final rangingEngine = RssiRangingEngine.instance();
    final result = rangingEngine.estimateDistance(rssi);
    final meters = result.estimatedDistance;

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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: snapshot.hasData
                              ? RescuePalette.critical.withValues(alpha: 0.3)
                              : RescuePalette.border,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 20,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题栏
                          Row(
                            children: [
                              // 标题
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: snapshot.hasData
                                        ? const [
                                            Color(0xFFFF6B6B),
                                            Color(0xFFEE5A5A),
                                          ]
                                        : const [
                                            Color(0xFF2DD4A0),
                                            Color(0xFF20B88A),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (snapshot.hasData
                                                  ? RescuePalette.critical
                                                  : RescuePalette.success)
                                              .withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isMapView
                                          ? Icons.map_outlined
                                          : Icons.radar,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isMapView ? '战术地图' : '雷达监测',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // 视图切换按钮
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 雷达模式按钮
                                    GestureDetector(
                                      onTap: () {
                                        if (_isMapView) {
                                          setState(() {
                                            _isMapView = false;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: !_isMapView
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: !_isMapView
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Icon(
                                          Icons.radar,
                                          size: 18,
                                          color: !_isMapView
                                              ? RescuePalette.success
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                    // 地图模式按钮
                                    GestureDetector(
                                      onTap: () {
                                        if (!_isMapView) {
                                          setState(() {
                                            _isMapView = true;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _isMapView
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: _isMapView
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Icon(
                                          Icons.map_outlined,
                                          size: 18,
                                          color: _isMapView
                                              ? RescuePalette.accent
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_isMapView)
                            // [新增] 地图模式
                            Container(
                              height: 280,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: const OfflineTacticalMapView(),
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
                        title: 'AR 搜救罗盘',
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
        // 雷达容器 - 精致声纳扫描屏幕
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return CustomPaint(
              size: const Size(220, 220),
              painter: _SonarRadarPainter(
                sweepAngle: controller.value * math.pi * 2,
                isScanning: isScanning,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 简约风格雷达绘制器
class _SonarRadarPainter extends CustomPainter {
  _SonarRadarPainter({required this.sweepAngle, required this.isScanning});

  final double sweepAngle;
  final bool isScanning;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 4;

    final linePaint = Paint()
      ..color = const Color(0xFF9CA3AF).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // 外圈
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = const Color(0xFF9CA3AF).withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 同心圆
    for (int i = 1; i <= 3; i++) {
      final r = radius * i / 3;
      canvas.drawCircle(Offset(cx, cy), r, linePaint);
    }

    // 十字线
    canvas.drawLine(
      Offset(cx, cy - radius),
      Offset(cx, cy + radius),
      linePaint,
    );
    canvas.drawLine(
      Offset(cx - radius, cy),
      Offset(cx + radius, cy),
      linePaint,
    );

    // 扫描线
    if (isScanning) {
      canvas.drawLine(
        Offset(cx, cy),
        Offset(
          cx + radius * math.cos(sweepAngle),
          cy + radius * math.sin(sweepAngle),
        ),
        Paint()
          ..color = const Color(0xFF3B82F6).withValues(alpha: 0.6)
          ..strokeWidth = 1.5,
      );
    }

    // 简约方向标记
    final cardinals = [
      ('N', -math.pi / 2, const Color(0xFFEF4444)),
      ('E', 0.0, const Color(0xFF9CA3AF)),
      ('S', math.pi / 2, const Color(0xFF9CA3AF)),
      ('W', math.pi, const Color(0xFF9CA3AF)),
    ];

    for (final (letter, angle, color) in cardinals) {
      final labelR = radius - 10;
      final x = cx + labelR * math.cos(angle);
      final y = cy + labelR * math.sin(angle);

      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    // 中心点
    canvas.drawCircle(
      Offset(cx, cy),
      2,
      Paint()..color = const Color(0xFF9CA3AF),
    );
  }

  @override
  bool shouldRepaint(_SonarRadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle;
  }
}

class _SosAlertCard extends StatelessWidget {
  const _SosAlertCard({required this.message, required this.distanceText});

  final SosMessage message;
  final String distanceText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF0F0), Color(0xFFFDE8E8), Color(0xFFFCD8D8)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: RescuePalette.critical.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: RescuePalette.critical.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏
          Row(
            children: [
              // 脉冲警告图标
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: 1.15),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                builder: (_, value, __) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: RescuePalette.critical.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: RescuePalette.critical,
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现附近求救信号！',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: RescuePalette.critical,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      '请及时响应并提供援助',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RescuePalette.critical.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          // 指标网格
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AlertMetric(
                icon: Icons.near_me,
                label: '距离估算',
                value: distanceText,
              ),
              _AlertMetric(
                icon: Icons.signal_cellular_alt,
                label: '信号强度',
                value: '${message.rssi} dBm',
              ),
              _AlertMetric(
                icon: Icons.bloodtype_outlined,
                label: '血型',
                value: message.bloodType.label,
              ),
              _AlertMetric(
                icon: Icons.location_on_outlined,
                label: '坐标',
                value:
                    '${message.latitude.toStringAsFixed(5)}, ${message.longitude.toStringAsFixed(5)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 底部信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '设备: ${message.remoteId}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RescuePalette.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatRelativeTime(message.receivedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: RescuePalette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化相对时间
  String _formatRelativeTime(DateTime receivedAt) {
    final diff = DateTime.now().difference(receivedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m前';
    return '${diff.inHours}h前';
  }
}

class _AlertMetric extends StatelessWidget {
  const _AlertMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: RescuePalette.critical.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: RescuePalette.critical),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RescuePalette.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
