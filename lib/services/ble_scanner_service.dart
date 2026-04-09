import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database.dart';
import '../models/sos_message.dart' as models;
import 'ble_mesh_exceptions.dart';
import 'ble_mesh_service.dart';
import 'coded_phy_scanner.dart';

class BleScannerService extends ChangeNotifier {
  BleScannerService() {
    if (Platform.isAndroid) {
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        _adapterState = state;
        notifyListeners();
      });
    }
  }

  static const int rescueCompanyId = 0xFFFF;
  static const int _expectedPayloadLength = 14;
  static const int _legacyPayloadLength = 10;
  static const Duration _duplicateSuppressionWindow = Duration(seconds: 30);

  final StreamController<models.SosMessage> _sosMessageController =
      StreamController<models.SosMessage>.broadcast();

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<CodedPhyScanResult>? _codedPhySubscription;
  Future<void>? _initFuture;

  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};
  bool _supportsCodedPhy = false;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BleMeshException? _lastException;
  bool _isInitializing = false;
  bool _isScanning = false;
  bool _permissionsGranted = false;

  BluetoothAdapterState get adapterState => _adapterState;
  bool get isInitializing => _isInitializing;
  bool get isScanning => _isScanning;
  bool get permissionsGranted => _permissionsGranted;
  bool get isAdapterReady => _adapterState == BluetoothAdapterState.on;
  bool get supportsCodedPhy => _supportsCodedPhy;
  BleMeshException? get lastException => _lastException;
  String? get lastError => _lastException?.message;
  Stream<models.SosMessage> get sosMessageStream =>
      _sosMessageController.stream;

  Future<void> init() {
    if (!Platform.isAndroid) {
      _permissionsGranted = true;
      _lastException = null;
      notifyListeners();
      return Future.value();
    }

    return _initFuture ??= _performInit().whenComplete(() {
      _initFuture = null;
    });
  }

  Future<void> startScanning() async {
    await init();
    if (!Platform.isAndroid) {
      throw const BleMeshUnsupportedException('当前仅实现了 Android 端的 BLE 扫描。');
    }
    if (!isAdapterReady) {
      const exception = BleMeshBluetoothDisabledException(
        '蓝牙未开启，无法开始扫描附近的 SOS 信标。',
      );
      _setException(exception);
      throw exception;
    }

    await stopScanning();
    _recentFingerprints.clear();

    // 检查 Coded PHY 支持并启动并行扫描
    _supportsCodedPhy = await CodedPhyScanner.supportsCodedPhy();
    if (_supportsCodedPhy) {
      debugPrint(
        '[BLE Scanner] Device supports Coded PHY (BLE Long Range 300m)',
      );
      _startCodedPhyScan();
    } else {
      debugPrint(
        '[BLE Scanner] Device does NOT support Coded PHY, using traditional BLE only',
      );
    }

    _scanResultsSubscription = FlutterBluePlus.onScanResults.listen(
      _handleScanResults,
      onError: _handleScanError,
    );

    try {
      _isScanning = true;
      notifyListeners();
      await FlutterBluePlus.startScan(
        withMsd: [MsdFilter(rescueCompanyId)],
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
      );
      _setException(null);
    } catch (error) {
      _isScanning = false;
      final exception = _mapScanError(error);
      _setException(exception);
      await _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;
      throw exception;
    }
  }

  /// 启动 Coded PHY 扫描（用于接收 Long Range 信号）
  void _startCodedPhyScan() {
    try {
      _codedPhySubscription = CodedPhyScanner.startScan().listen(
        (result) {
          _handleCodedPhyResult(result);
        },
        onError: (error) {
          debugPrint('[BLE Scanner] Coded PHY scan error: $error');
        },
      );
    } catch (e) {
      debugPrint('[BLE Scanner] Failed to start Coded PHY scan: $e');
    }
  }

  /// 处理 Coded PHY 扫描结果
  void _handleCodedPhyResult(CodedPhyScanResult result) {
    // 提取 Manufacturer Specific Data
    final msd = result.msd;
    if (msd == null) return;

    final companyId = msd['companyId'] as int?;
    final data = msd['data'] as List<dynamic>?;

    if (companyId != rescueCompanyId || data == null) return;

    final payload = data.map((e) => e as int).toList();

    // 解码 SOS payload
    try {
      final message = decodeSosPayload(
        payload,
        remoteId: result.address,
        deviceName: result.name,
        rssi: result.rssi,
        receivedAt: DateTime.now(),
      );
      bleMeshService.addRelayMessage(message);
      _sosMessageController.add(message);
      debugPrint(
        '[BLE Scanner Coded PHY] Decoded SOS from ${result.address} '
        '(rssi=${result.rssi}, phy=${result.phy}, isLongRange=${result.isCodedPhy})',
      );
    } catch (e) {
      debugPrint('[BLE Scanner Coded PHY] Failed to decode payload: $e');
    }
  }

  models.SosMessage decodeSosPayload(
    List<int> payload, {
    required String remoteId,
    String deviceName = '',
    int rssi = 0,
    DateTime? receivedAt,
    int companyId = rescueCompanyId,
  }) {
    // 支持 8 字节紧凑格式（远距离优化）
    if (payload.length == 8) {
      return _decodeCompactPayload(
        payload,
        remoteId: remoteId,
        deviceName: deviceName,
        rssi: rssi,
        receivedAt: receivedAt,
        companyId: companyId,
      );
    }

    // 支持 14 字节标准格式和 10 字节遗留格式
    if (payload.length == _legacyPayloadLength) {
      return _decodeLegacyPayload(
        payload,
        remoteId: remoteId,
        deviceName: deviceName,
        rssi: rssi,
        receivedAt: receivedAt,
        companyId: companyId,
      );
    }

    if (payload.length != _expectedPayloadLength) {
      throw BleMeshInvalidPayloadException(
        'SOS 载荷长度错误，期望 $_expectedPayloadLength 字节，实际为 ${payload.length} 字节。',
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(payload));
    final protocolVersion = byteData.getUint8(0);
    final bloodTypeCode = byteData.getUint8(1);
    final latitude = byteData.getFloat32(2, Endian.little);
    final longitude = byteData.getFloat32(6, Endian.little);
    // offset 10-13: timestamp (uint32 LE) — 暂不存入 SosMessage

    return models.SosMessage(
      companyId: companyId,
      remoteId: remoteId,
      deviceName: deviceName,
      sosFlag: protocolVersion != 0,
      latitude: latitude,
      longitude: longitude,
      bloodTypeCode: bloodTypeCode,
      rssi: rssi,
      receivedAt: receivedAt ?? DateTime.now(),
      rawPayload: List<int>.unmodifiable(payload),
    );
  }

  /// 解码 8 字节紧凑格式
  /// 格式: [version(1)][flags(1)][lat_int16(2)][lon_int16(2)][timestamp_u16(2)]
  models.SosMessage _decodeCompactPayload(
    List<int> payload, {
    required String remoteId,
    String deviceName = '',
    int rssi = 0,
    DateTime? receivedAt,
    int companyId = rescueCompanyId,
  }) {
    final byteData = ByteData.sublistView(Uint8List.fromList(payload));
    final flags = byteData.getUint8(1);

    // 检查紧凑格式标志 (bit7)
    if ((flags & 0x80) == 0) {
      throw const BleMeshInvalidPayloadException('紧凑格式标志位不正确');
    }

    final sosFlag = (flags & 0x01) != 0;

    // 解压缩坐标
    const latScale = 32767.0 / 90.0;
    const lonScale = 32767.0 / 180.0;

    final latInt = byteData.getInt16(2, Endian.little);
    final lonInt = byteData.getInt16(4, Endian.little);

    final latitude = latInt / latScale;
    final longitude = lonInt / lonScale;

    // 恢复时间戳
    final baseTime = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch ~/ 1000;
    final timestampOffset = byteData.getUint16(6, Endian.little);
    final receivedTimestamp = baseTime + timestampOffset;

    return models.SosMessage(
      companyId: companyId,
      remoteId: remoteId,
      deviceName: deviceName,
      sosFlag: sosFlag,
      latitude: latitude,
      longitude: longitude,
      bloodTypeCode: 0, // 紧凑格式不包含血型
      rssi: rssi,
      receivedAt: receivedAt ??
          DateTime.fromMillisecondsSinceEpoch(receivedTimestamp * 1000),
      rawPayload: List<int>.unmodifiable(payload),
    );
  }

  /// 解码 10 字节遗留格式（int32 坐标 × 10⁶）
  models.SosMessage _decodeLegacyPayload(
    List<int> payload, {
    required String remoteId,
    String deviceName = '',
    int rssi = 0,
    DateTime? receivedAt,
    int companyId = rescueCompanyId,
  }) {
    final byteData = ByteData.sublistView(Uint8List.fromList(payload));
    final sosFlag = byteData.getUint8(0) != 0;
    final latitudeInt = byteData.getInt32(1, Endian.little);
    final longitudeInt = byteData.getInt32(5, Endian.little);
    final bloodTypeCode = byteData.getInt8(9);

    return models.SosMessage(
      companyId: companyId,
      remoteId: remoteId,
      deviceName: deviceName,
      sosFlag: sosFlag,
      latitude: latitudeInt / 1000000.0,
      longitude: longitudeInt / 1000000.0,
      bloodTypeCode: bloodTypeCode,
      rssi: rssi,
      receivedAt: receivedAt ?? DateTime.now(),
      rawPayload: List<int>.unmodifiable(payload),
    );
  }

  Future<void> stopScanning() async {
    await _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;

    // 停止 Coded PHY 扫描
    await _codedPhySubscription?.cancel();
    _codedPhySubscription = null;
    await CodedPhyScanner.stopScan();

    if (Platform.isAndroid && FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (error) {
        final exception = _mapScanError(error);
        _setException(exception);
        _isScanning = false;
        notifyListeners();
        throw exception;
      }
    }

    _isScanning = false;
    notifyListeners();
  }

  Future<void> _performInit() async {
    if (_isInitializing) {
      return;
    }

    _isInitializing = true;
    _setException(null);
    notifyListeners();

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        throw const BleMeshUnsupportedException('当前设备不支持 BLE 扫描。');
      }

      await _ensureRuntimePermissions();
      if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.unknown) {
        _adapterState = await FlutterBluePlus.adapterState.first;
      } else {
        _adapterState = FlutterBluePlus.adapterStateNow;
      }
      _permissionsGranted = true;
    } on BleMeshException catch (error) {
      if (error is BleMeshPermissionDeniedException) {
        _permissionsGranted = false;
      }
      _setException(error);
      rethrow;
    } catch (error) {
      _permissionsGranted = false;
      final exception = BleMeshPlatformException(
        platformCode: 'scan_init_failed',
        message: 'BLE 扫描初始化失败。',
        details: error,
      );
      _setException(exception);
      throw exception;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _ensureRuntimePermissions() async {
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final deniedPermissions = <Permission>[];
    final permanentlyDeniedPermissions = <Permission>[];

    for (final entry in statuses.entries) {
      if (!entry.value.isGranted) {
        deniedPermissions.add(entry.key);
      }
      if (entry.value.isPermanentlyDenied) {
        permanentlyDeniedPermissions.add(entry.key);
      }
    }

    if (deniedPermissions.isNotEmpty) {
      throw BleMeshPermissionDeniedException(
        deniedPermissions: deniedPermissions,
        permanentlyDeniedPermissions: permanentlyDeniedPermissions,
        message: permanentlyDeniedPermissions.isNotEmpty
            ? '扫描所需的蓝牙或定位权限被永久拒绝，请前往系统设置手动开启。'
            : '扫描所需的蓝牙或定位权限未授予。',
      );
    }

    _permissionsGranted = true;
  }

  Future<void> _handleScanResults(List<ScanResult> results) async {
    for (final result in results) {
      final payload =
          result.advertisementData.manufacturerData[rescueCompanyId];
      if (payload == null) {
        continue;
      }

      try {
        final message = decodeSosPayload(
          payload,
          remoteId: result.device.remoteId.str,
          deviceName: result.advertisementData.advName,
          rssi: result.rssi,
          receivedAt: result.timeStamp,
          companyId: rescueCompanyId,
        );

        // Save to database for persistence and upload
        await appDb.saveIncomingSos(message);
        bleMeshService.addRelayMessage(message);

        if (_shouldEmit(message)) {
          _sosMessageController.add(message);
        }
      } on BleMeshException catch (error) {
        _setException(error);
      } catch (error) {
        _setException(
          BleMeshPlatformException(
            platformCode: 'scan_decode_failed',
            message: '扫描结果解码失败。',
            details: error,
          ),
        );
      }
    }
  }

  void _handleScanError(Object error) {
    final exception = _mapScanError(error);
    _setException(exception);
  }

  bool _shouldEmit(models.SosMessage message) {
    final now = DateTime.now();
    _recentFingerprints.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _duplicateSuppressionWindow,
    );

    final fingerprint = _buildFingerprint(message);
    final lastSeen = _recentFingerprints[fingerprint];
    if (lastSeen != null &&
        now.difference(lastSeen) <= _duplicateSuppressionWindow) {
      return false;
    }

    _recentFingerprints[fingerprint] = now;
    return true;
  }

  String _buildFingerprint(models.SosMessage message) {
    return message.rawPayload
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  BleMeshException _mapScanError(Object error) {
    if (error is BleMeshException) {
      return error;
    }

    final message = error.toString().toLowerCase();
    if (message.contains('permission')) {
      return const BleMeshPermissionDeniedException(
        deniedPermissions: [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ],
        permanentlyDeniedPermissions: [],
      );
    }
    if (message.contains('powered off') ||
        message.contains('bluetooth') && message.contains('off')) {
      return const BleMeshBluetoothDisabledException('蓝牙已关闭，无法继续扫描。');
    }
    if (message.contains('unsupported')) {
      return const BleMeshUnsupportedException('当前设备不支持 BLE 扫描。');
    }

    return BleMeshPlatformException(
      platformCode: 'scan_failed',
      message: 'BLE 扫描失败。',
      details: error,
    );
  }

  void _setException(BleMeshException? exception) {
    _lastException = exception;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopScanning());
    _adapterSubscription?.cancel();
    _sosMessageController.close();
    super.dispose();
  }
}

final bleScannerService = BleScannerService();
