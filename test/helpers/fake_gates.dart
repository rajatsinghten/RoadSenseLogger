import 'package:roadsense_logger/core/permissions/permission_service.dart';
import 'package:roadsense_logger/services/recording/recording_environment.dart';

class FakePermissionsGate implements PermissionsGate {
  bool granted = true;
  int ensureCount = 0;
  bool? lastAudio;

  @override
  Future<bool> ensurePermissions({required bool audio}) async {
    ensureCount++;
    lastAudio = audio;
    return granted;
  }
}

class FakeRecordingEnvironment implements RecordingEnvironment {
  int enterCount = 0;
  int exitCount = 0;

  @override
  Future<void> enterRecording() async {
    enterCount++;
  }

  @override
  Future<void> exitRecording() async {
    exitCount++;
  }
}
