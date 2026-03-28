# 离线战术地图集成方案

## 概述

本方案为 Rescue Mesh 系统引入纯离线的 MBTiles 战术地图引擎，并实现与现有声呐雷达视图的一键无缝切换。

## 核心差异对比 (Diff)

### 1. 新增文件

#### `lib/widgets/offline_tactical_map_view.dart`
- **类名**: `OfflineTacticalMapView` (ConsumerStatefulWidget)
- **功能**: MBTiles 离线地图渲染 + 动态求救者标靶
- **特性**:
  - 使用 `flutter_map` + `flutter_map_mbtiles`
  - 实时监听 `meshStateProvider`
  - 红色脉冲信标标记
  - 异常降级处理（文件不存在时显示占位 UI）

#### `lib/services/mbtiles_reader.dart`
- **类名**: `MbtilesReader`, `MbTilesTileProvider`
- **功能**: SQLite MBTiles 数据库读取器
- **特性**:
  - 支持 TMS/XYZ 坐标转换
  - 读取地图元数据 (zoom level, bounds, center)
  - 异步瓦片加载

### 2. 改造 `mesh_dashboard_page.dart`

#### 关键变更点

**2.1 导入新组件**
```dart
// 新增导入
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/offline_tactical_map_view.dart';
import 'widgets/sonar_radar_widget.dart';
```

**2.2 添加视图切换状态**
```dart
class _MeshDashboardPageState extends State<MeshDashboardPage> {
  // ... 现有代码 ...
  
  // [新增] 视图模式切换
  bool _isMapView = false; // false = 雷达模式，true = 地图模式
}
```

**2.3 视图切换插槽 (在雷达监测区)**
```dart
// 原文 (约第 350-375 行):
if (!snapshot.hasData)
  _RadarSilentPanel(...)
else
  _SosAlertCard(...)

// 修改为:
AnimatedSwitcher(
  duration: const Duration(milliseconds: 300),
  transitionBuilder: (child, animation) {
    return FadeTransition(opacity: animation, child: child);
  },
  child: _isMapView
      ? OfflineTacticalMapView(key: const ValueKey('map'))
      : snapshot.hasData
          ? _SosAlertCard(...)
          : _RadarSilentPanel(..., key: const ValueKey('radar')),
)
```

**2.4 控制按钮 (在右上角或悬浮按钮)**
```dart
// 在 AppBar 或 Stack 中添加切换按钮
Positioned(
  top: 16,
  right: 16,
  child: FloatingActionButton.small(
    heroTag: 'view_toggle',
    backgroundColor: RescuePalette.panel,
    onPressed: () {
      setState(() {
        _isMapView = !_isMapView;
      });
    },
    child: Icon(
      _isMapView ? Icons.radar : Icons.map,
      color: _isMapView ? RescuePalette.accent : RescuePalette.success,
    ),
  ),
)
```

### 3. 资源文件配置

#### `pubspec.yaml`
```yaml
# 确保声明 MBTiles 文件路径
flutter:
  assets:
    - assets/maps/tactical.mbtiles
```

#### 文件放置位置
```
rescue_mesh_app/
└── assets/
    └── maps/
        └── tactical.mbtiles  # 需手动准备
```

## 工作流程

### 首次启动流程
1. 应用启动时检查 `assets/maps/tactical.mbtiles` 是否存在
2. 若存在 → 复制到本地存储目录 (`getApplicationDocumentsDirectory()/maps/`)
3. 若不存在 → 显示降级 UI ("离线瓦片未就绪")
4. 用户可随时切换回雷达模式

### 运行时流程
1. 用户点击 FAB 切换按钮
2. `setState(() => _isMapView = !_isMapView)`
3. `AnimatedSwitcher` 执行淡入淡出动画
4. 地图模式下：
   - `OfflineTacticalMapView` 监听 `meshStateProvider`
   - 遍历有坐标的求救者 → 生成 `Marker` 列表
   - 每个标记使用 `_PulsingBeaconPainter` 绘制脉冲效果

## 架构图

```
mesh_dashboard_page.dart
├── _MeshDashboardPageState
│   ├── _isMapView (bool)           ← 视图切换状态
│   ├── setState()                   ← 触发切换
│   │
│   └── build()
│       └── AnimatedSwitcher
│           ├── [雷达模式]
│           │   └── SonarRadarWidget / _RadarSilentPanel
│           │       └── ref.watch(meshStateProvider)
│           │
│           └── [地图模式]
│               └── OfflineTacticalMapView
│                   ├── FlutterMap
│                   │   ├── TileLayer (MbTilesTileProvider)
│                   │   └── MarkerLayer (动态求救者)
│                   │
│                   └── ref.watch(meshStateProvider)
│                       └── discoveredDevices
│                           └── payload.latitude/longitude
```

## 性能优化

1. **60 FPS 保证**:
   - `OfflineTacticalMapView` 使用 `AnimatedBuilder` 仅重绘脉冲标记
   - 地图瓦片缓存由 `flutter_map` 自动管理

2. **状态共享**:
   - 雷达和地图共享同一份 `meshStateProvider`
   - 无重复数据流，Riverpod 自动去重

3. **异常降级**:
   - MBTiles 文件检查在 `initState` 中异步执行
   - 缺失时立即返回占位组件，不阻塞 UI

## 使用说明

### 准备 MBTiles 文件

1. 使用 MapTiler、QGIS 等工具生成战术地图 MBTiles
2. 放置到 `assets/maps/tactical.mbtiles`
3. 运行 `flutter pub get`

### 切换视图

- 点击 FAB 按钮在雷达/地图间切换
- 地图模式下红色脉冲标靶代表求救者
- 标靶颜色根据 RSSI 动态变化 (红→黄→绿)

## 后续扩展建议

1. **多地图支持**: 添加地图选择器 (卫星图/地形图/街道图)
2. **离线路径规划**: 集成 GraphHopper 或 OSRM 离线版
3. **轨迹记录**: 在地图上绘制救援队伍移动轨迹
4. **热力图**: 基于 RSSI 和历史数据生成信号热力图

## 注意事项

⚠️ **MBTiles 文件大小**:
- 建议控制在 50MB 以内
- 过大的文件会导致首次启动复制缓慢

⚠️ **SQLite 依赖**:
- 已在 `pubspec.yaml` 中通过 `sqlite3_flutter_libs` 提供
- 无需额外配置

⚠️ **坐标系统**:
- MBTiles 使用 TMS (Tile Map Service) 坐标
- `flutter_map` 使用 XYZ 坐标
- `MbTilesTileProvider` 已自动处理转换

---

**生成时间**: 2026-03-28  
**适用版本**: Rescue Mesh App v1.0.0
