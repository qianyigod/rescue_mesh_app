enum BloodType {
  unknown(0),
  a(1),
  b(2),
  ab(3),
  o(4);

  const BloodType(this.code);

  final int code;

  String get label {
    switch (this) {
      case BloodType.a:
        return 'A 型';
      case BloodType.b:
        return 'B 型';
      case BloodType.ab:
        return 'AB 型';
      case BloodType.o:
        return 'O 型';
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

  static const current = EmergencyProfile(
    callsign: 'Rescuer A007',
    bloodType: BloodType.o,
    allergies: 'Penicillin',
    emergencyContact: '138-XXXX-1234',
  );
}
