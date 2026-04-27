import 'package:flutter/material.dart';

import 'models/emergency_profile.dart';
import 'services/ble_mesh_exceptions.dart';
import 'services/ble_mesh_service.dart';
import 'services/sos_trigger_service.dart';
import 'theme/rescue_theme.dart';

class SosPage extends StatefulWidget {
  SosPage({
    super.key,
    BleMeshService? bleService,
    SosTriggerService? triggerService,
  }) : bleService = bleService ?? bleMeshService,
       triggerService = triggerService ?? sosTriggerService;

  final BleMeshService bleService;
  final SosTriggerService triggerService;

  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  String _statusText = '等待发起 SOS 广播。系统会优先尝试实时定位，失败后再询问是否使用缓存坐标。';
  bool _isLocating = false;

  Future<void> _triggerSos() async {
    if (_isLocating || widget.bleService.isBroadcastingNow) {
      return;
    }

    setState(() {
      _isLocating = true;
      _statusText = '正在尝试获取实时位置并准备 SOS...';
    });

    try {
      final resolution = await widget.triggerService.resolveLocationForSos();
      if (resolution.requiresCacheConfirmation) {
        final confirmed = await _confirmUseCachedLocation(resolution);
        if (!mounted) {
          return;
        }
        if (!confirmed) {
          setState(() {
            _statusText = '已取消发送 SOS，等待重新定位。';
          });
          return;
        }
      }

      final result = await widget.triggerService.sendResolvedSos(
        bleService: widget.bleService,
        bloodType: EmergencyProfile.current.bloodType,
        resolution: resolution,
      );

      if (!mounted) {
        return;
      }

      final locationSourceLabel = resolution.requiresCacheConfirmation
          ? '使用缓存坐标'
          : '使用实时坐标';
      setState(() {
        if (result.uploadedToCommandCenter && result.broadcastStarted) {
          _statusText = '''
SOS 已广播并上传到指挥中心
$locationSourceLabel
纬度: ${result.latitude.toStringAsFixed(5)}
经度: ${result.longitude.toStringAsFixed(5)}
'''.trim();
        } else if (result.uploadedToCommandCenter && result.bleError != null) {
          _statusText = 'SOS 已上传到指挥中心，但 BLE 广播失败：${result.bleError}';
        } else if (result.syncError != null && result.broadcastStarted) {
          _statusText = 'SOS 已广播，但联网同步失败：${result.syncError}';
        } else if (result.syncError != null && result.bleError != null) {
          _statusText =
              'SOS 已写入本地，但 BLE 广播和联网同步都失败。BLE：${result.bleError}；网络：${result.syncError}';
        } else {
          _statusText = '''
SOS 已保存到本地
$locationSourceLabel
纬度: ${result.latitude.toStringAsFixed(5)}
经度: ${result.longitude.toStringAsFixed(5)}
'''.trim();
        }
      });
    } on BleMeshException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'SOS 发起失败：${error.message}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'SOS 发起失败：$error';
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
      await widget.bleService.stopSosBroadcast();
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = 'BLE SOS 广播已停止，本地记录仍然保留。';
      });
    } on BleMeshException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusText = '停止广播失败：${error.message}';
      });
    }
  }

  Future<bool> _confirmUseCachedLocation(SosLocationResolution resolution) async {
    final cachedAtText = resolution.cachedAt == null
        ? '未知'
        : _formatDateTime(resolution.cachedAt!);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('实时定位失败'),
          content: Text(
            '没有拿到新的实时坐标。\n'
            '是否使用最近一次缓存坐标继续发送 SOS？\n\n'
            '缓存时间：$cachedAtText\n'
            '纬度：${resolution.latitude.toStringAsFixed(5)}\n'
            '经度：${resolution.longitude.toStringAsFixed(5)}\n\n'
            '${resolution.failureReason ?? ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('使用缓存坐标发送'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:${twoDigits(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.bleService,
      builder: (context, _) {
        return StreamBuilder<bool>(
          stream: widget.bleService.isBroadcasting,
          initialData: widget.bleService.isBroadcastingNow,
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
                      value: widget.bleService.isAdapterReady ? '在线' : '离线',
                      tone: widget.bleService.isAdapterReady
                          ? RescuePalette.success
                          : RescuePalette.critical,
                      subtitle: widget.bleService.permissionsGranted
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
                          ? 'Manufacturer Data 正在发送 SOS 信号'
                          : '点击 SOS 按钮开始广播求救数据',
                    ),
                    const SizedBox(height: 16),
                    _StatusBanner(
                      title: '中继模式',
                      value: widget.bleService.relayEnabled ? '已启用' : '已停用',
                      tone: widget.bleService.relayEnabled
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
                                  onPressed: widget.bleService.init,
                                  child: const Text('初始化 BLE'),
                                ),
                                OutlinedButton(
                                  onPressed:
                                      widget.bleService.ensureRuntimePermissions,
                                  child: const Text('检查权限'),
                                ),
                                if (isBroadcasting)
                                  OutlinedButton(
                                    onPressed: _stopBroadcast,
                                    child: const Text('停止广播'),
                                  ),
                              ],
                            ),
                            if (widget.bleService.lastError != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                widget.bleService.lastError!,
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
