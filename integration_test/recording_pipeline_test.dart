// Integration tests for the recording pipeline (FR-092).
//
// REQUIRES A PHYSICAL DEVICE OR EMULATOR with:
//   - camera (for the video leg; tests degrade honestly without it)
//   - IMU sensors (emulators typically provide accelerometer/gyroscope)
//   - optional GPS
//
// Grant permissions before running to avoid system dialogs blocking the test:
//   adb shell pm grant ai.roadsense.roadsense_logger android.permission.CAMERA
//   adb shell pm grant ai.roadsense.roadsense_logger android.permission.ACCESS_FINE_LOCATION
//   adb shell pm grant ai.roadsense.roadsense_logger android.permission.ACCESS_COARSE_LOCATION
//
// Run with:  flutter test integration_test -d <device-id>
//
// If no device is attached these tests cannot run; the exact blocker is
// recorded in the project's final verification report.
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:roadsense_logger/app/app.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/data/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full recording session produces a valid dataset', (
    tester,
  ) async {
    final supportDir = await getApplicationSupportDirectory();
    final sessionRoot = Directory('${supportDir.path}/integration_sessions')
      ..createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRootDirProvider.overrideWithValue(sessionRoot),
          settingsStoreProvider.overrideWithValue(
            SharedPreferencesSettingsStore(prefs),
          ),
        ],
        child: const RoadSenseApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Session dialog → start → GPS pre-flight → record ~3 s → stop.
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'integration test run');
    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();
    if (find.text('No GPS fix yet').evaluate().isNotEmpty) {
      await tester.tap(find.text('Record anyway'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Stop'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    final sessions = sessionRoot.listSync().whereType<Directory>().toList();
    expect(sessions, isNotEmpty);
    final sessionDir = sessions.first;
    for (final name in [
      'video.mp4',
      'imu_raw.csv',
      'gps.csv',
      'merged.csv',
      'metadata.json',
      'diagnostics.json',
    ]) {
      expect(
        File('${sessionDir.path}/$name').existsSync(),
        isTrue,
        reason: '$name missing from ${sessionDir.path}',
      );
    }

    final imuLines = File('${sessionDir.path}/imu_raw.csv').readAsLinesSync();
    expect(imuLines.first, startsWith('timestamp_ns,t_video_s,unix_time_ms'));
    expect(imuLines.length, greaterThan(10)); // real IMU rows were captured

    final mergedLines = File('${sessionDir.path}/merged.csv').readAsLinesSync();
    expect(mergedLines.first, startsWith('t_video_s,unix_time_ms'));
    expect(mergedLines.length, greaterThan(100)); // ~100 Hz over ≥1 s

    final metadata = File(
      '${sessionDir.path}/metadata.json',
    ).readAsStringSync();
    expect(metadata, contains('"status": "completed"'));
  });

  testWidgets('export packages a recorded session into a readable zip', (
    tester,
  ) async {
    final supportDir = await getApplicationSupportDirectory();
    final sessionRoot = Directory('${supportDir.path}/integration_sessions')
      ..createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        sessionRootDirProvider.overrideWithValue(sessionRoot),
        settingsStoreProvider.overrideWithValue(
          SharedPreferencesSettingsStore(prefs),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = container.read(sessionRepositoryProvider);
    final sessions = repository.listSessions();
    if (sessions.isEmpty) {
      // Run after the recording test; without a recorded session there is
      // nothing to export (recorded as skipped, not passed silently).
      markTestSkipped('no recorded session available for export');
      return;
    }

    final exporter = container.read(exportManagerProvider);
    final archive = await exporter.createFullArchive(sessions.first);
    expect(archive.existsSync(), isTrue);

    final decoded = ZipDecoder().decodeBytes(archive.readAsBytesSync());
    final names = {for (final f in decoded.files) f.name};
    expect(
      names,
      containsAll([
        'video.mp4',
        'imu_raw.csv',
        'gps.csv',
        'merged.csv',
        'metadata.json',
        'diagnostics.json',
      ]),
    );
  });
}
