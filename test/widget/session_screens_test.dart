import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/features/sessions/session_detail_screen.dart';
import 'package:roadsense_logger/features/sessions/session_list_screen.dart';

import '../helpers/fake_session_exporter.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_screens_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  SessionRecord record({
    String id = 'session_20261018_120000_aaaaaa',
    SessionStatus status = SessionStatus.completed,
    Map<String, Object?>? metadata,
  }) {
    return SessionRecord(
      id: id,
      directory: Directory('${tempDir.path}/$id'),
      status: status,
      metadata: metadata,
    );
  }

  Future<void> useTallScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget detailPage(
    SessionRecord record,
    FakeSessionExporter exporter, {
    Future<void> Function(String id)? onDelete,
  }) {
    return MaterialApp(
      home: SessionDetailScreen(
        record: record,
        exporter: exporter,
        onDelete: onDelete ?? (id) async {},
      ),
    );
  }

  group('SessionDetailScreen', () {
    testWidgets('unknown values display as unavailable, never zero', (
      tester,
    ) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      await tester.pumpWidget(detailPage(record(metadata: {}), exporter));

      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('0.0 s'), findsNothing);
      expect(find.text('0 m'), findsNothing);
    });

    testWidgets('shows counts, distance and achieved rates when known', (
      tester,
    ) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      await tester.pumpWidget(
        detailPage(
          record(
            metadata: {
              'session': {'duration_s': 12.5},
              'gps': {'distance_m': 152.5, 'avg_speed_mps': 4.2},
              'imu': {
                'acc': {'event_count': 2400, 'achieved_rate_hz': 198.7},
                'gyro': {'event_count': 2400, 'achieved_rate_hz': 197.9},
              },
              'quality': {'gps_fix_count': 12},
              'video': {
                'requested_width': 1920,
                'requested_height': 1080,
                'requested_fps': 30,
                'resolution_preset': 'veryHigh',
              },
            },
          ),
          exporter,
        ),
      );

      expect(find.text('12.5 s'), findsOneWidget);
      expect(find.text('152.5 m'), findsOneWidget);
      expect(find.text('198.7 Hz'), findsOneWidget);
      expect(find.textContaining('1920 × 1080'), findsOneWidget);
    });

    testWidgets('interruption and recovery warnings are surfaced', (
      tester,
    ) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      await tester.pumpWidget(
        detailPage(
          record(
            status: SessionStatus.recovered,
            metadata: {
              'interruption': {
                'interrupted': true,
                'reason': 'camera disconnected',
              },
              'recovery': {'recovered': true},
              'quality': {'gyro_missing_rows': 5, 'gps_stale_rows': 2},
            },
          ),
          exporter,
        ),
      );

      expect(find.textContaining('Recording was interrupted'), findsOneWidget);
      expect(find.textContaining('Recovered'), findsOneWidget);
      expect(find.textContaining('Gyroscope data missing'), findsOneWidget);
      expect(find.textContaining('GPS stale'), findsOneWidget);
    });

    testWidgets('export failure surfaces a clear message', (tester) async {
      final exporter = FakeSessionExporter()
        ..fullArchiveError = ExportFailure('missing video.mp4');
      await tester.pumpWidget(detailPage(record(), exporter));

      await tester.tap(find.text('Share full archive (ZIP)'));
      await tester.pumpAndSettle();

      expect(find.text('missing video.mp4'), findsOneWidget);
    });

    testWidgets('delete requires confirmation', (tester) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      var deleted = false;
      await tester.pumpWidget(
        detailPage(record(), exporter, onDelete: (id) async => deleted = true),
      );

      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();
      expect(find.text('Delete session?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);

      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('save to Downloads builds the archive and reports where', (
      tester,
    ) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      await tester.pumpWidget(detailPage(record(), exporter));

      await tester.tap(find.text('Save full archive to Downloads'));
      await tester.pumpAndSettle();

      expect(exporter.fullArchiveCount, 1);
      expect(exporter.saveCount, 1);
      expect(
        find.text(
          'Saved to Download/RoadSense/session_20261018_120000_aaaaaa.zip',
        ),
        findsOneWidget,
      );
    });

    testWidgets('save CSVs to Downloads uses the CSV-only archive', (
      tester,
    ) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter();
      await tester.pumpWidget(detailPage(record(), exporter));

      await tester.tap(find.text('Save CSVs to Downloads'));
      await tester.pumpAndSettle();

      expect(exporter.csvArchiveCount, 1);
      expect(exporter.lastSaved!.path, endsWith('_csv.zip'));
    });

    testWidgets('a failed save shows the error', (tester) async {
      await useTallScreen(tester);
      final exporter = FakeSessionExporter()
        ..saveError = ExportFailure('Could not save x.zip to Downloads');
      await tester.pumpWidget(detailPage(record(), exporter));

      await tester.tap(find.text('Save full archive to Downloads'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save x.zip to Downloads'), findsOneWidget);
    });
  });

  group('SessionListScreen', () {
    testWidgets('lists sessions with status identification', (tester) async {
      final root = Directory('${tempDir.path}/sessions')..createSync();
      Directory('${root.path}/session_20261018_120000_aaaaaa').createSync();
      File(
        '${root.path}/session_20261018_120000_aaaaaa/metadata.json',
      ).writeAsStringSync('{"status":"completed"}');
      Directory('${root.path}/session_20261018_130000_bbbbbb').createSync();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(
              SessionRepository(rootDir: root),
            ),
            exportManagerProvider.overrideWithValue(FakeSessionExporter()),
          ],
          child: const MaterialApp(home: SessionListScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('session_20261018_130000_bbbbbb'), findsOneWidget);
      expect(find.text('session_20261018_120000_aaaaaa'), findsOneWidget);
      expect(find.text('complete'), findsOneWidget);
      expect(find.text('incomplete'), findsOneWidget);
    });

    testWidgets('empty history shows a placeholder', (tester) async {
      final root = Directory('${tempDir.path}/empty_sessions')..createSync();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionRepositoryProvider.overrideWithValue(
              SessionRepository(rootDir: root),
            ),
            exportManagerProvider.overrideWithValue(FakeSessionExporter()),
          ],
          child: const MaterialApp(home: SessionListScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('No sessions recorded yet'), findsOneWidget);
    });
  });
}
