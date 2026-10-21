/// Application shell: Material 3 theming, recording-first workflow and
/// navigation to settings and session history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/features/recording/recording_screen.dart';
import 'package:roadsense_logger/features/sessions/session_list_screen.dart';
import 'package:roadsense_logger/features/settings/settings_screen.dart';

class RoadSenseApp extends ConsumerStatefulWidget {
  const RoadSenseApp({super.key});

  @override
  ConsumerState<RoadSenseApp> createState() => _RoadSenseAppState();
}

class _RoadSenseAppState extends ConsumerState<RoadSenseApp> {
  /// The shell's own context sits above [MaterialApp], so navigation must go
  /// through the navigator the app creates.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recordingControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    return MaterialApp(
      title: 'RoadSense Logger',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: RecordingScreen(
        controller: controller,
        settings: settings,
        permissions: ref.watch(permissionsGateProvider),
        environment: ref.watch(recordingEnvironmentProvider),
        onOpenSettings: () => _push(const SettingsScreen()),
        onOpenHistory: () => _push(const SessionListScreen()),
        loadLastConfig: settingsController.loadLastConfig,
        saveLastConfig: settingsController.saveLastConfig,
      ),
    );
  }

  void _push(Widget screen) {
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (context) => screen),
    );
  }
}
