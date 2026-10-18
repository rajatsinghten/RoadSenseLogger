/// Persistent recording settings and pre-recording selections (FR-072/73).
///
/// Values stored here are *requested* settings; achieved hardware behavior is
/// reported separately in session metadata (NFR-005).
library;

import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SettingsStore {
  Future<SessionSettings> loadSettings();

  Future<void> saveSettings(SessionSettings settings);

  /// Previous pre-recording dialog selections, or null when never saved.
  Future<SessionConfig?> loadLastConfig();

  Future<void> saveLastConfig(SessionConfig config);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _imuRateKey = 'imu_rate';
  static const _mergedRateKey = 'merged_rate_hz';
  static const _videoWidthKey = 'video_width';
  static const _videoHeightKey = 'video_height';
  static const _videoFpsKey = 'video_fps';
  static const _audioKey = 'audio_enabled';
  static const _maxImuGapKey = 'max_imu_gap_ms';
  static const _maxGpsAgeKey = 'max_gps_age_s';
  static const _vehicleKey = 'vehicle_type';
  static const _mountKey = 'mount_position';
  static const _notesKey = 'notes';

  @override
  Future<SessionSettings> loadSettings() async {
    return SessionSettings(
      imuRate: ImuRateSetting.values.firstWhere(
        (rate) => rate.label == _prefs.getString(_imuRateKey),
        orElse: () => ImuRateSetting.hz200,
      ),
      mergedRateHz: _prefs.getDouble(_mergedRateKey) ?? 100,
      videoWidth: _prefs.getInt(_videoWidthKey) ?? 1920,
      videoHeight: _prefs.getInt(_videoHeightKey) ?? 1080,
      videoFps: _prefs.getInt(_videoFpsKey) ?? 30,
      audioEnabled: _prefs.getBool(_audioKey) ?? false,
      maxImuGapMs: _prefs.getDouble(_maxImuGapKey) ?? 250,
      maxGpsAgeS: _prefs.getDouble(_maxGpsAgeKey) ?? 5,
    );
  }

  @override
  Future<void> saveSettings(SessionSettings settings) async {
    await Future.wait([
      _prefs.setString(_imuRateKey, settings.imuRate.label),
      _prefs.setDouble(_mergedRateKey, settings.mergedRateHz),
      _prefs.setInt(_videoWidthKey, settings.videoWidth),
      _prefs.setInt(_videoHeightKey, settings.videoHeight),
      _prefs.setInt(_videoFpsKey, settings.videoFps),
      _prefs.setBool(_audioKey, settings.audioEnabled),
      _prefs.setDouble(_maxImuGapKey, settings.maxImuGapMs),
      _prefs.setDouble(_maxGpsAgeKey, settings.maxGpsAgeS),
    ]);
  }

  @override
  Future<SessionConfig?> loadLastConfig() async {
    final vehicle = _prefs.getString(_vehicleKey);
    final mount = _prefs.getString(_mountKey);
    if (vehicle == null || mount == null) return null;
    try {
      return SessionConfig(
        vehicleType: VehicleType.fromId(vehicle),
        mountPosition: MountPosition.fromId(mount),
        notes: _prefs.getString(_notesKey) ?? '',
        settings: await loadSettings(),
      );
    } on ArgumentError {
      return null;
    }
  }

  @override
  Future<void> saveLastConfig(SessionConfig config) async {
    await Future.wait([
      _prefs.setString(_vehicleKey, config.vehicleType.id),
      _prefs.setString(_mountKey, config.mountPosition.id),
      _prefs.setString(_notesKey, config.notes),
    ]);
  }
}
