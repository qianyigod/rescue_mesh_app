import 'package:flutter/material.dart';
import 'models/emergency_profile.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'services/sos_trigger_service.dart';
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
      _statusText = '??????????? SOS...';
    });

    try {
      final result = await sosTriggerService.triggerSos(
        bleService: bleMeshService,
        bloodType: EmergencyProfile.current.bloodType,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (result.uploadedToCommandCenter && result.broadcastStarted) {
          _statusText = '''
SOS ??????????????
??: ${result.latitude.toStringAsFixed(5)}
??: ${result.longitude.toStringAsFixed(5)}
??? ${result.uploadedCount} ????
'''.trim();
        } else if (result.uploadedToCommandCenter && result.bleError != null) {
          _statusText =
              'SOS ???????????? BLE ?????${result.bleError}';
        } else if (result.syncError != null && result.broadcastStarted) {
          _statusText = '''
SOS ????????????${result.syncError}
?????????????????
'''.trim();
        } else if (result.syncError != null && result.bleError != null) {
          _statusText = '''
SOS ???????? BLE ????????????
BLE?${result.bleError}
???${result.syncError}
'''.trim();
        } else {
          _statusText = '''
SOS ????
??: ${result.latitude.toStringAsFixed(5)}
??: ${result.longitude.toStringAsFixed(5)}
'''.trim();
        }
      });
    } on BleMeshException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'SOS ????: ${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '???????: $error';
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
                                    color: RescuePalette.textPrimary.withValues(
                                      alpha: 0.14,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          ((_isLocating || isBroadcasting)
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
                                    ?.copyWith(color: RescuePalette.critical),
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
