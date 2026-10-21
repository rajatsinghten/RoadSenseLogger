import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/app/app.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';

import '../helpers/fake_gates.dart';
import '../helpers/fake_recording_controller.dart';
import '../helpers/in_memory_settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_navigation_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Widget buildApp({
    InMemorySettingsStore? store,
    FakeRecordingController? controller,
  }) => ProviderScope(
    overrides: [
      sessionRootDirProvider.overrideWithValue(tempDir),
      settingsStoreProvider.overrideWithValue(store ?? InMemorySettingsStore()),
      recordingControllerProvider.overrideWithValue(
        controller ?? FakeRecordingController(),
      ),
      permissionsGateProvider.overrideWithValue(FakePermissionsGate()),
      recordingEnvironmentProvider.overrideWithValue(
        FakeRecordingEnvironment(),
      ),
    ],
    child: const RoadSenseApp(),
  );

  testWidgets('settings button opens the settings screen', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });

  testWidgets('sessions button opens the session history', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Sessions'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(AppBar, 'Sessions'), findsOneWidget);
  });

  testWidgets('saved settings are used for the recording', (tester) async {
    const saved = SessionSettings(
      imuRate: ImuRateSetting.hz100,
      videoWidth: 1280,
      videoHeight: 720,
      videoFps: 60,
    );
    final store = InMemorySettingsStore()..settings = saved;
    final controller = FakeRecordingController();
    await tester.pumpWidget(buildApp(store: store, controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record anyway'));
    await tester.pumpAndSettle();

    final settings = controller.startedConfig!.settings;
    expect(settings.imuRate, ImuRateSetting.hz100);
    expect(settings.videoWidth, 1280);
    expect(settings.videoFps, 60);
    expect(store.lastConfig, isNotNull);
  });
}
