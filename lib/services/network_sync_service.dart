import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database.dart';
import 'network_sync_exceptions.dart';

typedef ConnectivityStatusStreamProvider =
    Stream<List<ConnectivityResult>> Function();
typedef ConnectivityStatusSnapshotProvider =
    Future<List<ConnectivityResult>> Function();

class NetworkSyncService extends ChangeNotifier {
  static const String _deviceIdPreferenceKey = 'network_sync_device_id';

  NetworkSyncService({
    AppDatabase? database,
    Connectivity? connectivity,
    http.Client? httpClient,
    Uri? endpoint,
    Duration? requestTimeout,
    String? muleId,
    ConnectivityStatusStreamProvider? connectivityStreamProvider,
    ConnectivityStatusSnapshotProvider? connectivitySnapshotProvider,
  }) : _database = database ?? appDb,
       _connectivity = connectivity ?? Connectivity(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _endpoint =
           endpoint ?? Uri.parse('http://101.35.52.133:3000/api/sos/sync'),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 12),
       _muleId = muleId,
       _connectivityStreamProvider = connectivityStreamProvider,
       _connectivitySnapshotProvider = connectivitySnapshotProvider;

  final AppDatabase _database;
  final Connectivity _connectivity;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri _endpoint;
  final Duration _requestTimeout;
  final String? _muleId;
  final ConnectivityStatusStreamProvider? _connectivityStreamProvider;
  final ConnectivityStatusSnapshotProvider? _connectivitySnapshotProvider;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  NetworkSyncException? _lastException;
  DateTime? _lastSuccessfulSyncAt;
  bool _isListening = false;
  bool _isSyncing = false;
  bool _hasNetwork = false;

  bool get isListening => _isListening;
  bool get isSyncing => _isSyncing;
  bool get hasNetwork => _hasNetwork;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  NetworkSyncException? get lastException => _lastException;
  String? get lastError => _lastException?.message;

  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    _isListening = true;
    _setException(null);
    notifyListeners();

