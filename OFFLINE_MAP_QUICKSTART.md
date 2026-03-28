# 离线地图 - 5 分钟快速上手

## ⚡ 极速部署（3 步搞定）

### Step 1: 复制 MBTiles 文件
```bash
# 假设你已经有一个 tactical.mbtiles 文件
# 将它复制到项目的 assets/maps 目录

# Windows PowerShell
Copy-Item `
  "C:\Downloads\tactical.mbtiles" `
  "e:\MyProject\rescue_mesh_app\assets\maps\tactical.mbtiles"

# 或手动复制：
# 1. 找到你的 tactical.mbtiles 文件
# 2. 复制到 rescue_mesh_app/assets/maps/ 文件夹
```

### Step 2: 运行应用
```bash
cd e:\MyProject\rescue_mesh_app
flutter pub get
flutter run
```

### Step 3: 测试切换
1. 应用启动后进入首页
2. 点击右上角的 **地图图标** 🗺️
3. 看到地图即为成功！

---

## 🎯 如果没有 MBTiles 文件？

### 方案 A: 使用占位图测试（最快）

即使没有 MBTiles 文件，代码也会显示降级提示，不会崩溃。

**预期效果**:
```
┌─────────────────────┐
│     🗺️❌           │
│  离线瓦片未就绪     │
│  请维持雷达模式     │
│                     │
│  提示：将           │
│  tactical.mbtiles   │
│  放置于 assets/maps/│
└─────────────────────┘
```

### 方案 B: 快速生成测试用 MBTiles（10 分钟）

#### 使用在线工具（推荐新手）
1. 访问：https://mbtiles-simple.vercel.app/
2. 选择一个小区域（如你所在的城市公园）
3. 缩放级别：12-15
4. 点击下载

#### 使用 QGIS（高质量）
```bash
# 1. 下载并安装 QGIS
# https://qgis.org/zh-CN/site/forusers/download.html

# 2. 打开 QGIS，添加 OpenStreetMap 图层
# 图层 → 添加图层 → XYZ 图层
# URL: https://tile.openstreetmap.org/{z}/{x}/{y}.png

# 3. 导出为 MBTiles
# 右键图层 → 导出 → 另存为
# 格式：MBTiles
# 缩放：12-15
# 范围：选择一个小区或公园（文件小）
```

---

## 🔍 验证是否成功

### 检查清单
- [ ] 首页右上角有切换按钮
- [ ] 点击按钮能切换模式
- [ ] 雷达模式正常工作（原有功能）
- [ ] 地图模式：
  - ✅ 有 MBTiles → 显示地图 + 红色标记
  - ❌ 无 MBTiles → 显示降级提示

### 调试技巧

#### 检查文件是否存在
```dart
// 在 offline_tactical_map_view.dart 中添加
print('MBTiles file exists: ${await File(_mapFilePath!).exists()}');
```

#### 查看控制台日志
```bash
# 运行应用时观察输出
flutter run --verbose

# 查找关键词：
# - "MBTiles"
# - "tactical.mbtiles"
# - "MbtilesReader"
```

---

## 📱 效果预览

### 雷达模式（原有功能）
```
┌─────────────────────────┐
│  雷达监测区       [🗺️]  │
│  ┌─────────────────┐   │
│  │   ╭─────────╮   │   │
│  │  ╱  扫描波   ╲  │   │
│  │ │  ●   ▲   │ │   │
│  │  ╲  ●   ╱  │   │
│  │   ╰─────────╯   │   │
│  └─────────────────┘   │
└─────────────────────────┘
```

### 地图模式（新增功能）
```
┌─────────────────────────┐
│  雷达监测区       [📡]  │
│  ┌─────────────────┐   │
│  │  ┌───────────┐  │   │
│  │  │  地图瓦片  │  │   │
│  │  │   🔴      │  │   │ ← 求救者
│  │  │      🔴   │  │   │ ← 求救者
│  │  │  🔴       │  │   │ ← 求救者
│  │  └───────────┘  │   │
│  └─────────────────┘   │
└─────────────────────────┘
```

