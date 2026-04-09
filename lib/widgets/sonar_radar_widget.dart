import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/mesh_state_provider.dart';
import '../theme/rescue_theme.dart';

/// 高性能声呐雷达组件
///
/// 特性：
/// - 使用 CustomPainter 实现 60fps 流畅动画
/// - 局部刷新，不影响父组件
/// - 根据 RSSI 信号强度绘制设备光点
/// - 淡入淡出动画过渡
class SonarRadarWidget extends ConsumerStatefulWidget {
  const SonarRadarWidget({super.key, this.size = 320});

  /// 雷达尺寸（宽高相等）
  final double size;

  @override
  ConsumerState<SonarRadarWidget> createState() => _SonarRadarWidgetState();
}

class _SonarRadarWidgetState extends ConsumerState<SonarRadarWidget>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  // 磁力计订阅
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  double _currentHeading = 0.0; // 当前朝向角度（0-360度）

  // 用于跟踪已显示的设备，实现淡入动画
  final Set<String> _displayedDevices = {};
  final Map<String, AnimationController> _deviceAnimationControllers = {};
  final Map<String, Animation<double>> _deviceFadeAnimations = {};

  @override
  void initState() {
    super.initState();
    _setupScanAnimation();
    _initializeMagnetometer();
  }

  void _setupScanAnimation() {
    _scanController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
  }

  /// 初始化磁力计传感器
  void _initializeMagnetometer() {
    _magnetometerSubscription = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      // 计算方位角（0-360度）
      // 使用 atan2(x, y)，其中 y 轴指向设备顶部（前进方向）
      // 当设备顶部指向北时，heading = 0；指向东时，heading = 90
      var heading = math.atan2(event.x, event.y) * (180.0 / math.pi);

      // 归一化到 0-360 范围
      if (heading < 0) heading += 360;

      if (mounted) {
        setState(() {
          _currentHeading = heading;
        });
      }
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _magnetometerSubscription?.cancel();
    for (final controller in _deviceAnimationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 为设备创建淡入动画控制器
  AnimationController _getOrCreateDeviceAnimationController(String deviceId) {
    if (!_deviceAnimationControllers.containsKey(deviceId)) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );

      _deviceAnimationControllers[deviceId] = controller;
      _deviceFadeAnimations[deviceId] = Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeIn));

      controller.forward();
    }
    return _deviceAnimationControllers[deviceId]!;
  }

  /// 清理已消失的设备动画控制器
  void _cleanupDeviceAnimations(Set<String> activeDeviceIds) {
    final toRemove = <String>[];

    for (final deviceId in _deviceAnimationControllers.keys) {
      if (!activeDeviceIds.contains(deviceId)) {
        _deviceAnimationControllers[deviceId]?.dispose();
        toRemove.add(deviceId);
      }
    }

    for (final deviceId in toRemove) {
      _deviceAnimationControllers.remove(deviceId);
      _deviceFadeAnimations.remove(deviceId);
      _displayedDevices.remove(deviceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 Mesh 状态，但只提取需要的数据
    final meshState = ref.watch(meshStateProvider);
    final devices = meshState.sortedDevices;

    // 更新设备动画
    final activeDeviceIds = devices.map((d) => d.macAddress).toSet();
    _cleanupDeviceAnimations(activeDeviceIds);

    for (final device in devices) {
      if (!_displayedDevices.contains(device.macAddress)) {
        _displayedDevices.add(device.macAddress);
      }
      _getOrCreateDeviceAnimationController(device.macAddress);
    }

    // 为方向标签预留额外空间（标签在圆外 20px 处）
    const labelPadding = 20.0;
    final totalSize = widget.size + labelPadding * 2;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: CustomPaint(
        painter: RadarPainter(
          scanProgress: _scanAnimation.value,
          devices: devices,
          deviceFadeAnimations: _deviceFadeAnimations,
          centerX: totalSize / 2,
          centerY: totalSize / 2,
          radius: widget.size / 2 - 10,
          heading: _currentHeading,
          radarSize: widget.size,
        ),
      ),
    );
  }
}

