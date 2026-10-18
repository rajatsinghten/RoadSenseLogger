/// Device behavior while recording (FR-005): keep the screen awake and lock
/// orientation during a session, restore normal behavior afterwards.
library;

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract interface class RecordingEnvironment {
  Future<void> enterRecording();

  Future<void> exitRecording();
}

class SystemRecordingEnvironment implements RecordingEnvironment {
  @override
  Future<void> enterRecording() async {
    await WakelockPlus.enable();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  Future<void> exitRecording() async {
    await WakelockPlus.disable();
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
}
