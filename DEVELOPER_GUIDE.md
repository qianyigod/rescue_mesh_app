# Rescue Mesh — Developer Guide

> **项目代号:** RESCUE MESH · 离线应急救援网络
> **文档状态:** v1.0 · 2026-03-21 · 

---

## 🌍 项目代号与愿景

**一句话价值主张：** 在完全断网的极端灾害现场，让每一部手机都成为生命接力站——遇险者的求救信号通过蓝牙 Mesh 跳传至拥有网络的"数据骡子"，再批量上报至云端大屏，守护每一条不能失联的生命。

### 核心工作流

```
[ 遇险者手机 ]
  ├─ 端侧 AI (llama.cpp) 辅助填写医疗档案
  └─ BLE Manufacturer Data 广播 SOS 信标 (10字节)
         ↓ 蓝牙扫描 (30秒本地去重)
[ 数据骡子手机 ]  (路过现场的任意用户)
  └─ flutter_blue_plus 接收 → Drift/SQLite 本地存储
         ↓ 网络恢复时自动触发 (connectivity_plus)
[ Node.js 后端 ]
  └─ POST /api/sos/sync → 10分钟窗口服务端去重 → MongoDB 持久化
         ↓ Socket.io 实时推送   
[ Vue 3 大屏 ]
  └─ Leaflet 地图红点 + ECharts 图表 + AlertFeed 滚动告警
```

---

## 🛠️ 技术栈总览

### 移动端 (Flutter)

| 依赖 | 版本 | 用途 |
|------|------|------|
| `flutter_blue_plus` | 1.35.5 | BLE 广播 (SOS发送) + 扫描 (数据骡子接收) |
| `drift` + `sqlite3_flutter_libs` | 2.19.0 / 0.5.24 | 本地 SQLite 持久化，含 Drift ORM 代码生成 |
| `connectivity_plus` | 6.0.3 | 监听网络状态，网络恢复时触发自动同步 |
| `http` | 1.2.1 | HTTP POST 批量上报至后端 |
| `permission_handler` | 11.3.1 | 运行时申请蓝牙/定位权限 |
| `location` | 5.0.3 | 获取 GPS 坐标 |
| `flutter_map` + `latlong2` | 6.1.0 / 0.9.1 | 移动端地图显示 |
| `fcllama` / `llama_cpp_dart` | — | 端侧大模型推理（集成中） |

> **BLE 广播实现细节：** Dart 层通过 Android Method Channel `rescue_mesh/advertiser` 调用原生 Kotlin/Java 实现广播，因 Flutter BLE 库在部分 Android 版本不支持主动广播。

### 后端 (Node.js)

| 依赖 | 版本 | 用途 |
|------|------|------|
| `express` | 4.19.2 | REST API 框架 |
| `mongoose` | 8.4.1 | MongoDB ODM，含 GeoJSON 2dsphere 索引 |
| `socket.io` | 4.7.5 | 向大屏实时推送新 SOS 事件 |
| `dotenv` | 16.4.5 | 环境变量管理 |
| `cors` | 2.8.5 | 跨域支持 |

### 前端大屏 (Vue 3)

| 依赖 | 版本 | 用途 |
|------|------|------|
| `vue` | 3.4.27 | 响应式 UI 框架 |
| `echarts` | 5.5.0 | 血型分布玫瑰图 + 12小时趋势折线图 |
| `leaflet` | 1.9.4 | 实时 SOS 地图（CartoDB Dark Matter 暗色底图） |
| `socket.io-client` | 4.7.5 | 接收后端实时推送 |
| `vite` | 5.2.11 | 构建工具 |

---

## 📂 核心项目结构

