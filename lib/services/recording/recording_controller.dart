/// UI-facing recording lifecycle seam (implemented by
/// `RecordingSessionManager`, faked in widget tests).
library;

import 'package:flutter/widgets.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/domain/recording_state_machine.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';

abstract interface class RecordingController {
  RecordingState get state;

  SessionMetadata? get lastMetadata;

  Stream<RecordingSnapshot> get snapshots;

  RecordingSnapshot snapshot();

  /// Initializes the camera for the live preview (FR-013).
  Future<void> prepareCamera(VideoConfig config);

  /// Starts GPS ahead of recording so a fix can be acquired while the user
  /// configures the session. Fixes received here are not persisted.
  Future<void> prepareGps();

  Widget buildPreview();

  Future<void> start(SessionConfig config);

  Future<void> stop();

  Future<void> interrupt(String reason);

  void reset();
}
