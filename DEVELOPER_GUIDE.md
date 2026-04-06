# Rescue Mesh — Developer Guide

> **项目代号:** RESCUE MESH · 离线应急救援网络
> **文档版本:** v2.0 · 2026-04-04 · 全面更新
> **适用 SDK:** Flutter 3.11+ · Dart 3.11+

---

## 🌍 项目愿景

**一句话价值主张：** 在完全断网的极端灾害现场，让每一部手机都成为生命接力站——遇险者的求救信号通过蓝牙 Mesh 跳传至拥有网络的"数据骡子"，再批量上报至云端大屏，守护每一条不能失联的生命。

### 核心工作流

```
[ 遇险者手机 ]
  ├─ 端侧 AI (fcllama / llama.cpp) 辅助填写医疗档案
  └─ BLE Manufacturer Data 广播 SOS 信标 (14字节)
         ↓ 蓝牙扫描 (30秒本地去重)
[ 数据骡子手机 ]  (路过现场的任意用户)
  ├─ flutter_blue_plus 接收 → Drift/SQLite 本地存储
  ├─ Riverpod MeshState 实时更新
  └─ 声呐雷达 / 离线战术地图 可视化
         ↓ 网络恢复时自动触发 (connectivity_plus)
[ Node.js 后端 ]
  └─ POST /api/sos/sync → 10分钟窗口服务端去重 → MongoDB 持久化
         ↓ Socket.io 实时推送
[ Vue 3 大屏 ]
  └─ Leaflet 地图红点 + ECharts 图表 + AlertFeed 滚动告警
```

### 架构分层

```
┌─────────────────────────────────────────────────┐
│                   UI Layer                      │
│  Dashboard / Radar / Map / Profile / AI Chat    │
├─────────────────────────────────────────────────┤
│               State Management                  │
│         Riverpod (MeshStateProvider)            │
├─────────────────────────────────────────────────┤
│               Service Layer                     │
│ BleMesh │ Scanner │ Sync │ Dispatch │ PowerSave │
├─────────────────────────────────────────────────┤
│              Data / Protocol Layer              │
│   Drift DB │ BLE Payload │ MBTiles │ Models     │
├─────────────────────────────────────────────────┤
│              Platform Layer                     │
│   Android BLE Advertiser │ Foreground Service   │
└─────────────────────────────────────────────────┘
```

---

## 🛠️ 技术栈总览

### 移动端 (Flutter)

| 依赖 | 版本 | 用途 |
|------|------|------|
| `flutter_blue_plus` | 1.35.5 | BLE 广播 (SOS 发送) + 扫描 (数据骡子接收) |
| `drift` + `sqlite3_flutter_libs` | 2.19.0 / 0.5.24 | 本地 SQLite 持久化，含 Drift ORM 代码生成 |
| `flutter_riverpod` + `riverpod_annotation` | 3.3.1 / 4.0.2 | 声明式状态管理，MeshState 全局共享 |
| `connectivity_plus` | 6.0.3 | 监听网络状态，网络恢复时触发自动同步 |
| `http` | 1.2.1 | HTTP POST 批量上报至后端 |
| `permission_handler` | 11.3.1 | 运行时申请蓝牙/定位权限 |
| `location` | 5.0.3 | 获取 GPS 坐标 |
| `flutter_map` + `latlong2` | 6.1.0 / 0.9.1 | 移动端离线地图渲染 |
| `sqlite3` | 2.1.0 (+ override 3.1.5) | MBTiles 本地瓦片数据库读取 |
| `flutter_background_service` | 5.0.5 | 前台后台服务，持续广播 SOS |
| `flutter_local_notifications` | 17.2.1 | 常驻通知栏通知 |
| `screen_brightness` | 2.1.7 | 极限省电模式降低屏幕亮度 |
| `shared_preferences` | 2.3.2 | 轻量键值存储（省电模式开关、设备 ID） |
| `fcllama` / `llama_cpp_dart` | 0.0.3 / 0.2.0 | 端侧大模型推理（离线急救问答） |
| `camera` | 0.11.0 | AR 救援罗盘摄像头叠加 |
| `sensors_plus` | 6.1.1 | 传感器数据（加速度计、陀螺仪） |
| `geolocator` | 13.0.2 | 高精度定位服务 |
| `vibration` | 2.0.1 | SOS 触发触觉反馈 |
| `share_plus` / `url_launcher` | 12.0.1 / 6.3.2 | 分享功能与外部链接跳转 |

> **BLE 广播实现细节：** Dart 层通过 Android Method Channel `rescue_mesh/advertiser` 调用原生 Kotlin 实现广播。广播载荷为 **14 字节**二进制格式（v1 协议）。

### 后端 (Node.js)

| 依赖 | 用途 |
|------|------|
| `express` | REST API 框架 |
| `mongoose` | MongoDB ODM，含 GeoJSON 2dsphere 索引 |
| `socket.io` | 向大屏实时推送新 SOS 事件 |
| `dotenv` | 环境变量管理 |
| `cors` | 跨域支持 |

