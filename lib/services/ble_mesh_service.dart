import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../database.dart';
import '../models/emergency_profile.dart';
import '../models/sos_advertisement_payload.dart';
import '../models/sos_message.dart' as models;
import 'ble_mesh_exceptions.dart';
import 'ble_payload_encoder.dart';
import 'power_saving_manager.dart';

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

  // Relay Queue mechanism
  Timer? _interleavedBroadcastTimer;
  final Map<String, _RelayQueueEntry> _relayQueue = {};
  bool _isOwnSosActive = false;
  List<int>? _ownSosPayload;
  String? _lastBroadcastKey;

  // Constants for relay mechanism - 优化传播距离
  static const Duration _relayFetchInterval = Duration(
    seconds: 30,
  ); // 缩短获取间隔，更快响应新消息
  static const Duration _relayMaxAge = Duration(hours: 6); // 延长有效期，支持更远距离传播
  static const int _maxRelayPayloads = 15; // 增加中继容量，从5提升到15
  static const Duration _relayCooldown = Duration(seconds: 6);
  static const int _defaultRelayBudget = 4;
  static const int _ownRelayBudget = 1 << 20;
  static const Duration _broadcastSwitchInterval = Duration(
    milliseconds: 800,
  ); // 缩短切换间隔，提高传播效率

  // 使用紧凑格式 payload（8字节 vs 14字节）
  // 更小的 payload = 空中传输时间更短 = 接收成功率更高
  static const bool _useCompactPayload = true;

  Timer? _relayFetchTimer;

  BluetoothAdapterState get adapterState => _adapterState;
  bool get permissionsGranted => _permissionsGranted;
  bool get isInitializing => _isInitializing;
  bool get isBroadcastingNow => _isBroadcastingNow;
  bool get isAdvertising => _isBroadcastingNow;
  bool get relayEnabled => _relayEnabled;
  bool get isRelayActive => _relayQueue.isNotEmpty;
  int get queueLength => _relayQueue.length;
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
      const exception = BleMeshBluetoothDisabledException();
      _setException(exception);
      throw exception;
    }

    // 根据配置选择编码格式
    List<int> encodedPayload;
    if (_useCompactPayload) {
      // 紧凑格式 (8字节) — 远距离传输
      encodedPayload = _wrapManufacturerData(
        companyId,
        BlePayloadEncoder.encodeCompactSosData(
          lat: latitude,
          lon: longitude,
          bloodType: bloodType.code,
          time: DateTime.now(),
          sosFlag: sosFlag ? 1 : 0,
        ),
      );
    } else {
      // 标准格式 (14字节)
      final payload = SosAdvertisementPayload(
        companyId: companyId,
        longitude: longitude,
        latitude: latitude,
        bloodType: bloodType,
        sosFlag: sosFlag,
      );
      encodedPayload = payload.manufacturerPayload;
    }

    try {
      // Store own SOS payload（不含Company ID的部分）
      _ownSosPayload = encodedPayload;
      _isOwnSosActive = true;

      // Stop any existing broadcast first
      await _stopNativeBroadcast();

      // Start interleaved broadcast with relay queue
      await _startInterleavedBroadcast();

      _setException(null);
    } on PlatformException catch (error) {
      final exception = _mapPlatformException(error);
      _setException(exception);
      throw exception;
    } on BleMeshException catch (error) {
      _setException(error);
      rethrow;
    } catch (error) {
      final exception = BleMeshPlatformException(
        platformCode: 'start_broadcast_failed',
        message: '启动 SOS 广播失败：$error',
        details: error,
      );
      _setException(exception);
      throw exception;
    }
  }

  Future<void> stopSosBroadcast() async {
    // Stop the interleaved broadcast timer
    _interleavedBroadcastTimer?.cancel();
    _interleavedBroadcastTimer = null;

    // Stop the relay fetch timer
    _relayFetchTimer?.cancel();
    _relayFetchTimer = null;

    // Clear the broadcast queue
    _relayQueue.clear();
    _lastBroadcastKey = null;
    _ownSosPayload = null;
    _isOwnSosActive = false;

    // Stop the native broadcast
    await _stopNativeBroadcast();

    if (!Platform.isAndroid) {
      _isBroadcastingNow = false;
      _isBroadcastingController.add(false);
      notifyListeners();
      return;
    }

    _setException(null);
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

  // ============================================================================
  // Relay Queue Mechanism - Core Implementation
  // ============================================================================

  /// Start the interleaved broadcast mechanism with relay queue
  ///
  /// This implements the "Store & Forward" multi-hop relay algorithm:
  /// 1. Broadcast own SOS signal (priority 0)
  /// 2. Cycle through relay payloads from other devices
  /// 3. Switch every 1.5 seconds to simulate round-robin broadcasting
  Future<void> _startInterleavedBroadcast() async {
    if (!Platform.isAndroid) {
      debugPrint(
        '[BLE Relay] Interleaved broadcast not supported on this platform',
      );
      return;
    }

    try {
      if (_isOwnSosActive && _ownSosPayload != null) {
        _upsertRelayEntry(
          _RelayQueueEntry(
            key: _buildRelayKey(_ownSosPayload!),
            payloadBytes: _ownSosPayload!,
            firstSeenAt: DateTime.now(),
            lastSeenAt: DateTime.now(),
            relayBudget: _ownRelayBudget,
            relayCount: 0,
            isOwnPayload: true,
            sourceMac: 'self',
            basePriority: 100,
          ),
        );
      }

      try {
        await _rebuildBroadcastQueue();
      } catch (error) {
        debugPrint(
          '[BLE Relay] Failed to rebuild broadcast queue (continuing with existing queue): $error',
        );
      }

      // Start the periodic timer to switch broadcasts
      _interleavedBroadcastTimer?.cancel();
      _interleavedBroadcastTimer = Timer.periodic(
        _broadcastSwitchInterval,
        (_) => unawaited(_switchBroadcastPayload()),
      );

      // Start periodic relay payload refresh
      _relayFetchTimer?.cancel();
      _relayFetchTimer = Timer.periodic(
        _relayFetchInterval,
        (_) => _refreshRelayPayloads(),
      );

      // Set broadcasting state to true
      _isBroadcastingNow = true;
      _isBroadcastingController.add(true);
      notifyListeners();

      await _switchBroadcastPayload(forceImmediate: true);

      debugPrint(
        '[BLE Relay] Interleaved broadcast started with ${_relayQueue.length} payloads',
      );
    } catch (error) {
      debugPrint('[BLE Relay] Failed to start interleaved broadcast: $error');
      rethrow;
    }
  }

  /// Fetch unuploaded SOS records from database for relay
  ///
  /// Storm prevention mechanisms:
  /// - Only fetch records from last 2 hours (prevent infinite broadcast)
  /// - Limit to 5 most recent records (prevent Bluetooth payload overload)
  Future<List<StoredSosMessage>> _fetchRelayPayloads() async {
    if (!_relayEnabled) {
      debugPrint('[BLE Relay] Relay is disabled, skipping fetch');
      return [];
    }

    try {
      final now = DateTime.now();
      final threshold = now.subtract(_relayMaxAge);

      // Query database for unuploaded recent SOS messages
      // 智能中继选择：优先选择更新的消息，确保传播链不断裂
      final messages = await appDb
          .customSelect(
            '''
        SELECT id, sender_mac, latitude, longitude, blood_type, timestamp, is_uploaded
        FROM sos_messages
        WHERE is_uploaded = 0 AND timestamp >= ?
        ORDER BY timestamp DESC  -- 优先选择最新的消息，保证传播时效性
        LIMIT ?
        ''',
            variables: [
              Variable<DateTime>(threshold),
              const Variable<int>(_maxRelayPayloads),
            ],
            readsFrom: const {},
          )
          .get();

      final storedMessages = messages.map((row) {
        return StoredSosMessage(
          id: row.read<int>('id'),
          senderMac: row.read<String>('sender_mac'),
          latitude: row.read<double>('latitude'),
          longitude: row.read<double>('longitude'),
          bloodType: row.read<int>('blood_type'),
          timestamp: row.read<DateTime>('timestamp'),
          isUploaded: row.read<bool>('is_uploaded'),
        );
      }).toList();

      debugPrint(
        '[BLE Relay] Fetched ${storedMessages.length} relay payloads from database',
      );
      return storedMessages;
    } catch (error) {
      debugPrint('[BLE Relay] Failed to fetch relay payloads: $error');
      return [];
    }
  }

  /// Refresh relay payloads periodically
  Future<void> _refreshRelayPayloads() async {
    debugPrint('[BLE Relay] Refreshing relay payloads...');
    await _rebuildBroadcastQueue();
  }

  /// Rebuild the broadcast queue with own SOS + relay payloads
  ///
  /// Queue structure:
  /// - Index 0: Own SOS payload (if active)
  /// - Index 1..N: Relay payloads from other devices
  Future<void> _rebuildBroadcastQueue() async {
    _pruneRelayQueue();

    if (_isOwnSosActive && _ownSosPayload != null) {
      _upsertRelayEntry(
        _RelayQueueEntry(
          key: _buildRelayKey(_ownSosPayload!),
          payloadBytes: _ownSosPayload!,
          firstSeenAt: DateTime.now(),
          lastSeenAt: DateTime.now(),
          relayBudget: _ownRelayBudget,
          relayCount: 0,
          isOwnPayload: true,
          sourceMac: 'self',
          basePriority: 100,
        ),
      );
    }

    final relayMessages = await _fetchRelayPayloads();
    final seenKeys = <String>{};

    for (final message in relayMessages) {
      try {
        final payloadBytes = _encodeRelayPayload(
          latitude: message.latitude,
          longitude: message.longitude,
          bloodTypeCode: message.bloodType,
          timestamp: message.timestamp,
        );
        final entryKey = _buildRelayKey(payloadBytes);
        seenKeys.add(entryKey);
        _upsertRelayEntry(
          _RelayQueueEntry(
            key: entryKey,
            payloadBytes: payloadBytes,
            firstSeenAt: message.timestamp,
            lastSeenAt: DateTime.now(),
            relayBudget: _defaultRelayBudget,
            relayCount: 0,
            isOwnPayload: false,
            sourceMac: message.senderMac,
            dbMessageId: message.id,
            basePriority: 55,
            originatingTimestamp: message.timestamp,
          ),
        );
        debugPrint('[BLE Relay] Added relay payload from ${message.senderMac}');
      } catch (error) {
        debugPrint('[BLE Relay] Failed to encode relay payload: $error');
      }
    }

    _pruneRelayQueue(retainKeys: seenKeys);
    debugPrint(
      '[BLE Relay] Queue rebuilt with ${_relayQueue.length} total payloads',
    );
    notifyListeners();
  }

  /// Switch to the next broadcast payload in round-robin fashion
  ///
  /// This is the "interleaved" part of the algorithm:
  /// - Stop current broadcast
  /// - Wait for completion
  /// - Start new broadcast with next payload
  Future<void> _switchBroadcastPayload({bool forceImmediate = false}) async {
    _pruneRelayQueue();
    if (_relayQueue.isEmpty) {
      debugPrint('[BLE Relay] Queue empty, skipping switch');
      return;
    }

    try {
      final nextEntry = _selectNextRelayEntry(forceImmediate: forceImmediate);
      if (nextEntry == null) {
        debugPrint('[BLE Relay] No eligible payload found for this cycle');
        return;
      }

      debugPrint('[BLE Relay] Switching to payload ${nextEntry.key}');

      // Ensure we stop before starting new broadcast
      await _stopNativeBroadcast();

      // Small delay to ensure Bluetooth hardware is ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Start new broadcast with next payload
      await _startNativeBroadcast(nextEntry.payloadBytes);
      nextEntry.lastRelayedAt = DateTime.now();
      if (!nextEntry.isOwnPayload) {
        nextEntry.relayCount += 1;
        nextEntry.relayBudget -= 1;
      }
      _lastBroadcastKey = nextEntry.key;
      _pruneRelayQueue();
    } catch (error) {
      debugPrint('[BLE Relay] Error switching payload: $error');
      // Don't rethrow - continue trying to switch
    }
  }

  /// Stop the native BLE broadcast (Android platform)
  Future<void> _stopNativeBroadcast() async {
    if (!Platform.isAndroid) {
      _isBroadcastingNow = false;
      _isBroadcastingController.add(false);
      notifyListeners();
      return;
    }

    try {
      await _broadcastChannel.invokeMethod<void>('stopSosBroadcast');
      _isBroadcastingNow = false;
      _isBroadcastingController.add(false);
      notifyListeners();
      debugPrint('[BLE Relay] Native broadcast stopped');
    } on PlatformException catch (error) {
      debugPrint('[BLE Relay] Error stopping broadcast: ${error.code}');
      // Don't throw - continue anyway
    } catch (error) {
      debugPrint('[BLE Relay] Unexpected error stopping broadcast: $error');
      // Don't throw - continue anyway
    }
  }

  /// Start native BLE broadcast with specific payload (Android platform)
  Future<void> _startNativeBroadcast(List<int> payloadBytes) async {
    if (!Platform.isAndroid) {
      _isBroadcastingNow = true;
      _isBroadcastingController.add(true);
      notifyListeners();
      return;
    }

    try {
      // Extract manufacturer ID and payload from the full data
      final manufacturerId = (payloadBytes[1] << 8) | payloadBytes[0];
      final actualPayload = payloadBytes.sublist(2);

      await _broadcastChannel.invokeMethod<void>('startSosBroadcast', {
        'manufacturerId': manufacturerId,
        'payload': actualPayload,
        'advertiseIntervalMs': powerSavingManager
            .getBleAdvertiseInterval()
            .inMilliseconds,
      });

      _isBroadcastingNow = true;
      _isBroadcastingController.add(true);
      notifyListeners();
      debugPrint(
        '[BLE Relay] Native broadcast started with payload length ${actualPayload.length}',
      );
    } on PlatformException catch (error) {
      debugPrint('[BLE Relay] Error starting broadcast: ${error.code}');
      // Don't rethrow - try to recover
      _isBroadcastingNow = true;
      _isBroadcastingController.add(true);
      notifyListeners();
    } catch (error) {
      debugPrint('[BLE Relay] Unexpected error starting broadcast: $error');
      // Don't rethrow - try to recover
      _isBroadcastingNow = true;
      _isBroadcastingController.add(true);
      notifyListeners();
    }
  }

  /// Manually add a relay payload to the queue (for real-time relay)
  ///
  /// This can be called by the BLE scanner service when it discovers
  /// a new SOS message from another device
  void addRelayPayload(SosAdvertisementPayload payload) {
    final payloadBytes = payload.rawManufacturerData;
    final key = _buildRelayKey(payloadBytes);
    _upsertRelayEntry(
      _RelayQueueEntry(
        key: key,
        payloadBytes: payloadBytes,
        firstSeenAt: payload.timestamp ?? DateTime.now(),
        lastSeenAt: DateTime.now(),
        relayBudget: _defaultRelayBudget,
        relayCount: 0,
        isOwnPayload: false,
        basePriority: 60,
        originatingTimestamp: payload.timestamp,
      ),
    );
    debugPrint('[BLE Relay] Added payload $key, queue size: ${_relayQueue.length}');
    notifyListeners();
  }

  void addRelayMessage(models.SosMessage message) {
    final payloadBytes = _wrapManufacturerData(message.companyId, message.rawPayload);
    final key = _buildRelayKey(payloadBytes);
    _upsertRelayEntry(
      _RelayQueueEntry(
        key: key,
        payloadBytes: payloadBytes,
        firstSeenAt: message.receivedAt,
        lastSeenAt: DateTime.now(),
        relayBudget: _defaultRelayBudget,
        relayCount: 0,
        isOwnPayload: false,
        sourceMac: message.remoteId,
        basePriority: 70,
        sourceRssi: message.rssi,
        originatingTimestamp: message.receivedAt,
      ),
    );
    debugPrint(
      '[BLE Relay] Added realtime relay message $key (rssi=${message.rssi}), queue size: ${_relayQueue.length}',
    );
    notifyListeners();
  }

  List<int> _wrapManufacturerData(int companyId, List<int> manufacturerPayload) {
    final bytes = <int>[
      companyId & 0xFF,
      (companyId >> 8) & 0xFF,
      ...manufacturerPayload,
    ];
    return List<int>.unmodifiable(bytes);
  }

  List<int> _encodeRelayPayload({
    required double latitude,
    required double longitude,
    required int bloodTypeCode,
    required DateTime timestamp,
    int companyId = 0xFFFF,
  }) {
    if (_useCompactPayload) {
      return _wrapManufacturerData(
        companyId,
        BlePayloadEncoder.encodeCompactSosData(
          lat: latitude,
          lon: longitude,
          bloodType: bloodTypeCode,
          time: timestamp,
          sosFlag: 1,
        ),
      );
    }

    final bloodType = BloodType.values.firstWhere(
      (bt) => bt.code == bloodTypeCode,
      orElse: () => BloodType.unknown,
    );
    return SosAdvertisementPayload(
      companyId: companyId,
      longitude: longitude,
      latitude: latitude,
      bloodType: bloodType,
      sosFlag: true,
      timestamp: timestamp,
    ).rawManufacturerData;
  }

  String _buildRelayKey(List<int> payloadBytes) {
    return payloadBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _upsertRelayEntry(_RelayQueueEntry incoming) {
    final existing = _relayQueue[incoming.key];
    if (existing != null) {
      existing.lastSeenAt = incoming.lastSeenAt;
      existing.sourceRssi = _preferRssi(existing.sourceRssi, incoming.sourceRssi);
      existing.basePriority = math.max(existing.basePriority, incoming.basePriority);
      existing.dbMessageId ??= incoming.dbMessageId;
      existing.sourceMac ??= incoming.sourceMac;
      existing.relayBudget = math.max(existing.relayBudget, incoming.relayBudget);
      if (incoming.originatingTimestamp != null) {
        if (existing.originatingTimestamp == null ||
            incoming.originatingTimestamp!.isBefore(existing.originatingTimestamp!)) {
          existing.originatingTimestamp = incoming.originatingTimestamp;
        }
      }
      return;
    }

    if (_relayQueue.length >= _maxRelayPayloads + (_isOwnSosActive ? 1 : 0)) {
      _evictLowestPriorityRelay();
    }

    _relayQueue[incoming.key] = incoming;
  }

  int? _preferRssi(int? current, int? next) {
    if (next == null) return current;
    if (current == null) return next;
    return next > current ? next : current;
  }

  void _evictLowestPriorityRelay() {
    final now = DateTime.now();
    final candidates = _relayQueue.values.where((entry) => !entry.isOwnPayload).toList();
    if (candidates.isEmpty) {
      return;
    }
    candidates.sort((a, b) => _scoreRelayEntry(a, now).compareTo(_scoreRelayEntry(b, now)));
    _relayQueue.remove(candidates.first.key);
  }

  void _pruneRelayQueue({Set<String>? retainKeys}) {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    for (final entry in _relayQueue.values) {
      if (entry.isOwnPayload) {
        continue;
      }
      final expiredByBudget = entry.relayBudget <= 0;
      final expiredByAge = now.difference(entry.lastSeenAt) > _relayMaxAge;
      final missingFromSnapshot =
          retainKeys != null && !retainKeys.contains(entry.key) && entry.dbMessageId != null;
      if (expiredByBudget || expiredByAge || missingFromSnapshot) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _relayQueue.remove(key);
    }
  }

  _RelayQueueEntry? _selectNextRelayEntry({required bool forceImmediate}) {
    final now = DateTime.now();
    final candidates = _relayQueue.values.where((entry) {
      if (!forceImmediate &&
          entry.lastRelayedAt != null &&
          now.difference(entry.lastRelayedAt!) < _relayCooldown) {
        return false;
      }
      if (!entry.isOwnPayload && entry.relayBudget <= 0) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final scoreCompare = _scoreRelayEntry(b, now).compareTo(_scoreRelayEntry(a, now));
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final aLast = a.lastRelayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bLast = b.lastRelayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aLast.compareTo(bLast);
    });

    if (_lastBroadcastKey != null &&
        candidates.length > 1 &&
        candidates.first.key == _lastBroadcastKey) {
      return candidates[1];
    }
    return candidates.first;
  }

  double _scoreRelayEntry(_RelayQueueEntry entry, DateTime now) {
    final ageSeconds = now.difference(entry.firstSeenAt).inSeconds;
    final freshnessScore = math.max(0, 180 - ageSeconds) / 12.0;
    final cooldownScore = entry.lastRelayedAt == null
        ? 8.0
        : math.min(now.difference(entry.lastRelayedAt!).inSeconds / 2.0, 10.0);
    final relayBudgetScore = entry.isOwnPayload ? 30.0 : entry.relayBudget * 3.0;
    final relayPenalty = entry.relayCount * 2.0;
    final rssiScore = entry.sourceRssi == null
        ? 1.0
        : ((entry.sourceRssi! + 100).clamp(0, 70) / 10.0);
    final repeatPenalty = entry.key == _lastBroadcastKey ? 6.0 : 0.0;
    final ownScore = entry.isOwnPayload ? 40.0 : 0.0;

    return entry.basePriority +
        ownScore +
        freshnessScore +
        cooldownScore +
        relayBudgetScore +
        rssiScore -
        relayPenalty -
        repeatPenalty;
  }

  /// Mark a relay payload as uploaded (will be removed from queue)
  Future<void> markRelayAsUploaded(int messageId) async {
    try {
      await appDb.customUpdate(
        '''
        UPDATE sos_messages
        SET is_uploaded = 1
        WHERE id = ?
        ''',
        variables: [Variable<int>(messageId)],
        updates: const {},
      );
      debugPrint('[BLE Relay] Marked message $messageId as uploaded');

      // Rebuild queue to remove uploaded message
      await _rebuildBroadcastQueue();
    } catch (error) {
      debugPrint('[BLE Relay] Failed to mark message as uploaded: $error');
    }
  }

  @override
  void dispose() {
    // Clean up relay timers
    _interleavedBroadcastTimer?.cancel();
    _interleavedBroadcastTimer = null;
    _relayFetchTimer?.cancel();
    _relayFetchTimer = null;

    _adapterSubscription?.cancel();
    _broadcastSubscription?.cancel();
    _isBroadcastingController.close();
    super.dispose();
  }
}

class _RelayQueueEntry {
  _RelayQueueEntry({
    required this.key,
    required this.payloadBytes,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.relayBudget,
    required this.relayCount,
    required this.isOwnPayload,
    required this.basePriority,
    this.sourceMac,
    this.dbMessageId,
    this.sourceRssi,
    this.originatingTimestamp,
  });

  final String key;
  final List<int> payloadBytes;
  final DateTime firstSeenAt;
  DateTime lastSeenAt;
  DateTime? lastRelayedAt;
  int relayBudget;
  int relayCount;
  final bool isOwnPayload;
  int basePriority;
  String? sourceMac;
  int? dbMessageId;
  int? sourceRssi;
  DateTime? originatingTimestamp;
}

final bleMeshService = BleMeshService();
