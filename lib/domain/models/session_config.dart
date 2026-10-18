/// Session configuration and recording settings (FR-022, FR-072, FR-073).
///
/// Values here are *requested* settings; achieved hardware behavior is
/// recorded separately in `metadata.json` (NFR-005).
library;

enum VehicleType {
  bike('bike'),
  car('car'),
  auto('auto'),
  bus('bus');

  const VehicleType(this.id);

  final String id;

  static VehicleType fromId(String id) => VehicleType.values.firstWhere(
    (v) => v.id == id,
    orElse: () => throw ArgumentError.value(id, 'id'),
  );
}

enum MountPosition {
  handlebar('handlebar'),
  dashboard('dashboard'),
  windshield('windshield'),
  other('other');

  const MountPosition(this.id);

  final String id;

  static MountPosition fromId(String id) => MountPosition.values.firstWhere(
    (v) => v.id == id,
    orElse: () => throw ArgumentError.value(id, 'id'),
  );
}

enum ImuRateSetting {
  hz100('100 Hz', 10000),
  hz200('200 Hz', 5000),
  fastest('Fastest', 0);

  const ImuRateSetting(this.label, this.periodUs);

  final String label;

  /// Nominal sampling period in microseconds requested from `SensorManager`
  /// (`0` means `SENSOR_DELAY_FASTEST`). A request is not a guarantee.
  final int periodUs;

  static ImuRateSetting fromLabel(String label) =>
      ImuRateSetting.values.firstWhere(
        (s) => s.label == label,
        orElse: () => throw ArgumentError.value(label, 'label'),
      );
}

class SessionSettings {
  const SessionSettings({
    this.imuRate = ImuRateSetting.hz200,
    this.mergedRateHz = 100,
    this.videoWidth = 1920,
    this.videoHeight = 1080,
    this.videoFps = 30,
    this.audioEnabled = false,
    this.maxImuGapMs = 250,
    this.maxGpsAgeS = 5,
  });

  final ImuRateSetting imuRate;
  final double mergedRateHz;
  final int videoWidth;
  final int videoHeight;
  final int videoFps;
  final bool audioEnabled;

  /// Gaps longer than this are not interpolated across (FR-061), ms.
  final double maxImuGapMs;

  /// GPS fixes older than this are treated as missing (FR-062), seconds.
  final double maxGpsAgeS;

  SessionSettings copyWith({
    ImuRateSetting? imuRate,
    double? mergedRateHz,
    int? videoWidth,
    int? videoHeight,
    int? videoFps,
    bool? audioEnabled,
    double? maxImuGapMs,
    double? maxGpsAgeS,
  }) {
    return SessionSettings(
      imuRate: imuRate ?? this.imuRate,
      mergedRateHz: mergedRateHz ?? this.mergedRateHz,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoFps: videoFps ?? this.videoFps,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      maxImuGapMs: maxImuGapMs ?? this.maxImuGapMs,
      maxGpsAgeS: maxGpsAgeS ?? this.maxGpsAgeS,
    );
  }

  Map<String, Object?> toJson() => {
    'imu_rate': imuRate.label,
    'merged_rate_hz': mergedRateHz,
    'video_width': videoWidth,
    'video_height': videoHeight,
    'video_fps': videoFps,
    'audio_enabled': audioEnabled,
    'max_imu_gap_ms': maxImuGapMs,
    'max_gps_age_s': maxGpsAgeS,
  };
}

/// User-entered per-session metadata (FR-073).
class SessionConfig {
  const SessionConfig({
    required this.vehicleType,
    required this.mountPosition,
    this.notes = '',
    this.settings = const SessionSettings(),
  });

  final VehicleType vehicleType;
  final MountPosition mountPosition;
  final String notes;
  final SessionSettings settings;

  Map<String, Object?> toJson() => {
    'vehicle_type': vehicleType.id,
    'mount_position': mountPosition.id,
    'notes': notes,
    'settings': settings.toJson(),
  };
}
