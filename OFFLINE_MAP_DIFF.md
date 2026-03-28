# 离线地图集成 - 快速参考 (DIFF)

## 文件清单

### ✅ 新增文件
1. `lib/widgets/offline_tactical_map_view.dart` - 离线战术地图组件
2. `lib/services/mbtiles_reader.dart` - MBTiles读取服务
3. `OFFLINE_MAP_INTEGRATION.md` - 详细集成指南
4. `OFFLINE_MAP_DIFF.md` - 本文件

### 🔄 修改文件
1. `lib/mesh_dashboard_page.dart` - 首页大盘

---

## 具体改动详情

### 1. `lib/mesh_dashboard_page.dart`

#### 改动 ①：导入语句 (顶部)
```diff
  import 'package:flutter/material.dart';
+ import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:location/location.dart';
  
  // ... 中间省略 ...
  
  import 'theme/rescue_theme.dart';
+ import 'widgets/offline_tactical_map_view.dart';
+ import 'widgets/sonar_radar_widget.dart';
```

#### 改动 ②：状态变量 (第 23 行附近)
```diff
  class _MeshDashboardPageState extends State<MeshDashboardPage>
      with TickerProviderStateMixin {
    late final AnimationController _pulseController;
    late final AnimationController _radarController;
    late final Listenable _servicesListenable;
  
    String? _actionStatus;
    Stream<SosMessage>? _sosStream;
+   
+   // [新增] 视图模式切换：false = 雷达模式，true = 地图模式
+   bool _isMapView = false;
  
    @override
    void initState() {
```

#### 改动 ③：雷达监测区 UI (第 350-390 行附近)
```diff
- child: Column(
-   crossAxisAlignment: CrossAxisAlignment.start,
-   children: [
-     Text(
-       '雷达监测区',
-       style: Theme.of(context).textTheme.titleMedium
-           ?.copyWith(
-             fontWeight: FontWeight.w900,
-             letterSpacing: 0.8,
-           ),
-     ),
-     const SizedBox(height: 14),
-     if (!snapshot.hasData)
-       _RadarSilentPanel(
-         controller: _radarController,
-         isScanning: widget.scannerService.isScanning,
-       )
-     else
-       _SosAlertCard(
-         message: snapshot.data!,
-         distanceText: _formatDistance(
-           snapshot.data!.rssi,
-         ),
-       ),
-   ],
- ),

+ child: Column(
+   crossAxisAlignment: CrossAxisAlignment.start,
+   children: [
+     Row(
+       children: [
+         Expanded(
+           child: Text(
+             '雷达监测区',
+             style: Theme.of(context).textTheme.titleMedium
+                 ?.copyWith(
+                   fontWeight: FontWeight.w900,
+                   letterSpacing: 0.8,
+                 ),
+           ),
+         ),
+         // [新增] 视图切换按钮
+         IconButton(
+           icon: Icon(
+             _isMapView ? Icons.radar : Icons.map,
+             color: _isMapView
+                 ? RescuePalette.accent
+                 : RescuePalette.success,
+           ),
+           tooltip: _isMapView
+               ? '切换到雷达模式'
+               : '切换到地图模式',
+           onPressed: () {
+             setState(() {
+               _isMapView = !_isMapView;
+             });
+           },
+         ),
+       ],
+     ),
+     const SizedBox(height: 14),
+     if (_isMapView)
+       // [新增] 地图模式
+       SizedBox(
+         height: 280,
+         child: OfflineTacticalMapView(),
+       )
+     else
+       // [原有] 雷达模式
+       StreamBuilder<SosMessage>(
+         stream: _sosStream,
+         builder: (context, snapshot) {
+           if (!snapshot.hasData) {
+             return _RadarSilentPanel(
+               controller: _radarController,
+               isScanning: widget.scannerService.isScanning,
+             );
+           } else {
+             return _SosAlertCard(
+               message: snapshot.data!,
+               distanceText: _formatDistance(
+                 snapshot.data!.rssi,
+               ),
+             );
+           }
+         },
+       ),
+   ],
+ ),
```

---

### 2. `lib/widgets/offline_tactical_map_view.dart` (新建)

**完整文件内容已在之前创建，此处省略。**

核心功能：
- ConsumerStatefulWidget
- 监听 `meshStateProvider`
- 使用 `flutter_map` + `MbTilesTileProvider`
- 动态生成红色脉冲标记
- 异常降级处理

---

### 3. `lib/services/mbtiles_reader.dart` (新建)

**完整文件内容已在之前创建，此处省略。**

核心功能：
- SQLite MBTiles 数据库读取
- TMS/XYZ 坐标转换
- 异步瓦片加载
- 元数据解析 (zoom, bounds, center)

---

## 使用步骤

### Step 1: 准备 MBTiles 文件
```bash
# 将战术地图 MBTiles 文件放到以下位置
rescue_mesh_app/assets/maps/tactical.mbtiles
```

### Step 2: 更新 pubspec.yaml (如需要)
```yaml
flutter:
  assets:
    - assets/maps/tactical.mbtiles
```

### Step 3: 运行应用
```bash
flutter pub get
flutter run
```

### Step 4: 测试切换功能
1. 首页右上角出现地图/雷达切换按钮
2. 点击按钮即可在两种模式间切换
3. 如果 MBTiles 文件不存在，会显示降级提示

---

## 可视化对比

### 原页面结构
```
┌─────────────────────────────┐
│  雷达监测区                  │
│  ┌─────────────────────┐    │
│  │  SonarRadarWidget   │    │
│  │  或 RadarSilentPanel│    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

### 改造后页面结构
```
┌─────────────────────────────┐
│  雷达监测区       [🗺️]       │ ← 新增切换按钮
│  ┌─────────────────────┐    │
│  │  地图模式：          │    │
│  │  OfflineTacticalMap │    │
│  │  + 红色脉冲标记      │    │
│  ├─────────────────────┤    │
│  │  雷达模式：          │    │
│  │  SonarRadarWidget   │    │
│  │  或 RadarSilentPanel│    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

---

## 状态流转

```mermaid
graph LR
    A[启动应用] --> B{MBTiles 存在？}
    B -->|是 | C[地图模式可用]
    B -->|否 | D[显示降级提示]
    C --> E[点击切换按钮]
    D --> E
    E --> F{当前模式？}
    F -->|雷达 | G[切换到地图]
    F -->|地图 | H[切换到雷达]
    G --> I[显示求救者标记]
    H --> J[显示声呐扫描]
```

---

## 关键特性

✅ **无缝切换**: 使用 `setState` + 三元表达式实现瞬间切换  
✅ **状态共享**: 地图和雷达共享 `meshStateProvider`  
✅ **异常安全**: MBTiles 缺失时自动降级  
✅ **性能优化**: 脉冲动画独立渲染，不影响地图主线程  
✅ **零侵入**: 不影响现有雷达功能  

---

## 故障排查

### 问题 1: 切换按钮不显示
- 检查 `_isMapView` 变量是否正确添加
- 确认 `IconButton` 代码块在正确位置

### 问题 2: 地图模式显示空白
- 检查 `assets/maps/tactical.mbtiles` 是否存在
- 查看控制台是否有 SQLite 错误
- 确认 `MbTilesTileProvider` 路径正确

### 问题 3: 标记不显示
- 确认 `meshStateProvider` 中有带坐标的设备
- 检查 `payload.latitude` 和 `payload.longitude` 是否为 null
- 调整地图初始中心点和缩放级别

---

**最后更新**: 2026-03-28  
**适用版本**: Rescue Mesh App v1.0.0
