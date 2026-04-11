import 'package:flutter/material.dart';

import 'theme/rescue_theme.dart';
import 'widgets/offline_tactical_map_view.dart';

class OfflineMapPage extends StatelessWidget {
  const OfflineMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F6F9),
        foregroundColor: RescuePalette.textPrimary,
        title: const Text('离线战术地图'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD9E5EC)),
          ),
          clipBehavior: Clip.antiAlias,
          child: const OfflineTacticalMapView(),
        ),
      ),
    );
  }
}
