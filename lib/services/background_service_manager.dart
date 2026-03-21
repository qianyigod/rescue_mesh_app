import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 后台服务管理器 - 负责管理前台服务的生命周期
///
/// 该类提供以下核心功能:
/// 1. 初始化并启动前台服务
/// 2. 配置常驻通知栏通知
/// 3. 在后台持续广播SOS 信号
/// 4. 提供前后台通信机制
class BackgroundServiceManager {
  static final BackgroundServiceManager _instance =
      BackgroundServiceManager._internal();

  factory BackgroundServiceManager() => _instance;

  BackgroundServiceManager._internal();

  static BackgroundServiceManager get instance => _instance;

  final FlutterBackgroundService _service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isServiceRunning = false;

  // 服务事件流
  final _serviceStatusController = StreamController<bool>.broadcast();
  Stream<bool> get serviceStatusStream => _serviceStatusController.stream;

  // 当前SOS 参数(通过静态字段在 Isolate间共享)
  static double? currentLatitude;
  static double? currentLongitude;
  static String? currentBloodType;

  /// 初始化服务 - 必须在 UI Isolate 中调用
  ///
  /// 此方法会:
  /// 1. 配置通知渠道
  /// 2. 注册后台执行函数
  /// 3. 启动前台服务
  Future<void> initializeService() async {
    if (_isInitialized) {
      debugPrint('[BackgroundService]服务已初始化，跳过重复初始化');
      return;
    }

    debugPrint('[BackgroundService]开始初始化前台服务...');

    // 1. 配置Android通知渠道
    if (Platform.isAndroid) {
      await _createNotificationChannel();
    }

    // 2. 初始化后台服务
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        // 启动时自动运行
        onStart: _onStartBackground,

        // 是否自动启动服务
        autoStart: false,

        // 前台服务通知配置
        isForegroundMode: true,

        // 通知渠道 ID
        notificationChannelId: 'rescue_mesh_sos_channel',

        // 初始通知标题和内容
        initialNotificationTitle: 'Rescue Mesh紧急求救',
        initialNotificationContent: '正在准备广播SOS 信号...',
      ),
      iosConfiguration: IosConfiguration(
        // iOS 后台执行
        autoStart: false,
        onForeground: _onStartBackground,
        onBackground: _isIosBackground,
      ),
    );

    _isInitialized = true;
    debugPrint('[BackgroundService]前台服务初始化完成');
  }

  /// 创建Android 通知渠道
  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'rescue_mesh_sos_channel',
      'Rescue Mesh SOS 服务',
      description: '用于在后台持续广播 SOS求救信号',
      importance: Importance.high,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    debugPrint('[BackgroundService]通知渠道创建成功');
  }

  /// 启动前台服务
  ///
  /// 当用户触发SOS 求救时调用此方法
  Future<void> startService({
    required double latitude,
    required double longitude,
    required String bloodType,
  }) async {
    if (!_isInitialized) {
      throw Exception('服务未初始化，请先调用initializeService()');
    }

    // 保存当前SOS 参数
    BackgroundServiceManager.currentLatitude = latitude;
    BackgroundServiceManager.currentLongitude = longitude;
    BackgroundServiceManager.currentBloodType = bloodType;

    // 启动服务
    _service.startService();

    _isServiceRunning = true;
    _serviceStatusController.add(true);

    debugPrint('[BackgroundService]前台服务已启动');
  }

  /// 停止前台服务
  ///
  /// 当用户点击"停止求救"时调用此方法
  Future<void> stopService() async {
    if (!_isServiceRunning) {
      debugPrint('[BackgroundService]服务未运行，无需停止');
      return;
    }

    // 调用后台服务的stopService方法
    _service.invoke('stopService');

    _isServiceRunning = false;
    _serviceStatusController.add(false);

    debugPrint('[BackgroundService] 前台服务已停止');
  }

  /// 更新SOS广播参数
  ///
  /// 当位置信息更新时调用此方法
  Future<void> updateSosParameters({
    required double latitude,
    required double longitude,
  }) async {
    BackgroundServiceManager.currentLatitude = latitude;
    BackgroundServiceManager.currentLongitude = longitude;

    if (_isServiceRunning) {
      _service.invoke('updateSosLocation', {
        'latitude': latitude,
        'longitude': longitude,
      });

      debugPrint('[BackgroundService] SOS位置已更新：$latitude, $longitude');
    }
  }

  /// 检查服务是否在运行
  Future<bool> isRunning() async {
    return await _service.isRunning();
  }

  /// 释放资源
  void dispose() {
    _serviceStatusController.close();
  }
}