```
rescue_mesh_app/
│
├── lib/                          # Flutter 移动端
│   ├── main.dart                 # ★ 应用入口：4Tab导航 + 服务初始化编排
│   ├── database.dart             # ★ Drift ORM：SosRecords/SosMessages 表定义 + 去重逻辑
│   ├── database.g.dart           # [自动生成，勿手动修改] Drift 代码生成产物
│   │
│   ├── sos_page.dart             # UI：SOS 发送控制页（触发广播、获取GPS）
│   ├── ai_chat_page.dart         # UI：端侧 AI 对话页（llama.cpp 集成中）
│   ├── message_page.dart         # UI：收到的 SOS 消息列表
│   ├── profile_page.dart         # UI：个人设置页
│   ├── mesh_dashboard_page.dart  # UI：Mesh 网络状态看板
│   ├── medical_profile_page.dart # UI：医疗档案（血型/过敏/既往病史）⭐待美化
│   │
│   ├── models/
│   │   ├── sos_message.dart              # SOS 数据模型（MAC、坐标、血型、时间戳）
│   │   ├── emergency_profile.dart        # BloodType 枚举 + EmergencyProfile 数据类
│   │   └── sos_advertisement_payload.dart # BLE 广播载荷结构定义
│   │
│   ├── services/
│   │   ├── ble_mesh_service.dart         # ★ BLE 广播服务：startSosBroadcast/stopSosBroadcast
│   │   ├── ble_scanner_service.dart      # ★ BLE 扫描服务：解析10字节载荷，30s窗口去重
│   │   ├── network_sync_service.dart     # ★ 网络同步：监听连接变化，批量 POST /api/sos/sync
│   │   ├── ble_mesh_exceptions.dart      # BLE 相关异常类型
│   │   └── network_sync_exceptions.dart  # 网络同步异常类型
│   │
│   └── theme/
│       └── rescue_theme.dart             # 全局主题配置（颜色、字体）
│
├── server/                       # Node.js 后端
│   ├── src/
│   │   ├── index.js              # ★ 应用入口：Express + Socket.io + MongoDB 初始化
│   │   ├── models/
│   │   │   └── SosRecord.js      # ★ Mongoose Schema：GeoJSON Point、2dsphere索引、confidence虚拟字段
│   │   ├── routes/
│   │   │   └── sos.js            # ★ 核心路由：POST /api/sos/sync（去重上报）+ GET /api/sos/active
│   │   └── socket/
│   │       └── index.js          # Socket.io 模块：init() + broadcastNewSos()
│   │
│   ├── .env                      # 本地环境变量（不入库，需手动创建）
│   ├── .env.example              # 环境变量模板
│   └── package.json
│
├── dashboard/                    # Vue 3 大屏前端
│   ├── src/
│   │   ├── main.js               # Vue 3 应用挂载入口
│   │   ├── App.vue               # ★ 根组件：三栏 Grid 布局 + 顶部状态栏（时钟/连接状态）
│   │   ├── style.css             # 全局暗色主题 + 动画（blink/sos-ring/scan-line）
│   │   │
│   │   ├── components/
│   │   │   ├── AlertFeed.vue     # ★ 左侧：SOS 告警滚动列表（TransitionGroup，最多300条）
│   │   │   ├── MapComponent.vue  # ★ 中央：Leaflet 地图 + 脉冲 DivIcon 红点标记
│   │   │   └── StatsComponent.vue# ★ 右侧：ECharts 血型玫瑰图 + 12小时趋势折线图
│   │   │
│   │   └── composables/
│   │       └── useSocket.js      # ★ 全局状态单例：Socket.io连接 + 响应式alerts/bloodCounts
│   │
│   ├── index.html
│   └── package.json
│
├── assets/                       # 静态资源（模型文件、图片等）
├── android/                      # Android 原生层（含 BLE 广播 Method Channel 实现）
├── ios/                          # iOS 原生层
├── pubspec.yaml                  # Flutter 依赖声明
└── README.md
```

---

## 🚀 局域网联调与启动指南

