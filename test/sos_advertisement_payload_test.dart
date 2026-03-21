import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_mesh_app/models/emergency_profile.dart';
import 'package:rescue_mesh_app/models/sos_advertisement_payload.dart';

void main() {
  test('SOS manufacturer data encodes company id, flag, lat, lon, and blood type', () {
    const payload = SosAdvertisementPayload(
      companyId: 0xFFFF,
      longitude: 121.4737,
      latitude: 31.2304,
      bloodType: BloodType.o,
      sosFlag: true,
    );

    expect(payload.rawManufacturerData.length, 12);
    expect(payload.rawManufacturerData[0], 0xFF);
    expect(payload.rawManufacturerData[1], 0xFF);
    expect(payload.manufacturerPayload.length, 10);
    expect(payload.manufacturerPayload[0], 1);
    expect(payload.manufacturerPayload[9], BloodType.o.code);
  });
}
