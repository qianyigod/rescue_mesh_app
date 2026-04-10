import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';

import '../services/rssi_ranging_engine.dart';
import '../theme/rescue_theme.dart';

/// AR 搜救罗盘页面
///
/// 集成摄像头实时预览、传感器融合（指南针/陀螺仪）、GPS 方位角计算
/// 以及 BLE RSSI 信号强度，提供直观的 AR 战术标靶指引
class ArRescueCompassPage extends StatefulWidget {
  const ArRescueCompassPage({
    super.key,
    required this.targetLatitude,
    required this.targetLongitude,
    this.targetRssi = -70,
    this.targetName = '求救者',
  });

  /// 目标求救者纬度
  final double targetLatitude;

  /// 目标求救者经度
  final double targetLongitude;

  /// 蓝牙 RSSI 信号强度（用于估算距离）
  final int targetRssi;

  /// 目标名称
  final String targetName;

  @override
  State<ArRescueCompassPage> createState() => _ArRescueCompassPageState();
}

class _ArRescueCompassPageState extends State<ArRescueCompassPage> {
  CameraController? _cameraController;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<Position>? _positionSubscription;

  // 当前设备朝向（方位角，单位：度）
  double _currentHeading = 0.0;
  double _headingJitter = 0.0;

  // 设备倾斜角（度）
  double _pitch = 0.0;
  double _roll = 0.0;

  // 目标相对于正北的方位角（单位：度）
  double _targetBearing = 0.0;

  // 视场角偏差（目标方位角 - 当前朝向）
  double _fovDelta = 0.0;

  // 估算距离（单位：米）
  double _estimatedDistance = 0.0;

  // 当前位置
  Position? _currentPosition;

  // 是否已定位
  bool _isPositioned = false;

  // 摄像头是否可用
  bool _isCameraInitialized = false;
  bool _cameraAssistEnabled = false;
  bool _isCameraLoading = false;

  // 标靶是否居中（偏差角 < 5 度）
  bool _isTargetCentered = false;

  // 最近位置更新时间
  DateTime? _lastPositionUpdateAt;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  /// 检查并请求权限
  Future<void> _checkAndRequestPermissions() async {
    try {
      // 请求位置权限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showPermissionDialog('位置权限', '需要位置权限来计算目标方位角。请在设置中开启位置权限。');
        }
        return;
      }

