import 'package:permission_handler/permission_handler.dart';

abstract class BleMeshException implements Exception {
  const BleMeshException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BleMeshException($code): $message';
}

class BleMeshUnsupportedException extends BleMeshException {
  const BleMeshUnsupportedException([String? message])
    : super(
        'ble_unsupported',
        message ?? '当前设备不支持 BLE 广播能力。',
      );
}

class BleMeshPermissionDeniedException extends BleMeshException {
  const BleMeshPermissionDeniedException({
    required this.deniedPermissions,
    required this.permanentlyDeniedPermissions,
    String? message,
  }) : super(
         'permission_denied',
         message ?? '蓝牙或定位权限未授予，无法继续执行 SOS 广播。',
       );

  final List<Permission> deniedPermissions;
  final List<Permission> permanentlyDeniedPermissions;
}

class BleMeshAdapterUnavailableException extends BleMeshException {
  const BleMeshAdapterUnavailableException([String? message])
    : super(
        'adapter_unavailable',
        message ?? '当前设备不可用，未检测到蓝牙适配器。',
      );
}

class BleMeshBluetoothDisabledException extends BleMeshException {
  const BleMeshBluetoothDisabledException([String? message])
    : super(
        'bluetooth_disabled',
        message ?? '蓝牙尚未开启，请先打开蓝牙后再发起 SOS 广播。',
      );
}

class BleMeshInvalidPayloadException extends BleMeshException {
  const BleMeshInvalidPayloadException([String? message])
    : super(
        'invalid_payload',
        message ?? 'SOS 广播载荷无效，请检查坐标或血型数据。',
      );
}

class BleMeshBroadcastFailedException extends BleMeshException {
  const BleMeshBroadcastFailedException({
    required this.platformCode,
    required String message,
    this.details,
  }) : super('broadcast_failed', message);

  final String platformCode;
  final Object? details;
}

class BleMeshPlatformException extends BleMeshException {
  const BleMeshPlatformException({
    required this.platformCode,
    required String message,
    this.details,
  }) : super('platform_error', message);

  final String platformCode;
  final Object? details;
}
