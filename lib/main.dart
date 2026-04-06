import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_chat_page.dart';
import 'database.dart';
import 'mesh_dashboard_page.dart';
import 'message_page.dart';
import 'models/emergency_profile.dart';
import 'models/sos_message.dart' as models;
import 'profile_page.dart';
import 'radar_demo_page.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/network_sync_service.dart';
import 'services/power_saving_manager.dart';
import 'theme/rescue_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await powerSavingManager.initialize();

  // Auto-load user profile from SharedPreferences
  await EmergencyProfile.loadFromPrefs();

  // Initialize database and sync loaded profile
  await appDb
      .getCurrentMedicalProfile()
      .then((profile) {
        if (profile != null) {
          EmergencyProfile.updateProfile(
            callsign: profile.name.isNotEmpty
                ? profile.name
                : EmergencyProfile.current.callsign,
            bloodType:
                profile.bloodType >= 0 &&
                    profile.bloodType < BloodType.values.length
                ? BloodType.values[profile.bloodType]
                : BloodType.unknown,
            allergies: profile.allergies,
            emergencyContact: profile.emergencyContact,
          );
        }
      })
      .catchError((_) => null);

  runApp(const ProviderScope(child: RescueApp()));
}

class RescueApp extends StatelessWidget {
  const RescueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rescue Mesh 救援系统现场端',
      debugShowCheckedModeBanner: false,
      theme: buildRescueTheme(),
      home: const MainScreen(),
    );
  }
}

enum _MainTab { dashboard, radar, ai, message, profile }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  _MainTab _currentTab = _MainTab.dashboard;
  StreamSubscription<dynamic>? _incomingSosSubscription;
  bool _isInitializing = true;
  List<String> _initErrors = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final errors = <String>[];

    // 并行初始化所有服务，等待全部完成
    final results = await Future.wait([
      _safeInitialize(
        'PowerSavingManager',
        () => powerSavingManager.initialize(),
      ),
      _safeInitialize('BleMeshService', () => bleMeshService.init()),
      _safeInitialize('BleScannerService', () => bleScannerService.init()),
      _safeInitialize(
        'NetworkSyncService',
        () => networkSyncService.startListening(),
      ),
    ]);

    // 收集所有初始化错误
    for (final result in results) {
      if (result != null) {
        errors.add(result);
      }
    }

    // 所有服务初始化完成后，才开始监听 SOS 流
    if (errors.isEmpty) {
      _incomingSosSubscription = bleScannerService.sosMessageStream.listen((
        message,
      ) {
        appDb
            .saveIncomingSos(message as models.SosMessage)
            .catchError((_) => 0);
      });
    }

    if (mounted) {
      setState(() {
        _initErrors = errors;
        _isInitializing = false;
      });
    }

    if (errors.isNotEmpty) {
      debugPrint('[Init Warning] 部分服务初始化失败: ${errors.join("; ")}');
    }
  }

  /// 安全初始化单个服务，返回错误信息（成功则返回 null）
  Future<String?> _safeInitialize(
    String serviceName,
    Future<void> Function() init,
  ) async {
    try {
      await init();
      return null;
    } catch (e) {
      return '$serviceName: $e';
    }
  }

  @override
  void dispose() {
    _incomingSosSubscription?.cancel();
    bleScannerService.stopScanning().catchError((_) => null);
    bleMeshService.stopSosBroadcast().catchError((_) => null);
    networkSyncService.stopListening().catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 初始化期间显示加载界面
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: RescuePalette.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: RescuePalette.critical),
              const SizedBox(height: 24),
              const Text(
                '正在初始化救援系统...',
                style: TextStyle(
                  color: RescuePalette.textPrimary,
                  fontSize: 16,
                ),
              ),
              if (_initErrors.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '部分服务初始化失败:\n${_initErrors.join("\n")}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: RescuePalette.critical,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        bleMeshService,
        bleScannerService,
        powerSavingManager,
      ]),
      builder: (context, _) {
        final visibleTabs = <_MainTab>[
          _MainTab.dashboard,
          _MainTab.radar,
          if (powerSavingManager.shouldEnableLocalAi()) _MainTab.ai,
          _MainTab.message,
          _MainTab.profile,
        ];
        final effectiveTab = visibleTabs.contains(_currentTab)
            ? _currentTab
            : _MainTab.dashboard;

        if (effectiveTab != _currentTab) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _currentTab = effectiveTab;
            });
          });
        }

        final ready =
            bleMeshService.permissionsGranted &&
            bleScannerService.permissionsGranted &&
            (bleMeshService.isAdapterReady || bleScannerService.isAdapterReady);
        final selectedIndex = visibleTabs.indexOf(effectiveTab);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Rescue Mesh'),
                Text(
                  powerSavingManager.isUltraPowerSavingMode
                      ? '绝境省电已激活｜AI 已关闭｜BLE ${powerSavingManager.getBleAdvertiseInterval().inSeconds}s'
                      : ready
                      ? '现场终端已就绪，可接入指挥系统'
                      : '终端能力降级，请检查蓝牙与权限',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: powerSavingManager.isUltraPowerSavingMode
                        ? const Color(0xFFC7921F)
                        : ready
                        ? RescuePalette.success
                        : RescuePalette.critical,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          body: _buildPage(effectiveTab),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: (index) {
              setState(() {
                _currentTab = visibleTabs[index];
              });
            },
            items: visibleTabs
                .map(
                  (tab) => switch (tab) {
                    _MainTab.dashboard => const BottomNavigationBarItem(
                      icon: Icon(Icons.dashboard),
                      label: '首页',
                    ),
                    _MainTab.radar => const BottomNavigationBarItem(
                      icon: Icon(Icons.radar),
                      label: '雷达',
                    ),
                    _MainTab.ai => const BottomNavigationBarItem(
                      icon: Icon(Icons.medical_services),
                      label: 'AI 助手',
                    ),
                    _MainTab.message => const BottomNavigationBarItem(
                      icon: Icon(Icons.message),
                      label: '记录',
                    ),
                    _MainTab.profile => const BottomNavigationBarItem(
                      icon: Icon(Icons.person),
                      label: '资料',
                    ),
                  },
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _buildPage(_MainTab tab) {
    return switch (tab) {
      _MainTab.dashboard => MeshDashboardPage(),
      _MainTab.radar => const RadarDemoPage(),
      _MainTab.ai => const AiChatPage(),
      _MainTab.message => const MessagePage(),
      _MainTab.profile => const ProfilePage(),
    };
  }
}
