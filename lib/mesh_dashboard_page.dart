import 'package:flutter/material.dart';

import 'models/emergency_profile.dart';
import 'models/sos_message.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/rssi_ranging_engine.dart';
import 'services/sos_trigger_service.dart';
import 'theme/rescue_theme.dart';
import 'widgets/sonar_radar_widget.dart';

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
  late final Listenable _servicesListenable;

  String? _actionStatus;
  Stream<SosMessage>? _sosStream;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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
        _actionStatus = '正在获取位置并准备发起 SOS 广播...';
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
              'SOS 已广播并上传到指挥中心。纬度 ${result.latitude.toStringAsFixed(5)}，经度 ${result.longitude.toStringAsFixed(5)}。';
        } else if (result.uploadedToCommandCenter && result.bleError != null) {
          _actionStatus = 'SOS 已上传到指挥中心，但本地 BLE 广播失败：${result.bleError}';
        } else if (result.syncError != null && result.broadcastStarted) {
          _actionStatus = 'SOS 已广播，但联网上传失败：${result.syncError}。网络恢复后会继续重试。';
        } else if (result.syncError != null && result.bleError != null) {
          _actionStatus =
              'SOS 已保存到本地，但 BLE 广播和联网上传都失败。BLE：${result.bleError}；网络：${result.syncError}';
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
            ? '已切到雷达页，扫描正在运行。'
            : '雷达未运行，请检查蓝牙和权限后重试。';
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
    final result = RssiRangingEngine.instance().estimateDistance(rssi);
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
                            'Rescue Mesh 现场终端',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
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
                                ? '求救中'
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
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: RescuePalette.border),
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2DD4A0), Color(0xFF20B88A)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.radar,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '雷达入口',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            widget.scannerService.isScanning ? '运行中' : '待启动',
                            style: TextStyle(
                              color: widget.scannerService.isScanning
                                  ? RescuePalette.success
                                  : RescuePalette.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Center(child: MiniSonarRadarWidget(size: 180)),
                      const SizedBox(height: 14),
                      const Text(
                        '搜寻逻辑已统一到雷达页。进入雷达后，系统会根据锁定目标的 RSSI/测距结果加快滴滴节奏。',
                        style: TextStyle(
                          color: RescuePalette.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                StreamBuilder<SosMessage>(
                  stream: _sosStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: RescuePalette.border),
                        ),
                        child: const Text(
                          '当前没有新的求救信号。启动雷达扫描后，这里会优先显示最近一次 SOS 事件。',
                          style: TextStyle(
                            color: RescuePalette.textMuted,
                            height: 1.5,
                          ),
                        ),
                      );
                    }

                    final message = snapshot.data!;
                    return _SosAlertCard(
                      message: message,
                      distanceText: _formatDistance(message.rssi),
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
                            ? '正在求救...'
                            : '发起 SOS 广播',
                        subtitle: widget.sosService.isBroadcastingNow
                            ? '点击停止广播'
                            : '向附近终端发送求救信标',
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
                            ? '进入雷达中'
                            : '打开雷达搜寻',
                        subtitle: widget.scannerService.isScanning
                            ? '点击继续查看锁定目标'
                            : '锁定信号源并用滴滴节奏搜寻',
                        active: widget.scannerService.isScanning,
                        activeColor: RescuePalette.success,
                        idleBackground: RescuePalette.successSoft,
                        iconColor: RescuePalette.success,
                        onTap: _toggleRadarScanning,
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
          Row(
            children: [
              Container(
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发现附近求救信号',
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
