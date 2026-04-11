import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/mesh_state_provider.dart';
import '../theme/rescue_theme.dart';

class SonarRadarWidget extends ConsumerStatefulWidget {
  const SonarRadarWidget({super.key, this.size = 320, this.trackedDeviceId});

  final double size;
  final String? trackedDeviceId;

  @override
  ConsumerState<SonarRadarWidget> createState() => _SonarRadarWidgetState();
}

class _SonarRadarWidgetState extends ConsumerState<SonarRadarWidget>
    with TickerProviderStateMixin {
  late final AnimationController _scanController;
  late final Animation<double> _scanAnimation;

  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  double _currentHeading = 0.0;

  final Set<String> _displayedDevices = {};
  final Map<String, AnimationController> _deviceAnimationControllers = {};
  final Map<String, Animation<double>> _deviceFadeAnimations = {};

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
    _initializeMagnetometer();
  }

  void _initializeMagnetometer() {
    _magnetometerSubscription = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      var heading = math.atan2(event.x, event.y) * (180.0 / math.pi);
      if (heading < 0) {
        heading += 360;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _currentHeading = heading;
      });
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
    final meshState = ref.watch(meshStateProvider);
    final devices = meshState.activeDevices;
    final activeDeviceIds = devices.map((d) => d.macAddress).toSet();

    _cleanupDeviceAnimations(activeDeviceIds);
    for (final device in devices) {
      if (!_displayedDevices.contains(device.macAddress)) {
        _displayedDevices.add(device.macAddress);
      }
      _getOrCreateDeviceAnimationController(device.macAddress);
    }

    const labelPadding = 20.0;
    final totalSize = widget.size + labelPadding * 2;

    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, _) => SizedBox(
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
            trackedDeviceId: widget.trackedDeviceId,
          ),
        ),
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.scanProgress,
    required this.devices,
    required this.deviceFadeAnimations,
    required this.centerX,
    required this.centerY,
    required this.radius,
    required this.trackedDeviceId,
    this.heading = 0.0,
  });

  final double scanProgress;
  final List<DiscoveredDevice> devices;
  final Map<String, Animation<double>> deviceFadeAnimations;
  final double centerX;
  final double centerY;
  final double radius;
  final String? trackedDeviceId;
  final double heading;

  @override
  void paint(Canvas canvas, Size size) {
    _drawRadarBackground(canvas);
    _drawConcentricCircles(canvas);
    _drawScanLine(canvas);
    _drawDeviceDots(canvas);
  }

  void _drawRadarBackground(Canvas canvas) {
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
    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(centerX, centerY), radius + 2, bgPaint);
    canvas.drawCircle(Offset(centerX, centerY), radius + 2, borderPaint);
  }

  void _drawConcentricCircles(Canvas canvas) {
    final paint = Paint()
      ..color = RescuePalette.accent.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final distances = [50, 100, 150];
    for (var i = 0; i < 3; i++) {
      final circleRadius = radius * (i + 1) / 3;
      canvas.drawCircle(Offset(centerX, centerY), circleRadius, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${distances[i]}m',
          style: TextStyle(
            color: RescuePalette.accent.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          centerX + circleRadius - textPainter.width / 2,
          centerY - textPainter.height / 2,
        ),
      );
    }

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

    _drawCompassLabels(canvas);
  }

  void _drawCompassLabels(Canvas canvas) {
    final rotationRad = -heading * math.pi / 180.0;
    final directions = [
      ('N', -math.pi / 2, const Color(0xFFFF1744)),
      ('E', 0.0, const Color(0xFF00E5FF)),
      ('S', math.pi / 2, const Color(0xFFFFEA00)),
      ('W', math.pi, const Color(0xFF76FF03)),
    ];

    for (final (label, baseAngle, color) in directions) {
      final angle = baseAngle + rotationRad;
      final labelRadius = radius + 18;
      final x = centerX + labelRadius * math.cos(angle);
      final y = centerY + labelRadius * math.sin(angle);
      final fontSize = label == 'N' ? 16.0 : 13.0;
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
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: fillColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    final offsetX = x - textPainter.width / 2;
    final offsetY = y - textPainter.height / 2;
    final offset = strokeWidth / 2;

    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) {
          continue;
        }
        final bgPainter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: strokeColor,
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        bgPainter.paint(
          canvas,
          Offset(offsetX + dx * offset, offsetY + dy * offset),
        );
      }
    }

    textPainter.paint(canvas, Offset(offsetX, offsetY));
  }

  void _drawScanLine(Canvas canvas) {
    final sweepAngle = scanProgress * 2 * math.pi;
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
      if (fadeAnimation == null || fadeAnimation.value <= 0.01) {
        continue;
      }

      final opacity = fadeAnimation.value;
      final distance = device.estimatedDistance.clamp(0, 150);
      final normalizedDistance = distance / 150;
      final adjustedAngle = _getDeviceAngle(device) - heading * math.pi / 180.0;

      final dotX =
          centerX + normalizedDistance * radius * math.cos(adjustedAngle);
      final dotY =
          centerY + normalizedDistance * radius * math.sin(adjustedAngle);

      final isTracked = device.macAddress == trackedDeviceId;
      final (dotColor, dotSize) = _getDotProperties(
        device.rssi,
        opacity,
        isTracked: isTracked,
      );

      final paint = Paint()
        ..color = dotColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset(dotX, dotY), dotSize, paint);

      if (isTracked) {
        final trackedPaint = Paint()
          ..color = RescuePalette.warning.withValues(alpha: 0.9 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(dotX, dotY), dotSize * 2.8, trackedPaint);
      }

      final haloPaint = Paint()
        ..color = dotColor.withValues(alpha: 0.3 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(dotX, dotY), dotSize * 2, haloPaint);

      _drawPulseEffect(canvas, Offset(dotX, dotY), dotColor, opacity);
    }
  }

  (Color, double) _getDotProperties(
    int rssi,
    double opacity, {
    required bool isTracked,
  }) {
    final normalizedRssi = ((rssi + 100).clamp(0, 100) / 100);
    const red = 255;
    final green = (50 * (1 - normalizedRssi)).toInt();
    final blue = (50 * (1 - normalizedRssi)).toInt();
    final baseSize = 4.0 + (normalizedRssi * 4) + (isTracked ? 2 : 0);
    return (Color.fromRGBO(red, green, blue, opacity), baseSize);
  }

  void _drawPulseEffect(
    Canvas canvas,
    Offset center,
    Color color,
    double opacity,
  ) {
    final pulseProgress = (scanProgress * 2) % 1.0;
    if (pulseProgress < 0.1) {
      return;
    }

    const pulseRadius = 8.0;
    final pulseOpacity = (1 - pulseProgress) * 0.3 * opacity;
    final pulsePaint = Paint()
      ..color = color.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, pulseRadius + pulseProgress * 16, pulsePaint);
  }

  double _getDeviceAngle(DiscoveredDevice device) {
    if (device.payload.latitude != 0 && device.payload.longitude != 0) {
      final latDiff = device.payload.latitude;
      final lonDiff = device.payload.longitude;
      return math.atan2(lonDiff, latDiff);
    }

    final hash = device.macAddress.hashCode;
    return (hash % 360) * math.pi / 180;
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return scanProgress != oldDelegate.scanProgress ||
        devices != oldDelegate.devices ||
        heading != oldDelegate.heading ||
        trackedDeviceId != oldDelegate.trackedDeviceId;
  }
}

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
    _magnetometerSubscription = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      var heading = math.atan2(event.x, event.y) * (180.0 / math.pi);
      if (heading < 0) {
        heading += 360;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _currentHeading = heading;
      });
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
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CustomPaint(
                  painter: _CrosshairPainter(heading: _currentHeading),
                ),
              ),
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
                  const Text(
                    '设备',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
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

    final rotationRad = -heading * math.pi / 180.0;
    final directions = [
      ('N', -math.pi / 2, const Color(0xFFFF1744)),
      ('E', 0.0, const Color(0xFF00E5FF)),
      ('S', math.pi / 2, const Color(0xFFFFEA00)),
      ('W', math.pi, const Color(0xFF76FF03)),
    ];

    for (final (label, baseAngle, color) in directions) {
      final angle = baseAngle + rotationRad;
      final labelRadius = radius - 8;
      final x = centerX + labelRadius * math.cos(angle);
      final y = centerY + labelRadius * math.sin(angle);

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: label == 'N' ? 11.0 : 9.0,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
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