---

## 🎨 自定义你的地图

### 修改默认显示位置
编辑 `lib/widgets/offline_tactical_map_view.dart` 第 140 行：

```dart
// 默认北京
initialCenter: const LatLng(39.9042, 116.4074),

// 改为上海
initialCenter: const LatLng(31.2304, 121.4737),

// 改为广州
initialCenter: const LatLng(23.1291, 113.2644),

// 改为深圳
initialCenter: const LatLng(22.5431, 114.0579),
```

### 修改标记颜色
编辑 `_PulsingBeaconPainter` 类（约第 250 行）：

```dart
// 当前：红→绿渐变
final paintColor = Color.lerp(
  RescuePalette.critical,  // 弱信号（红色）
  RescuePalette.success,   // 强信号（绿色）
  signalQuality,
)!;

// 改为：蓝→紫渐变
final paintColor = Color.lerp(
  Colors.blue,
  Colors.purple,
  signalQuality,
)!;
```

---

## 🐛 遇到问题？

### 问题 1: 找不到切换按钮
**原因**: 代码未正确合并  
**解决**:
```bash
# 检查 mesh_dashboard_page.dart 是否包含以下代码
grep "_isMapView" lib/mesh_dashboard_page.dart
grep "OfflineTacticalMapView" lib/mesh_dashboard_page.dart

# 如果没有，重新应用 diff
```

### 问题 2: 地图模式闪退
**原因**: MBTiles 文件损坏或太大  
**解决**:
1. 检查文件大小（应 < 100MB）
2. 用 SQLite 浏览器验证：
   ```bash
   sqlite3 tactical.mbtiles "PRAGMA integrity_check;"
   ```
3. 如果返回 `ok` 则文件正常

### 问题 3: 没有显示求救者标记
**原因**: meshStateProvider 中没有带坐标的设备  
**解决**:
```dart
// 添加调试输出
print('Total devices: ${meshState.discoveredDevices.length}');

meshState.discoveredDevices.values.forEach((device) {
  print('Device: ${device.address}');
  print('  Lat: ${device.payload.latitude}');
  print('  Lng: ${device.payload.longitude}');
  print('  RSSI: ${device.rssi}');
});
```

---

## 📚 深入阅读

- [完整集成指南](OFFLINE_MAP_INTEGRATION.md) - 架构设计与工作原理
- [Diff 文档](OFFLINE_MAP_DIFF.md) - 逐行代码对比
- [MBTiles 制备指南](MAPTILES_SETUP_GUIDE.md) - 4 种制作方法
- [实施总结](OFFLINE_MAP_SUMMARY.md) - 功能清单与验收标准

---

## 💡 专业提示

### 提示 1: 使用小文件测试
开发阶段使用 < 10MB 的小文件，加快迭代速度

### 提示 2: 准备多个测试文件
```
assets/maps/
├── tactical_beijing.mbtiles    # 北京区域
├── tactical_shanghai.mbtiles   # 上海区域
├── tactical_test.mbtiles       # 测试用（极小）
```

### 提示 3: 热重载测试
修改标记样式后，使用热重载快速预览：
```bash
# 按 r 进行热重载（保持状态）
# 按 R 进行热重启（重置状态）
```

---

## ✅ 完成标志

当你看到以下效果时，说明集成成功：

```
[✓] 应用正常启动
[✓] 首页显示雷达模式（原有功能）
[✓] 右上角有地图/雷达切换按钮
[✓] 点击切换后显示地图模式
[✓] 地图上有红色脉冲标记（如有求救者）
[✓] 切换流畅无卡顿
[✓] 无错误日志
```

**恭喜！离线地图引擎已成功集成！** 🎉

---

**最后更新**: 2026-03-28  
**适用版本**: Rescue Mesh App v1.0.0  
**预计耗时**: 5-10 分钟
