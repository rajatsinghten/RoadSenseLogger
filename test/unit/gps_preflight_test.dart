import 'dart:async';

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/permissions/permission_service.dart';
import 'package:roadsense_logger/data/session/session_store.dart';
import 'package:roadsense_logger/domain/models/session_config.dart';
import 'package:roadsense_logger/domain/models/gps_fix.dart';
import 'package:roadsense_logger/services/location/gps_recorder.dart';
import 'package:roadsense_logger/services/location/location_source.dart';
import 'package:roadsense_logger/services/native/native_bridge.dart';
import 'package:roadsense_logger/services/recording/recording_session_manager.dart';

import '../helpers/fakes.dart';

class _PermissionControl extends FakeNativeControl {
  _PermissionControl({required this.granted, this.denied = const {}})
    : super(clock: FakeClock());

  final Set<String> granted;
  final Set<String> denied;
  int requestCount = 0;

  @override
  Future<Map<String, bool>> checkPermissions(List<String> permissions) async =>
      {for (final p in permissions) p: granted.contains(p)};

  @override
  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    requestCount++;
    granted.addAll(permissions.where((p) => !denied.contains(p)));
    return {for (final p in permissions) p: true};
  }
}

/// Emits a fix from inside `startGps`, as a fast native collector could.
class _EagerSource implements LocationSource {
  _EagerSource({this.failStart = false});

  final bool failStart;
  int startCount = 0;
  final StreamController<NativeGpsEvent> controller =
      StreamController<NativeGpsEvent>.broadcast(sync: true);

  @override
  Stream<NativeGpsEvent> get gpsEvents => controller.stream;

  @override
  Future<void> startGps({required int intervalMs}) async {
    startCount++;
    if (failStart) {
      throw PlatformException(
        code: 'LOCATION_SERVICES_OFF',
        message: 'Location services are turned off',
      );
    }
    controller.add(
      const NativeGpsEvent.accepted(
        GpsFix(
          timestampNs: 1000,
          unixTimeMs: 1,
          latitude: 12.0,
          longitude: 77.0,
        ),
      ),
    );
  }

  @override
  Future<void> stopGps() async {}
}

