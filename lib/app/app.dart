/// Application shell: Material 3 theming and the recording-first workflow.
library;

import 'package:flutter/material.dart';
import 'package:roadsense_logger/features/recording/recording_screen.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';

class RoadSenseApp extends StatelessWidget {
  const RoadSenseApp({super.key, required this.controller});

  final RecordingController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadSense Logger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: RecordingScreen(controller: controller),
    );
  }
}
