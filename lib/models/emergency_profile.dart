import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BloodType {
  unknown(-1),
  a(0),
  b(1),
  ab(2),
  o(3);

  const BloodType(this.code);

  final int code;

  String get label {
    switch (this) {
      case BloodType.a:
        return 'A型';
      case BloodType.b:
        return 'B型';
      case BloodType.ab:
        return 'AB型';
      case BloodType.o:
        return 'O型';
      case BloodType.unknown:
        return '未知';
    }
  }
}

class EmergencyProfile {
  const EmergencyProfile({
    required this.callsign,
    required this.bloodType,
    required this.allergies,
    required this.emergencyContact,
  });

  final String callsign;
  final BloodType bloodType;
  final String allergies;
  final String emergencyContact;

  /// 使用 ValueNotifier 实现响应式更新
  static final emergencyProfile = ValueNotifier<EmergencyProfile>(
    const EmergencyProfile(
      callsign: 'Rescuer A007',
      bloodType: BloodType.o,
      allergies: 'Penicillin',
      emergencyContact: '138-XXXX-1234',
    ),
  );

  /// 方便访问当前值
  static EmergencyProfile get current => emergencyProfile.value;

  /// 从 SharedPreferences 加载数据
  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final callsign = prefs.getString('emergency_callsign');
      final bloodTypeCode = prefs.getInt('emergency_blood_type');
      final allergies = prefs.getString('emergency_allergies');
      final contact = prefs.getString('emergency_contact');

      if (callsign != null ||
          bloodTypeCode != null ||
          allergies != null ||
          contact != null) {
        emergencyProfile.value = EmergencyProfile(
          callsign: callsign ?? current.callsign,
          bloodType: bloodTypeCode != null
              ? BloodType.values.firstWhere(
                  (t) => t.code == bloodTypeCode,
                  orElse: () => BloodType.unknown,
                )
              : current.bloodType,
          allergies: allergies ?? current.allergies,
          emergencyContact: contact ?? current.emergencyContact,
        );
        debugPrint('[EmergencyProfile] Loaded from SharedPreferences');
      }
    } catch (e) {
      debugPrint('[EmergencyProfile] Error loading from prefs: $e');
    }
  }

  /// 保存数据到 SharedPreferences
  static Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emergency_callsign', current.callsign);
      await prefs.setInt('emergency_blood_type', current.bloodType.code);
      await prefs.setString('emergency_allergies', current.allergies);
      await prefs.setString('emergency_contact', current.emergencyContact);
      debugPrint('[EmergencyProfile] Saved to SharedPreferences');
    } catch (e) {
      debugPrint('[EmergencyProfile] Error saving to prefs: $e');
    }
  }

  /// 更新档案数据
  static void updateProfile({
    String? callsign,
    BloodType? bloodType,
    String? allergies,
    String? emergencyContact,
  }) {
    emergencyProfile.value = EmergencyProfile(
      callsign: callsign ?? current.callsign,
      bloodType: bloodType ?? current.bloodType,
      allergies: allergies ?? current.allergies,
      emergencyContact: emergencyContact ?? current.emergencyContact,
    );
  }
}