### 前端大屏 (Vue 3)

| 依赖 | 用途 |
|------|------|
| `vue` | 响应式 UI 框架 |
| `echarts` | 血型分布玫瑰图 + 12 小时趋势折线图 |
| `leaflet` | 实时 SOS 地图（CartoDB Dark Matter 暗色底图） |
| `socket.io-client` | 接收后端实时推送 |
| `vite` | 构建工具 |

---

## 📂 核心项目结构

```
rescue_mesh_app/
│
├── lib/                              # Flutter 移动端
│   ├── main.dart                     # ★ 应用入口：5Tab导航 + 服务初始化编排
│   ├── database.dart                 # ★ Drift ORM：3张表 + 去重逻辑 (schema v3)
│   ├── database.g.dart               # [自动生成，勿手动修改]
│   │
│   ├── sos_page.dart                 # UI：SOS 发送控制页
│   ├── ai_chat_page.dart             # UI：端侧 AI 对话页（fcllama 集成）
│   ├── message_page.dart             # UI：收到的 SOS 消息列表
│   ├── profile_page.dart             # UI：个人设置页
│   ├── mesh_dashboard_page.dart      # UI：Mesh 网络状态看板（雷达/地图双模式）
│   ├── medical_profile_page.dart     # UI：医疗档案管理
│   ├── ar_rescue_compass_page.dart   # UI：AR 救援罗盘
│   ├── radar_demo_page.dart          # UI：声呐雷达独立演示页
│   │
│   ├── models/
│   │   ├── sos_message.dart          # SOS 数据模型（MAC、坐标、血型、RSSI）
│   │   ├── sos_payload.dart          # BLE 载荷解码后的纯数据类
│   │   ├── sos_advertisement_payload.dart # BLE 广播载荷结构定义
│   │   ├── emergency_profile.dart    # BloodType 枚举 + EmergencyProfile
│   │   └── mesh_state_provider.dart  # ★ Riverpod 状态：MeshState / DiscoveredDevice
│   │
│   ├── services/
│   │   ├── ble_mesh_service.dart     # ★ BLE 广播服务 + Relay Queue 中继队列
│   │   ├── ble_scanner_service.dart  # ★ BLE 扫描服务：解析14字节载荷，30s去重
│   │   ├── ble_payload_encoder.dart  # BLE 二进制编解码器（encode/decode）
│   │   ├── ble_mesh_exceptions.dart  # BLE 异常类型体系
│   │   ├── network_sync_service.dart # ★ 网络同步：connectivity 监听 + 批量 POST
│   │   ├── network_sync_exceptions.dart # 网络同步异常类型
│   │   ├── sos_dispatch_manager.dart # SOS 调度中心：探网→上云→近场广播
│   │   ├── sos_trigger_service.dart  # SOS 触发服务：统一入口
│   │   ├── background_service_manager.dart # 前台后台服务管理
│   │   ├── power_saving_manager.dart # ★ 省电管理：GPS策略/BLE间隔/屏幕亮度
│   │   └── mbtiles_reader.dart       # MBTiles 离线瓦片读取器
│   │
│   ├── widgets/
│   │   ├── sonar_radar_widget.dart   # ★ 60fps 声呐雷达可视化
│   │   ├── offline_tactical_map_view.dart # 离线战术地图（MBTiles + 脉冲标记）
│   │   └── ultra_power_switch_widget.dart # 极限求生模式开关
│   │
│   └── theme/
│       └── rescue_theme.dart         # 全局主题（RescuePalette + ThemeData）
│
├── server/                           # Node.js 后端
│   ├── src/
│   │   ├── index.js                  # Express + Socket.io + MongoDB 初始化
│   │   ├── models/SosRecord.js       # Mongoose Schema + GeoJSON 索引
│   │   ├── routes/sos.js             # POST /api/sos/sync + GET /api/sos/active
│   │   └── socket/index.js           # Socket.io 模块
│   ├── .env / .env.example           # 环境变量
│   └── package.json
│
├── dashboard/                        # Vue 3 指挥大屏
│   ├── src/
│   │   ├── main.js / App.vue         # 应用入口 + 三栏 Grid 布局
│   │   ├── style.css                 # 暗色主题 + 动画定义
│   │   ├── components/
│   │   │   ├── AlertFeed.vue         # SOS 告警滚动列表
│   │   │   ├── MapComponent.vue      # Leaflet 地图 + 脉冲红点
│   │   │   └── StatsComponent.vue    # ECharts 血型玫瑰 + 趋势折线
│   │   └── composables/useSocket.js  # Socket.io 连接 + 响应式状态
│   ├── index.html / package.json
│   └── vite.config.js
│
├── test/                             # 单元测试
│   ├── ble_payload_encoder_test.dart
│   ├── ble_scanner_service_test.dart
│   ├── database_test.dart
│   ├── network_sync_service_test.dart
│   ├── sos_advertisement_payload_test.dart
│   └── widget_test.dart
│
├── assets/models/                    # AI 模型文件
├── android/                          # Android 原生层（含 BLE 广播 Method Channel）
└── pubspec.yaml                      # Flutter 依赖声明
```