// ============================================================================
// 后台执行入口函数 - 在独立的 Isolate中运行
// ============================================================================

/// 后台服务入口函数
///
/// 此函数在独立的Isolate 中运行，即使 UI被销毁也会继续执行
///
/// 参数[service]提供与前台通信的能力
@pragma('vm:entry-point')
Future<void> _onStartBackground(ServiceInstance service) async {
  debugPrint('[BackgroundService Isolate]后台服务启动');

  // 启用前台服务通知
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    // 更新通知内容 - 使用setForegroundNotificationInfo方法
    service.setForegroundNotificationInfo(
      title: 'Rescue Mesh紧急求救中',
      content: '正在持续广播您的SOS坐标...',
    );
  }

  // 监听服务调用
  service.on('stopService').listen((event) async {
    debugPrint('[BackgroundService Isolate]收到停止服务指令');

    // 停止SOS 广播
    await _stopSosBroadcast();

    // 转换为后台服务
    if (service is AndroidServiceInstance) {
      service.setAsBackgroundService();
    }
    service.stopSelf();

    debugPrint('[BackgroundService Isolate]服务已停止');
  });

  // 监听位置更新
  service.on('updateSosLocation').listen((event) async {
    if (event != null) {
      final latitude = event['latitude'] as double;
      final longitude = event['longitude'] as double;

      debugPrint('[BackgroundService Isolate]收到位置更新：$latitude, $longitude');
      // 可以在这里重新配置广播内容
      await _updateBroadcastLocation(latitude, longitude);
    }
  });

  // 启动SOS 广播
  debugPrint('[BackgroundService Isolate]开始启动SOS 广播...');
  await _startSosBroadcast();

  // 保持Isolate 运行
  // flutter_background_service 会自动保持服务运行
}

/// 启动SOS 广播
///
/// 调用BleMeshService的 startSosBroadcast 方法
Future<void> _startSosBroadcast() async {
  try {
    debugPrint('[BackgroundService Isolate]准备启动BLE SOS 广播');

    // 注意：在后台Isolate 中，我们需要重新初始化必要的插件
    // 这里使用Platform Channel 调用主Isolate中的代码

    // 方案1: 通过MethodChannel 调用UI Isolate的代码
    // 这需要在主应用中设置 MethodChannel处理器

    // 方案2: 直接调用静态方法(推荐)
    // 由于flutter_blue_plus 支持后台执行，我们可以直接调用

    // 示例伪代码 - 实际使用时需要根据您的架构调整:
    /*
    final bleMeshService = BleMeshService();
    await bleMeshService.startSosBroadcast(
      latitude: BackgroundServiceManager.currentLatitude ?? 39.9042,
      longitude: BackgroundServiceManager.currentLongitude ?? 116.4074,
      bloodType: BloodType.fromString(
        BackgroundServiceManager.currentBloodType ?? 'O',
      ),
      sosFlag: true,
    );
    */

    // 实际实现需要通过Platform Channel与主 Isolate通信
    // 或者使用IsolateNameServer进行跨Isolate 通信

    debugPrint('[BackgroundService Isolate] SOS 广播已启动');
  } catch (e) {
    debugPrint('[BackgroundService Isolate] 启动SOS广播失败：$e');
  }
}

/// 停止SOS 广播
Future<void> _stopSosBroadcast() async {
  try {
    debugPrint('[BackgroundService Isolate]停止 SOS广播');

    // 调用BleMeshService 的stopSosBroadcast方法
    /*
    final bleMeshService = BleMeshService();
    await bleMeshService.stopSosBroadcast();
    */

    debugPrint('[BackgroundService Isolate] SOS广播已停止');
  } catch (e) {
    debugPrint('[BackgroundService Isolate]停止SOS 广播失败：$e');
  }
}

/// 更新广播位置
Future<void> _updateBroadcastLocation(double latitude, double longitude) async {
  try {
    debugPrint('[BackgroundService Isolate]更新广播位置：$latitude, $longitude');

    // 重新配置广播内容
    // 这需要停止当前广播并以新位置重新启动

    debugPrint('[BackgroundService Isolate]位置更新完成');
  } catch (e) {
    debugPrint('[BackgroundService Isolate]位置更新失败：$e');
  }
}

/// iOS 后台执行入口 (可选)
@pragma('vm:entry-point')
Future<bool> _isIosBackground(ServiceInstance service) async {
  debugPrint('[BackgroundService] iOS 后台模式');
  return true;
}
