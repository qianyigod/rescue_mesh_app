import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/emergency_profile.dart';
import '../models/sos_advertisement_payload.dart';
import 'ble_mesh_exceptions.dart';

class BleMeshService extends ChangeNotifier {
  BleMeshService() {
    if (Platform.isAndroid) {
      _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
        _adapterState = state;
        notifyListeners();
      });
      _broadcastSubscription = _broadcastStateChannel
          .receiveBroadcastStream()
          .listen(_handleBroadcastState, onError: _handleBroadcastStateError);
    }
  }

  static const MethodChannel _broadcastChannel = MethodChannel(
    'rescue_mesh/advertiser',
  );
  static const EventChannel _broadcastStateChannel = EventChannel(
    'rescue_mesh/advertiser_state',
  );

  final StreamController<bool> _isBroadcastingController =
      StreamController<bool>.broadcast();

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<dynamic>? _broadcastSubscription;
  Future<void>? _initFuture;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  BleMeshException? _lastException;
  bool _isInitializing = false;
  bool _isBroadcastingNow = false;
  bool _permissionsGranted = false;
  bool _relayEnabled = true;

  BluetoothAdapterState get adapterState => _adapterState;
  bool get permissionsGranted => _permissionsGranted;
  bool get isInitializing => _isInitializing;
  bool get isBroadcastingNow => _isBroadcastingNow;
  bool get isAdvertising => _isBroadcastingNow;
  bool get relayEnabled => _relayEnabled;
  BleMeshException? get lastException => _lastException;
  String? get lastError => _lastException?.message;
  bool get isAdapterReady => _adapterState == BluetoothAdapterState.on;
  Stream<bool> get isBroadcasting => _isBroadcastingController.stream;

  @Deprecated('Use init() instead.')
  Future<void> initialize() => init();

  @Deprecated('Use startSosBroadcast() instead.')
  Future<void> startSosAdvertising(SosAdvertisementPayload payload) {
    return startSosBroadcast(
      latitude: payload.latitude,
      longitude: payload.longitude,
      bloodType: payload.bloodType,
      sosFlag: payload.sosFlag,
      companyId: payload.companyId,
    );
  }

  @Deprecated('Use stopSosBroadcast() instead.')
  Future<void> stopSosAdvertising() => stopSosBroadcast();

  @Deprecated('Use isBroadcasting instead.')
  Stream<bool> get advertisingState => isBroadcasting;

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

  Future<void> refresh() async {
    await init();
  }

  @Deprecated('Use init() instead.')
  Future<bool> ensureRuntimePermissions() async {
    await init();
    return _permissionsGranted;
  }

  Future<void> startSosBroadcast({
    required double latitude,
    required double longitude,
    required BloodType bloodType,
    bool sosFlag = true,
    int companyId = 0xFFFF,
  }) async {
    await init();
    if (!Platform.isAndroid) {
      throw const BleMeshUnsupportedException('当前仅实现了 Android 端的 SOS BLE 广播。');
    }
    if (!isAdapterReady) {
      final exception = const BleMeshBluetoothDisabledException();
      _setException(exception);
      throw exception;
    }

    final payload = SosAdvertisementPayload(
      companyId: companyId,
      longitude: longitude,
      latitude: latitude,
      bloodType: bloodType,
      sosFlag: sosFlag,
    );

    try {
      await _broadcastChannel.invokeMethod<void>('startSosBroadcast', {
        'manufacturerId': payload.companyId,
        'payload': payload.manufacturerPayload,
      });
      _setException(null);
    } on PlatformException catch (error) {
      final exception = _mapPlatformException(error);
      _setException(exception);
      throw exception;
    } on BleMeshException catch (error) {
      _setException(error);
      throw error;
    }
  }

  Future<void> stopSosBroadcast() async {
    if (!Platform.isAndroid) {
      _isBroadcastingNow = false;
      _isBroadcastingController.add(false);
      notifyListeners();
      return;
    }

    try {
      await _broadcastChannel.invokeMethod<void>('stopSosBroadcast');
      _setException(null);
    } on PlatformException catch (error) {
      final exception = BleMeshPlatformException(
        platformCode: error.code,
        message: error.message ?? '停止 SOS 广播失败。',
        details: error.details,
      );
      _setException(exception);
      throw exception;
    }
  }

  Future<void> setRelayEnabled(bool value) async {
    _relayEnabled = value;
    notifyListeners();
  }

  Future<void> _performInit() async {
    if (_isInitializing) return;

    _isInitializing = true;
    _setException(null);
    notifyListeners();

    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        throw const BleMeshUnsupportedException();
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
        platformCode: 'init_failed',
        message: 'BLE 初始化失败。',
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
      Permission.bluetoothAdvertise,
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
            ? '部分蓝牙或定位权限被永久拒绝，请前往系统设置手动开启。'
            : '蓝牙或定位权限被拒绝，无法继续执行 SOS 广播。',
      );
    }

    _permissionsGranted = true;
  }

  void _handleBroadcastState(dynamic value) {
    if (value is bool) {
      _isBroadcastingNow = value;
      _isBroadcastingController.add(value);
      notifyListeners();
    }
  }

  void _handleBroadcastStateError(Object error) {
    final exception = BleMeshPlatformException(
      platformCode: 'state_stream_failed',
      message: '广播状态监听失败。',
      details: error,
    );
    _setException(exception);
  }

  BleMeshException _mapPlatformException(PlatformException error) {
    switch (error.code) {
      case 'unsupported':
        return BleMeshUnsupportedException(error.message);
      case 'permission':
        return BleMeshPermissionDeniedException(
          deniedPermissions: [
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
            Permission.bluetoothConnect,
            Permission.locationWhenInUse,
          ],
          permanentlyDeniedPermissions: [],
          message: error.message ?? '广播权限不足，请先授权蓝牙与定位权限。',
        );
      case 'disabled':
        return BleMeshBluetoothDisabledException(error.message);
      case 'unavailable':
        return BleMeshAdapterUnavailableException(error.message);
      case 'invalid_args':
        return BleMeshInvalidPayloadException(error.message);
      case 'broadcast_failed':
      case 'advertise_failed':
        return BleMeshBroadcastFailedException(
          platformCode: error.code,
          message: error.message ?? 'SOS 广播启动失败。',
          details: error.details,
        );
      default:
        return BleMeshPlatformException(
          platformCode: error.code,
          message: error.message ?? '发生未预期的 BLE 平台错误。',
          details: error.details,
        );
    }
  }

  void _setException(BleMeshException? exception) {
    _lastException = exception;
    notifyListeners();
  }

  @override
  void dispose() {
    _adapterSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _isBroadcastingController.close();
    super.dispose();
  }
}

final bleMeshService = BleMeshService();
