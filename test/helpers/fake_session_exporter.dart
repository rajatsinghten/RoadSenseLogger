import 'dart:io';

import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/services/export/export_manager.dart';

/// UI-level export fake (no archiving, no platform channels).
class FakeSessionExporter implements SessionExporter {
  Object? fullArchiveError;
  Object? csvArchiveError;
  Object? saveError;

  int fullArchiveCount = 0;
  int csvArchiveCount = 0;
  int shareCount = 0;
  int saveCount = 0;
  File? lastShared;
  File? lastSaved;

  @override
  Future<File> createFullArchive(SessionRecord record) async {
    if (fullArchiveError != null) throw fullArchiveError!;
    fullArchiveCount++;
    return File('/tmp/${record.id}.zip');
  }

  @override
  Future<File> createCsvArchive(SessionRecord record) async {
    if (csvArchiveError != null) throw csvArchiveError!;
    csvArchiveCount++;
    return File('/tmp/${record.id}_csv.zip');
  }

  @override
  Future<void> shareArchive(File archive, {String? subject}) async {
    shareCount++;
    lastShared = archive;
  }

  @override
  Future<String> saveToDownloads(File archive) async {
    if (saveError != null) throw saveError!;
    saveCount++;
    lastSaved = archive;
    return 'Download/RoadSense/${archive.uri.pathSegments.last}';
  }
}