---

## 🚀 局域网联调与启动指南

> ⚠️ **Localhost 陷阱 — 必读！**
>
> 移动端真机和大屏浏览器都无法通过 `localhost` 或 `127.0.0.1` 访问你的后端，**必须**使用电脑的局域网 IPv4 地址。
>
> **获取局域网 IP：**
> ```powershell
> ipconfig
> # 找 "WLAN" 或 "以太网适配器" 下的 IPv4 地址
> ```
>
> 后续步骤中，将所有 `<YOUR_LAN_IP>` 替换为你的 IP 地址。
> **所有设备（手机、浏览器）必须连接同一个 Wi-Fi！**

### Step 1：启动后端 (Node.js)

```bash
cd server
cp .env.example .env    # 或使用 copy .env.example .env (Windows)
# 编辑 .env，填写 MONGODB_URI
npm install
node src/index.js
```

启动成功后应看到：
```
[Server] MongoDB connected
[Server] Listening on http://0.0.0.0:3000
```

### Step 2：启动大屏前端 (Vue 3)

```bash
cd dashboard
npm install
npm run dev
```

修改 [dashboard/src/composables/useSocket.js](dashboard/src/composables/useSocket.js) 中的 Socket.io 连接地址为 `http://<YOUR_LAN_IP>:3000`。

### Step 3：运行移动端 (Flutter)

```bash
flutter pub get
flutter devices
flutter run -d <device_id>
```

**选择运行环境：**
```bash
# 本地开发（Android 模拟器连接宿主机）
flutter run --dart-define=ENV=local

# 云服务器（连接远程服务器）
flutter run --dart-define=ENV=production

# 真机调试（连接局域网内的电脑）
flutter run --dart-define=API_BASE_URL=http://<YOUR_LAN_IP>:3000
```

> ~~**修改后端同步地址：** 打开 [lib/services/network_sync_service.dart](lib/services/network_sync_service.dart)，将 `_endpoint` 改为 `http://<YOUR_LAN_IP>:3000/api/sos/sync`。~~ （已废弃，改用 `--dart-define` 参数）

**重新生成 Drift 代码（若修改了 database.dart）：**
```bash
dart run build_runner build
```

### 联调验证清单

- [ ] 后端控制台无报错，MongoDB 已连接
- [ ] 大屏左上角显示绿色"已连接"状态
- [ ] 手机 App 能正常启动，各 Tab 可切换
- [ ] 在手机 SOS 页触发广播，另一台手机能扫描到信号
- [ ] 手机网络恢复后，大屏自动出现新的 SOS 告警

---

## 📡 关键数据结构速查

### BLE 广播载荷 (14 字节 · v1 协议)

| 偏移 | 长度 | 类型 | 字段 |
|------|------|------|------|
| 0 | 1 | uint8 | 协议版本号 (0x01) |
| 1 | 1 | uint8 | 血型编码 (0-255) |
| 2 | 4 | float32 LE | 纬度 |
| 6 | 4 | float32 LE | 经度 |
| 10 | 4 | uint32 LE | UTC Unix 时间戳 (秒) |

编解码由 [lib/services/ble_payload_encoder.dart](lib/services/ble_payload_encoder.dart) 处理。

### 血型编码对照表

| Flutter 枚举 | code | 显示 | 颜色 |
|-------------|------|------|------|
| `unknown` | -1 | 未知 | `#9966FF` |
| `a` | 0 | A 型 | `#FF6B6B` |
| `b` | 1 | B 型 | `#4BC0C0` |
| `ab` | 2 | AB 型 | `#FFCE56` |
| `o` | 3 | O 型 | `#00E5FF` |

### 三层去重机制

| 层级 | 位置 | 去重窗口 | 依据 |
|------|------|---------|------|
| BLE 扫描层 | [ble_scanner_service.dart](lib/services/ble_scanner_service.dart) | 30 秒 | fingerprint (MAC+坐标) |
| 本地数据库层 | [database.dart](lib/database.dart) | 5 分钟 | senderMac + 时间戳 |
| 服务端层 | `server/src/routes/sos.js` | 10 分钟 | senderMac + 时间戳 |

---

## 🏗️ 服务层详解

### 1. BleMeshService — BLE 广播服务

**文件：** [lib/services/ble_mesh_service.dart](lib/services/ble_mesh_service.dart)

**职责：**
- 通过 Android Method Channel 控制 BLE 广播的启停
- 管理广播状态流 (`Stream<bool>`)
- 支持 **Relay Queue 中继队列**：缓存待广播的 SOS 消息，依次发送
- 权限检查与适配器状态监听

**核心 API：**
```dart
Future<void> initialize();          // 初始化（检查权限 + 适配器）
Future<void> startSosBroadcast();   // 开始广播自身 SOS
Future<void> stopSosBroadcast();    // 停止广播
bool get isBroadcasting;            // 当前广播状态
Stream<bool> get broadcastingStream; // 广播状态流
```

