# 前台服务 (Foreground Service) 集成指南

## 概述

本文档说明如何在Rescue Mesh 应用中集成和使用前台服务，确保 SOS蓝牙广播在锁屏或后台情况下持续运行。

## 核心原理

### 为什么需要前台服务？

Android 系统为了节省电量，会在应用退到后台或锁屏后杀死进程。前台服务通过显示一个常驻通知，告诉系统"这个应用正在执行重要任务"，从而获得更高的优先级，避免被系统杀死。

### 架构设计

```
UI Isolate (主线程)
    │
    ├── BackgroundServiceManager (单例)
    │       │
    │       ├── 配置通知渠道
    │       ├── 启动/停止服务
    │       └── 前后台通信
    │
    └── BleMeshService (BLE 广播)
    
Background Isolate (后台线程)
    │
    ├── onStart()入口函数
    │       │
    │       ├── 显示常驻通知
    │       ├── 调用 BleMeshService.startSosBroadcast()
    │       └── 监听停止指令
    │
    └── 持续广播SOS信号 (即使UI 销毁)
```

## 集成步骤

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 在应用启动时初始化服务

在`lib/main.dart` 的`main()` 函数中：

```dart
import 'services/background_service_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化前台服务(必须在UI Isolate 中)
  await BackgroundServiceManager.instance.initializeService();
  
  runApp(const RescueMeshApp());
}
```

### 3. 在SOS 页面中使用

在 `lib/sos_page.dart` 中集成：

```dart
import 'services/background_service_manager.dart';
import 'services/ble_mesh_service.dart';

class SosPage extends StatefulWidget {
  @override
  State<SosPage> createState() => _SosPageState();
}

class _SosPageState extends State<SosPage> {
  final BackgroundServiceManager _backgroundService = 
      BackgroundServiceManager.instance;
  final BleMeshService _bleMeshService = BleMeshService();
  
  bool _isSosActive = false;
  bool _isServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await _backgroundService.isRunning();
    setState(() {
      _isServiceRunning = isRunning;
      _isSosActive = isRunning;
    });
  }

  /// 触发SOS 求救
  Future<void> _triggerSos() async {
    try {
      // 1. 获取当前位置 (使用您的定位服务)
      final location = await _getLocation(); // 伪代码
      
      // 2. 获取用户血型(从配置文件)
      final bloodType = await _getBloodType(); // 伪代码
      
      // 3. 启动前台服务(这会自动启动BLE 广播)
      await _backgroundService.startService(
        latitude: location.latitude,
        longitude: location.longitude,
        bloodType: bloodType,
      );
      
      setState(() {
        _isSosActive = true;
        _isServiceRunning = true;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS 求救已启动！后台将持续广播您的坐标。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动失败：$e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// 停止SOS 求救
  Future<void> _stopSos() async {
    try {
      // 停止前台服务(会自动停止BLE 广播并撤销通知)
      await _backgroundService.stopService();
      
      setState(() {
        _isSosActive = false;
        _isServiceRunning = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS 求救已停止'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('停止失败：$e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  /// 更新位置(可选 - 当位置发生变化时)
  Future<void> _updateLocation(double latitude, double longitude) async {
    if (_isServiceRunning) {
      await _backgroundService.updateSosParameters(
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS 紧急求救'),
        backgroundColor: _isSosActive ? Colors.red : null,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 状态指示器
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSosActive ? Colors.red : Colors.grey,
              ),
              child: Icon(
                _isSosActive ? Icons.sos : Icons.shield_outlined,
                size: 100,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            
            // 状态文本
            Text(
              _isSosActive 
                ? '🆘 正在广播SOS信号\n通知栏常驻，锁屏也能继续工作' 
                : '点击按钮触发SOS 求救',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 40),
            
            // SOS按钮
            ElevatedButton(
              onPressed: _isSosActive ? _stopSos : _triggerSos,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSosActive ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 60,
                  vertical: 20,
                ),
              ),
              child: Text(
                _isSosActive ? '停止求救' : '触发SOS',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // 服务状态
            Text(
              _isServiceRunning 
                ? '✓ 前台服务运行中' 
                : '○ 服务未运行',
              style: TextStyle(
                color: _isServiceRunning ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 注意：不要在 dispose中停止服务
    // 用户应该手动点击"停止求救"按钮
    super.dispose();
  }
}
```

### 4. Android 12+ 特殊处理

对于Android 12 (API 31)及以上版本，需要在运行时请求前台服务权限：

```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> requestForegroundServicePermission() async {
  if (Platform.isAndroid) {
    // Android 13+ 需要通知权限
    if (Platform.version >= '33') {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
  }
}
```

## 关键配置说明

### AndroidManifest.xml 权限详解

