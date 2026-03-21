abstract class NetworkSyncException implements Exception {
  const NetworkSyncException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'NetworkSyncException($code): $message';
}

class NetworkSyncRequestFailedException extends NetworkSyncException {
  const NetworkSyncRequestFailedException({
    required this.statusCode,
    required this.responseBody,
  }) : super(
         'sync_request_failed',
         '后端未确认接收救援数据，状态码: $statusCode。',
       );

  final int statusCode;
  final String responseBody;
}

class NetworkSyncTimeoutException extends NetworkSyncException {
  const NetworkSyncTimeoutException()
    : super('sync_timeout', '连接指挥中心超时，本地求救数据将等待下次联网后重试。');
}

class NetworkSyncOfflineException extends NetworkSyncException {
  const NetworkSyncOfflineException()
    : super('sync_offline', '当前设备仍处于离线状态，无法同步本地求救数据。');
}

class NetworkSyncUnexpectedException extends NetworkSyncException {
  const NetworkSyncUnexpectedException({
    required this.details,
    String? message,
  }) : super(
         'sync_unexpected',
         message ?? '自动同步过程中发生未知错误，本地数据已保留等待重试。',
       );

  final Object details;
}
