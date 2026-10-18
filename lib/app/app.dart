/// Application shell: Material 3 theming, recording-first workflow and
/// navigation to settings and session history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/app/providers.dart';
import 'package:roadsense_logger/features/recording/recording_screen.dart';
import 'package:roadsense_logger/features/sessions/session_list_screen.dart';
import 'package:roadsense_logger/features/settings/settings_screen.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';

class RoadSenseApp extends ConsumerWidget {
  const RoadSenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(recordingControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    return MaterialApp(
      title: 'RoadSense Logger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: RecordingScreen(
        controller: controller,
        settings: settings,
        onOpenSettings: () => _openSettings(context, controller),
        onOpenHistory: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const SessionListScreen(),
          ),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context, RecordingController controller) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const SettingsScreen()),
    );
  }
}
