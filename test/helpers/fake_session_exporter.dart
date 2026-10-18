import 'dart:io';

import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/services/export/export_manager.dart';

/// UI-level export fake (no archiving, no platform channels).
class FakeSessionExporter implements SessionExporter {
  Object? fullArchiveError;
  Object? csvArchiveError;
  Object? openError;

  int fullArchiveCount = 0;
  int csvArchiveCount = 0;
  int shareCount = 0;
  int openCount = 0;
  File? lastShared;
  String? lastOpenedSessionId;

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
  Future<void> openSessionFolder(SessionRecord record) async {
    if (openError != null) throw openError!;
    openCount++;
    lastOpenedSessionId = record.id;
  }
}
