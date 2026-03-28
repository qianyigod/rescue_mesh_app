import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_chat_page.dart';
import 'database.dart';
import 'mesh_dashboard_page.dart';
import 'message_page.dart';
import 'profile_page.dart';
import 'radar_demo_page.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/network_sync_service.dart';
import 'services/power_saving_manager.dart';
import 'theme/rescue_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await powerSavingManager.initialize();
  runApp(const RescueApp());
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

  @override
  void initState() {
    super.initState();

    powerSavingManager.initialize().catchError((_) => null);
    bleMeshService.init().catchError((_) => null);
    bleScannerService.init().catchError((_) => null);
    networkSyncService.startListening().catchError((_) => null);
    _incomingSosSubscription = bleScannerService.sosMessageStream.listen((
      message,
    ) {
      appDb.saveIncomingSos(message).catchError((_) => 0);
    });
  }

  @override
  void dispose() {
    _incomingSosSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
