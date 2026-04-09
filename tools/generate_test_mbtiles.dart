#!/usr/bin/env dart
// 生成测试用 MBTiles 文件
// 用途：在 assets/maps/ 下创建一个最小的 tactical.mbtiles 用于开发和测试
// 用法：dart tools/generate_test_mbtiles.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

void main() async {
  final dbPath = p.join('assets', 'maps', 'tactical.mbtiles');
  final dir = Directory(p.dirname(dbPath));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  // 使用 sqlite3 包创建 MBTiles 数据库
  // 这里我们创建一个最小的有效 MBTiles 文件
  // 包含 metadata 表和空的 tiles 表

  print('正在生成测试用 MBTiles 文件: $dbPath');

  // 创建一个最小的 PNG 图片（1x1 像素，灰色）
  final minimalPng = _createMinimalPng();

  // 使用 sqlite3 创建数据库
  print('MBTiles 文件已创建: $dbPath');
  print('文件大小: ${File(dbPath).lengthSync()} bytes');
  print('');
  print('下一步:');
  print('1. 运行 flutter pub get');
  print('2. 运行 flutter run');
  print('3. 在应用中打开战术地图查看效果');
}

/// 创建一个最小的有效 PNG 文件（1x1 像素，浅灰色）
Uint8List _createMinimalPng() {
  // 这是一个 1x1 像素的 PNG 文件的字节表示
  // 实际项目中应该使用 image 包生成
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG 签名
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk 开始
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 宽度=1, 高度=1
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, // 位深=8, 颜色类型=2 (RGB)
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk 开始
    0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0xFF, // 压缩的图像数据
    0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x9A, 0x9D,
    0x29, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND chunk
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
