import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/mesh_state_provider.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_scanner_service.dart';
import 'theme/rescue_theme.dart';
import 'widgets/sonar_radar_widget.dart';

class RadarDemoPage extends ConsumerStatefulWidget {
  const RadarDemoPage({super.key, this.isActive = false});

  final bool isActive;

  @override
  ConsumerState<RadarDemoPage> createState() => _RadarDemoPageState();
}

class _RadarDemoPageState extends ConsumerState<RadarDemoPage> {
  Timer? _feedbackTimer;
  DateTime? _lastFeedbackAt;
  DateTime? _lastHapticAt;
  String? _selectedDeviceId;
  bool _followNearest = true;
  bool _feedbackEnabled = true;
  DiscoveredDevice? _trackedDevice;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _feedbackTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => _emitSearchFeedback(),
    );
  }

  @override
  void didUpdateWidget(covariant RadarDemoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _lastFeedbackAt = null;
      _lastHapticAt = null;
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _emitSearchFeedback() async {
    final device = _trackedDevice;
    if (!widget.isActive ||
        !_feedbackEnabled ||
        !_isScanning ||
        device == null) {
      _lastFeedbackAt = null;
      _lastHapticAt = null;
      return;
    }

    if (DateTime.now().difference(device.lastUpdatedAt) >
        const Duration(seconds: 5)) {
      _lastFeedbackAt = null;
      _lastHapticAt = null;
      return;
    }

    final profile = _feedbackProfileFor(device);
    final now = DateTime.now();
    if (_lastFeedbackAt != null &&
        now.difference(_lastFeedbackAt!).inMilliseconds < profile.intervalMs) {
      return;
    }

    _lastFeedbackAt = now;
    unawaited(SystemSound.play(SystemSoundType.click));

    if (!profile.enableHaptic) {
      return;
    }

    if (_lastHapticAt == null ||
        now.difference(_lastHapticAt!).inMilliseconds >= 500) {
      _lastHapticAt = now;
      unawaited(HapticFeedback.lightImpact());
    }
  }

  Future<void> _toggleRadarScanning(BuildContext context, WidgetRef ref) async {
    try {
      if (bleScannerService.isScanning) {
        await bleScannerService.stopScanning();
      } else {
        await bleScannerService.startScanning();
      }
      ref
          .read(meshStateProvider.notifier)
          .setScanning(bleScannerService.isScanning);
    } on BleMeshException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('雷达扫描切换失败: $error')));
    }
  }

  void _lockTarget(DiscoveredDevice device) {
    setState(() {
      _followNearest = false;
      _selectedDeviceId = device.macAddress;
      _trackedDevice = device;
      _lastFeedbackAt = null;
      _lastHapticAt = null;
    });
  }

  void _followNearestTarget(List<DiscoveredDevice> devices) {
    final next = devices.isEmpty ? null : devices.first;
    setState(() {
      _followNearest = true;
      _selectedDeviceId = next?.macAddress;
      _trackedDevice = next;
      _lastFeedbackAt = null;
      _lastHapticAt = null;
    });
  }

  DiscoveredDevice? _resolveTrackedDevice(List<DiscoveredDevice> devices) {
    if (devices.isEmpty) {
      return null;
    }

    if (_followNearest) {
      return devices.first;
    }

    for (final device in devices) {
      if (device.macAddress == _selectedDeviceId) {
        return device;
      }
    }

    return devices.first;
  }

  void _reconcileSelection(
    List<DiscoveredDevice> devices,
    DiscoveredDevice? trackedDevice,
  ) {
    final nextId = trackedDevice?.macAddress;
    final nextFollowNearest =
        devices.isEmpty ||
        _followNearest ||
        !devices.any((device) => device.macAddress == _selectedDeviceId);

    if (nextId == _selectedDeviceId && nextFollowNearest == _followNearest) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _followNearest = nextFollowNearest;
        _selectedDeviceId = nextId;
        _lastFeedbackAt = null;
        _lastHapticAt = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final meshState = ref.watch(meshStateProvider);
    final devices = [...meshState.activeDevices]..sort(_compareDevices);
    final trackedDevice = _resolveTrackedDevice(devices);
    final profile = trackedDevice == null
        ? null
        : _feedbackProfileFor(trackedDevice);

    _trackedDevice = trackedDevice;
    _isScanning = meshState.isScanning;
    _reconcileSelection(devices, trackedDevice);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F6F9),
        foregroundColor: RescuePalette.textPrimary,
        title: const Text('雷达搜寻'),
        actions: [
          IconButton(
            tooltip: meshState.isScanning ? '停止雷达扫描' : '启动雷达扫描',
            onPressed: () => _toggleRadarScanning(context, ref),
            icon: Icon(
              meshState.isScanning ? Icons.pause_rounded : Icons.radar_rounded,
            ),
          ),
          IconButton(
            tooltip: '清除设备',
            onPressed: () {
              ref.read(meshStateProvider.notifier).clearDevices();
              _followNearestTarget(const <DiscoveredDevice>[]);
            },
            icon: const Icon(Icons.clear_all_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatusPanel(
            isScanning: meshState.isScanning,
            lastScanTime: meshState.lastScanTime,
            totalDevices: meshState.discoveredDevices.length,
            activeDevices: devices.length,
            trackedMode: _followNearest ? '自动锁最近目标' : '手动锁定目标',
          ),
          const SizedBox(height: 16),
          _SearchPanel(
            isScanning: meshState.isScanning,
            trackedDeviceId: trackedDevice?.macAddress,
            guidance: profile?.guidance ?? '启动扫描后锁定一个目标，靠近时滴滴会自动变快。',
            feedbackEnabled: _feedbackEnabled,
            onFeedbackChanged: (enabled) {
              setState(() {
                _feedbackEnabled = enabled;
                _lastFeedbackAt = null;
                _lastHapticAt = null;
              });
            },
          ),
          const SizedBox(height: 16),
          _TrackingPanel(
            device: trackedDevice,
            profile: profile,
            feedbackEnabled: _feedbackEnabled,
            followNearest: _followNearest,
            onFollowNearest: devices.isEmpty
                ? null
                : () => _followNearestTarget(devices),
          ),
          const SizedBox(height: 16),
          _DeviceSection(
            devices: devices,
            trackedDeviceId: trackedDevice?.macAddress,
            followNearest: _followNearest,
            onTrackDevice: _lockTarget,
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.isScanning,
    required this.lastScanTime,
    required this.totalDevices,
    required this.activeDevices,
    required this.trackedMode,
  });

  final bool isScanning;
  final DateTime? lastScanTime;
  final int totalDevices;
  final int activeDevices;
  final String trackedMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatePill(
                label: isScanning ? '扫描中' : '扫描已停止',
                color: isScanning
                    ? const Color(0xFF15803D)
                    : const Color(0xFF64748B),
                background: isScanning
                    ? const Color(0xFFE8F7ED)
                    : const Color(0xFFEFF3F6),
              ),
              _StatePill(
                label: lastScanTime == null
                    ? '尚未扫描'
                    : '更新 ${_formatRelativeTime(lastScanTime!)}',
                color: const Color(0xFF0F766E),
                background: const Color(0xFFE6FFFB),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '搜寻状态',
            style: TextStyle(
              color: RescuePalette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: '总设备', value: '$totalDevices'),
              _MetricTile(label: '活跃目标', value: '$activeDevices'),
              _MetricTile(label: '锁定模式', value: trackedMode),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.isScanning,
    required this.trackedDeviceId,
    required this.guidance,
    required this.feedbackEnabled,
    required this.onFeedbackChanged,
  });

  final bool isScanning;
  final String? trackedDeviceId;
  final String guidance;
  final bool feedbackEnabled;
  final ValueChanged<bool> onFeedbackChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF081827), Color(0xFF0D2235), Color(0xFF11304A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '搜寻雷达',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isScanning ? 'RSSI 只适合判断接近趋势，靠近时滴滴会更密。' : '先启动扫描，再从下面选择要跟踪的目标。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: SonarRadarWidget(
              size: 280,
              trackedDeviceId: trackedDeviceId,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            guidance,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: Colors.white70),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '滴滴反馈',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: feedbackEnabled,
                  onChanged: onFeedbackChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingPanel extends StatelessWidget {
  const _TrackingPanel({
    required this.device,
    required this.profile,
    required this.feedbackEnabled,
    required this.followNearest,
    required this.onFollowNearest,
  });

  final DiscoveredDevice? device;
  final _FeedbackProfile? profile;
  final bool feedbackEnabled;
  final bool followNearest;
  final VoidCallback? onFollowNearest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E5EC)),
      ),
      child: device == null || profile == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前锁定',
                  style: TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '还没有可追踪目标。启动扫描后，系统会默认跟随最近设备。',
                  style: TextStyle(color: RescuePalette.textMuted, height: 1.5),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '当前锁定',
                        style: TextStyle(
                          color: RescuePalette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onFollowNearest,
                      icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                      label: Text(followNearest ? '跟随最近中' : '改为跟随最近'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _deviceTitle(device!),
                  style: const TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: _formatDistance(device!)),
                    _InfoChip(label: '${device!.rssi} dBm'),
                    _InfoChip(label: device!.confidenceLabel),
                    _InfoChip(label: profile!.cadenceLabel),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: profile!.progress,
                    backgroundColor: const Color(0xFFE9EEF2),
                    valueColor: AlwaysStoppedAnimation<Color>(profile!.color),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  profile!.proximityLabel,
                  style: TextStyle(
                    color: profile!.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  profile!.guidance,
                  style: const TextStyle(
                    color: RescuePalette.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  feedbackEnabled ? '滴滴已启用，节奏会随距离变化。' : '滴滴已关闭，可先看距离变化再决定是否打开。',
                  style: TextStyle(
                    color: feedbackEnabled
                        ? RescuePalette.success
                        : RescuePalette.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.devices,
    required this.trackedDeviceId,
    required this.followNearest,
    required this.onTrackDevice,
  });

  final List<DiscoveredDevice> devices;
  final String? trackedDeviceId;
  final bool followNearest;
  final ValueChanged<DiscoveredDevice> onTrackDevice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设备列表 (${devices.length})',
            style: const TextStyle(
              color: RescuePalette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '点任一设备即可锁定该信号源。未手动锁定时，系统会自动跟随最近目标。',
            style: TextStyle(color: RescuePalette.textMuted, height: 1.45),
          ),
          const SizedBox(height: 12),
          if (devices.isEmpty)
            const Text(
              '当前没有活跃设备。',
              style: TextStyle(color: RescuePalette.textMuted),
            )
          else
            ...devices.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DeviceCard(
                  device: device,
                  isTracked: device.macAddress == trackedDeviceId,
                  isAutoTracked:
                      followNearest && device.macAddress == trackedDeviceId,
                  onTrack: () => onTrackDevice(device),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isTracked,
    required this.isAutoTracked,
    required this.onTrack,
  });

  final DiscoveredDevice device;
  final bool isTracked;
  final bool isAutoTracked;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final signalColor = _signalColor(device.rssi);

    return InkWell(
      onTap: onTrack,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isTracked ? const Color(0xFFF4FBFF) : const Color(0xFFF7FBFD),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isTracked ? RescuePalette.accent : const Color(0xFFD9E5EC),
            width: isTracked ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _deviceTitle(device),
                    style: const TextStyle(
                      color: RescuePalette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatePill(
                  label: isTracked
                      ? isAutoTracked
                            ? '自动跟随'
                            : '已锁定'
                      : _signalLabel(device.rssi),
                  color: isTracked ? RescuePalette.accent : signalColor,
                  background: (isTracked ? RescuePalette.accent : signalColor)
                      .withValues(alpha: 0.12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              device.macAddress,
              style: const TextStyle(
                color: RescuePalette.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: _formatDistance(device)),
                _InfoChip(label: device.distanceDescription),
                _InfoChip(label: '${device.rssi} dBm'),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onTrack,
                icon: const Icon(Icons.my_location_rounded, size: 18),
                label: Text(isTracked ? '重新锁定' : '锁定此目标'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104, maxWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: RescuePalette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: RescuePalette.textMuted)),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2EDF2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: RescuePalette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeedbackProfile {
  const _FeedbackProfile({
    required this.intervalMs,
    required this.proximityLabel,
    required this.cadenceLabel,
    required this.guidance,
    required this.color,
    required this.progress,
    required this.enableHaptic,
  });

  final int intervalMs;
  final String proximityLabel;
  final String cadenceLabel;
  final String guidance;
  final Color color;
  final double progress;
  final bool enableHaptic;
}

_FeedbackProfile _feedbackProfileFor(DiscoveredDevice device) {
  final distance = device.estimatedDistance;
  final hasDistance = distance.isFinite && distance > 0;

  if ((hasDistance && distance <= 1.5) || device.rssi >= -55) {
    return const _FeedbackProfile(
      intervalMs: 180,
      proximityLabel: '极近距离',
      cadenceLabel: '0.18 秒/次',
      guidance: '信号已经很强，缩小步幅，围绕目标做小范围确认。',
      color: RescuePalette.critical,
      progress: 0.96,
      enableHaptic: true,
    );
  }

  if ((hasDistance && distance <= 3) || device.rssi >= -60) {
    return const _FeedbackProfile(
      intervalMs: 280,
      proximityLabel: '非常接近',
      cadenceLabel: '0.28 秒/次',
      guidance: '继续保持当前方向，优先看滴滴是否继续加快。',
      color: RescuePalette.warning,
      progress: 0.84,
      enableHaptic: true,
    );
  }

  if ((hasDistance && distance <= 6) || device.rssi >= -67) {
    return const _FeedbackProfile(
      intervalMs: 420,
      proximityLabel: '接近中',
      cadenceLabel: '0.42 秒/次',
      guidance: '已经进入近距离区，建议减速，观察每一步后的反馈变化。',
      color: RescuePalette.warning,
      progress: 0.68,
      enableHaptic: false,
    );
  }

  if ((hasDistance && distance <= 12) || device.rssi >= -75) {
    return const _FeedbackProfile(
      intervalMs: 650,
      proximityLabel: '中等距离',
      cadenceLabel: '0.65 秒/次',
      guidance: '维持大方向搜索，尝试左右微调，找出滴滴更密的一侧。',
      color: RescuePalette.accent,
      progress: 0.5,
      enableHaptic: false,
    );
  }

  if ((hasDistance && distance <= 25) || device.rssi >= -85) {
    return const _FeedbackProfile(
      intervalMs: 950,
      proximityLabel: '远距离',
      cadenceLabel: '0.95 秒/次',
      guidance: '信号较弱，先扩大搜索步幅，确认哪一侧反馈更稳定。',
      color: RescuePalette.accent,
      progress: 0.3,
      enableHaptic: false,
    );
  }

  return const _FeedbackProfile(
    intervalMs: 1400,
    proximityLabel: '边缘信号',
    cadenceLabel: '1.40 秒/次',
    guidance: '这是很弱的边缘信号，优先移动位置，等节奏明显变快后再细找。',
    color: RescuePalette.textMuted,
    progress: 0.14,
    enableHaptic: false,
  );
}

int _compareDevices(DiscoveredDevice a, DiscoveredDevice b) {
  final aDistance = a.estimatedDistance > 0
      ? a.estimatedDistance
      : double.infinity;
  final bDistance = b.estimatedDistance > 0
      ? b.estimatedDistance
      : double.infinity;
  final distanceOrder = aDistance.compareTo(bDistance);
  if (distanceOrder != 0) {
    return distanceOrder;
  }
  return b.rssi.compareTo(a.rssi);
}

String _deviceTitle(DiscoveredDevice device) {
  final parts = device.macAddress.split(':');
  if (parts.length >= 2) {
    return '终端 ${parts[parts.length - 2]}${parts.last}'.toUpperCase();
  }
  return device.macAddress;
}

String _formatDistance(DiscoveredDevice device) {
  final distance = device.estimatedDistance;
  if (!distance.isFinite || distance <= 0) {
    return '距离未知';
  }
  if (distance < 1) {
    return '约 ${(distance * 100).round()} 厘米';
  }
  return '约 ${distance.toStringAsFixed(1)} 米';
}

String _formatRelativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 10) return '刚刚更新';
  if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  return '${diff.inHours} 小时前';
}

String _signalLabel(int rssi) {
  if (rssi >= -60) return '强信号';
  if (rssi >= -75) return '中信号';
  return '弱信号';
}

Color _signalColor(int rssi) {
  if (rssi >= -60) return const Color(0xFF15803D);
  if (rssi >= -75) return const Color(0xFFC77700);
  return const Color(0xFFB42318);
}
