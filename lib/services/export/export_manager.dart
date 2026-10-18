/// Session export (FR-070, FR-071): ZIP archives shared via content URIs.
///
/// Archives are built with streaming file encoding so large videos are never
/// loaded into memory. Required dataset files must exist; optional files are
/// included when available. Missing required files raise [ExportFailure]
/// with the exact list (never a silently incomplete archive).
library;

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:roadsense_logger/core/errors/app_failure.dart';
import 'package:roadsense_logger/data/session/session_repository.dart';
import 'package:roadsense_logger/services/native/native_control.dart';
import 'package:share_plus/share_plus.dart';

/// UI-facing export seam (implemented by [ExportManager]).
abstract interface class SessionExporter {
  Future<File> createFullArchive(SessionRecord record);

  Future<File> createCsvArchive(SessionRecord record);

  Future<void> shareArchive(File archive, {String? subject});

  Future<void> openSessionFolder(SessionRecord record);
}

class ExportManager implements SessionExporter {
  ExportManager({required this.cacheDir, required this.native});

  final Directory cacheDir;
  final NativeControl native;

  /// Builds the full session archive (video + CSVs + metadata).
  @override
  Future<File> createFullArchive(SessionRecord record) =>
      _buildArchive(record, includeVideo: true);

  /// Builds a CSV-only archive (dataset CSVs + metadata, no video).
  @override
  Future<File> createCsvArchive(SessionRecord record) =>
      _buildArchive(record, includeVideo: false);

  Future<File> _buildArchive(
    SessionRecord record, {
    required bool includeVideo,
  }) async {
    final paths = record.paths;
    final required = <String>[
      paths.imuFile,
      paths.gpsFile,
      paths.metadataFile,
      if (includeVideo) paths.videoFile,
    ];
    final missing = [
      for (final file in required)
        if (!File(file).existsSync()) file.split('/').last,
    ];
    if (missing.isNotEmpty) {
      throw ExportFailure(
        'Cannot export session ${record.id}: missing ${missing.join(', ')}',
        context: {'missing': missing},
      );
    }

    await cacheDir.create(recursive: true);
    final archivePath =
        '${cacheDir.path}/${record.id}${includeVideo ? '' : '_csv'}.zip';
    final encoder = ZipFileEncoder();
    try {
      encoder.create(archivePath);
      if (includeVideo) {
        await encoder.addFile(File(paths.videoFile));
      }
      await encoder.addFile(File(paths.imuFile));
      await encoder.addFile(File(paths.gpsFile));
      for (final optional in [paths.mergedFile, paths.diagnosticsFile]) {
        if (File(optional).existsSync()) {
          await encoder.addFile(File(optional));
        }
      }
      await encoder.addFile(File(paths.metadataFile));
    } catch (error) {
      throw ExportFailure('Failed to build session archive', cause: error);
    } finally {
      await encoder.close();
    }
    return File(archivePath);
  }

  /// Shares an archive via the Android share sheet (content URI).
  @override
  Future<void> shareArchive(File archive, {String? subject}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(archive.path)], subject: subject),
      );
    } catch (error) {
      throw ExportFailure('Failed to share ${archive.path}', cause: error);
    }
  }

  /// Opens the session directory with a system file viewer where supported.
  @override
  Future<void> openSessionFolder(SessionRecord record) async {
    try {
      await native.openFolder(record.directory.path);
    } catch (error) {
      throw ExportFailure(
        'Could not open ${record.id} in a file viewer',
        cause: error,
      );
    }
  }
}
