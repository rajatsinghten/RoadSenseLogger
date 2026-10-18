/// Session summary and actions (FR-070, FR-074). Unknown values display as
/// unavailable (—), never zero.
library;

import 'package:flutter/material.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/services/export/export_manager.dart';

class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({
    super.key,
    required this.record,
    required this.exporter,
    required this.onDelete,
  });

  final SessionRecord record;
  final SessionExporter exporter;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(record.id)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Summary(record: record),
          const SizedBox(height: 24),
          Text('Actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share full archive (ZIP)'),
            onPressed: () => _run(context, () async {
              final archive = await exporter.createFullArchive(record);
              await exporter.shareArchive(
                archive,
                subject: 'RoadSense session ${record.id}',
              );
            }),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.table_chart),
            label: const Text('Export CSVs only (ZIP)'),
            onPressed: () => _run(context, () async {
              final archive = await exporter.createCsvArchive(record);
              await exporter.shareArchive(
                archive,
                subject: 'RoadSense data ${record.id}',
              );
            }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: const Text('Open folder'),
            onPressed: () =>
                _run(context, () => exporter.openSessionFolder(record)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('Delete session'),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on AppFailure catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'This permanently removes ${record.id} and all of its files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await onDelete(record.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final distance = record.gpsDistanceM;
    final avgSpeed = record.gpsAvgSpeedMps;
    final accRate = record.accAchievedRateHz;
    final gyroRate = record.gyroAchievedRateHz;
    final warnings = <String>[
      if (record.interrupted)
        'Recording was interrupted: ${record.interruptionReason ?? 'unknown reason'}',
      if (record.recovered)
        'Recovered from an interrupted session; raw data may be partial',
      if ((record.quality['gyro_missing_rows'] as num? ?? 0) > 0)
        'Gyroscope data missing for some merged rows',
      if ((record.quality['gps_stale_rows'] as num? ?? 0) > 0)
        'GPS stale for some merged rows',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.status.id,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _row(
              'Duration',
              record.durationS == null
                  ? '—'
                  : '${record.durationS!.toStringAsFixed(1)} s',
            ),
            _row(
              'Distance',
              distance == null ? '—' : '${distance.toStringAsFixed(1)} m',
            ),
            _row(
              'Average speed',
              avgSpeed == null ? '—' : '${avgSpeed.toStringAsFixed(2)} m/s',
            ),
            _row('ACC events', '${record.accEventCount ?? '—'}'),
            _row('GYRO events', '${record.gyroEventCount ?? '—'}'),
            _row('GPS fixes', '${record.gpsFixCount ?? '—'}'),
            _row(
              'ACC achieved rate',
              accRate == null ? '—' : '${accRate.toStringAsFixed(1)} Hz',
            ),
            _row(
              'GYRO achieved rate',
              gyroRate == null ? '—' : '${gyroRate.toStringAsFixed(1)} Hz',
            ),
            _row('Video', _videoText()),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final warning in warnings)
                Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _videoText() {
    final width = record.videoRequestedWidth;
    final height = record.videoRequestedHeight;
    final fps = record.videoRequestedFps;
    if (width == null || height == null) return '—';
    return '$width × $height'
        '${fps == null ? '' : ' @ $fps FPS target'}'
        '${record.videoResolutionPreset == null ? '' : ' (${record.videoResolutionPreset})'}';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value)],
      ),
    );
  }
}
