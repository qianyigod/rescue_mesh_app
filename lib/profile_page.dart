import 'package:flutter/material.dart';

import 'medical_profile_page.dart';
import 'models/emergency_profile.dart';
import 'services/ble_mesh_service.dart';
import 'theme/rescue_theme.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bleMeshService,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF2F5F7), Color(0xFFE1E7EB)],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDFEFE),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFD3DCE3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE95A5A), Color(0xFFB61F30)],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFBE2E2),
                          width: 4,
                        ),
                      ),
                      child: const Icon(
                        Icons.health_and_safety,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      EmergencyProfile.current.callsign,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14202A),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bleMeshService.isAdapterReady
                          ? '蓝牙已就绪'
                          : '蓝牙待命中',
                      style: const TextStyle(
                        color: Color(0xFF5D7283),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _StatusTile(
                            label: 'Mesh',
                            value: bleMeshService.relayEnabled ? '已启用' : '已停用',
                            accent: bleMeshService.relayEnabled
                                ? RescuePalette.accent
                                : const Color(0xFF7F8E99),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatusTile(
                            label: '广播',
                            value: bleMeshService.isAdvertising ? '进行中' : '空闲',
                            accent: bleMeshService.isAdvertising
                                ? RescuePalette.critical
                                : const Color(0xFF7F8E99),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MedicalProfilePage(),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('编辑医疗档案'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: RescuePalette.accent,
                          side: const BorderSide(color: RescuePalette.accent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: '紧急资料',
                stripeColor: RescuePalette.critical,
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.bloodtype,
                      iconColor: RescuePalette.critical,
                      label: '血型',
                      value: EmergencyProfile.current.bloodType.label,
                    ),
                    const Divider(height: 1, color: Color(0xFFD9E2E8)),
                    _InfoRow(
                      icon: Icons.warning_amber,
                      iconColor: Color(0xFFE29726),
                      label: '过敏史',
                      value: EmergencyProfile.current.allergies,
                    ),
                    const Divider(height: 1, color: Color(0xFFD9E2E8)),
                    _InfoRow(
                      icon: Icons.contact_phone,
                      iconColor: RescuePalette.success,
                      label: '紧急联系人',
                      value: EmergencyProfile.current.emergencyContact,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                title: 'Mesh 控制',
                stripeColor: RescuePalette.accent,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      title: const Text(
                        '自动中继',
                        style: TextStyle(
                          color: Color(0xFF14202A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        '作为离线 BLE Mesh 节点转发附近求救数据',
                        style: TextStyle(color: Color(0xFF5D7283)),
                      ),
                      value: bleMeshService.relayEnabled,
                      activeColor: RescuePalette.accent,
                      onChanged: bleMeshService.setRelayEnabled,
                    ),
                    const Divider(height: 1, color: Color(0xFFD9E2E8)),
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.bluetooth_searching,
                          color: RescuePalette.accent,
                        ),
                      ),
                      title: const Text(
                        '重新检查蓝牙权限',
                        style: TextStyle(
                          color: Color(0xFF14202A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text(
                        '检查并重新授予蓝牙相关权限',
                        style: TextStyle(color: Color(0xFF5D7283)),
                      ),
                      onTap: bleMeshService.ensureRuntimePermissions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.stripeColor,
    required this.child,
  });

  final String title;
  final Color stripeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD3DCE3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: stripeColor, width: 6),
                bottom: const BorderSide(color: Color(0xFFD9E2E8)),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF14202A),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5D7283),
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF14202A),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD5DFE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7D89),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