```xml
<!-- 基础前台服务权限 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />

<!-- Android 12+ (API 31)细分权限 -->
<!-- 用于BLE设备连接 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<!-- 用于位置广播 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

<!-- Android 14+ (API 34)通知权限 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### 通知渠道配置

```dart
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'rescue_mesh_sos_channel',  // 渠道ID (必须与配置一致)
  'Rescue Mesh SOS 服务',      // 渠道名称 (用户可见)
  description: '用于在后台持续广播SOS求救信号',
  importance: Importance.high,  // 高优先级，确保通知可见
  enableVibration: false,       // 不震动
  playSound: false,             // 不播放声音
  showBadge: false,             // 不显示角标
);
```

## 测试验证

### 测试步骤

1. **启动测试**
   ```bash
   flutter run --release
   ```

2. **触发SOS**
   - 打开应用，进入 SOS页面
   - 点击"触发SOS"按钮
   - 确认通知栏出现常驻通知

3. **后台测试**
   - 按Home 键退回桌面
   - 观察通知栏通知依然存在
   - 打开其他应用，确认通知未被移除

4. **锁屏测试**
   - 锁屏手机
   - 等待5-10分钟
   - 解锁后检查通知是否仍在

5. **停止测试**
   - 返回应用，点击"停止求救"
   - 确认通知消失，服务停止

### 调试技巧

```dart
// 在服务启动前后添加日志
debugPrint('[SOS]准备启动前台服务...');
await _backgroundService.startService(...);
debugPrint('[SOS]前台服务已启动 ✓');

// 监听服务状态
_backgroundService.serviceStatusStream.listen((isRunning) {
  debugPrint('[SOS]服务状态变化：$isRunning');
});
```

## 常见问题

### Q1: 为什么锁屏后还是被杀死了？

**可能原因：**
1. 没有正确配置`FOREGROUND_SERVICE_LOCATION`权限
2. 通知渠道重要性不是`IMPORTANCE_HIGH`
3. 某些厂商系统(小米、华为等) 需要额外设置自启动权限

**解决方案：**
```dart
// 确保配置了正确的通知重要性
foregroundServiceNotificationImportance: ForegroundServiceImportance.high,
```

### Q2: 通知栏显示两个通知？

**原因：** 可能重复调用了`startService()`

**解决方案：**
```dart
// 在启动前检查状态
final isRunning = await _backgroundService.isRunning();
if (!isRunning) {
  await _backgroundService.startService(...);
}
```

### Q3: 如何确保BLE 广播在后台持续运行？

**关键点：**
1. `flutter_blue_plus` 支持后台执行
2. 必须在后台 Isolate 中重新初始化BLE
3. 使用Platform Channel 或 IsolateNameServer 进行跨Isolate 通信

**参考实现：**
```dart
// 在onStart() 中
@pragma('vm:entry-point')
Future<void> onStart() async {
  // 确保 BLE在后台 Isolate 中初始化
  await FlutterBluePlus.setLogLevel(LogLevel.verbose);
  
  // 调用主 Isolate的 BleMeshService
  // 通过 IsolateNameServer 发送消息
  final port = IsolateNameServer.lookupPortByName('ble_mesh_port');
  port?.send({'action': 'start_sos', 'latitude': ...});
}
```

### Q4: Android 14 上通知不显示？

**原因：** Android 14要求前台服务启动后 5秒内必须显示通知

**解决方案：**
```dart
// 确保在configure时就设置了初始通知
await _service.configure(
  androidConfiguration: AndroidConfiguration(
    initialNotificationTitle: 'Rescue Mesh 紧急求救',
    initialNotificationContent: '正在准备广播SOS信号...',
    // ...
  ),
);
```

## 电池优化白名单(可选)

对于极端情况，可以引导用户将应用加入电池优化白名单：

```dart
import 'package:permission_handler/permission_handler.dart';

Future<void> requestIgnoreBatteryOptimizations() async {
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (!status.isGranted) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}
```

**注意：** 这需要在AndroidManifest 中添加：
```xml
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

## 性能优化建议

1. **位置更新频率**
   - 不要频繁调用`updateSosParameters()`
   - 建议每 30秒或位置变化超过100米时更新一次

2. **BLE 广播间隔**
   - 默认500ms-1s即可
   - 过快的广播会加速耗电

3. **通知更新**
   - 避免频繁更新通知内容
   - 只在关键状态变化时更新

## 完整代码示例

完整的集成代码请参见：
- `lib/services/background_service_manager.dart` - 服务管理器
- `lib/sos_page.dart` - SOS页面集成示例
- `android/app/src/main/AndroidManifest.xml` - 权限配置

## 注意事项

⚠️ **重要提醒：**

1. **测试充分性**：在不同品牌手机(小米、华为、OPPO、vivo等)上测试，各厂商的后台管理策略不同

2. **用户告知**：在首次启动时向用户说明需要常驻通知，这是为了保活SOS功能

3. **电量消耗**：持续 BLE广播会消耗电量，建议在 UI上显示电量提示

4. **隐私保护**：确保位置信息只在SOS 模式下广播，平时不收集

5. **法律合规**：在某些地区，持续广播可能被误认为恶意软件，需谨慎使用