      // 检查位置服务是否启用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showPermissionDialog('位置服务', '位置服务未启用。请开启位置服务以使用 AR 罗盘功能。');
        }
        return;
      }

      // 权限已获得，初始化所有功能
      _initializeAll();
    } catch (e) {
      debugPrint('权限检查失败：$e');
      if (mounted) {
        _showPermissionDialog('权限错误', '无法获取必要权限：$e');
      }
    }
  }

  /// 显示权限提示对话框
  void _showPermissionDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: RescuePalette.warning,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: RescuePalette.accent,
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 初始化所有功能
  Future<void> _initializeAll() async {
    _initializeSensors();
    await _initializeLocationTracking();
    _estimateDistanceFromRssi();
  }

  /// 初始化摄像头
  Future<void> _initializeCamera() async {
    if (_isCameraInitialized || _isCameraLoading) {
      return;
    }
    try {
      setState(() {
        _isCameraLoading = true;
      });
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _isCameraLoading = false;
      });
    } catch (e) {
      debugPrint('摄像头初始化失败：$e');
      if (!mounted) return;
      setState(() {
        _isCameraLoading = false;
        _cameraAssistEnabled = false;
      });
    }
  }

  /// 初始化传感器
  void _initializeSensors() {
    // 监听指南针数据
    _magnetometerSubscription = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      // 计算方位角（0-360 度），使用倾斜补偿
      final rawHeading = _calculateHeadingFromMagnetometer(event);
      final heading = _smoothHeading(_currentHeading, rawHeading, 0.18);
      final headingJitter = _angleDifference(rawHeading, heading).abs();

      if (!mounted) return;

      setState(() {
        _currentHeading = heading;
        _headingJitter = (_headingJitter * 0.82) + (headingJitter * 0.18);
        _updateFovDelta();
        _checkTargetAlignment();
      });
    });

    // 监听加速度计数据（用于设备倾斜补偿）
    _accelerometerSubscription = accelerometerEventStream().listen((
      AccelerometerEvent event,
    ) {
      final acceleration = event;
      // 计算俯仰角和滚转角
      final pitch =
          math.atan2(
            acceleration.x,
            math.sqrt(
              acceleration.y * acceleration.y + acceleration.z * acceleration.z,
            ),
          ) *
          (180.0 / math.pi);

      final roll =
          math.atan2(
            acceleration.y,
            math.sqrt(
              acceleration.x * acceleration.x + acceleration.z * acceleration.z,
            ),
          ) *
          (180.0 / math.pi);

      if (!mounted) return;

      setState(() {
        _pitch = pitch;
        _roll = roll;
      });
    });
  }

  /// 从磁力计数据计算方位角（含倾斜补偿）
  ///
  /// 使用加速度计数据进行倾斜补偿，提高方位角精度
  double _calculateHeadingFromMagnetometer(MagnetometerEvent event) {
    // 使用最新的倾斜角进行补偿
    final pitchRad = _pitch * math.pi / 180.0;
    final rollRad = _roll * math.pi / 180.0;

    // 倾斜补偿公式
    // 将磁力计数据从设备坐标系转换到水平坐标系
    final cosPitch = math.cos(pitchRad);
    final sinPitch = math.sin(pitchRad);
    final cosRoll = math.cos(rollRad);
    final sinRoll = math.sin(rollRad);

    // 补偿后的 X 和 Y 分量
    final compensatedX = event.x * cosPitch + event.z * sinPitch;
    final compensatedY =
        event.x * sinRoll * sinPitch +
        event.y * cosRoll -
        event.z * sinRoll * cosPitch;

    // 计算方位角（弧度）
    var heading = math.atan2(compensatedY, compensatedX);

    // 转换为角度并确保在 0-360 范围内
    var degrees = heading * (180.0 / math.pi);
    if (degrees < 0) {
      degrees += 360;
    }

    return degrees;
  }

  /// 启动位置追踪并持续刷新目标方位
  Future<void> _initializeLocationTracking() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _updatePosition(position);

      _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
        ),
      ).listen(
        _updatePosition,
        onError: (Object error) {
          debugPrint('位置流更新失败：$error');
        },
      );
    } catch (e) {
      debugPrint('获取位置失败：$e');
      if (!mounted) return;
      setState(() {
        _isPositioned = false;
      });
    }
  }

  void _updatePosition(Position position) {
    _currentPosition = position;
    _targetBearing = Geolocator.bearingBetween(
      position.latitude,
      position.longitude,
      widget.targetLatitude,
      widget.targetLongitude,
    );

    if (!mounted) return;
    setState(() {
      _isPositioned = true;
      _lastPositionUpdateAt = DateTime.now();
      _updateFovDelta();
    });
  }

  /// 根据 RSSI 估算距离（使用统一测距引擎）
  void _estimateDistanceFromRssi() {
    final rangingEngine = RssiRangingEngine.instance();
    final result = rangingEngine.estimateDistance(widget.targetRssi);

    setState(() {
      _estimatedDistance = result.estimatedDistance;
    });
  }

  /// 更新视场角偏差
  void _updateFovDelta() {
    if (!_isPositioned) {
      _fovDelta = 0;
      return;
    }

    _fovDelta = _angleDifference(_targetBearing, _currentHeading);
  }

  /// 检查目标是否对准
  void _checkTargetAlignment() {
    final isCentered = _fovDelta.abs() < 5.0;

    if (isCentered != _isTargetCentered) {
      setState(() {
        _isTargetCentered = isCentered;
      });

      // 触发震动反馈
      if (isCentered) {
        _triggerHapticFeedback();
      }
    }
  }

  /// 触发触觉反馈
  Future<void> _triggerHapticFeedback() async {
    try {
      if (await Vibration.hasVibrator()) {
        // 短促的双脉冲震动
        await Vibration.vibrate(duration: 50, amplitude: 128);

        // 短暂延迟后第二次震动
        await Future.delayed(const Duration(milliseconds: 100));

        await Vibration.vibrate(duration: 50, amplitude: 128);
      } else {
        // 如果没有震动马达，使用系统 HapticFeedback
        await HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('震动反馈失败：$e');
    }
  }

  double _angleDifference(double target, double current) {
    var delta = target - current;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  double _smoothHeading(double current, double next, double factor) {
    if (current == 0) {
      return next;
    }
    final delta = _angleDifference(next, current);
    final smoothed = current + delta * factor;
    return (smoothed % 360 + 360) % 360;
  }

  Future<void> _toggleCameraAssist() async {
    if (_cameraAssistEnabled) {
      await _disposeCameraController();
      setState(() {
        _cameraAssistEnabled = false;
      });
      return;
    }

    setState(() {
      _cameraAssistEnabled = true;
    });
    await _initializeCamera();
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      await controller.dispose();
    }
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
        _isCameraLoading = false;
      });
    } else {
      _isCameraInitialized = false;
      _isCameraLoading = false;
    }
  }

  double get _tiltMagnitude => math.max(_pitch.abs(), _roll.abs());

  String get _sensorQualityLabel {
    if (!_isPositioned) {
      return '低';
    }
    if (_headingJitter < 4 && _tiltMagnitude < 20) {
      return '高';
    }
    if (_headingJitter < 10 && _tiltMagnitude < 35) {
      return '中';
    }
    return '低';
  }

  Color get _sensorQualityColor {
    switch (_sensorQualityLabel) {
      case '高':
        return RescuePalette.success;
      case '中':
        return RescuePalette.warning;
      default:
        return RescuePalette.critical;
    }
  }

  String get _trackingModeLabel {
    if (_estimatedDistance <= 0) {
      return '方向辅助';
    }
    if (_estimatedDistance > 120) {
      return '远距引导';
    }
    if (_estimatedDistance > 25) {
      return '接近模式';
    }
    return '近距搜寻';
  }

  String get _practicalHint {
    if (!_isPositioned) {
      return '等待定位完成后再参考方向，当前结果可能偏差较大。';
    }
    if (_sensorQualityLabel == '低') {
      return '当前传感器稳定度较低，建议放平手机并结合雷达/地图判断。';
    }
    if (_isTargetCentered) {
      return '方向基本对准，继续前进并观察距离变化。';
    }
    if (_fovDelta.abs() > 90) {
      return '目标大概率在身后，先完成转身再继续接近。';
    }
    return '先按箭头修正朝向，再观察信号与距离是否持续变强。';
  }

  bool get _shouldRecommendCameraAssist {
    return _isPositioned &&
        _estimatedDistance > 0 &&
        _estimatedDistance <= 20 &&
        !_cameraAssistEnabled;
  }

  bool get _shouldRecommendCompassOnly {
    return (!_isPositioned || _estimatedDistance > 40) && _cameraAssistEnabled;
  }

  String get _modeRecommendationTitle {
    if (!_isPositioned) {
      return '先完成罗盘定向';
    }
    if (_estimatedDistance <= 0) {
      return '继续使用罗盘';
    }
    if (_estimatedDistance <= 20) {
      return _cameraAssistEnabled ? '已进入近距辅助' : '建议切到相机辅助';
    }
    if (_estimatedDistance <= 60) {
      return '保持罗盘主导';
    }
    return '远距阶段优先罗盘';
  }

  String get _modeRecommendationBody {
    if (!_isPositioned) {
      return '定位未完成前先保持罗盘模式，并结合雷达页判断目标大致方向。';
    }
    if (_estimatedDistance <= 0) {
      return '距离还在估算中，建议继续观察朝向修正和信号强弱变化。';
    }
    if (_estimatedDistance <= 20) {
      return _cameraAssistEnabled
          ? '你已经接近目标，优先用相机辅助做左右微调，同时观察距离是否继续缩短。'
          : '你已经接近目标，建议打开相机辅助来微调左右方向，罗盘继续负责大方向。';
    }
    if (_estimatedDistance <= 60) {
      return '当前仍以大方向接近为主，除非现场遮挡明显，否则不必提前进入相机模式。';
    }
    return '距离较远时相机参考价值有限，优先看罗盘方向、距离趋势和地图/雷达信息。';
  }

  Color get _modeRecommendationColor {
    if (_estimatedDistance > 0 && _estimatedDistance <= 20) {
      return RescuePalette.warning;
    }
    return RescuePalette.accent;
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) {
      return '刚刚';
    }
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds} 秒前';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} 分钟前';
    }
    return '${diff.inHours} 小时前';
  }

  /// 显示操作菜单（仅保留目标信息）
  void _showActionMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: RescuePalette.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: RescuePalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: RescuePalette.warning.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: RescuePalette.warning,
                ),
              ),
              title: const Text('目标信息'),
              subtitle: const Text('查看详细的求救者信息'),
              onTap: () {
                Navigator.pop(context);
                _showTargetDetails();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 显示目标详情对话框
  void _showTargetDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: RescuePalette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: RescuePalette.criticalSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sos, color: RescuePalette.critical),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.targetName)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                icon: Icons.my_location,
                label: '纬度',
                value: widget.targetLatitude.toStringAsFixed(6),
              ),
              _buildDetailRow(
                icon: Icons.location_on,
                label: '经度',
                value: widget.targetLongitude.toStringAsFixed(6),
              ),
              _buildDetailRow(
                icon: Icons.straighten,
                label: '估算距离',
                value: '${_estimatedDistance.toStringAsFixed(1)} 米',
              ),
              _buildDetailRow(
                icon: Icons.wifi,
                label: '信号强度',
                value: '${widget.targetRssi} dBm',
              ),
              _buildDetailRow(
                icon: Icons.access_time,
                label: '更新时间',
                value: _lastPositionUpdateAt == null
                    ? '未获取'
                    : _formatRelativeTime(_lastPositionUpdateAt!),
              ),
              if (_currentPosition != null)
                _buildDetailRow(
                  icon: Icons.person_pin_circle_outlined,
                  label: '当前位置',
                  value:
                      '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
                ),
              _buildDetailRow(
                icon: Icons.explore_outlined,
                label: '目标方位',
                value: _isPositioned ? '${_targetBearing.toStringAsFixed(0)}°' : '等待定位',
              ),
              const Divider(height: 24),
              const Text(
                '提示：以上距离为基于信号强度的估算值，实际距离可能因环境因素有所不同。',
                style: TextStyle(
                  fontSize: 12,
                  color: RescuePalette.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RescuePalette.accent.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // 图标容器
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: RescuePalette.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: RescuePalette.accent),
          ),
          const SizedBox(width: 12),
          // 标签
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: RescuePalette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 值
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: RescuePalette.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _positionSubscription?.cancel();
    unawaited(_disposeCameraController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6F8),
        foregroundColor: RescuePalette.textPrimary,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.explore_rounded, size: 22),
            const SizedBox(width: 8),
            Text(widget.targetName),
          ],
        ),
        actions: [
          // 更多操作按钮
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '更多操作',
            onPressed: _showActionMenu,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: RescuePalette.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_currentHeading.toStringAsFixed(0)}°',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: RescuePalette.textPrimary,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildHeroCard(),
          const SizedBox(height: 16),
          _buildModeRecommendationCard(),
          const SizedBox(height: 16),
          _buildStatusGrid(),
          const SizedBox(height: 16),
          _buildCameraAssistCard(),
          const SizedBox(height: 16),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildModeRecommendationCard() {
    final showAction =
        _shouldRecommendCameraAssist || _shouldRecommendCompassOnly;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RescuePalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _modeRecommendationColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _shouldRecommendCameraAssist
                  ? Icons.camera_alt_rounded
                  : Icons.explore_rounded,
              color: _modeRecommendationColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modeRecommendationTitle,
                  style: const TextStyle(
                    color: RescuePalette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _modeRecommendationBody,
                  style: const TextStyle(
                    color: RescuePalette.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (showAction) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _toggleCameraAssist,
                    icon: Icon(_shouldRecommendCameraAssist
                        ? Icons.camera_alt_rounded
                        : Icons.visibility_off_rounded),
                    label: Text(
                      _shouldRecommendCameraAssist
                          ? '打开相机辅助'
                          : '关闭相机辅助',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          _modeRecommendationColor.withValues(alpha: 0.14),
                      foregroundColor: _modeRecommendationColor,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1C2A), Color(0xFF14314A), Color(0xFF1B4867)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF14314A).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroBadge(label: _trackingModeLabel, color: _sensorQualityColor),
              _HeroBadge(
                label: '可信度 $_sensorQualityLabel',
                color: _sensorQualityColor,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '方向优先',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _practicalHint,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: _CompassDial(
              turnAngle: _fovDelta,
              centered: _isTargetCentered,
              headingText: _getDirectionText(),
            ),
          ),
          const SizedBox(height: 18),
          _buildDirectionIndicator(),
        ],
      ),
    );
  }

  Widget _buildDirectionIndicator() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            _getDirectionArrow(),
            color: _isTargetCentered
                ? RescuePalette.success
                : RescuePalette.warning,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _getDirectionText(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${_fovDelta.abs().toStringAsFixed(0)}°',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatusCard(
          title: '预估距离',
          value: _formatDistanceText(),
          tone: RescuePalette.accentSoft,
          color: RescuePalette.accent,
          icon: Icons.straighten_rounded,
        ),
        _StatusCard(
          title: '目标方位',
          value: _isPositioned ? '${_targetBearing.toStringAsFixed(0)}°' : '等待定位',
          tone: RescuePalette.successSoft,
          color: RescuePalette.success,
          icon: Icons.explore_rounded,
        ),
        _StatusCard(
          title: '传感器稳定',
          value: _sensorQualityLabel,
          tone: _sensorQualityColor.withValues(alpha: 0.14),
          color: _sensorQualityColor,
          icon: Icons.sensors_rounded,
        ),
        _StatusCard(
          title: '位置更新',
          value: _lastPositionUpdateAt == null
              ? '未获取'
              : _formatRelativeTime(_lastPositionUpdateAt!),
          tone: RescuePalette.warning.withValues(alpha: 0.16),
          color: RescuePalette.warning,
          icon: Icons.my_location_rounded,
        ),
      ],
    );
  }

  Widget _buildCameraAssistCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RescuePalette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_rounded, color: RescuePalette.textMuted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '相机辅助',
                    style: TextStyle(
                      color: RescuePalette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Switch(
                  value: _cameraAssistEnabled,
                  onChanged: (_) => _toggleCameraAssist(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '只在接近目标时打开，用来微调左右方向；主导航仍以罗盘和距离变化为准。',
              style: TextStyle(
                color: RescuePalette.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildCameraPreviewArea(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreviewArea() {
    if (!_cameraAssistEnabled) {
      return _buildCameraPlaceholder('相机辅助已关闭');
    }
    if (_isCameraLoading) {
      return Container(
        color: const Color(0xFF0F1720),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_isCameraInitialized && _cameraController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          CustomPaint(
            painter: ArTargetPainter(
              fovDelta: _fovDelta,
              isCentered: _isTargetCentered,
              distance: _estimatedDistance,
              rssi: widget.targetRssi,
            ),
          ),
        ],
      );
    }
    return _buildCameraPlaceholder('摄像头暂不可用');
  }

  Widget _buildCameraPlaceholder(String label) {
    return Container(
      color: const Color(0xFF0F1720),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 36),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: ElevatedButton.icon(
            icon: Icon(_cameraAssistEnabled
                ? Icons.visibility_off_rounded
                : Icons.camera_alt_rounded),
            label: Text(_cameraAssistEnabled ? '关闭相机辅助' : '打开相机辅助'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RescuePalette.panel,
              foregroundColor: RescuePalette.textPrimary,
              elevation: 0,
              side: const BorderSide(color: RescuePalette.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _toggleCameraAssist,
          ),
        ),
        SizedBox(
          width: 180,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.info_outline_rounded),
            label: const Text('目标详情'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RescuePalette.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: _showTargetDetails,
          ),
        ),
      ],
    );
  }

  /// 获取方向指引文字
  String _getDirectionText() {
    if (_isTargetCentered) {
      return '✓ 目标已锁定';
    }

    final absDelta = _fovDelta.abs();
    if (_fovDelta > 0) {
      if (absDelta < 15) {
        return '稍向右转';
      } else if (absDelta < 45) {
        return '向右转';
      } else if (absDelta < 135) {
        return '大幅向右转';
      } else {
        return '向后转';
      }
    } else {
      if (absDelta < 15) {
        return '稍向左转';
      } else if (absDelta < 45) {
        return '向左转';
      } else if (absDelta < 135) {
        return '大幅向左转';
      } else {
        return '向后转';
      }
    }
  }

  /// 获取方向箭头图标
  IconData _getDirectionArrow() {
    if (_isTargetCentered) {
      return Icons.check_circle_rounded;
    }
    return _fovDelta > 0 ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded;
  }

  String _formatDistanceText() {
    if (_estimatedDistance <= 0 || !_estimatedDistance.isFinite) {
      return '等待估算';
    }
    if (_estimatedDistance > 1000) {
      return '${(_estimatedDistance / 1000).toStringAsFixed(2)} km';
    }
    return '${_estimatedDistance.toStringAsFixed(1)} m';
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.tone,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color tone;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 156),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: RescuePalette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompassDial extends StatelessWidget {
  const _CompassDial({
    required this.turnAngle,
    required this.centered,
    required this.headingText,
  });

  final double turnAngle;
  final bool centered;
  final String headingText;

  @override
  Widget build(BuildContext context) {
    final arrowColor = centered ? RescuePalette.success : RescuePalette.warning;

    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF18364D), Color(0xFF102536), Color(0xFF08131C)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(12, (index) {
            final angle = index * math.pi / 6;
            final longTick = index % 3 == 0;
            final tickHeight = longTick ? 18.0 : 10.0;
            return Transform.rotate(
              angle: angle,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 18),
                  width: 2,
                  height: tickHeight,
                  color: longTick
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
            );
          }),
          Positioned(
            top: 22,
            child: Text(
              'N',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Transform.rotate(
            angle: turnAngle * math.pi / 180,
            child: Icon(Icons.navigation_rounded, size: 112, color: arrowColor),
          ),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0F1F2B),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  centered ? '已对准' : '修正中',
                  style: TextStyle(
                    color: arrowColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    headingText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// AR 标靶绘制器
///
/// 负责在摄像头画面上绘制战术光圈标靶
class ArTargetPainter extends CustomPainter {
  ArTargetPainter({
    required this.fovDelta,
    required this.isCentered,
    required this.distance,
    required this.rssi,
  });

  /// 视场角偏差（度）
  final double fovDelta;

  /// 是否已居中锁定
  final bool isCentered;

  /// 估算距离（米）
  final double distance;

  /// RSSI 信号强度
  final int rssi;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 根据 FOV 偏差计算标靶的水平偏移
    // 假设手机水平视场角约为 60 度
    const horizontalFov = 60.0;
    final normalizedOffset = fovDelta / horizontalFov;
    final targetX = centerX + (normalizedOffset * size.width * 0.4);

    // 限制标靶不超出屏幕边界
    final clampedX = targetX.clamp(50.0, size.width - 50.0);

    // 根据距离和 RSSI 计算标靶大小
    const baseRadius = 40.0;
    final rssiFactor = ((rssi + 100) / 70).clamp(0.5, 1.5);
    final distanceFactor = (100 / (distance + 1)).clamp(0.3, 1.2);
    final radius = baseRadius * rssiFactor * distanceFactor;

    // 绘制标靶外圈
    final outerPaint = Paint()
      ..color = isCentered
          ? RescuePalette.accent.withValues(alpha: 0.8)
          : RescuePalette.accent.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(Offset(clampedX, centerY), radius, outerPaint);

    // 绘制标靶内圈
    final innerPaint = Paint()
      ..color = isCentered
          ? RescuePalette.success.withValues(alpha: 0.6)
          : RescuePalette.accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(clampedX, centerY), radius * 0.6, innerPaint);

    // 绘制中心点
    final centerPaint = Paint()
      ..color = isCentered ? RescuePalette.success : RescuePalette.accent
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(clampedX, centerY), 4, centerPaint);

    // 绘制十字准星
    final crossPaint = Paint()
      ..color = isCentered
          ? RescuePalette.success.withValues(alpha: 0.8)
          : RescuePalette.accent.withValues(alpha: 0.5)
      ..strokeWidth = 2;

    // 横线
    canvas.drawLine(
      Offset(clampedX - radius * 0.8, centerY),
      Offset(clampedX + radius * 0.8, centerY),
      crossPaint,
    );

    // 竖线
    canvas.drawLine(
      Offset(clampedX, centerY - radius * 0.8),
      Offset(clampedX, centerY + radius * 0.8),
      crossPaint,
    );

    // 绘制方位角刻度（装饰性）
    _drawAngleMarkers(canvas, size, clampedX, centerY, radius);
  }

  /// 绘制方位角刻度标记
  void _drawAngleMarkers(
    Canvas canvas,
    Size size,
    double centerX,
    double centerY,
    double radius,
  ) {
    final markerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // 四个方向的刻度线
    const angles = [0, 45, 90, 135, 180, 225, 270, 315];

    for (final angle in angles) {
      final radians = angle * (math.pi / 180);
      const innerRadiusMultiplier = 1.1;
      const outerRadiusMultiplier = 1.2;
      final innerRadius = radius * innerRadiusMultiplier;
      final outerRadius = radius * outerRadiusMultiplier;

      final startX = centerX + innerRadius * math.cos(radians);
      final startY = centerY + innerRadius * math.sin(radians);
      final endX = centerX + outerRadius * math.cos(radians);
      final endY = centerY + outerRadius * math.sin(radians);

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), markerPaint);
    }
  }

  @override
  bool shouldRepaint(ArTargetPainter oldDelegate) {
    return oldDelegate.fovDelta != fovDelta ||
        oldDelegate.isCentered != isCentered ||
        oldDelegate.distance != distance ||
        oldDelegate.rssi != rssi;
  }
}
