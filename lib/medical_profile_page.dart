import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database.dart';
import 'models/emergency_profile.dart';
import 'theme/rescue_theme.dart';

// ── Database-backed storage ───────────────────────────────────
// Using Drift database instead of SharedPreferences

class MedicalProfilePage extends StatefulWidget {
  const MedicalProfilePage({super.key});

  @override
  State<MedicalProfilePage> createState() => _MedicalProfilePageState();
}

class _MedicalProfilePageState extends State<MedicalProfilePage> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _historyCtrl = TextEditingController();
  final _allergyCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  BloodType _blood = BloodType.unknown;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDatabase();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _historyCtrl.dispose();
    _allergyCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFromDatabase() async {
    try {
      final profile = await appDb.getCurrentMedicalProfile();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = profile?.name ?? '';
        _ageCtrl.text = profile?.age ?? '';
        _historyCtrl.text = profile?.medicalHistory ?? '';
        _allergyCtrl.text = profile?.allergies ?? '';
        _contactCtrl.text = profile?.emergencyContact ?? '';
        final code = profile?.bloodType ?? -1;
        _blood = BloodType.values.firstWhere(
          (t) => t.code == code,
          orElse: () => BloodType.unknown,
        );
      });
    } catch (e) {
      debugPrint('Error loading medical profile: $e');
      if (!mounted) return;
      setState(() {
        // Use default empty values
        _nameCtrl.text = '';
        _ageCtrl.text = '';
        _historyCtrl.text = '';
        _allergyCtrl.text = '';
        _contactCtrl.text = '';
        _blood = BloodType.unknown;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Save to database
      await appDb.saveMedicalProfile(
        name: _nameCtrl.text.trim(),
        age: _ageCtrl.text.trim(),
        bloodType: _blood.code,
        medicalHistory: _historyCtrl.text.trim(),
        allergies: _allergyCtrl.text.trim(),
        emergencyContact: _contactCtrl.text.trim(),
      );

      // Sync to EmergencyProfile
      EmergencyProfile.updateProfile(
        callsign: _nameCtrl.text.trim().isEmpty ? _nameCtrl.text.trim() : null,
        bloodType: _blood,
        allergies: _allergyCtrl.text.trim(),
        emergencyContact: _contactCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: RescuePalette.success, size: 20),
              SizedBox(width: 10),
              Text(
                '✅ 档案已安全保存到数据库',
                style: TextStyle(
                  color: RescuePalette.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error saving medical profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error, color: RescuePalette.critical, size: 20),
              SizedBox(width: 10),
              Text(
                '❌ 保存失败，请重试',
                style: TextStyle(
                  color: RescuePalette.critical,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RescuePalette.background,
      appBar: AppBar(
        title: const Text(
          '医疗档案',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _MedCard(
                  icon: Icons.person_outline,
                  color: RescuePalette.accent,
                  title: '基本信息',
                  child: Column(
                    children: [
                      _field(_nameCtrl, '真实姓名', '如：张三', Icons.badge_outlined),
                      const SizedBox(height: 12),
                      _field(
                        _ageCtrl,
                        '年龄',
                        '如：28',
                        Icons.cake_outlined,
                        kb: TextInputType.number,
                        fmt: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _MedCard(
                  icon: Icons.bloodtype,
                  color: RescuePalette.critical,
                  title: '血型',
                  child: _buildBloodChips(),
                ),
                const SizedBox(height: 14),
                _MedCard(
                  icon: Icons.medical_information_outlined,
                  color: const Color(0xFFE29726),
                  title: '健康记录',
                  child: Column(
                    children: [
                      _field(
                        _historyCtrl,
                        '既往病史',
                        '如：高血压、哮喘（没有可留空）',
                        Icons.history_edu_outlined,
                        lines: 3,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _allergyCtrl,
                        '过敏史',
                        '如：青霉素过敏（没有可留空）',
                        Icons.warning_amber_outlined,
                        lines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _MedCard(
                  icon: Icons.contact_phone_outlined,
                  color: RescuePalette.success,
                  title: '紧急联系人',
                  child: _field(
                    _contactCtrl,
                    '联系电话',
                    '如：138-0000-1234',
                    Icons.phone_outlined,
                    kb: TextInputType.phone,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: RescuePalette.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '所有数据仅存储于本设备，仅在 SOS 广播时使用',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: RescuePalette.textMuted.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSaveBtn(),
        ],
      ),
    );
  }

  // ── Header gradient banner ──────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C6B88), Color(0xFF1E8A5C)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x302C6B88),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.health_and_safety,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '个人医疗档案',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '求救时随 SOS 信号自动广播给救援人员',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Generic text field ──────────────────────────────────────
  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint,
    IconData icon, {
    TextInputType kb = TextInputType.text,
    List<TextInputFormatter>? fmt,
    int lines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: kb,
      inputFormatters: fmt,
      maxLines: lines,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: RescuePalette.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(
          color: RescuePalette.textMuted,
          fontSize: 13.5,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(icon, size: 20, color: RescuePalette.accent),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
      ),
    );
  }

  // ── Blood type ChoiceChips ──────────────────────────────────
  Widget _buildBloodChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: BloodType.values.map((bt) {
        final sel = _blood == bt;
        final selColor = bt == BloodType.unknown
            ? RescuePalette.accent
            : RescuePalette.critical;
        return ChoiceChip(
          label: Text(
            bt.label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: sel ? Colors.white : RescuePalette.textPrimary,
            ),
          ),
          selected: sel,
          selectedColor: selColor,
          backgroundColor: RescuePalette.background,
          side: BorderSide(
            color: sel ? selColor : RescuePalette.border,
            width: 1.2,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          showCheckmark: false,
          onSelected: (_) => setState(() => _blood = bt),
        );
      }).toList(),
    );
  }

  // ── Gradient save button ────────────────────────────────────
  Widget _buildSaveBtn() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C6B88), Color(0xFF1E8A5C)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x401E8A5C),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _saving ? null : _save,
              borderRadius: BorderRadius.circular(18),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.save_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '保存档案',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable card shell ──────────────────────────────────────
class _MedCard extends StatelessWidget {
  const _MedCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: RescuePalette.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RescuePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: RescuePalette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: RescuePalette.border),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}