    try {
      final initialStatuses = await _getConnectivitySnapshot();
      _hasNetwork = _hasUsableNetwork(initialStatuses);
      notifyListeners();

      _connectivitySubscription = _getConnectivityStream().listen(
        _handleConnectivityChanged,
        onError: (Object error) {
          _setException(
            NetworkSyncUnexpectedException(
              details: error,
              message:
                  'Network state listener failed. Automatic sync is paused until restart.',
            ),
          );
        },
      );

      if (_hasNetwork) {
        unawaited(syncNow());
      }
    } catch (error) {
      _isListening = false;
      final exception = NetworkSyncUnexpectedException(
        details: error,
        message: 'Failed to initialize network sync listener.',
      );
      _setException(exception);
      rethrow;
    }
  }

  Future<int> syncNow() async {
    if (_isSyncing) {
      debugPrint('[NetworkSync] Sync already running, skipping duplicate call.');
      return 0;
    }

    final currentStatuses = await _getConnectivitySnapshot();
    final currentHasNetwork = _hasUsableNetwork(currentStatuses);
    _hasNetwork = currentHasNetwork;

    if (!currentHasNetwork) {
      debugPrint('[NetworkSync] No usable network connection, aborting sync.');
      const exception = NetworkSyncOfflineException();
      _setException(exception);
      throw exception;
    }

    _isSyncing = true;
    _setException(null);
    notifyListeners();

    try {
      final deviceId = await _getOrCreateDeviceId();
      final pendingMessages = await _database.getPendingUploads();
      debugPrint(
        '[NetworkSync] Pending SOS messages: ${pendingMessages.length}',
      );

      if (pendingMessages.isEmpty) {
        debugPrint('[NetworkSync] Nothing to upload.');
        return 0;
      }

      final medicalProfile = await _getMedicalProfileJson();
      final firstMessageId = pendingMessages.first.id;
      final uploadData = pendingMessages.map((message) {
        final data = _mapMessageToJson(message, deviceId);
        if (message.id == firstMessageId && medicalProfile.isNotEmpty) {
          data['medicalProfile'] = medicalProfile;
        }
        return data;
      }).toList(growable: false);

      final requestBody = <String, Object?>{
        'muleId': _muleId ?? deviceId,
        'records': uploadData,
      };

      debugPrint('[NetworkSync] POST $_endpoint');
      debugPrint('[NetworkSync] Body: ${jsonEncode(requestBody)}');

      final response = await _httpClient
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(_requestTimeout);

      debugPrint('[NetworkSync] Response status: ${response.statusCode}');
      debugPrint('[NetworkSync] Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _database.markAsUploaded(
          pendingMessages.map((message) => message.id).toList(growable: false),
        );
        _lastSuccessfulSyncAt = DateTime.now();
        debugPrint(
          '[NetworkSync] Uploaded ${pendingMessages.length} SOS message(s).',
        );
        return pendingMessages.length;
      }

      final exception = NetworkSyncRequestFailedException(
        statusCode: response.statusCode,
        responseBody: response.body,
      );
      _setException(exception);
      return 0;
    } on TimeoutException {
      debugPrint('[NetworkSync] Request timed out.');
      const exception = NetworkSyncTimeoutException();
      _setException(exception);
      return 0;
    } on SocketException catch (error) {
      debugPrint('[NetworkSync] Socket error: $error');
      final exception = NetworkSyncUnexpectedException(
        details: error,
        message:
            'Failed to reach the command server. SOS data will stay local and retry later.',
      );
      _setException(exception);
      return 0;
    } catch (error) {
      debugPrint('[NetworkSync] Unexpected error: $error');
      if (error is NetworkSyncException) {
        _setException(error);
        return 0;
      }

      final exception = NetworkSyncUnexpectedException(details: error);
      _setException(exception);
      return 0;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isListening = false;
    notifyListeners();
  }

  void _handleConnectivityChanged(List<ConnectivityResult> statuses) {
    final hasNetwork = _hasUsableNetwork(statuses);
    final shouldTriggerSync = !_hasNetwork && hasNetwork;
    debugPrint(
      '[NetworkSync] Connectivity changed: $_hasNetwork -> $hasNetwork, trigger sync: $shouldTriggerSync',
    );
    _hasNetwork = hasNetwork;
    notifyListeners();

    if (shouldTriggerSync) {
      unawaited(syncNow());
    }
  }

  Stream<List<ConnectivityResult>> _getConnectivityStream() {
    return _connectivityStreamProvider?.call() ??
        _connectivity.onConnectivityChanged;
  }

  Future<List<ConnectivityResult>> _getConnectivitySnapshot() {
    return _connectivitySnapshotProvider?.call() ??
        _connectivity.checkConnectivity();
  }

  bool _hasUsableNetwork(List<ConnectivityResult> statuses) {
    for (final status in statuses) {
      if (status != ConnectivityResult.none) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> _mapMessageToJson(
    StoredSosMessage message,
    String deviceId,
  ) {
    return <String, Object?>{
      'id': message.id,
      'senderMac': _normalizeSenderMac(message.senderMac, deviceId),
      'latitude': message.latitude,
      'longitude': message.longitude,
      'bloodType': message.bloodType,
      'timestamp': message.timestamp.toUtc().toIso8601String(),
    };
  }

  String _normalizeSenderMac(String senderMac, String deviceId) {
    final normalized = senderMac.trim().toUpperCase();
    if (normalized.isEmpty || normalized == 'SELF') {
      return deviceId;
    }
    return normalized;
  }

  Future<Map<String, Object?>> _getMedicalProfileJson() async {
    try {
      final profile = await _database.getCurrentMedicalProfile();
      if (profile == null) {
        return <String, Object?>{};
      }

      return <String, Object?>{
        'name': profile.name,
        'age': profile.age,
        'bloodTypeDetail': profile.bloodType,
        'medicalHistory': profile.medicalHistory,
        'allergies': profile.allergies,
        'emergencyContact': profile.emergencyContact,
      };
    } catch (error) {
      debugPrint('[NetworkSync] Failed to load medical profile: $error');
      return <String, Object?>{};
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existingId = prefs.getString(_deviceIdPreferenceKey);
    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }

    final random = Random();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(16).toRadixString(16),
    ).join().toUpperCase();
    final deviceId =
        'PHONE-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase()}-$suffix';
    await prefs.setString(_deviceIdPreferenceKey, deviceId);
    return deviceId;
  }

  void _setException(NetworkSyncException? exception) {
    _lastException = exception;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stopListening());
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}

final networkSyncService = NetworkSyncService();
