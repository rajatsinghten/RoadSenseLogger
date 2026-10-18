/// Riverpod dependency wiring (NFR-007): one state-management solution,
/// constructor-based injection, platform seams overridable in tests.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roadsense_logger/core/logging/logger.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/data/session/session_store.dart';
import 'package:roadsense_logger/data/settings/settings_store.dart';
import 'package:roadsense_logger/features/settings/settings_controller.dart';
import 'package:roadsense_logger/services/camera/camera_video_recorder.dart';
import 'package:roadsense_logger/services/camera/video_recorder.dart';
import 'package:roadsense_logger/services/export/export_manager.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/native/native_control.dart';
import 'package:roadsense_logger/services/recovery/recovery_service.dart';
import 'package:roadsense_logger/services/recording/recording_controller.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';
import 'package:roadsense_logger/services/sensors/sensor_source.dart';

final loggerProvider = Provider<Logger>((ref) => Logger());

/// Backing store for settings; overridden in tests with an in-memory store.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw StateError('settingsStoreProvider must be overridden'),
);

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SessionSettings>(
      (ref) => SettingsController(ref.watch(settingsStoreProvider)),
    );

/// Root directory for session storage; overridden once at bootstrap.
final sessionRootDirProvider = Provider<Directory>(
  (ref) => throw StateError('sessionRootDirProvider must be overridden'),
);

final nativeBridgeProvider = Provider<NativeBridge>((ref) => NativeBridge());

final nativeControlProvider = Provider<NativeControl>(
  (ref) => ref.watch(nativeBridgeProvider),
);

final sensorSourceProvider = Provider<SensorSource>(
  (ref) => ref.watch(nativeBridgeProvider),
);

final locationSourceProvider = Provider<LocationSource>(
  (ref) => ref.watch(nativeBridgeProvider),
);

final videoRecorderProvider = Provider<VideoRecorder>(
  (ref) => CameraVideoRecorder(
    elapsedNs: () => ref.read(nativeControlProvider).getElapsedNs(),
  ),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(rootDir: ref.watch(sessionRootDirProvider)),
);

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(rootDir: ref.watch(sessionRootDirProvider)),
);

final recoveryServiceProvider = Provider<RecoveryService>(
  (ref) => RecoveryService(repository: ref.watch(sessionRepositoryProvider)),
);

final exportCacheDirProvider = Provider<Directory>(
  (ref) => Directory('${ref.watch(sessionRootDirProvider).path}/.export_cache'),
);

final exportManagerProvider = Provider<ExportManager>(
  (ref) => ExportManager(
    cacheDir: ref.watch(exportCacheDirProvider),
    native: ref.watch(nativeControlProvider),
  ),
);

final recordingControllerProvider = Provider<RecordingController>((ref) {
  final manager = RecordingSessionManager(
    sensors: ref.watch(sensorSourceProvider),
    location: ref.watch(locationSourceProvider),
    video: ref.watch(videoRecorderProvider),
    native: ref.watch(nativeControlProvider),
    store: ref.watch(sessionStoreProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Live recording state for the UI (starts from the current snapshot).
final recordingSnapshotProvider = StreamProvider<RecordingSnapshot>((
  ref,
) async* {
  final controller = ref.watch(recordingControllerProvider);
  yield controller.snapshot();
  yield* controller.snapshots;
});
