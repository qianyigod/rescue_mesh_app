import 'package:flutter/material.dart';

import 'database.dart';
import 'models/emergency_profile.dart';
import 'theme/rescue_theme.dart';

class MessagePage extends StatelessWidget {
  const MessagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF7FAFC),
            Color(0xFFF0F5F7),
            Color(0xFFE7EEF2),
          ],
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<List<StoredSosMessage>>(
          stream: appDb.watchStoredSosMessages(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '记录加载失败：${snapshot.error}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: RescuePalette.critical,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final records = snapshot.data ?? const <StoredSosMessage>[];
            if (records.isEmpty) {
              return _EmptyRecordsView();
            }

            final pendingCount = records.where((item) => !item.isUploaded).length;

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: RescuePalette.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: RescuePalette.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 16,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '救援记录中心',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '雷达扫描到的求救记录存储在此，联网后自动上传至指挥中心。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: RescuePalette.textMuted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _SummaryPill(
                            label: '累计记录',
                            value: '${records.length}',
                            tone: RescuePalette.accent,
                          ),
                          _SummaryPill(
                            label: '待上传',
                            value: '$pendingCount',
                            tone: pendingCount > 0
                                ? RescuePalette.warning
                                : RescuePalette.success,
                          ),
                          _SummaryPill(
                            label: '已同步',
                            value: '${records.length - pendingCount}',
                            tone: RescuePalette.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ...records.map((record) => _StoredSosCard(record: record)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyRecordsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: RescuePalette.accentSoft,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.inbox_rounded,
                size: 42,
                color: RescuePalette.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '记录仓暂时为空',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '开启雷达扫描后，附近求救者的信标会自动静默入库，并在这里实时显示。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: RescuePalette.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: RescuePalette.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RescuePalette.border),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: RescuePalette.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: tone, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoredSosCard extends StatelessWidget {
  const _StoredSosCard({
    required this.record,
  });

  final StoredSosMessage record;

  BloodType get _bloodType {
    for (final type in BloodType.values) {
      if (type.code == record.bloodType) {
        return type;
      }
    }
    return BloodType.unknown;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = record.isUploaded
        ? RescuePalette.success
        : RescuePalette.warning;
    final statusBackground = record.isUploaded
        ? RescuePalette.successSoft
        : const Color(0xFFFFE8C7);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RescuePalette.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RescuePalette.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: record.isUploaded
                      ? RescuePalette.successSoft
                      : RescuePalette.criticalSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  record.isUploaded
                      ? Icons.cloud_done_rounded
                      : Icons.warning_amber_rounded,
                  color: record.isUploaded
                      ? RescuePalette.success
                      : RescuePalette.critical,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.senderMac,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '接收于 ${_formatTime(record.timestamp)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RescuePalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  record.isUploaded ? '已同步' : '待上传',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _RecordMetric(
                label: '血型',
                value: _bloodType.label,
              ),
              _RecordMetric(
                label: '纬度',
                value: record.latitude.toStringAsFixed(5),
              ),
              _RecordMetric(
                label: '经度',
                value: record.longitude.toStringAsFixed(5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute:$second';
  }
}

class _RecordMetric extends StatelessWidget {
  const _RecordMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: RescuePalette.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RescuePalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: RescuePalette.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: RescuePalette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
