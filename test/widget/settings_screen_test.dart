import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/features/settings/settings_screen.dart';

import '../helpers/in_memory_settings_store.dart';

void main() {
  late InMemorySettingsStore store;

  setUp(() {
    store = InMemorySettingsStore();
  });

  Widget buildScreen() => ProviderScope(
    overrides: [settingsStoreProvider.overrideWithValue(store)],
    child: const MaterialApp(home: SettingsScreen()),
  );

  group('SettingsScreen', () {
    testWidgets('shows requested settings with an honesty note', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.textContaining('Requested settings'), findsOneWidget);
      expect(find.text('IMU target rate'), findsOneWidget);
      expect(find.text('Merged CSV rate (Hz)'), findsOneWidget);
      expect(find.text('Record audio'), findsOneWidget);
    });

    testWidgets('changing the IMU rate persists through the store', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('200 Hz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fastest').last);
      await tester.pumpAndSettle();

      expect(store.settings.imuRate, ImuRateSetting.fastest);
    });

    testWidgets('toggling audio persists through the store', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(store.settings.audioEnabled, isTrue);
    });
  });
}
