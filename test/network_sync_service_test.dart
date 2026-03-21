import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rescue_mesh_app/database.dart';
import 'package:rescue_mesh_app/models/sos_message.dart';
import 'package:rescue_mesh_app/services/network_sync_service.dart';

void main() {
  group('NetworkSyncService', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('startListening 时若已联网会自动上传待同步记录', () async {
      await database.saveIncomingSos(_buildMessage('AA:BB:CC:DD:EE:FF'));

      late List<dynamic> requestBody;
      final service = NetworkSyncService(
        database: database,
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as List<dynamic>;
          return http.Response('ok', 200);
        }),
        connectivitySnapshotProvider:
            () async => const [ConnectivityResult.wifi],
        connectivityStreamProvider: () => const Stream.empty(),
      );

      await service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requestBody, hasLength(1));
      expect(requestBody.single['senderMac'], 'AA:BB:CC:DD:EE:FF');
      expect(await database.getPendingUploads(), isEmpty);

      service.dispose();
    });

    test('网络从离线恢复时会自动触发同步', () async {
      await database.saveIncomingSos(_buildMessage('11:22:33:44:55:66'));

      final connectivityController =
          StreamController<List<ConnectivityResult>>.broadcast();
      var requestCount = 0;

      final service = NetworkSyncService(
        database: database,
        httpClient: MockClient((request) async {
          requestCount += 1;
          return http.Response('ok', 200);
        }),
        connectivitySnapshotProvider:
            () async => const [ConnectivityResult.none],
        connectivityStreamProvider: () => connectivityController.stream,
      );

      await service.startListening();
      expect(service.hasNetwork, isFalse);

      connectivityController.add(const [ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(requestCount, 1);
      expect(await database.getPendingUploads(), isEmpty);

      await connectivityController.close();
      service.dispose();
    });

    test('服务器失败时保留待上传状态', () async {
      await database.saveIncomingSos(_buildMessage('77:88:99:AA:BB:CC'));

      final service = NetworkSyncService(
        database: database,
        httpClient: MockClient((request) async => http.Response('error', 500)),
        connectivitySnapshotProvider:
            () async => const [ConnectivityResult.wifi],
        connectivityStreamProvider: () => const Stream.empty(),
      );

      await service.startListening();
      final uploadedCount = await service.syncNow();

      expect(uploadedCount, 0);
      expect(await database.getPendingUploads(), hasLength(1));
      expect(service.lastError, contains('状态码: 500'));

      service.dispose();
    });
  });
}

SosMessage _buildMessage(String remoteId) {
  return SosMessage(
    companyId: 0xFFFF,
    remoteId: remoteId,
    deviceName: 'rescuer',
    sosFlag: true,
    latitude: 31.2304,
    longitude: 121.4737,
    bloodTypeCode: 4,
    rssi: -60,
    receivedAt: DateTime(2026, 3, 20, 10, 0, 0),
    rawPayload: const [1, 0, 0, 0, 0, 0, 0, 0, 0, 4],
  );
}