> ⚠️ **Localhost 陷阱 — 必读！**
>
> 移动端真机 和 大屏浏览器 都不在你的电脑上运行，它们无法通过 `localhost` 或 `127.0.0.1` 访问你的后端。
> 你**必须**使用电脑在局域网内的真实 IPv4 地址。
>
> **获取局域网 IP：**
> ```bash
> # Windows
> ipconfig
> # 找 "以太网适配器" 或 "WLAN" 下的 IPv4 地址，例如 192.168.1.105
>
> # macOS / Linux
> ifconfig | grep "inet "
> ```
>
> 后续步骤中，将所有 `<YOUR_LAN_IP>` 替换为你获取到的 IP 地址。
> **所有设备（手机、浏览器）必须连接同一个 Wi-Fi 网络！**

---

### Step 1：启动后端 (Node.js)

**1. 创建 `.env` 文件**

在 `server/` 目录下，复制 `.env.example` 并填写：

```bash
cd server
cp .env.example .env
```

编辑 `server/.env`：

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/rescue_mesh
# 若使用 MongoDB Atlas，替换为你的连接字符串
```

**2. 安装依赖并启动**

```bash
cd server
npm install
node src/index.js
```

启动成功后你应看到：
```
[Server] MongoDB connected
[Server] Listening on http://0.0.0.0:3000
```

> 确保 MongoDB 已在本地运行（`mongod`），或使用 Atlas 云数据库。

---

### Step 2：启动大屏前端 (Vue 3)

**1. 修改后端连接地址**

打开 [dashboard/src/composables/useSocket.js](dashboard/src/composables/useSocket.js)，找到 Socket.io 连接初始化部分，将地址改为：

```js
// 修改前（示例）
const socket = io('http://localhost:3000')

// 修改后
const socket = io('http://<YOUR_LAN_IP>:3000')
```

同时检查 `fetchActive` 函数中的 REST API 地址是否也需要同步修改。

**2. 安装依赖并启动**

```bash
cd dashboard
npm install
npm run dev
```

Vite 启动后访问 `http://localhost:5173`，在大屏上应能看到连接状态变为绿色。

---

### Step 3：运行移动端 (Flutter)

**1. 修改后端同步地址**

打开 [lib/services/network_sync_service.dart](lib/services/network_sync_service.dart)，找到 API endpoint 配置：

```dart
// 修改前（生产环境地址）
static const String _syncUrl = 'https://api.rescuemesh.com/v1/sos/sync';

// 修改后（局域网调试）
static const String _syncUrl = 'http://<YOUR_LAN_IP>:3000/api/sos/sync';
```

**2. 连接真机并运行**

```bash
# 查看已连接设备
flutter devices

# 运行到指定设备（推荐真机，模拟器不支持 BLE 广播）
flutter run -d <device_id>
```

> **Android 权限提示：** 首次运行需在手机上允许蓝牙、定位权限。部分 Android 12+ 设备需要同时开启"附近设备"权限。

**3. 重新生成 Drift 代码（若修改了 database.dart）**

```bash
dart run build_runner build
```

---

### 联调验证清单

- [ ] 后端控制台无报错，MongoDB 已连接
- [ ] 大屏左上角显示绿色"已连接"状态
- [ ] 手机 App 能正常启动，四个 Tab 可切换
- [ ] 在手机 SOS 页触发广播，另一台手机能扫描到信号
- [ ] 手机网络恢复后，大屏自动出现新的 SOS 告警卡片和地图红点

---

## 📡 关键数据结构速查

### BLE 广播载荷 (10 字节)

```
Byte 0      : SOS flag (0x01 = 求救中)
Bytes 1-4   : latitude  (float32, little-endian)
Bytes 5-8   : longitude (float32, little-endian)
Byte 9      : bloodType code
```

### 批量同步请求体 (POST /api/sos/sync)

```json
{
  "muleId": "AA:BB:CC:DD:EE:FF",
  "records": [
    {
      "senderMac": "11:22:33:44:55:66",
      "latitude": 39.9093,
      "longitude": 116.3974,
      "bloodType": 0,
      "timestamp": "2024-06-15T08:30:00.000Z"
    }
  ]
}
```

