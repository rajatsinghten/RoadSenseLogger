import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/services/export/export_manager.dart';

import '../helpers/fakes.dart';

void main() {
  late Directory tempDir;
  late Directory cacheDir;
  late SessionRepository repository;
  late FakeNativeControl native;
  late ExportManager exportManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_test');
    cacheDir = Directory('${tempDir.path}/cache');
    repository = SessionRepository(rootDir: tempDir);
    native = FakeNativeControl(clock: FakeClock());
    exportManager = ExportManager(cacheDir: cacheDir, native: native);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  SessionRecord makeSession({
    required String id,
    bool withVideo = true,
    bool withMerged = true,
  }) {
    final dir = Directory('${tempDir.path}/$id')..createSync(recursive: true);
    if (withVideo) File('${dir.path}/video.mp4').writeAsStringSync('videodata');
    File('${dir.path}/imu_raw.csv').writeAsStringSync(
      'timestamp_ns,t_video_s,unix_time_ms,sensor,x,y,z\n1,0,0,ACC,1,2,3\n',
    );
    File('${dir.path}/gps.csv').writeAsStringSync(
      'timestamp_ns,t_video_s,unix_time_ms,latitude,longitude,altitude_m,'
      'speed_mps,bearing_deg,accuracy_m\n1,0,0,1.0,2.0,,,,\n',
    );
    if (withMerged) {
      File('${dir.path}/merged.csv').writeAsStringSync('t_video_s\n0\n');
    }
    File(
      '${dir.path}/metadata.json',
    ).writeAsStringSync('{"status":"completed"}');
    File('${dir.path}/diagnostics.json').writeAsStringSync('{"events":[]}');
    return repository.findById(id)!;
  }

  List<String> archiveNames(File archive) {
    final bytes = ZipDecoder().decodeBytes(archive.readAsBytesSync());
    return [for (final file in bytes.files) file.name]..sort();
  }

  group('ExportManager', () {
    test(
      'full archive contains video, csvs, metadata and diagnostics',
      () async {
        final record = makeSession(id: 'session_20261018_120000_aaaaaa');
        final archive = await exportManager.createFullArchive(record);

        expect(archive.existsSync(), isTrue);
        expect(archiveNames(archive), [
          'diagnostics.json',
          'gps.csv',
          'imu_raw.csv',
          'merged.csv',
          'metadata.json',
          'video.mp4',
        ]);
      },
    );

    test('csv archive excludes the video', () async {
      final record = makeSession(id: 'session_20261018_130000_bbbbbb');
      final archive = await exportManager.createCsvArchive(record);

      final names = archiveNames(archive);
      expect(names, isNot(contains('video.mp4')));
      expect(names, contains('imu_raw.csv'));
      expect(names, containsAll(['gps.csv', 'metadata.json']));
    });

    test('missing required files raise ExportFailure listing them', () async {
      final record = makeSession(
        id: 'session_20261018_140000_cccccc',
        withVideo: false,
      );
      await expectLater(
        exportManager.createFullArchive(record),
        throwsA(
          isA<ExportFailure>().having(
            (e) => e.message,
            'message',
            contains('video.mp4'),
          ),
        ),
      );
    });

    test('optional merged/diagnostics are skipped when absent', () async {
      final record = makeSession(
        id: 'session_20261018_150000_dddddd',
        withMerged: false,
      );
      File(
        '${tempDir.path}/session_20261018_150000_dddddd/diagnostics.json',
      ).deleteSync();
      final archive = await exportManager.createFullArchive(record);
      expect(archiveNames(archive), [
        'gps.csv',
        'imu_raw.csv',
        'metadata.json',
        'video.mp4',
      ]);
    });

    test(
      're-exporting the same session overwrites the archive cleanly',
      () async {
        final record = makeSession(id: 'session_20261018_160000_eeeeee');
        final first = await exportManager.createFullArchive(record);
        final sizeFirst = first.lengthSync();
        final second = await exportManager.createFullArchive(record);
        expect(second.path, first.path);
        expect(second.lengthSync(), sizeFirst);
      },
    );

    test(
      'saveToDownloads copies the archive and removes the temp copy',
      () async {
        final record = makeSession(id: 'session_20261018_170000_ffffff');
        final archive = await exportManager.createFullArchive(record);

        final location = await exportManager.saveToDownloads(archive);

        expect(
          location,
          'Download/RoadSense/session_20261018_170000_ffffff.zip',
        );
        expect(native.saveToDownloadsCount, 1);
        expect(native.lastSavedPath, archive.path);
        expect(archive.existsSync(), isFalse);
      },
    );

    test('a failed save surfaces ExportFailure and cleans up', () async {
      final record = makeSession(id: 'session_20261018_180000_gggggg');
      final archive = await exportManager.createCsvArchive(record);
      native.saveToDownloadsError = Exception('disk full');

      await expectLater(
        exportManager.saveToDownloads(archive),
        throwsA(isA<ExportFailure>()),
      );
      expect(archive.existsSync(), isFalse);
    });
  });
}
