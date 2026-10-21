import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/app/app.dart';
import 'package:roadsense_logger/app/providers.dart';

import '../helpers/fake_gates.dart';
import '../helpers/fake_recording_controller.dart';
import '../helpers/in_memory_settings_store.dart';

void main() {
  late FakeRecordingController controller;
  late FakePermissionsGate permissions;
  late FakeRecordingEnvironment environment;

  setUp(() {
    controller = FakeRecordingController();
    permissions = FakePermissionsGate();
    environment = FakeRecordingEnvironment();
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      recordingControllerProvider.overrideWithValue(controller),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      permissionsGateProvider.overrideWithValue(permissions),
      recordingEnvironmentProvider.overrideWithValue(environment),
    ],
    child: const RoadSenseApp(),
  );

  group('permission flow (FR-080)', () {
    testWidgets('all permissions are requested when the app opens', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(permissions.ensureCount, 1);
      expect(controller.startCount, 0);
    });

    testWidgets('denied permission blocks recording with a clear message', (
      tester,
    ) async {
      permissions.granted = false;
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(permissions.ensureCount, 1); // at launch

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(permissions.ensureCount, 2);
      expect(find.textContaining('Camera permission'), findsOneWidget);
      expect(find.text('Session details'), findsNothing);
      expect(controller.startCount, 0);
    });

    testWidgets('audio permission is only requested when audio is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();

      expect(permissions.lastAudio, isFalse);
    });
  });

  group('GPS pre-flight (FR-033)', () {
    testWidgets('missing GPS fix requires an explicit decision', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();
      expect(controller.prepareGpsCount, 1);

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();

      expect(controller.prepareGpsCount, 2);
      expect(find.text('No GPS fix yet'), findsOneWidget);
      expect(controller.startCount, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.startCount, 0);
    });

    testWidgets('proceeding without GPS starts the session', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record anyway'));
      await tester.pumpAndSettle();

      expect(controller.startCount, 1);
    });
  });

  group('recording environment (FR-005)', () {
    testWidgets('keep-awake constraints wrap the recording session', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record anyway'));
      await tester.pumpAndSettle();

      expect(environment.enterCount, 1);
      expect(environment.exitCount, 0);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(environment.exitCount, 1);
    });
  });
}
