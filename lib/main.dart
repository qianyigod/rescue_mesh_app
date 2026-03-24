import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_chat_page.dart';
import 'database.dart';
import 'mesh_dashboard_page.dart';
import 'message_page.dart';
import 'profile_page.dart';
import 'services/ble_mesh_service.dart';
import 'services/ble_scanner_service.dart';
import 'services/network_sync_service.dart';
import 'theme/rescue_theme.dart';

void main() {
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;
  StreamSubscription<dynamic>? _incomingSosSubscription;

  @override
  void initState() {
    super.initState();
    _pages = [
      MeshDashboardPage(),
      const AiChatPage(),
      const MessagePage(),
      const ProfilePage(),
    ];

<<<<<<< HEAD
    bleMeshService.init().catchError((_) => null);
    bleScannerService.init().catchError((_) => null);
    networkSyncService.startListening().catchError((_) => null);
    _incomingSosSubscription = bleScannerService.sosMessageStream.listen((
      message,
    ) {
      appDb.saveIncomingSos(message).catchError((_) => null);
=======
    bleMeshService.init().catchError((_) {});
    bleScannerService.init().catchError((_) {});
    networkSyncService.startListening().catchError((_) {});
    _incomingSosSubscription = bleScannerService.sosMessageStream.listen((
      message,
    ) {
      appDb.saveIncomingSos(message).catchError((_) {});
>>>>>>> 269523386e01298e8124e2d5e7fe1cc2f78937a3
    });
  }

  @override
  void dispose() {
    _incomingSosSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: Listenable.merge([bleMeshService, bleScannerService]),
          builder: (context, _) {
            final ready =
                bleMeshService.permissionsGranted &&
                bleScannerService.permissionsGranted &&
                (bleMeshService.isAdapterReady ||
                    bleScannerService.isAdapterReady);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Rescue Mesh'),
                Text(
                  ready ? '现场终端已就绪，可接入指挥系统' : '终端能力降级，请检查蓝牙与权限',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ready
                        ? RescuePalette.success
                        : RescuePalette.critical,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '首页'),
          BottomNavigationBarItem(
            icon: Icon(Icons.medical_services),
            label: 'AI 助手',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: '记录'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '资料'),
        ],
      ),
    );
  }
}
