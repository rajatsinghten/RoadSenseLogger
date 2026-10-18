import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/services/camera/camera_video_recorder.dart';

void main() {
  group('resolutionPresetFor', () {
    test('maps 1920x1080 request to veryHigh', () {
      expect(resolutionPresetFor(1920, 1080), ResolutionPreset.veryHigh);
    });

    test('maps portrait request by short side', () {
      expect(resolutionPresetFor(1080, 1920), ResolutionPreset.veryHigh);
    });

    test('maps lower and higher tiers', () {
      expect(resolutionPresetFor(640, 480), ResolutionPreset.medium);
      expect(resolutionPresetFor(1280, 720), ResolutionPreset.high);
      expect(resolutionPresetFor(2560, 1440), ResolutionPreset.ultraHigh);
      expect(resolutionPresetFor(3840, 2160), ResolutionPreset.max);
    });
  });
}