### 血型编码对照表

| Flutter 枚举 | MongoDB 存储值 | 大屏显示 | 颜色 |
|-------------|--------------|---------|------|
| `unknown(0)` | `-1` | 未知 | `#9966FF` |
| `a(1)` | `0` | A型 | `#FF6B6B` |
| `b(2)` | `1` | B型 | `#4BC0C0` |
| `ab(3)` | `2` | AB型 | `#FFCE56` |
| `o(4)` | `3` | O型 | `#00E5FF` |

> ⚠️ **已知不一致：** Flutter 枚举值 (`0-4`) 与 MongoDB 存储值 (`-1,0,1,2,3`) 存在偏移，`network_sync_service.dart` 中需确认映射转换逻辑是否正确。

### 三层去重机制

| 层级 | 位置 | 去重窗口 | 依据 |
|------|------|---------|------|
| BLE 扫描层 | `ble_scanner_service.dart` | 30 秒 | fingerprint (MAC+坐标) |
| 本地数据库层 | `database.dart` | 5 分钟 | senderMac + 时间戳 |
| 服务端层 | `server/src/routes/sos.js` | 10 分钟 | senderMac + 时间戳 |

---

## 🎯 队友优化任务分配

### 🖥️ 前端大屏优化 (dashboard/)

**1. ECharts 图表动画增强**

文件：[dashboard/src/components/StatsComponent.vue](dashboard/src/components/StatsComponent.vue)

当前状态：图表已实现，但数据更新时缺少流畅过渡动画。

任务：
- 为玫瑰图设置 `animationType: 'scale'`，`animationDuration: 800`
- 折线图新增数据点时使用 `chart.appendData()` 而非全量 `setOption()`，避免闪烁
- 当 `alerts` 为空时显示"等待数据接入..."的空状态占位

**2. Leaflet 地图红点 Ripple 动效优化**

文件：[dashboard/src/components/MapComponent.vue](dashboard/src/components/MapComponent.vue)、[dashboard/src/style.css](dashboard/src/style.css)

当前状态：脉冲动画类 `.sos-marker / .sos-dot / .sos-ring` 已在 CSS 中定义。

任务：
- 新增告警时，对应标记播放一次"爆闪"入场动画（scale 0→1.5→1）
- 超过 30 分钟的旧告警标记降低不透明度（0.4），颜色从红色渐变为橙色
- 点击标记弹出 Popup 显示：MAC后四位 / 血型 / 时间 / 中继次数(confidence)

**3. 断线重连 UI 提示**

文件：[dashboard/src/App.vue](dashboard/src/App.vue)、[dashboard/src/composables/useSocket.js](dashboard/src/composables/useSocket.js)

任务：
- 在 `useSocket.js` 中监听 `socket.on('disconnect')` 和 `socket.on('reconnect_attempt')`
- 在顶部状态栏显示"连接中断，正在重连 (3)..."倒计时 UI
- 重连成功后自动调用 `fetchActive()` 补齐断线期间的数据

---

### ⚙️ 后端逻辑优化 (server/)

**1. 精准去重算法完善**

文件：[server/src/routes/sos.js](server/src/routes/sos.js)

当前状态：基于 `senderMac + timestamp` 10分钟窗口去重。

任务：
- 增加坐标漂移容忍：同一 MAC 在 10 分钟内、GPS 坐标偏差 < 100 米范围内，视为同一事件
- 合并时更新 `location` 为多次上报的坐标**加权平均值**，提升定位精度（更多骡子 → 更准确）
- 完善 `details[]` 返回字段，包含每条记录的处理结果

**2. MongoDB 空间查询加速**

文件：[server/src/models/SosRecord.js](server/src/models/SosRecord.js)

当前状态：已建立 `2dsphere` 索引，但未在查询中使用 `$near` 进行范围搜索。

