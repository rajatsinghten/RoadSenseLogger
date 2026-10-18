import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/data/settings/settings_store.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesSettingsStore', () {
    test('round-trips requested settings', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesSettingsStore(
        await SharedPreferences.getInstance(),
      );

      const settings = SessionSettings(
        imuRate: ImuRateSetting.hz100,
        mergedRateHz: 50,
        videoWidth: 1280,
        videoHeight: 720,
        videoFps: 60,
        audioEnabled: true,
        maxImuGapMs: 100,
        maxGpsAgeS: 10,
      );
      await store.saveSettings(settings);

      final restored = await store.loadSettings();
      expect(restored.imuRate, ImuRateSetting.hz100);
      expect(restored.mergedRateHz, 50);
      expect(restored.videoWidth, 1280);
      expect(restored.videoHeight, 720);
      expect(restored.videoFps, 60);
      expect(restored.audioEnabled, isTrue);
      expect(restored.maxImuGapMs, 100);
      expect(restored.maxGpsAgeS, 10);
    });

    test('defaults match the spec when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesSettingsStore(
        await SharedPreferences.getInstance(),
      );

      final settings = await store.loadSettings();
      expect(settings.imuRate, ImuRateSetting.hz200);
      expect(settings.mergedRateHz, 100);
      expect(settings.videoWidth, 1920);
      expect(settings.videoHeight, 1080);
      expect(settings.audioEnabled, isFalse);
    });

    test('round-trips pre-recording selections', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesSettingsStore(
        await SharedPreferences.getInstance(),
      );

      expect(await store.loadLastConfig(), isNull);

      const config = SessionConfig(
        vehicleType: VehicleType.bike,
        mountPosition: MountPosition.handlebar,
        notes: 'monsoon ride',
      );
      await store.saveLastConfig(config);

      final restored = await store.loadLastConfig();
      expect(restored!.vehicleType, VehicleType.bike);
      expect(restored.mountPosition, MountPosition.handlebar);
      expect(restored.notes, 'monsoon ride');
    });
  });
}