/// 雷达绘制器
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.scanProgress,
    required this.devices,
    required this.deviceFadeAnimations,
    required this.centerX,
    required this.centerY,
    required this.radius,
    this.heading = 0.0,
    this.radarSize = 320,
  });

  final double scanProgress;
  final List<DiscoveredDevice> devices;
  final Map<String, Animation<double>> deviceFadeAnimations;
  final double centerX;
  final double centerY;
  final double radius;
  final double heading; // 当前设备朝向角度（0-360度）
  final double radarSize; // 雷达圆盘的实际尺寸（不含标签padding）

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制雷达背景圆盘
    _drawRadarBackground(canvas);

    // 绘制同心圆网格
    _drawConcentricCircles(canvas);

    // 绘制扫描线
    _drawScanLine(canvas);

    // 绘制设备光点
    _drawDeviceDots(canvas);
  }

  /// 绘制雷达背景圆盘
  void _drawRadarBackground(Canvas canvas) {
    // 背景渐变
    final rect = Rect.fromCircle(
      center: Offset(centerX, centerY),
      radius: radius + 2,
    );
    const gradient = RadialGradient(
      colors: [Color(0xFF0D1B2A), Color(0xFF1B2838), Color(0xFF0A0F1A)],
      stops: [0.0, 0.7, 1.0],
    );

    final bgPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), radius + 2, bgPaint);

    // 外圈边框
    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(centerX, centerY), radius + 2, borderPaint);
  }

  void _drawConcentricCircles(Canvas canvas) {
    final paint = Paint()
      ..color = RescuePalette.accent.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 绘制 3 个同心圆（代表 50m, 100m, 150m）
    final distances = [50, 100, 150];
    for (int i = 0; i < 3; i++) {
      final circleRadius = radius * (i + 1) / 3;
      canvas.drawCircle(Offset(centerX, centerY), circleRadius, paint);

      // 绘制距离标签
      final textStyle = TextStyle(
        color: RescuePalette.accent.withValues(alpha: 0.5),
        fontSize: 10,
        fontWeight: FontWeight.w400,
      );
      final textSpan = TextSpan(text: '${distances[i]}m', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          centerX + circleRadius - textPainter.width / 2,
          centerY - textPainter.height / 2,
        ),
      );
    }

    // 绘制十字线
    canvas.drawLine(
      Offset(centerX, centerY - radius),
      Offset(centerX, centerY + radius),
      paint,
    );
    canvas.drawLine(
      Offset(centerX - radius, centerY),
      Offset(centerX + radius, centerY),
      paint,
    );

    // 绘制东南西北方向标记（随手机转动旋转）
    _drawCompassLabels(canvas);
  }

  /// 绘制东南西北方向标签
  void _drawCompassLabels(Canvas canvas) {
    // heading 是设备朝向正北的角度
    // 当设备朝北时 heading=0，朝东时 heading=90
    // 我们需要反向旋转标签
    final rotationRad = -heading * math.pi / 180.0;

    // 在屏幕坐标系中：angle=-π/2 是上方(N)，angle=0 是右方(E)
    final directions = [
      ('N', -math.pi / 2, const Color(0xFFFF1744)), // 北 - 红色
      ('E', 0, const Color(0xFF00E5FF)), // 东 - 青色
      ('S', math.pi / 2, const Color(0xFFFFEA00)), // 南 - 黄色
      ('W', math.pi, const Color(0xFF76FF03)), // 西 - 绿色
    ];

    for (final (label, baseAngle, color) in directions) {
      // 应用旋转
      final angle = baseAngle + rotationRad;

      // 标签位置（在圆环外侧）
      final labelRadius = radius + 18;
      final x = centerX + labelRadius * math.cos(angle);
      final y = centerY + labelRadius * math.sin(angle);

      final isNorth = label == 'N';
      final fontSize = isNorth ? 16.0 : 13.0;

      // 绘制白色描边背景
      _drawOutlinedText(
        canvas,
        text: label,
        x: x,
        y: y,
        fontSize: fontSize,
        fillColor: color,
        strokeColor: const Color(0xFF000000),
        strokeWidth: 3.0,
        fontWeight: FontWeight.w900,
      );
    }
  }

  /// 绘制带描边的文字
  void _drawOutlinedText(
    Canvas canvas, {
    required String text,
    required double x,
    required double y,
    required double fontSize,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
    required FontWeight fontWeight,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: fillColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();

    final offsetX = x - textPainter.width / 2;
    final offsetY = y - textPainter.height / 2;

    // 先绘制描边（用更大的字体模拟）
    final strokeSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: strokeColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        shadows: [
          Shadow(color: strokeColor, offset: const Offset(0, 0), blurRadius: 0),
        ],
      ),
    );
    final strokePainter = TextPainter(
      text: strokeSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    strokePainter.layout();

    // 描边效果通过多层阴影实现
    final double offset = strokeWidth / 2;
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        final bgSpan = TextSpan(
          text: text,
          style: TextStyle(
            color: strokeColor,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        );
        final bgPainter = TextPainter(
          text: bgSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        bgPainter.layout();
        bgPainter.paint(
          canvas,
          Offset(offsetX + dx * offset, offsetY + dy * offset),
        );
      }
    }

    // 再绘制填充文字
    textPainter.paint(canvas, Offset(offsetX, offsetY));
  }

  void _drawScanLine(Canvas canvas) {
    final sweepAngle = scanProgress * 2 * math.pi;

    // 扫描渐变效果
    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: sweepAngle - math.pi / 2,
      colors: [
        RescuePalette.success.withValues(alpha: 0),
        RescuePalette.success.withValues(alpha: 0.6),
        RescuePalette.success.withValues(alpha: 0.8),
      ],
      stops: const [0.0, 0.8, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      paint,
    );
  }

  void _drawDeviceDots(Canvas canvas) {
    for (final device in devices) {
      final fadeAnimation = deviceFadeAnimations[device.macAddress];
      if (fadeAnimation == null) continue;

      final opacity = fadeAnimation.value;
      if (opacity <= 0.01) continue;

      // 使用真实距离，限制在雷达范围内
      final distance = device.estimatedDistance.clamp(0, 150);
      final normalizedDistance = distance / 150;

      // 使用 GPS 方位角（如果有位置信息），否则使用 MAC 地址哈希
      final deviceAngle = _getDeviceAngle(device);

      // 应用 heading 旋转：设备位置相对于地理北极固定
      // 当手机转动时，设备点在雷达上的位置要反向旋转
      final adjustedAngle = deviceAngle - heading * math.pi / 180.0;

      final dotX =
          centerX + normalizedDistance * radius * math.cos(adjustedAngle);
      final dotY =
          centerY + normalizedDistance * radius * math.sin(adjustedAngle);

      // 根据 RSSI 确定颜色和大小
      final rssi = device.rssi;
      final (dotColor, dotSize) = _getDotProperties(rssi, opacity);

      // 绘制光点
      final paint = Paint()
        ..color = dotColor
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(Offset(dotX, dotY), dotSize, paint);

      // 绘制外圈光晕
      final haloPaint = Paint()
        ..color = dotColor.withValues(alpha: 0.3 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(Offset(dotX, dotY), dotSize * 2, haloPaint);

      // 绘制脉冲效果
      _drawPulseEffect(canvas, Offset(dotX, dotY), dotColor, opacity);
    }
  }

  (Color, double) _getDotProperties(int rssi, double opacity) {
    // RSSI 越强（越接近 0），颜色越红，点越大
    final normalizedRssi = ((rssi + 100).clamp(0, 100) / 100);

    final red = 255;
    final green = (50 * (1 - normalizedRssi)).toInt();
    final blue = (50 * (1 - normalizedRssi)).toInt();

    final baseSize = 4.0 + (normalizedRssi * 4); // 4-8px

    return (Color.fromRGBO(red, green, blue, opacity), baseSize);
  }

  void _drawPulseEffect(
    Canvas canvas,
    Offset center,
    Color color,
    double opacity,
  ) {
    final pulseProgress = (scanProgress * 2) % 1.0;
    if (pulseProgress < 0.1) return;

    const pulseRadius = 8.0;
    final pulseOpacity = (1 - pulseProgress) * 0.3 * opacity;

    final pulsePaint = Paint()
      ..color = color.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, pulseRadius + pulseProgress * 16, pulsePaint);
  }

  /// 获取设备方位角（弧度）
  ///
  /// 优先使用 GPS 计算的方位角，如果没有位置信息则使用 MAC 地址哈希
  double _getDeviceAngle(DiscoveredDevice device) {
    // 尝试使用 GPS 位置计算方位角
    if (device.payload.latitude != 0 && device.payload.longitude != 0) {
      // 假设中心为当前位置（0, 0），设备位置为其 GPS 坐标
      // 方位角 = atan2(经度差, 纬度差)
      final latDiff = device.payload.latitude;
      final lonDiff = device.payload.longitude;
      return math.atan2(lonDiff, latDiff);
    }

    // 回退到 MAC 地址哈希（伪随机角度）
    final hash = device.macAddress.hashCode;
    return (hash % 360) * math.pi / 180;
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return scanProgress != oldDelegate.scanProgress ||
        devices != oldDelegate.devices ||
        heading != oldDelegate.heading;
  }
}