### 2. BleScannerService — BLE 扫描服务

**文件：** [lib/services/ble_scanner_service.dart](lib/services/ble_scanner_service.dart)

**职责：**
- 持续扫描 BLE 广播包（Company ID: `0xFFFF`）
- 解析 14 字节 SOS 载荷
- 30 秒窗口内基于 fingerprint 的去重
- 将有效 SOS 消息写入本地数据库

**核心 API：**
```dart
Future<void> initialize();
Future<void> startScanning();
Future<void> stopScanning();
Stream<SosMessage> get sosMessageStream;  // 接收到的 SOS 流
```

### 3. BlePayloadEncoder — 二进制编解码器

**文件：** [lib/services/ble_payload_encoder.dart](lib/services/ble_payload_encoder.dart)

**职责：**
- `encodeSosData()`：将经纬度、血型、时间戳编码为 14 字节数组
- `decodeSosData()`：将原始字节解码为 `SosPayload` 对象
- 输入验证（坐标范围、血型范围、时间戳范围）

**协议常量：**
```dart
static const int protocolVersion = 0x01;
static const int payloadLength = 14;
static const Endian byteOrder = Endian.little;
```

### 4. NetworkSyncService — 网络同步服务

**文件：** [lib/services/network_sync_service.dart](lib/services/network_sync_service.dart)

**职责：**
- 监听网络连通性变化（`connectivity_plus`）
- 网络恢复时自动触发同步
- 从 Drift DB 查询 `isUploaded = false` 的记录
- 批量 POST 至后端 `/api/sos/sync`
- 同步成功后标记 `isUploaded = true`

**核心 API：**
```dart
Future<void> startListening();  // 开始监听网络变化
Future<int> syncNow();          // 立即执行同步，返回上传数量
bool get hasNetwork;            // 当前是否有可用网络
DateTime? get lastSuccessfulSyncAt;
```

**依赖注入：** 支持通过构造函数注入 `AppDatabase`、`Connectivity`、`http.Client` 等，便于测试。

### 5. SosDispatchManager — SOS 调度中心

**文件：** [lib/services/sos_dispatch_manager.dart](lib/services/sos_dispatch_manager.dart)

**职责：** 统一管理 SOS 信号的发送路径
1. **探网**：检查当前网络连接状态
2. **上云**：网络可用时发送 HTTP POST 到后端
3. **近场/兜底**：无论网络状态，始终启动 BLE 广播

**单例模式：** `SosDispatchManager.instance.triggerSos(payload)`

### 6. SosTriggerService — SOS 触发服务

**文件：** [lib/services/sos_trigger_service.dart](lib/services/sos_trigger_service.dart)

**职责：** 提供统一的 SOS 触发入口，协调数据库写入、BLE 广播和网络同步。

**返回值：** `SosTriggerResult` 包含消息 ID、坐标、上传状态及各通道错误信息。

### 7. PowerSavingManager — 省电管理

**文件：** [lib/services/power_saving_manager.dart](lib/services/power_saving_manager.dart)

**职责：**
- **极限求生模式**开关（持久化到 SharedPreferences）
- GPS 策略切换：
  - 标准模式：高精度持续监听，1 秒间隔
  - 极限模式：省电模式单次定位，5 分钟间隔，250 米距离过滤器
- BLE 广播间隔调节：标准 1 秒 → 极限 5 秒
- 屏幕亮度自动降至 5%
- 应用生命周期感知（前后台切换时自动调整策略）

**核心 API：**
```dart
Future<void> setUltraPowerSavingMode(bool enabled);
bool get isUltraPowerSavingMode;
GpsUpdatePolicy getGpsUpdatePolicy();
Duration getBleAdvertiseInterval();
```

### 8. BackgroundServiceManager — 前台后台服务管理

**文件：** [lib/services/background_service_manager.dart](lib/services/background_service_manager.dart)

**职责：**
- 使用 `flutter_background_service` 维持后台持续运行
- 配置常驻通知栏通知（标题、内容、渠道 ID）
- 在后台 Isolate 中持续广播 SOS 信号
- 通过静态字段在 Isolate 间共享位置/血型数据

**核心 API：**
```dart
Future<void> initializeService();  // 初始化并启动
Future<void> startService();       // 启动前台服务
Future<void> stopService();        // 停止服务
```

### 9. MbtilesReader — 离线瓦片读取器

**文件：** [lib/services/mbtiles_reader.dart](lib/services/mbtiles_reader.dart)

**职责：**
- 从本地 MBTiles 文件读取地图瓦片
- 使用 `sqlite3` 直接查询瓦片数据
- 支持元数据读取（缩放级别、中心点、格式等）

