import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/mesh_state_provider.dart';
import '../theme/rescue_theme.dart';

class SearchFeedbackProfile {
  const SearchFeedbackProfile({
    required this.intervalMs,
    required this.pulseDurationMs,
    required this.proximityLabel,
    required this.cadenceLabel,
    required this.guidance,
    required this.color,
    required this.progress,
    required this.enableHaptic,
    required this.signalLost,
  });

  factory SearchFeedbackProfile.fromDevice(
    DiscoveredDevice device, {
    DateTime? now,
    Duration staleThreshold = const Duration(seconds: 3),
  }) {
    final resolvedNow = now ?? DateTime.now();
    if (resolvedNow.difference(device.lastUpdatedAt) >= staleThreshold) {
      return const SearchFeedbackProfile(
        intervalMs: 1600,
        pulseDurationMs: 90,
        proximityLabel: '目标暂失',
        cadenceLabel: '1.60 秒/次',
        guidance: '最近几秒没有收到新信号，先回到上次让滴滴变快的位置，再左右小步复扫。',
        color: RescuePalette.textMuted,
        progress: 0.12,
        enableHaptic: false,
        signalLost: true,
      );
    }

    final distance = device.estimatedDistance;
    final hasDistance = distance.isFinite && distance > 0;

    if ((hasDistance && distance <= 1.5) || device.rssi >= -55) {
      return const SearchFeedbackProfile(
        intervalMs: 180,
        pulseDurationMs: 120,
        proximityLabel: '极近距离',
        cadenceLabel: '0.18 秒/次',
        guidance: '信号已经很强，缩小步幅，围绕目标做小范围确认。',
        color: RescuePalette.critical,
        progress: 0.96,
        enableHaptic: true,
        signalLost: false,
      );
    }

    if ((hasDistance && distance <= 3) || device.rssi >= -60) {
      return const SearchFeedbackProfile(
        intervalMs: 280,
        pulseDurationMs: 110,
        proximityLabel: '非常接近',
        cadenceLabel: '0.28 秒/次',
        guidance: '继续保持当前方向，优先看滴滴是否继续加快。',
        color: RescuePalette.warning,
        progress: 0.84,
        enableHaptic: true,
        signalLost: false,
      );
    }

    if ((hasDistance && distance <= 6) || device.rssi >= -67) {
      return const SearchFeedbackProfile(
        intervalMs: 420,
        pulseDurationMs: 105,
        proximityLabel: '接近中',
        cadenceLabel: '0.42 秒/次',
        guidance: '已经进入近距离区域，建议减速，观察每一步后的反馈变化。',
        color: RescuePalette.warning,
        progress: 0.68,
        enableHaptic: false,
        signalLost: false,
      );
    }

    if ((hasDistance && distance <= 12) || device.rssi >= -75) {
      return const SearchFeedbackProfile(
        intervalMs: 650,
        pulseDurationMs: 100,
        proximityLabel: '中等距离',
        cadenceLabel: '0.65 秒/次',
        guidance: '维持大方向搜索，尝试左右微调，找出滴滴更密的一侧。',
        color: RescuePalette.accent,
        progress: 0.5,
        enableHaptic: false,
        signalLost: false,
      );
    }

    if ((hasDistance && distance <= 25) || device.rssi >= -85) {
      return const SearchFeedbackProfile(
        intervalMs: 950,
        pulseDurationMs: 95,
        proximityLabel: '远距离',
        cadenceLabel: '0.95 秒/次',
        guidance: '信号较弱，先扩大搜索步幅，确认哪一侧反馈更稳定。',
        color: RescuePalette.accent,
        progress: 0.3,
        enableHaptic: false,
        signalLost: false,
      );
    }

    return const SearchFeedbackProfile(
      intervalMs: 1400,
      pulseDurationMs: 90,
      proximityLabel: '边缘信号',
      cadenceLabel: '1.40 秒/次',
      guidance: '这是很弱的边缘信号，优先移动位置，等节奏明显变快后再细找。',
      color: RescuePalette.textMuted,
      progress: 0.14,
      enableHaptic: false,
      signalLost: false,
    );
  }

  final int intervalMs;
  final int pulseDurationMs;
  final String proximityLabel;
  final String cadenceLabel;
  final String guidance;
  final Color color;
  final double progress;
  final bool enableHaptic;
  final bool signalLost;
}

class SearchFeedbackService {
  SearchFeedbackService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'rescue_mesh/search_feedback';

  final MethodChannel _channel;

  DateTime? _lastPulseAt;
  DateTime? _lastHapticAt;

  void reset() {
    _lastPulseAt = null;
    _lastHapticAt = null;
  }

  Future<void> emitIfDue({
    required bool pageActive,
    required bool feedbackEnabled,
    required bool isScanning,
    required DiscoveredDevice? trackedDevice,
    DateTime? now,
  }) async {
    final resolvedNow = now ?? DateTime.now();
    if (!pageActive ||
        !feedbackEnabled ||
        !isScanning ||
        trackedDevice == null) {
      reset();
      return;
    }

    final profile = SearchFeedbackProfile.fromDevice(
      trackedDevice,
      now: resolvedNow,
    );
    if (_lastPulseAt != null &&
        resolvedNow.difference(_lastPulseAt!).inMilliseconds <
            profile.intervalMs) {
      return;
    }

    _lastPulseAt = resolvedNow;

    final shouldHaptic =
        profile.enableHaptic &&
        (_lastHapticAt == null ||
            resolvedNow.difference(_lastHapticAt!).inMilliseconds >= 500);
    if (shouldHaptic) {
      _lastHapticAt = resolvedNow;
    }

    await _emitPulse(profile: profile, enableHaptic: shouldHaptic);
  }

  Future<void> _emitPulse({
    required SearchFeedbackProfile profile,
    required bool enableHaptic,
  }) async {
    try {
      await _channel.invokeMethod<void>('emitSearchPulse', {
        'durationMs': profile.pulseDurationMs,
        'enableHaptic': enableHaptic,
        'signalLost': profile.signalLost,
      });
    } on MissingPluginException {
      await _emitFallback(enableHaptic: enableHaptic);
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        '[SearchFeedback] Native pulse failed: ${error.code} ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      await _emitFallback(enableHaptic: enableHaptic);
    }
  }

  Future<void> _emitFallback({required bool enableHaptic}) async {
    unawaited(SystemSound.play(SystemSoundType.alert));
    if (enableHaptic) {
      unawaited(HapticFeedback.lightImpact());
    }
  }
}
