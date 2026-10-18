import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/app/app.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';

import '../helpers/fake_recording_controller.dart';

void main() {
  late FakeRecordingController controller;

  setUp(() {
    controller = FakeRecordingController();
  });

  Widget buildApp() => RoadSenseApp(controller: controller);

  group('RecordingScreen', () {
    testWidgets('shows preview, metrics and a Record control when idle', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      expect(find.text('RoadSense Logger'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('ACC rate'), findsOneWidget);
      expect(find.text('00:00:00'), findsOneWidget);
    });

    testWidgets('record flow starts a session with dialog-provided config', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(find.text('Session details'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'highway run');
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();

      expect(controller.startCount, 1);
      expect(controller.startedConfig!.notes, 'highway run');
      expect(controller.startedConfig!.vehicleType, VehicleType.car);
      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('canceling the dialog does not start recording', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.startCount, 0);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('stop finalizes and reports the saved session', (tester) async {
      controller.state = RecordingState.recording;
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      expect(controller.stopCount, 1);
      expect(find.textContaining('Session saved'), findsOneWidget);
    });

    testWidgets('start failure surfaces an actionable message', (tester) async {
      controller.startError = CameraFailure('camera is busy');
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();

      expect(find.text('camera is busy'), findsOneWidget);
      expect(find.text('Record'), findsOneWidget);
    });

    testWidgets('camera preview errors show a placeholder, not a crash', (
      tester,
    ) async {
      controller.previewError = CameraFailure('no camera available');
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('Camera preview unavailable'), findsOneWidget);
    });

    testWidgets('reset is available after completion', (tester) async {
      controller.state = RecordingState.completed;
      await tester.pumpWidget(buildApp());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(controller.resetCount, 1);
      expect(find.text('Record'), findsOneWidget);
    });
  });
}