**MBTiles 规范：** 遵循 [MapBox MBTiles 规范](https://github.com/mapbox/mbtiles-spec)，底层为 SQLite 数据库，包含 `tiles` 表和 `metadata` 表。

---

## 📊 Riverpod 状态管理

### 架构设计

项目采用 **Riverpod** 进行全局状态管理，替代传统的 `ChangeNotifier` + `InheritedWidget` 模式，避免高频 BLE 事件导致的 UI 卡顿。

**核心文件：**
- [lib/models/mesh_state_provider.dart](lib/models/mesh_state_provider.dart) — 状态定义
- [lib/models/mesh_state_provider.g.dart](lib/models/mesh_state_provider.g.dart) — 自动生成（勿修改）

### 状态对象

```dart
@immutable
class DiscoveredDevice {
  final String macAddress;
  final SosPayload payload;
  final int rssi;
  final DateTime firstDiscoveredAt;
  final DateTime lastUpdatedAt;

  double get estimatedDistance;  // 基于 RSSI 的距离估算（米）
  DiscoveredDevice copyWith({...});
}

@immutable
class MeshState {
  final Map<String, DiscoveredDevice> discoveredDevices;
  // ... sortedDevices, activeDevices 等派生属性
}
```

### 使用方法

```dart
// 在 BLE 扫描回调中添加设备
ref.read(meshStateProvider.notifier).addOrUpdateDevice(mac, payload, rssi);

// 在 UI 中监听
final meshState = ref.watch(meshStateProvider);
final devices = meshState.sortedDevices;
```

### RSSI 距离估算

`DiscoveredDevice.estimatedDistance` 基于对数路径损耗模型：

```dart
double get estimatedDistance {
  const int txPower = -59;  // 假设发射功率
  final ratio = rssi.toDouble() / txPower;
  if (ratio < 1.0) {
    return math.pow(ratio, 10).toDouble();
  } else {
    return (0.89976 * math.pow(ratio, 7.7095) + 0.111);
  }
}
```

> ⚠️ **注意：** RSSI 测距受环境影响极大（障碍物、多径效应），仅供可视化参考。

### 最佳实践

1. **使用 `ref.watch()` 而非 `ref.read()`** 在 build 方法中
2. **定期清理过期设备**：调用 `notifier.removeStaleDevices(60)`
3. **避免在 build 中创建新对象**，Riverpod 会通过 `==` 比较避免不必要的重建

---

## 🗺️ 离线地图与 MBTiles

### 架构

```
MBTiles 文件 (sqlite3 格式)
       ↓
MbtilesReader 读取瓦片
       ↓
flutter_map TileProvider 渲染
       ↓
离线战术地图视图 + 脉冲求救标记
```

### 关键文件

| 文件 | 职责 |
|------|------|
| [lib/services/mbtiles_reader.dart](lib/services/mbtiles_reader.dart) | 从 MBTiles 文件读取瓦片 + 元数据 |
| [lib/widgets/offline_tactical_map_view.dart](lib/widgets/offline_tactical_map_view.dart) | 地图视图 + 脉冲 SOS 标记 |
| [lib/mesh_dashboard_page.dart](lib/mesh_dashboard_page.dart) | 地图模式切换（雷达 ↔ 地图） |

### 使用说明

1. 将 MBTiles 文件放置到 `{appDir}/maps/tactical.mbtiles`
2. 地图视图会自动检测并加载
3. 文件不存在时优雅降级显示空白地图
4. 求救者位置通过 Riverpod `meshStateProvider` 实时同步
5. 脉冲标记使用 `AnimationController` 实现呼吸灯效果

### 获取 MBTiles

推荐使用以下工具下载离线地图瓦片：
- **Mobile Atlas Creator (MOBAC)**：支持多种地图源，导出 MBTiles 格式
- **TileMill + mbutil**：自定义样式后导出

---

## 🎨 声呐雷达可视化

### 文件

[lib/widgets/sonar_radar_widget.dart](lib/widgets/sonar_radar_widget.dart)

### 性能特性

- **60fps 流畅动画**：使用 `CustomPainter` 直接绘制
- **局部刷新**：仅雷达区域重绘，不影响父组件
- **淡入动画**：新设备出现时有平滑的 FadeIn 过渡
- **脉冲效果**：每个设备光点带有呼吸灯效果

### 视觉效果

- 中心绿色同心圆代表自身位置
- 往外扩散的绿色扫描波纹（Ripple Effect）
- 红色闪烁光点代表求救者，大小和亮度根据 RSSI 动态调整
- 深色径向渐变背景

### 使用示例

```dart
// 完整雷达（推荐用于独立页面）
SonarRadarWidget(size: 320)

// 在 mesh_dashboard_page.dart 中
Consumer(
  builder: (context, ref, _) {
    final meshState = ref.watch(meshStateProvider);
    return SonarRadarWidget(size: 360);
  },
)
```

---

## 🔋 省电与后台服务

### 极限求生模式

通过 [lib/widgets/ultra_power_switch_widget.dart](lib/widgets/ultra_power_switch_widget.dart) 提供一键切换。

**进入极限模式后的变化：**
| 资源 | 标准模式 | 极限模式 | 效果 |
|------|---------|---------|------|
| GPS | 高精度持续监听 | 单次定位，5分钟间隔 | 大幅降低功耗 |
| BLE 广播 | 1 秒间隔 | 5 秒间隔 | 降低射频功耗 |
| 屏幕亮度 | 正常 | 5% | 屏幕是最耗电组件 |
| AI 引擎 | 运行 | 关闭 | 释放 CPU |

### 前台后台服务

通过 [lib/services/background_service_manager.dart](lib/services/background_service_manager.dart) 管理。

**关键设计：**
- 使用 `flutter_background_service` 确保后台不被系统杀死
- 常驻通知栏通知告知用户服务正在运行
- 通过静态字段在 Isolate 间共享数据（因为后台服务运行在独立 Isolate）

---

## 📡 联调验证清单

- [ ] 后端控制台无报错，MongoDB 已连接
- [ ] 大屏左上角显示绿色"已连接"状态
- [ ] 手机 App 能正常启动，各 Tab 可切换
- [ ] 在手机 SOS 页触发广播，另一台手机能扫描到信号
- [ ] 手机网络恢复后，大屏自动出现新的 SOS 告警
- [ ] 雷达页面能正确显示周围设备，光点位置和 RSSI 匹配
- [ ] 快速移动设备时，雷达动画保持 60fps 无卡顿
- [ ] 离线地图能正常加载 MBTiles 瓦片
- [ ] 极限求生模式切换后，GPS/BLE/亮度策略正确生效
- [ ] 前台服务通知栏常驻显示，后台广播持续运行

---

## � 代码审查与改进建议

> **最后审查日期：** 2026-04-06
> **审查范围：** 全量代码库（lib/、server/、dashboard/）

---

### 🔴 严重问题（阻塞上线）

#### 1. ~~BLE 协议长度不一致~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- `BleScannerService._expectedPayloadLength` 已从 `10` 改为 `14`
- `decodeSosPayload()` 的字节偏移已与 `BlePayloadEncoder` 完全对齐：
  - offset 0: 协议版本 (uint8)
  - offset 1: 血型编码 (uint8)
  - offset 2-5: 纬度 (float32 LE)
  - offset 6-9: 经度 (float32 LE)
  - offset 10-13: 时间戳 (uint32 LE)
- 移除了旧的 `_decodeCoordinate` 双重解析逻辑（float32 + int32/1000000 fallback），改为直接读取 float32

#### ~~2. 后端地址硬编码且多处不一致~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- 新增统一配置 [lib/config/app_config.dart](lib/config/app_config.dart)，通过 `--dart-define=ENV=xxx` 切换环境
- `network_sync_service.dart` 和 `sos_dispatch_manager.dart` 均已迁移到 `AppConfig`
- 不再需要手动修改源码中的 IP 地址

**使用方式：**
```bash
# 本地开发（连接本机模拟器）
flutter run --dart-define=ENV=local

# 云服务器（连接 101.35.52.133:3000）
flutter run --dart-define=ENV=production

# 自定义 IP（覆盖默认值）
flutter run --dart-define=ENV=local --dart-define=API_BASE_URL=http://192.168.1.100:3000
```

> ⚠️ **Android 模拟器注意：** 模拟器访问宿主机需用 `10.0.2.2` 而非 `localhost`。`ENV=local` 默认已配置为 `10.0.2.2:3000`。真机调试请使用 `--dart-define=API_BASE_URL=http://<你的局域网IP>:3000`。

#### ~~3. 服务生命周期管理不完整~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- [main.dart](lib/main.dart) 的 `dispose()` 中补充了服务清理逻辑
- 退出时会停止 BLE 扫描、BLE 广播、网络同步监听

#### ~~4. SOS 调度职责重叠~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- 已删除 `sos_dispatch_manager.dart`（无任何实际调用，仅有注释示例）
- `SosTriggerService` 作为唯一 SOS 触发入口，已被 `sos_page.dart` 和 `mesh_dashboard_page.dart` 使用
- `SosTriggerService` 的设计更清晰：数据库写入 → BLE 广播 → 网络同步，各通道错误独立报告

#### ~~5. `SosDispatchManager._sendHttpRequest` 缺少重试机制~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- `SosDispatchManager` 已删除，此问题随之消除
- `SosTriggerService` 通过 `NetworkSyncService.syncNow()` 执行同步，后者会在网络恢复时自动重试

#### ~~6. `main.dart` 中服务初始化缺乏顺序保障~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- 使用 `Future.wait` 并行等待所有服务初始化完成后再进入主界面
- 新增 `_safeInitialize` 辅助方法，捕获并记录每个服务的初始化错误，而非直接吞掉
- 初始化期间显示加载界面（"正在初始化救援系统..."），错误时显示具体失败信息
- SOS 消息流订阅仅在全部服务初始化成功后才注册，避免在 BLE 未就绪时触发异常
- 错误日志通过 `debugPrint` 输出，便于调试

**核心改动：**
```dart
// 并行初始化，等待全部完成
final results = await Future.wait([
  _safeInitialize('PowerSavingManager', () => powerSavingManager.initialize()),
  _safeInitialize('BleMeshService', () => bleMeshService.init()),
  _safeInitialize('BleScannerService', () => bleScannerService.init()),
  _safeInitialize('NetworkSyncService', () => networkSyncService.startListening()),
]);

// 收集错误并显示
for (final result in results) {
  if (result != null) errors.add(result);
}
```

#### ~~7. Drift 数据库缺少索引优化~~ — ✅ 已修复 (2026-04-06)

**修复内容：**
- 在 `SosMessages` 表中添加了两个索引：
  - `{isUploaded}` — 加速 `getPendingUploads()` 查询，避免全表扫描
  - `{senderMac, timestamp}` — 加速 `saveIncomingSos()` 去重查询
- 数据库 schema 版本从 3 升级到 4
- 迁移策略中为已有数据库通过 `m.createIndex()` 创建索引
- 新安装数据库会在建表时自动创建索引

**核心改动：**
```dart
@override
List<Set<Column>> get indices => [
  {isUploaded},              // 加速 getPendingUploads() 查询
  {senderMac, timestamp},    // 加速 saveIncomingSos() 去重查询
];
```

#### 8. 后台服务跨 Isolate 数据共享不安全

**问题描述：** `BackgroundServiceManager` 使用静态字段在 Isolate 间共享位置/血型数据。由于 Dart Isolate 是内存隔离的，静态字段在不同 Isolate 中是独立的副本，不是共享的。

**影响：** 后台 Isolate 可能使用过期的位置数据广播 SOS。

**建议：** 使用 `SendPort`/`ReceivePort` 或 `flutter_background_service` 提供的 `invoke_service_method` 进行跨 Isolate 通信。

---

### 🟢 改进建议（提升质量）

#### 9. 血型编码映射在同步时存在歧义

**问题描述：**
- Flutter `BloodType` 枚举：`unknown(-1), a(0), b(1), ab(2), o(3)`
- BLE 协议：血型作为 uint8（0-255），但 `unknown` 的 `-1` 会被截断为 255
- 后端 MongoDB 存储的值与前端枚举可能不对齐

**建议：** 在 `network_sync_service.dart` 中添加显式的血型转换函数，并在文档中明确定义编码映射。

#### 10. 缺少统一的日志框架

**问题描述：** 各处使用 `debugPrint` 输出日志，发布模式下会被丢弃。生产环境无法追踪问题。

**建议：** 引入 `logger` 包，或使用 `drift` 自带的日志机制。至少在生产模式下将关键事件写入本地文件。

#### 11. `ble_scanner_service.dart` 中去重指纹策略可优化

**问题描述：** 当前使用 MAC 地址 + 坐标构建 fingerprint。但 BLE 设备可能随机化 MAC 地址，导致同一设备被识别为多个节点。

**建议：** 考虑使用载荷内容的哈希作为去重标识（如 `senderMac + lat + lon + timestamp` 的 MD5），而非依赖 MAC 地址。

#### 12. 缺少单元测试覆盖

**问题描述：** `test/` 目录下的测试文件较少，核心服务（`BleMeshService`、`SosTriggerService`、`SosDispatchManager`）缺少测试。

**建议优先测试：**
- `BlePayloadEncoder` 的编解码往返一致性（当前因 #1 的 Bug 必定失败）
- `NetworkSyncService` 的网络异常场景（超时、断网、服务端 500）
- 数据库去重逻辑的正确性

#### 13. `pubspec.yaml` 依赖版本约束过宽

**问题描述：** 部分依赖使用 `^x.y.z` 宽松约束，可能导致不同开发者拉取到不同版本的依赖。

**建议：** 在 `pubspec_overrides.yaml` 中锁定关键依赖的版本，或使用 `flutter pub deps` 定期检查依赖树。

#### 14. 大屏仪表盘缺少 SOS 历史分页

**问题描述：** `GET /api/sos/active` 返回所有活跃 SOS 记录，无分页。当记录超过 1000 条时，前端渲染会卡顿。

**建议：** 后端添加 `?page=&limit=` 参数支持分页查询。

#### 15. 错误处理策略过于激进地吞掉异常

**问题描述：** `main.dart` 中多处 `.catchError((_) => null)` 会掩盖真实的初始化失败原因，导致应用看似正常运行但核心功能失效。

**建议：** 至少记录错误日志：`.catchError((e) => debugPrint('[Init Error] $e'))`，或在 UI 上显示降级提示。

---

## 📐 开发规范速记

```
坐标系约定：
  GeoJSON (MongoDB/Leaflet 内部): [longitude, latitude]  ← 注意是经度在前！
  Leaflet L.latLng / 显示层:       [latitude, longitude]
  Flutter 发送 JSON:               { "latitude": x, "longitude": y }

Socket 事件名：new_sos_alert
API 前缀：/api/sos/
BLE Company ID：0xFFFF
BLE 载荷长度：14 字节 (v1 协议)
环境切换：flutter run --dart-define=ENV=[local|production]

Drift 代码生成：
  dart run build_runner build        # 一次性生成
  dart run build_runner watch        # 监听模式

Git 分支建议：
  main        → 稳定版本，只接受 PR 合并
  feat/xxx    → 新功能开发
  fix/xxx     → Bug 修复
```

---

## 🔩 已知问题与 TODO

| # | 问题 | 位置 | 优先级 |
|---|------|------|--------|
| 1 | ~~**BLE 协议长度不一致**~~ encoder 14 字节 vs scanner 10 字节 — ✅ 已修复 (2026-04-06) | `ble_scanner_service.dart` | ✅ 已修复 |
| 2 | ~~**后端地址硬编码**~~ 已通过 AppConfig 统一配置 — ✅ 已修复 (2026-04-06) | `config/app_config.dart` | ✅ 已修复 |
| 3 | ~~**服务 dispose 不完整**~~ 已补充清理逻辑 — ✅ 已修复 (2026-04-06) | `main.dart` | ✅ 已修复 |
| 4 | ~~**SOS 调度职责重叠**~~ 已删除 SosDispatchManager — ✅ 已修复 (2026-04-06) | `sos_trigger_service.dart` | ✅ 已修复 |
| 5 | ~~**HTTP 同步无重试**~~ 随 SosDispatchManager 一并消除 — ✅ 已修复 (2026-04-06) | — | ✅ 已修复 |
| 6 | ~~**服务初始化无顺序保障**~~ 已使用 Future.wait 等待 — ✅ 已修复 (2026-04-06) | `main.dart` | ✅ 已修复 |
| 7 | ~~**Drift 数据库缺少索引**~~ 已添加 isUploaded 和复合索引 — ✅ 已修复 (2026-04-06) | `database.dart` | ✅ 已修复 |
| 8 | 跨 Isolate 静态字段不共享 | `background_service_manager.dart` | 🟡 中 |
| 9 | 血型编码映射歧义 | `emergency_profile.dart` + BLE 协议 | 🟡 中 |
| 10 | 缺少统一日志框架 | 全局 | 🟢 低 |
| 11 | BLE MAC 随机化影响去重 | `ble_scanner_service.dart` | 🟢 低 |
| 12 | 单元测试覆盖率不足 | `test/` | 🟡 中 |
| 13 | 大屏 SOS 列表无分页 | `GET /api/sos/active` | 🟡 中 |
| 14 | 错误处理过度吞异常 | `main.dart` | 🟡 中 |
| 15 | AR 救援罗盘页面待完善 | `lib/ar_rescue_compass_page.dart` | 🟢 低 |
| 16 | 医疗档案页 UI 待美化 | `lib/medical_profile_page.dart` | 🟡 中 |

---

## 📚 相关文档索引

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 项目概述与快速开始 |
| [BLE_RELAY_QUEUE_GUIDE.md](BLE_RELAY_QUEUE_GUIDE.md) | BLE 中继队列机制详解 |
| [FOREGROUND_SERVICE_GUIDE.md](FOREGROUND_SERVICE_GUIDE.md) | 前台后台服务生命周期管理 |
| [MAPTILES_SETUP_GUIDE.md](MAPTILES_SETUP_GUIDE.md) | 离线地图瓦片配置 |
| [OFFLINE_MAP_QUICKSTART.md](OFFLINE_MAP_QUICKSTART.md) | 离线地图快速入门 |
| [OFFLINE_MAP_INTEGRATION.md](OFFLINE_MAP_INTEGRATION.md) | 离线地图集成指南 |
| [OFFLINE_MAP_CHECKLIST.md](OFFLINE_MAP_CHECKLIST.md) | 离线地图检查清单 |
| [SOS_DISPATCH_GUIDE.md](SOS_DISPATCH_GUIDE.md) | SOS 调度中心详解 |
| [SERVER_DEPLOYMENT_GUIDE.md](SERVER_DEPLOYMENT_GUIDE.md) | 服务器部署指南 |
| [USER_DATA_PERSISTENCE_GUIDE.md](USER_DATA_PERSISTENCE_GUIDE.md) | 用户数据持久化指南 |
| [AR_RESCUE_COMPASS_GUIDE.md](AR_RESCUE_COMPASS_GUIDE.md) | AR 救援罗盘指南 |
| [AR_PERMISSIONS_CONFIG.md](AR_PERMISSIONS_CONFIG.md) | AR 权限配置 |
| [AR_ENTERPRISE_FEATURES.md](AR_ENTERPRISE_FEATURES.md) | AR 企业级功能 |
| [RELAY_API_REFERENCE.md](RELAY_API_REFERENCE.md) | 中继 API 参考 |

---

*"当所有通信都中断，这套系统是最后的呼救。做好它，值得。"*

---

**文档维护：** 核心架构有变动时请同步更新本文档。
