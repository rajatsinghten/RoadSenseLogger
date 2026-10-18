/// Session history persistence (FR-070): lists recorded sessions and their
/// completion status by reading each session directory (FR-055).
library;

import 'dart:convert';
import 'dart:io';

import 'package:roadsense_logger/data/session/session_paths.dart';
import 'package:roadsense_logger/domain/models/session_metadata.dart';

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.directory,
    required this.status,
    required this.metadata,
  });

  final String id;
  final Directory directory;
  final SessionStatus status;

  /// Parsed `metadata.json` contents, or null when absent (incomplete session).
  final Map<String, Object?>? metadata;

  SessionPaths get paths => SessionPaths(directory);

  /// Null when metadata is missing — never zero (FR-074).
  double? get durationS =>
      ((metadata?['session'] as Map<String, Object?>?)?['duration_s'] as num?)
          ?.toDouble();

  int? get accEventCount => _qualityInt('acc_event_count');

  int? get gyroEventCount => _qualityInt('gyro_event_count');

  int? get gpsFixCount => _qualityInt('gps_fix_count');

  int? _qualityInt(String key) {
    final quality = metadata?['quality'] as Map<String, Object?>?;
    return (quality?[key] as num?)?.toInt();
  }
}

class SessionRepository {
  SessionRepository({required this.rootDir});

  final Directory rootDir;

  /// Lists sessions newest-first by directory name (timestamped names).
  List<SessionRecord> listSessions() {
    if (!rootDir.existsSync()) return const [];
    final dirs = rootDir
        .listSync()
        .whereType<Directory>()
        .where((dir) => _isSessionDir(dir.path))
        .toList();
    dirs.sort((a, b) => b.path.compareTo(a.path));
    return [for (final dir in dirs) _record(dir)];
  }

  /// Finds one session by directory id.
  SessionRecord? findById(String id) {
    final dir = Directory('${rootDir.path}/$id');
    if (!_isSessionDir(dir.path) || !dir.existsSync()) return null;
    return _record(dir);
  }

  /// Deletes a session directory tree (FR-070, with UI confirmation).
  Future<void> deleteSession(String id) async {
    final dir = Directory('${rootDir.path}/$id');
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  SessionRecord _record(Directory dir) {
    final metadataFile = File('${dir.path}/metadata.json');
    Map<String, Object?>? metadata;
    var status = SessionStatus.incomplete;
    if (metadataFile.existsSync()) {
      try {
        final decoded = jsonDecode(metadataFile.readAsStringSync());
        if (decoded is Map<String, Object?>) {
          metadata = decoded;
          status = SessionStatus.values.firstWhere(
            (s) => s.id == decoded['status'],
            orElse: () => SessionStatus.incomplete,
          );
        }
      } catch (_) {
        // Unreadable metadata: the session stays incomplete (never complete).
      }
    }
    return SessionRecord(
      id: dir.path.split('/').last,
      directory: dir,
      status: status,
      metadata: metadata,
    );
  }

  static bool _isSessionDir(String path) =>
      path.split('/').last.startsWith('session_');
}
