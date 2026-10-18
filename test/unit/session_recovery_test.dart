import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/data/session/session_store.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';
import 'package:roadsense_logger/services/recovery/recovery_service.dart';

void main() {
  late Directory tempDir;
  late SessionRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('recovery_test');
    repository = SessionRepository(rootDir: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Directory makeSessionDir(String name) =>
      Directory('${tempDir.path}/$name')..createSync(recursive: true);

  void writeCompletedSession(String name) {
    final dir = makeSessionDir(name);
    File('${dir.path}/metadata.json').writeAsStringSync(
      jsonEncode({
        'session_id': name,
        'status': 'completed',
        'session': {'duration_s': 12.5},
        'quality': {
          'acc_event_count': 2400,
          'gyro_event_count': 2400,
          'gps_fix_count': 12,
        },
      }),
    );
    File('${dir.path}/imu_raw.csv').writeAsStringSync(
      'timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z\n1,0,0,ACC,1,1,1\n',
    );
    File('${dir.path}/video.mp4').writeAsStringSync('video');
  }

  group('SessionRepository', () {
    test('lists completed and incomplete sessions with status', () {
      writeCompletedSession('session_20261018_120000_aaaaaa');
      makeSessionDir('session_20261018_130000_bbbbbb');

      final sessions = repository.listSessions();
      expect(sessions.length, 2);
      expect(sessions.first.id, 'session_20261018_130000_bbbbbb');
      expect(sessions.first.status, SessionStatus.incomplete);
      expect(sessions.last.status, SessionStatus.completed);
      expect(sessions.last.durationS, 12.5);
      expect(sessions.last.accEventCount, 2400);
    });

    test('unknown metadata values stay null, never zero', () {
      makeSessionDir('session_20261018_140000_cccccc');
      final record = repository.listSessions().single;
      expect(record.durationS, isNull);
      expect(record.accEventCount, isNull);
    });

    test('deleteSession removes the directory tree', () async {
      writeCompletedSession('session_20261018_150000_dddddd');
      await repository.deleteSession('session_20261018_150000_dddddd');
      expect(repository.listSessions(), isEmpty);
    });
  });

  group('RecoveryService', () {
    test(
      'recovers an interrupted session with truncated corrupt tail',
      () async {
        final dir = makeSessionDir('session_20261018_160000_eeeeee');
        File('${dir.path}/video.mp4').writeAsStringSync('video');
        File('${dir.path}/imu_raw.csv.part').writeAsStringSync(
          'timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z\n'
          '100,0.1,0,ACC,1,1,1\n'
          '200,0.2,0,ACC,1,1,1\n'
          'CORRUPT_ROW\n',
        );
        File('${dir.path}/gps.csv.part').writeAsStringSync(
          'timestamp_ns,t_video_s,unix_time_ms,latitude,longitude,altitude_m,'
          'speed_mps,bearing_deg,accuracy_m\n'
          '150,0.15,0,12.9,77.5,,,,\n',
        );

        final service = RecoveryService(repository: repository);
        final report = await service.recoverAll();
        expect(report.recoveredSessions, ['session_20261018_160000_eeeeee']);

        // Part files renamed, corrupt tail truncated.
        expect(File('${dir.path}/imu_raw.csv.part').existsSync(), isFalse);
        final imuLines = File('${dir.path}/imu_raw.csv').readAsLinesSync();
        expect(imuLines.length, 3); // header + 2 valid rows
        expect(File('${dir.path}/gps.csv').readAsLinesSync().length, 2);

        // Metadata marks the session recovered with retained counts.
        final metadata =
            jsonDecode(File('${dir.path}/metadata.json').readAsStringSync())
                as Map<String, Object?>;
        expect(metadata['status'], 'recovered');
        final recovery = metadata['recovery']! as Map<String, Object?>;
        expect(recovery['recovered'], isTrue);
        expect(recovery['loss_window_s'], 1.0);
        final retained = recovery['retained_rows']! as Map<String, Object?>;
        expect(retained['imu'], 2);
        expect(retained['gps'], 1);
        expect((recovery['problems']! as List).join(), contains('truncated'));
      },
    );

    test('a recovered session is never marked completed', () async {
      makeSessionDir('session_20261018_170000_ffffff');
      await RecoveryService(repository: repository).recoverAll();
      final record = repository.listSessions().single;
      expect(record.status, SessionStatus.recovered);
    });

    test('completed sessions are untouched by recovery', () async {
      writeCompletedSession('session_20261018_180000_111111');
      final before = File(
        '${tempDir.path}/session_20261018_180000_111111/metadata.json',
      ).readAsStringSync();

      final report = await RecoveryService(repository: repository).recoverAll();
      expect(report.recoveredSessions, isEmpty);
      expect(report.skippedSessions, ['session_20261018_180000_111111']);
      expect(
        File(
          '${tempDir.path}/session_20261018_180000_111111/metadata.json',
        ).readAsStringSync(),
        before,
      );
    });

    test('missing files become recorded problems, not fabrications', () async {
      final dir = makeSessionDir('session_20261018_190000_222222');
      await RecoveryService(repository: repository).recoverAll();

      final metadata =
          jsonDecode(File('${dir.path}/metadata.json').readAsStringSync())
              as Map<String, Object?>;
      final recovery = metadata['recovery']! as Map<String, Object?>;
      final problems = (recovery['problems']! as List).join(' ');
      expect(problems, contains('imu_raw.csv missing'));
      expect(problems, contains('gps.csv missing'));
      expect(problems, contains('merged.csv missing'));
      expect(problems, contains('video.mp4 missing'));
    });

    test('exposes session creation naming for history', () async {
      final store = SessionStore(
        rootDir: tempDir,
        now: () => DateTime(2026, 10, 18, 20, 30, 45),
      );
      final paths = await store.createSession();
      final name = paths.sessionDir.path.split('/').last;
      expect(name, startsWith('session_20261018_203045_'));
      expect(repository.listSessions().single.id, name);
    });
  });
}