/// 简化的雷达显示组件（用于仪表盘等场景）
class MiniSonarRadarWidget extends StatefulWidget {
  const MiniSonarRadarWidget({super.key, this.size = 160});

  final double size;

  @override
  State<MiniSonarRadarWidget> createState() => _MiniSonarRadarWidgetState();
}

class _MiniSonarRadarWidgetState extends State<MiniSonarRadarWidget> {
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  double _currentHeading = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeMagnetometer();
  }

  void _initializeMagnetometer() {
    _magnetometerSubscription = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      var heading = math.atan2(event.x, event.y) * (180.0 / math.pi);
      if (heading < 0) heading += 360;

      if (mounted) {
        setState(() {
          _currentHeading = heading;
        });
      }
    });
  }

  @override
  void dispose() {
    _magnetometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final meshState = ref.watch(meshStateProvider);
        final activeDevices = meshState.activeDevices.length;

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF0D1B2A), Color(0xFF1B2838), Color(0xFF0A0F1A)],
              stops: [0.0, 0.7, 1.0],
            ),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 同心圆
              ...List.generate(3, (index) {
                final scale = (index + 1) / 3;
                return Container(
                  width: widget.size * scale,
                  height: widget.size * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                );
              }),

              // 十字线
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _CrosshairPainter(heading: _currentHeading),
                ),
              ),

              // 设备数量
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.bluetooth_searching,
                    color: Color(0xFF00E5FF),
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$activeDevices',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '设备',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 迷你雷达十字线绘制器（带旋转的方向标记）
class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({required this.heading});

  final double heading;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = size.width / 2;

    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 十字线
    canvas.drawLine(
      Offset(centerX, centerY - radius),
      Offset(centerX, centerY + radius),
      paint,
    );
    canvas.drawLine(
      Offset(centerX - radius, centerY),
      Offset(centerX + radius, centerY),
      paint,
    );

    // 方向标签
    final rotationRad = -heading * math.pi / 180.0;
    final directions = [
      ('N', -math.pi / 2, const Color(0xFFFF1744)),
      ('E', 0, const Color(0xFF00E5FF)),
      ('S', math.pi / 2, const Color(0xFFFFEA00)),
      ('W', math.pi, const Color(0xFF76FF03)),
    ];

    for (final (label, baseAngle, color) in directions) {
      final angle = baseAngle + rotationRad;
      final labelRadius = radius - 8;
      final x = centerX + labelRadius * math.cos(angle);
      final y = centerY + labelRadius * math.sin(angle);

      final isNorth = label == 'N';
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: isNorth ? 11.0 : 9.0,
          fontWeight: FontWeight.w900,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_CrosshairPainter oldDelegate) {
    return heading != oldDelegate.heading;
  }
}
