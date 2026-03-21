import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database.dart';
import 'network_sync_exceptions.dart';

typedef ConnectivityStatusStreamProvider =
    Stream<List<ConnectivityResult>> Function();
typedef ConnectivityStatusSnapshotProvider =
    Future<List<ConnectivityResult>> Function();

class NetworkSyncService extends ChangeNotifier {
  NetworkSyncService({
    AppDatabase? database,
    Connectivity? connectivity,
    http.Client? httpClient,
    Uri? endpoint,
    Duration? requestTimeout,
    ConnectivityStatusStreamProvider? connectivityStreamProvider,
    ConnectivityStatusSnapshotProvider? connectivitySnapshotProvider,
  }) : _database = database ?? appDb,
       _connectivity = connectivity ?? Connectivity(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _endpoint =
           endpoint ??
           Uri.parse('https://api.rescuemesh.com/v1/sos/sync'),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 12),
       _connectivityStreamProvider = connectivityStreamProvider,
       _connectivitySnapshotProvider = connectivitySnapshotProvider;

  final AppDatabase _database;
  final Connectivity _connectivity;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Uri _endpoint;
  final Duration _requestTimeout;
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
              message: '网络状态监听失败，自动同步已停止等待下一次重启。',
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
        message: '初始化网络同步监听失败。',
      );
      _setException(exception);
      rethrow;
    }
  }

  Future<int> syncNow() async {
    if (_isSyncing) {
      return 0;
    }

    if (!_hasNetwork) {
      final exception = const NetworkSyncOfflineException();
      _setException(exception);
      throw exception;
    }

    _isSyncing = true;
    _setException(null);
    notifyListeners();

    try {
      final pendingMessages = await _database.getPendingUploads();
      if (pendingMessages.isEmpty) {
        return 0;
      }

      final response = await _httpClient
          .post(
            _endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
              pendingMessages.map(_mapMessageToJson).toList(growable: false),
            ),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        await _database.markAsUploaded(
          pendingMessages.map((message) => message.id).toList(growable: false),
        );
        _lastSuccessfulSyncAt = DateTime.now();
        return pendingMessages.length;
      }

      final exception = NetworkSyncRequestFailedException(
        statusCode: response.statusCode,
        responseBody: response.body,
      );
      _setException(exception);
      return 0;
    } on TimeoutException {
      final exception = const NetworkSyncTimeoutException();
      _setException(exception);
      return 0;
    } on SocketException catch (error) {
      final exception = NetworkSyncUnexpectedException(
        details: error,
        message: '连接指挥中心失败，本地求救数据将保留并等待下次联网。',
      );
      _setException(exception);
      return 0;
    } catch (error) {
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

  Map<String, Object?> _mapMessageToJson(StoredSosMessage message) {
    return <String, Object?>{
      'id': message.id,
      'senderMac': message.senderMac,
      'latitude': message.latitude,
      'longitude': message.longitude,
      'bloodType': message.bloodType,
      'timestamp': message.timestamp.toUtc().toIso8601String(),
    };
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
