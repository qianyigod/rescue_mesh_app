# MBTiles 文件准备指南

## 什么是 MBTiles？

MBTiles 是一种基于 SQLite 的地图瓦片存储格式，由 MapBox 开发。它将大量的地图图片（瓦片）打包成一个单独的 `.mbtiles` 文件，非常适合离线地图应用。

### MBTiles 文件结构
```
tactical.mbtiles (SQLite 数据库)
├── metadata 表
│   ├── name: "战术地图"
│   ├── minzoom: 10
│   ├── maxzoom: 18
│   ├── bounds: 116.4074,39.9042,116.5074,40.0042
│   └── format: png
└── tiles 表
    ├── zoom_level: 13
    ├── tile_column: 6542
    ├── tile_row: 3211
    └── tile_data: (PNG 二进制数据)
```

---

## 方案一：使用 QGIS 生成 MBTiles（推荐）

### 步骤 1: 安装 QGIS
下载地址：https://qgis.org/

### 步骤 2: 加载地图源
1. 打开 QGIS
2. 点击 `图层` → `添加图层` → `添加 XYZ 图层`
3. 添加以下任一来源：
   - **OpenStreetMap**: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`
   - **Satellite (Google)**: 需要 API Key
   - **本地 GeoTIFF**: 如果有卫星影像数据

### 步骤 3: 设置导出范围
1. 右键点击图层 → `导出` → `另存为...`
2. 选择 `MBTiles` 格式
3. 设置参数：
   ```
   最小缩放级别：10
   最大缩放级别：18
   瓦片格式：PNG
   DPI: 96
   ```
4. 设置边界框（北京示例）：
   ```
   西：116.4074
   东：116.5074
   南：39.9042
   北：40.0042
   ```

### 步骤 4: 导出文件
1. 输出文件：`tactical.mbtiles`
2. 点击 `确定` 开始生成
3. 等待完成（可能需要几分钟）

---

## 方案二：使用 MapTiler Desktop

### 步骤 1: 下载 MapTiler
https://www.maptiler.com/desktop/

### 步骤 2: 导入数据
1. 打开 MapTiler Desktop
2. 拖拽卫星图片或地图到窗口
3. 选择 `Mercator` 投影

### 步骤 3: 配置输出
1. 选择 `MBTiles` 格式
2. 设置缩放级别：10-18
3. 选择图片质量：80%（平衡大小和质量）

### 步骤 4: 导出
点击 `Render` 开始生成

---

## 方案三：使用命令行工具（高级）

### 工具：gdal2tiles.py

```bash
# 安装 GDAL
sudo apt-get install gdal-bin

# 下载卫星图片（示例）
wget -O satellite.tif "https://example.com/satellite.tif"

# 生成 MBTiles
gdal2tiles.py -z 10-18 -w none -o google satellite.tif output_tiles

# 打包为 MBTiles
mb-util output_tiles tactical.mbtiles --scheme=tms
```

### 工具：mbutil
GitHub: https://github.com/mapbox/mbutil

```bash
# 安装
git clone https://github.com/mapbox/mbutil.git
cd mbutil
python setup.py install

# 使用
mb-util image_tiles tactical.mbtiles --scheme=tms
```

---

## 方案四：下载现成 MBTiles

### 资源网站
1. **OpenTopoMap**: https://opentopomap.org/
2. **Thunderforest**: https://www.thunderforest.com/
3. **Stamen**: http://maps.stamen.com/

⚠️ **注意**: 下载时请遵守各网站的许可协议和使用条款

---

## 文件大小优化建议

### 推荐配置
| 用途 | 缩放级别 | 面积 | 文件大小 |
|------|---------|------|---------|
| 城市救援 | 12-16 | 10×10 km | 20-50 MB |
| 山区搜救 | 10-14 | 50×50 km | 30-80 MB |
| 全国概览 | 6-10 | 全国 | 100-200 MB |

### 优化技巧
1. **限制缩放级别**: 只包含必要的层级（如 12-15）
2. **裁剪边界**: 只导出任务区域，不要全国
3. **压缩质量**: PNG 质量设为 80-85%
4. **矢量切片**: 考虑使用 PBF 格式（更小）

---

## 部署到项目

### 方法 1: 放入 Assets（适合小文件 < 50MB）
```bash
# 复制文件
cp tactical.mbtiles /path/to/rescue_mesh_app/assets/maps/

# 更新 pubspec.yaml
flutter:
  assets:
    - assets/maps/tactical.mbtiles
```

### 方法 2: 运行时下载（适合大文件）
```dart
// 首次启动时从服务器下载
Future<void> downloadMapFile() async {
  final appDir = await getApplicationDocumentsDirectory();
  final mapFile = File('${appDir.path}/maps/tactical.mbtiles');
  
  if (!await mapFile.exists()) {
    await mapFile.parent.create(recursive: true);
    
    final url = 'https://your-server.com/maps/tactical.mbtiles';
    final response = await http.get(Uri.parse(url));
    
    await mapFile.writeAsBytes(response.bodyBytes);
  }
}
```

### 方法 3: 手动放置（推荐 > 100MB）
```
应用启动时检测：
1. 检查 documents/maps/tactical.mbtiles
2. 不存在 → 显示提示让用户通过 USB 传输
3. 存在 → 正常加载
```

---

## 验证 MBTiles 文件

### 使用 SQLite 浏览器
```bash
# 打开文件
sqlite3 tactical.mbtiles

# 查看元数据
SELECT * FROM metadata;

# 查看瓦片数量
SELECT zoom_level, COUNT(*) FROM tiles GROUP BY zoom_level;

# 测试读取瓦片
SELECT tile_data FROM tiles 
WHERE zoom_level=13 AND tile_column=6542 AND tile_row=3211;
```

### 预期输出
```sql
-- metadata 表示例
name|tactical
minzoom|10
maxzoom|18
bounds|116.4074,39.9042,116.5074,40.0042
format|png

-- tiles 统计
zoom_level|count
10|4
11|16
12|64
13|256
14|1024
15|4096
16|16384
```

---

## 故障排查

### 问题 1: 瓦片不显示
```sql
-- 检查是否有数据
SELECT COUNT(*) FROM tiles;

-- 检查坐标系统
SELECT * FROM metadata WHERE name='bounds';
```

### 问题 2: 应用崩溃
- 检查文件大小（建议 < 200MB）
- 验证 SQLite 数据库完整性：
  ```bash
  sqlite3 tactical.mbtiles "PRAGMA integrity_check;"
  ```

### 问题 3: 坐标偏移
- 确认使用 WGS84 坐标系 (EPSG:4326)
- 检查 TMS/XYZ 坐标系统转换

---

## 最佳实践

✅ **DO**:
- 为不同任务区域准备多个 MBTiles 文件
- 定期更新地图数据
- 在 Wi-Fi 环境下预下载
- 测试不同缩放级别的显示效果

❌ **DON'T**:
- 不要包含超过 18 级的缩放（文件会巨大）
- 不要使用未压缩的 TIFF 直接转换
- 不要忽略许可协议
- 不要在应用中硬编码大文件

---

## 参考资源

- MBTiles 规范：https://github.com/mapbox/mbtiles-spec
- QGIS 官方文档：https://docs.qgis.org/
- MapTiler 教程：https://www.maptiler.com/how-to/
- GDAL 文档：https://gdal.org/programs/gdal2tiles.html

---

**更新时间**: 2026-03-28  
**适用版本**: Rescue Mesh App v1.0.0