void main() {
  group('PermissionService', () {
    test('audio enabled requires the microphone permission', () async {
      final native = _PermissionControl(
        granted: {'camera', 'fineLocation', 'coarseLocation', 'notifications'},
        denied: {'recordAudio'},
      );
      final service = PermissionService(native);
      expect(await service.ensurePermissions(audio: true), isFalse);
      expect(native.requestCount, 1);
      expect(await service.ensurePermissions(audio: false), isTrue);
    });

    test('denied location or notifications do not block recording', () async {
      final native = _PermissionControl(
        granted: {'camera'},
        denied: {'fineLocation', 'coarseLocation', 'notifications'},
      );
      expect(
        await PermissionService(native).ensurePermissions(audio: false),
        isTrue,
      );
    });

    test(
      're-requests when camera is granted but fine location is not',
      () async {
        final native = _PermissionControl(granted: {'camera'});
        final ok = await PermissionService(
          native,
        ).ensurePermissions(audio: false);
        expect(ok, isTrue);
        expect(native.requestCount, 1);
        expect(native.granted, contains('fineLocation'));
      },
    );

    test('does not prompt when every permission is already granted', () async {
      final native = _PermissionControl(
        granted: {'camera', 'fineLocation', 'coarseLocation', 'notifications'},
      );
      await PermissionService(native).ensurePermissions(audio: false);
      expect(native.requestCount, 0);
    });
  });

  group('GpsRecorder start', () {
    test('keeps a fix emitted while native collection starts', () async {
      final recorder = GpsRecorder(
        source: _EagerSource(),
        onFix: (_) {},
        onDiagnostic: (_) {},
        nowNs: () => 2000,
      );
      await recorder.start(intervalMs: 1000);
      expect(recorder.report().acceptedCount, 1);
      await recorder.stop();
    });

    test('rethrows a start failure and stays stoppable', () async {
      final recorder = GpsRecorder(
        source: _EagerSource(failStart: true),
        onFix: (_) {},
        onDiagnostic: (_) {},
        nowNs: () => 0,
      );
      await expectLater(
        recorder.start(intervalMs: 1000),
        throwsA(isA<PlatformException>()),
      );
      await recorder.stop();
    });
  });

  group('GPS status events', () {
    test('decodes a native status event', () {
      final event = NativeBridge.decodeGpsEvent({
        'kind': 'status',
        'status': 'approximate_only',
        'message': 'Only approximate location granted',
      });
      expect(event.isStatus, isTrue);
      expect(event.accepted, isFalse);
      expect(event.reason, 'approximate_only');
      expect(event.statusMessage, 'Only approximate location granted');
    });

    test('status is reported without counting as a rejected fix', () async {
      final source = _EagerSource();
      final recorder = GpsRecorder(
        source: source,
        onFix: (_) {},
        onDiagnostic: (_) {},
        nowNs: () => 0,
      );
      await recorder.start(intervalMs: 1000);
      source.controller.add(
        const NativeGpsEvent.status('fused_silent', 'Switched to device GPS'),
      );
      final report = recorder.report();
      expect(report.statusMessage, 'Switched to device GPS');
      expect(report.rejectedCount, 0);
      await recorder.stop();
    });

    test('a failed start keeps the platform reason', () async {
      final recorder = GpsRecorder(
        source: _EagerSource(failStart: true),
        onFix: (_) {},
        onDiagnostic: (_) {},
        nowNs: () => 0,
      );
      await expectLater(recorder.start(intervalMs: 1000), throwsA(anything));
      expect(
        recorder.report().statusMessage,
        'Location services are turned off',
      );
    });
  });

  group('RecordingSessionManager GPS preview', () {
    late Directory tempDir;
    late FakeClock clock;

    RecordingSessionManager build(LocationSource location) =>
        RecordingSessionManager(
          sensors: FakeSensorSource(),
          location: location,
          video: FakeVideoRecorder()
            ..videoStartNs = 2_000_000_000
            ..videoEndNs = 3_000_000_000,
          native: FakeNativeControl(clock: clock),
          store: SessionStore(
            rootDir: tempDir,
            now: () => DateTime(2026, 10, 21, 12),
            random: Random(1),
          ),
          monotonicNow: () => clock.nowNs,
          minFreeStorageBytes: 1024,
          tickInterval: const Duration(hours: 1),
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gps_preview_test');
      clock = FakeClock()..nowNs = 1_000_000_000;
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('shows idle fixes with a real age before recording', () async {
      final manager = build(_EagerSource());
      await manager.prepareGps();
      final report = manager.snapshot().gpsReport;
      expect(report.acceptedCount, 1);
      expect(report.lastFixAgeS, isNotNull);
      expect(
        manager.snapshot().warnings,
        isNot(contains(startsWith('No GPS'))),
      );
      await manager.dispose();
    });

    test('surfaces why GPS could not start and retries', () async {
      final source = _EagerSource(failStart: true);
      final manager = build(source);
      await manager.prepareGps();
      expect(
        manager.snapshot().warnings,
        contains('No GPS fix: Location services are turned off'),
      );
      await manager.prepareGps();
      expect(source.startCount, 2);
      await manager.dispose();
    });

    test('preview fixes are not persisted into the session', () async {
      final location = FakeLocationSource();
      final manager = build(location);
      await manager.prepareGps();
      location.controller.add(
        const NativeGpsEvent.accepted(
          GpsFix(timestampNs: 500, unixTimeMs: 1, latitude: 1, longitude: 2),
        ),
      );
      await manager.start(
        const SessionConfig(
          vehicleType: VehicleType.car,
          mountPosition: MountPosition.dashboard,
          notes: '',
        ),
      );
      expect(manager.snapshot().gpsReport.acceptedCount, 0);
      await manager.interrupt('test');
      await manager.dispose();
    });
  });
}
