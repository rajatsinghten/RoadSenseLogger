/// RoadSense Logger entry point: resolves app storage, runs interrupted-
/// session recovery (FR-055) and launches the app.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roadsense_logger/app/app.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/data/settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final sessionRoot = Directory('${supportDir.path}/sessions');
  await sessionRoot.create(recursive: true);

  final prefs = await SharedPreferences.getInstance();
  final overrides = [
    sessionRootDirProvider.overrideWithValue(sessionRoot),
    settingsStoreProvider.overrideWithValue(
      SharedPreferencesSettingsStore(prefs),
    ),
  ];
  final container = ProviderContainer(overrides: overrides);
  try {
    final report = await container.read(recoveryServiceProvider).recoverAll();
    if (report.recoveredSessions.isNotEmpty) {
      container
          .read(loggerProvider)
          .info('Recovered interrupted sessions: ${report.recoveredSessions}');
    }
  } catch (error) {
    container.read(loggerProvider).error('Session recovery failed', error);
  }

  runApp(
    ProviderScope(overrides: overrides, child: const RoadSenseApp()),
  );
}
