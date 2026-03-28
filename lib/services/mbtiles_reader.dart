import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter/painting.dart';

/// MBTiles 地图数据读取器
///
/// 用于从本地 MBTiles 文件中读取瓦片图像数据
/// MBTiles 规范：https://github.com/mapbox/mbtiles-spec
class MbtilesReader {
  MbtilesReader({required this.filePath});

  final String filePath;
  Database? _database;
  Map<String, dynamic>? _metadata;

  /// 打开数据库连接
  Future<void> open() async {
    if (_database != null) return;

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('MBTiles file not found', filePath);
    }

    _database = sqlite3.open(filePath);
    await _loadMetadata();
  }

  /// 关闭数据库连接
  void close() {
    _database?.close();
    _database = null;
    _metadata = null;
  }

  /// 加载地图元数据
  Future<void> _loadMetadata() async {
    if (_database == null) return;

    final metadata = <String, dynamic>{};
    final stmt = _database!.select('SELECT name, value FROM metadata');

    for (final row in stmt) {
      metadata[row['name'] as String] = row['value'];
    }

    _metadata = metadata;
  }

  /// 获取元数据
  String? getMetadata(String key) {
    return _metadata?[key] as String?;
  }

  /// 获取最小缩放级别
  int get minZoom {
    final value = getMetadata('minzoom');
    return value != null ? int.parse(value) : 0;
  }

  /// 获取最大缩放级别
  int get maxZoom {
    final value = getMetadata('maxzoom');
    return value != null ? int.parse(value) : 18;
  }

  /// 获取地图中心点
  LatLng? get center {
    final bounds = getMetadata('bounds');
    if (bounds != null) {
      final parts = bounds.split(',');
      if (parts.length >= 2) {
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lon != null && lat != null) {
          return LatLng(lat, lon);
        }
      }
    }
    return null;
  }

  /// 获取指定坐标的瓦片数据
  Future<Uint8List?> getTile(int z, int x, int y) async {
    if (_database == null) {
      await open();
    }

    // MBTiles 使用 TMS 坐标系统，需要转换为 XYZ
    final tmsY = (1 << z) - y - 1;

    final stmt = _database!.prepare('''
      SELECT tile_data FROM tiles 
      WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?
    ''');

    try {
      final results = stmt.select([z, x, tmsY]);
      if (results.isNotEmpty) {
        return results.first['tile_data'] as Uint8List?;
      }
    } finally {
      stmt.close();
    }

    return null;
  }

  /// 检查是否存在指定缩放级别的瓦片
  Future<bool> hasTile(int z, int x, int y) async {
    final tileData = await getTile(z, x, y);
    return tileData != null;
  }
}

/// 基于 MBTiles 的 TileProvider
///
/// 用于 flutter_map 的 TileLayer
class MbTilesTileProvider extends TileProvider {
  MbTilesTileProvider({required this.filePath});

  final String filePath;
  final Map<String, MbtilesReader> _readers = {};

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MbTilesImageProvider(
      filePath: filePath,
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
  }

  @override
  void dispose() {
    for (final reader in _readers.values) {
      reader.close();
    }
    _readers.clear();
    super.dispose();
  }
}

/// MBTiles 图像提供者
class MbTilesImageProvider extends ImageProvider<MbTilesImageProvider> {
  MbTilesImageProvider({
    required this.filePath,
    required this.z,
    required this.x,
    required this.y,
  });

  final String filePath;
  final int z;
  final int x;
  final int y;

  @override
  Future<MbTilesImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MbTilesImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    MbTilesImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    MbTilesImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final mbtilesReader = MbtilesReader(filePath: filePath);
      await mbtilesReader.open();

      final tileData = await mbtilesReader.getTile(z, x, y);
      mbtilesReader.close();

      if (tileData == null || tileData.isEmpty) {
        // 返回透明瓦片
        return _createTransparentTile(decode);
      }

      return decode(await ui.ImmutableBuffer.fromUint8List(tileData));
    } catch (e) {
      debugPrint('Error loading MBTiles tile: $e');
      return _createTransparentTile(decode);
    }
  }

  Future<ui.Codec> _createTransparentTile(ImageDecoderCallback decode) async {
    // 创建一个 1x1 像素的透明 PNG 数据
    // PNG 格式：最小透明 PNG (约 70 字节)
    final transparentPng = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 签名
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 像素
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT chunk
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND chunk
      0x42, 0x60, 0x82,
    ]);

    return decode(await ui.ImmutableBuffer.fromUint8List(transparentPng));
  }
}
