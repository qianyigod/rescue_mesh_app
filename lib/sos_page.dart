import 'package:flutter/material.dart';
import 'package:location/location.dart';

import 'database.dart';
import 'models/emergency_profile.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'theme/rescue_theme.dart';

class SosPage extends StatefulWidget {
  const SosPage({super.key});

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  String _statusText = '等待生成 SOS 数据包并加入 BLE Mesh 广播。';
  bool _isLocating = false;

  Future<void> _triggerSos() async {
    if (_isLocating || bleMeshService.isBroadcastingNow) {
      return;
    }

    setState(() {
      _isLocating = true;
      _statusText = '正在获取定位并打包 SOS 信标数据...';
    });

    try {
      final location = Location();

      var serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          throw const BleMeshPlatformException(
            platformCode: 'location_service_disabled',
            message: '定位服务未开启，无法附加坐标信息。',
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
          message: '定位权限未授予，无法广播当前位置。',
        );
      }

      setState(() {
        _statusText = '正在写入本地 Drift 记录，并启动 SOS 广播...';
      });

      final locationData = await location.getLocation();
      final latitude = locationData.latitude;
      final longitude = locationData.longitude;
      if (latitude == null || longitude == null) {
        throw const BleMeshPlatformException(
          platformCode: 'location_unavailable',
          message: '定位坐标不可用，请稍后重试。',
        );
      }

      await appDb.addRecord(
        SosRecordsCompanion.insert(
          latitude: latitude.toString(),
          longitude: longitude.toString(),
        ),
      );

      await bleMeshService.startSosBroadcast(
        latitude: latitude,
        longitude: longitude,
        bloodType: EmergencyProfile.current.bloodType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _statusText =
            'SOS 已进入广播态。\n纬度: $latitude\n经度: $longitude\nManufacturer Data 正在通过 BLE 持续发射。';
      });
    } on BleMeshException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'SOS 广播失败: ${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '出现未预期错误: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _stopBroadcast() async {
    try {
      await bleMeshService.stopSosBroadcast();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'BLE SOS 广播已停止，本地 Drift 记录仍然保留。';
      });
    } on BleMeshException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '停止广播失败: ${error.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bleMeshService,
      builder: (context, _) {
        return StreamBuilder<bool>(
          stream: bleMeshService.isBroadcasting,
          initialData: bleMeshService.isBroadcastingNow,
          builder: (context, snapshot) {
            final isBroadcasting = snapshot.data ?? false;
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF101820), RescuePalette.background],
                ),
              ),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _StatusBanner(
                      title: 'Mesh 链路',
                      value: bleMeshService.isAdapterReady ? '在线' : '离线',
                      tone: bleMeshService.isAdapterReady
                          ? RescuePalette.success
                          : RescuePalette.critical,
                      subtitle: bleMeshService.permissionsGranted
                          ? 'Android 12+ 蓝牙与定位权限已就绪'
                          : '仍缺少蓝牙广播所需运行时权限',
                    ),
                    const SizedBox(height: 16),
                    _StatusBanner(
                      title: '信标状态',
                      value: isBroadcasting ? '广播中' : '空闲',
                      tone: isBroadcasting
                          ? RescuePalette.critical
                          : RescuePalette.textMuted,
                      subtitle: isBroadcasting
                          ? 'Manufacturer Data 正在发射 SOS 信号'
                          : '点击 SOS 按钮开始广播求救数据',
                    ),
                    const SizedBox(height: 16),
                    _StatusBanner(
                      title: '中继模式',
                      value: bleMeshService.relayEnabled ? '已启用' : '已停用',
                      tone: bleMeshService.relayEnabled
                          ? RescuePalette.accent
                          : RescuePalette.textMuted,
                      subtitle: '本机可作为离线蓝牙 Mesh 节点待命',
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              '应急信标',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    letterSpacing: 2,
                                    color: RescuePalette.textMuted,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: _triggerSos,
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: (_isLocating || isBroadcasting)
                                        ? const [
                                            Color(0xFFF26161),
                                            Color(0xFF7A1212),
                                          ]
                                        : const [
                                            Color(0xFF5B6875),
                                            Color(0xFF303C49),
                                          ],
                                  ),
                                  border: Border.all(
                                    color: RescuePalette.textPrimary
                                        .withValues(alpha: 0.14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: ((_isLocating || isBroadcasting)
                                              ? RescuePalette.critical
                                              : Colors.white)
                                          .withValues(alpha: 0.25),
                                      blurRadius: 26,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isLocating
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : Text(
                                          isBroadcasting ? '广播中' : 'SOS',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 52,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _statusText,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    height: 1.5,
                                    color: RescuePalette.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.tonal(
                                  onPressed: bleMeshService.init,
                                  child: const Text('初始化 BLE'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      bleMeshService.ensureRuntimePermissions,
                                  child: const Text('检查权限'),
                                ),
                                if (isBroadcasting)
                                  OutlinedButton(
                                    onPressed: _stopBroadcast,
                                    child: const Text('停止广播'),
                                  ),
                              ],
                            ),
                            if (bleMeshService.lastError != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                bleMeshService.lastError!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: RescuePalette.critical,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.title,
    required this.value,
    required this.tone,
    required this.subtitle,
  });

  final String title;
  final String value;
  final Color tone;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: RescuePalette.textMuted,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RescuePalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
