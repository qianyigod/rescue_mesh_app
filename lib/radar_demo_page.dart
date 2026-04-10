import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ar_rescue_compass_page.dart';
import 'models/mesh_state_provider.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_scanner_service.dart';
import 'theme/rescue_theme.dart';
import 'widgets/sonar_radar_widget.dart';

class RadarDemoPage extends ConsumerWidget {
  const RadarDemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meshState = ref.watch(meshStateProvider);
    final devices = [...meshState.activeDevices]..sort(_compareDevices);
    final nearestDevice = devices.isEmpty ? null : devices.first;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F6F9),
        foregroundColor: RescuePalette.textPrimary,
        title: const Text('声呐雷达'),
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
            onPressed: () => ref.read(meshStateProvider.notifier).clearDevices(),
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
            locatedDevices: devices.where(_hasCoordinates).length,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF081827),
                  Color(0xFF0D2235),
                  Color(0xFF11304A),
                ],
              ),
            ),
            child: Column(
              children: [
                const Center(child: SonarRadarWidget(size: 280)),
                const SizedBox(height: 12),
                Text(
                  meshState.isScanning
                      ? '雷达正在监听附近 SOS 广播'
                      : '雷达扫描已停止，当前未在监听附近 SOS 广播',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _NearestPanel(device: nearestDevice),
          const SizedBox(height: 16),
          _DeviceSection(devices: devices),
        ],
      ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('雷达扫描切换失败: $error')),
      );
    }
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.isScanning,
    required this.lastScanTime,
    required this.totalDevices,
    required this.activeDevices,
    required this.locatedDevices,
  });

  final bool isScanning;
  final DateTime? lastScanTime;
  final int totalDevices;
  final int activeDevices;
  final int locatedDevices;

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
                label: isScanning ? '扫描中' : '扫描未启动',
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
            '雷达状态',
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
              _MetricTile(label: '可导航', value: '$locatedDevices'),
            ],
          ),
        ],
      ),
    );
  }
}

class _NearestPanel extends StatelessWidget {
  const _NearestPanel({required this.device});

  final DiscoveredDevice? device;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E5EC)),
      ),
      child: device == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最近目标',
                  style: TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '还没有接收到可显示的设备。启动扫描后，这里会优先显示最近的目标。',
                  style: TextStyle(color: RescuePalette.textMuted, height: 1.5),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '最近目标',
                  style: TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _deviceTitle(device!),
                  style: const TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: _formatDistance(device!)),
                    _InfoChip(label: '${device!.rssi} dBm'),
                    _InfoChip(label: _formatRelativeTime(device!.lastUpdatedAt)),
                  ],
                ),
              ],
            ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({required this.devices});

  final List<DiscoveredDevice> devices;

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
          const SizedBox(height: 12),
          if (devices.isEmpty)
            const Text(
              '当前没有活跃设备。',
              style: TextStyle(color: RescuePalette.textMuted),
            )
          else
            ...devices.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DeviceCard(device: device),
                )),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final hasLocation = _hasCoordinates(device);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E5EC)),
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
                label: _signalLabel(device.rssi),
                color: _signalColor(device.rssi),
                background: _signalColor(device.rssi).withValues(alpha: 0.12),
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
              _InfoChip(label: '血型 ${_bloodTypeLabel(device.payload.bloodType)}'),
              _InfoChip(label: '${device.rssi} dBm'),
            ],
          ),
          if (hasLocation) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArRescueCompassPage(
                      targetLatitude: device.payload.latitude,
                      targetLongitude: device.payload.longitude,
                      targetRssi: device.rssi,
                      targetName: _deviceTitle(device),
                    ),
                  ),
                ),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('打开导航'),
              ),
            ),
          ],
        ],
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
      width: 104,
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
              fontSize: 22,
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

int _compareDevices(DiscoveredDevice a, DiscoveredDevice b) {
  final aDistance = a.estimatedDistance > 0 ? a.estimatedDistance : double.infinity;
  final bDistance = b.estimatedDistance > 0 ? b.estimatedDistance : double.infinity;
  final distanceOrder = aDistance.compareTo(bDistance);
  if (distanceOrder != 0) {
    return distanceOrder;
  }
  return b.rssi.compareTo(a.rssi);
}

bool _hasCoordinates(DiscoveredDevice device) {
  return device.payload.latitude != 0 || device.payload.longitude != 0;
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

String _bloodTypeLabel(int code) {
  switch (code) {
    case 0:
      return 'O';
    case 1:
      return 'A';
    case 2:
      return 'B';
    case 3:
      return 'AB';
    default:
      return '未知';
  }
}