任务：
- 在 `GET /api/sos/active` 中增加可选的地理围栏参数：`?lat=&lon=&radius=5000`（单位：米）
- 使用 `$geoWithin` / `$centerSphere` 实现响应端查询指挥中心关注区域内的告警

**3. 数据老化与状态流转**

任务：
- 增加定时任务（`setInterval` 或 `node-cron`）：每 5 分钟将超过 2 小时无新上报的 `active` SOS 标记为 `stale`
- 为 `GET /api/sos/active` 增加分页参数 `?page=&limit=`，防止大屏初始化时数据量过大

---
//我来就行可以不用管

### 📱 移动端 UI/UX 优化 (lib/)

**1. 医疗档案页 Apple Health 极简风美化**

文件：[lib/medical_profile_page.dart](lib/medical_profile_page.dart)

任务：
- 参考 Apple Health 风格：卡片圆角 `16px`，白底+浅灰分割线，SF Pro 风字重
- 血型选择改为色块 RadioButton 组：A(红)/B(青)/AB(黄)/O(蓝)，选中后边框高亮+勾选图标
- 页面顶部增加一个"一键生成 SOS 二维码"按钮，将档案编码为 QR 供离线扫描

**2. BLE 扫描电量消耗优化**

文件：[lib/services/ble_scanner_service.dart](lib/services/ble_scanner_service.dart)

当前状态：使用低延迟扫描模式（`lowLatency`）。

任务：
- 前台活跃时使用 `lowLatency`，后台/息屏时切换为 `lowPower` 模式
- 监听 `AppLifecycleState`，在 `paused` 状态下降低扫描频率
- 扫描间隔增加**指数退避**：连续 5 分钟无新信号时，扫描间隔从 5s 逐步拉大到 30s

**3. 错误弹窗与状态反馈完善**

涉及文件：[lib/sos_page.dart](lib/sos_page.dart)、[lib/services/network_sync_service.dart](lib/services/network_sync_service.dart)

任务：
- SOS 触发失败（蓝牙未开启、定位被拒）时，弹出 `AlertDialog` 说明原因并引导用户去设置页
- 网络同步结果用 `SnackBar` 展示："已上传 12 条 SOS 记录 ✓" 或 "同步失败，将在下次联网时重试"
- `MeshDashboardPage` 中实时显示：当前广播状态 / 本地待上传记录数 / 最近一次同步时间

---

## 🔩 已知问题与 TODO

| # | 问题 | 位置 | 优先级 |
|---|------|------|--------|
| 1 | Flutter BloodType 枚举值与 MongoDB 存储值存在偏移 | `network_sync_service.dart` + `SosRecord.js` | 🔴 高 |
| 2 | 端侧 AI (`fcllama`/`llama_cpp_dart`) 依赖已声明但未实际接入 | `ai_chat_page.dart` | 🟡 中 |
| 3 | `network_sync_service.dart` 中后端地址硬编码为生产域名 | `lib/services/network_sync_service.dart` | 🔴 高（联调必改）|
| 4 | Android BLE 广播 Method Channel 实现在原生层，需补充说明 | `android/` | 🟡 中 |
| 5 | 大屏初始化时若 SOS 记录过多，无分页导致首屏卡顿 | `GET /api/sos/active` | 🟡 中 |

---

## 📐 开发规范速记

```
坐标系约定：
  GeoJSON (MongoDB/Leaflet 内部): [longitude, latitude]  ← 注意是经度在前！
  Leaflet L.latLng / 显示层:       [latitude, longitude]
  Flutter 发送 JSON:               { "latitude": x, "longitude": y }

Socket 事件名：new_sos_alert
API 前缀：/api/sos/

Git 分支建议：
  main        → 稳定版本，只接受 PR 合并
  feat/xxx    → 新功能开发
  fix/xxx     → Bug 修复
```

---

*"当所有通信都中断，这套系统是最后的呼救。做好它，值得。"*

---

**文档维护：** 核心架构有变动时请同步更新本文档。
