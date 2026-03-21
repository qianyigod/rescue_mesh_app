import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sos_message.dart';
import 'ble_mesh_exceptions.dart';

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
  static const int _expectedPayloadLength = 10;
  static const Duration _duplicateSuppressionWindow = Duration(seconds: 30);

  final StreamController<SosMessage> _sosMessageController =
      StreamController<SosMessage>.broadcast();

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  Future<void>? _initFuture;

  final Map<String, DateTime> _recentFingerprints = <String, DateTime>{};

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
  BleMeshException? get lastException => _lastException;
  String? get lastError => _lastException?.message;
  Stream<SosMessage> get sosMessageStream => _sosMessageController.stream;

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
      final exception = const BleMeshBluetoothDisabledException(
        '蓝牙未开启，无法开始扫描附近的 SOS 信标。',
      );
      _setException(exception);
      throw exception;
    }

    await stopScanning();
    _recentFingerprints.clear();

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

  SosMessage decodeSosPayload(
    List<int> payload, {
    required String remoteId,
    String deviceName = '',
    int rssi = 0,
    DateTime? receivedAt,
    int companyId = rescueCompanyId,
  }) {
    if (payload.length != _expectedPayloadLength) {
      throw BleMeshInvalidPayloadException(
        'SOS 载荷长度错误，期望 $_expectedPayloadLength 字节，实际为 ${payload.length} 字节。',
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(payload));
    final sosFlag = byteData.getUint8(0) != 0;
    final latitude = _decodeCoordinate(byteData, 1, isLatitude: true);
    final longitude = _decodeCoordinate(byteData, 5, isLatitude: false);
    final bloodTypeCode = byteData.getUint8(9);

    return SosMessage(
      companyId: companyId,
      remoteId: remoteId,
      deviceName: deviceName,
      sosFlag: sosFlag,
      latitude: latitude,
      longitude: longitude,
      bloodTypeCode: bloodTypeCode,
      rssi: rssi,
      receivedAt: receivedAt ?? DateTime.now(),
      rawPayload: List<int>.unmodifiable(payload),
    );
  }

  Future<void> stopScanning() async {
    await _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;

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

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final payload = result.advertisementData.manufacturerData[rescueCompanyId];
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

  double _decodeCoordinate(
    ByteData byteData,
    int offset, {
    required bool isLatitude,
  }) {
    final floatValue = byteData.getFloat32(offset, Endian.little);
    if (_isCoordinateInRange(floatValue, isLatitude: isLatitude)) {
      return floatValue;
    }

    final scaledValue = byteData.getInt32(offset, Endian.little) / 1000000.0;
    if (_isCoordinateInRange(scaledValue, isLatitude: isLatitude)) {
      return scaledValue;
    }

    throw BleMeshInvalidPayloadException(
      isLatitude ? '扫描到的纬度数据无效。' : '扫描到的经度数据无效。',
    );
  }

  bool _isCoordinateInRange(double value, {required bool isLatitude}) {
    if (!value.isFinite) {
      return false;
    }
    return isLatitude
        ? value >= -90.0 && value <= 90.0
        : value >= -180.0 && value <= 180.0;
  }

  bool _shouldEmit(SosMessage message) {
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

  String _buildFingerprint(SosMessage message) {
    final payloadHex = message.rawPayload
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${message.remoteId}|$payloadHex';
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
      return const BleMeshBluetoothDisabledException(
        '蓝牙已关闭，无法继续扫描。',
      );
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
