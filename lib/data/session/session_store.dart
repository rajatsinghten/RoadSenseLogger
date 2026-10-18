/// Session directory creation (FR-050): unique
/// `session_YYYYMMDD_HHMMSS_<id>` directories under the app-specific root.
library;

import 'dart:io';
import 'dart:math';

import 'package:roadsense_logger/data/session/session_paths.dart';

class SessionStore {
  SessionStore({
    required this.rootDir,
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random();

  final Directory rootDir;
  final DateTime Function() _now;
  final Random _random;

  /// Creates a fresh session directory and returns its paths.
  Future<SessionPaths> createSession() async {
    final stamp = _now();
    final id = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final name =
        'session_${_four(stamp.year)}${_two(stamp.month)}${_two(stamp.day)}'
        '_${_two(stamp.hour)}${_two(stamp.minute)}${_two(stamp.second)}_$id';
    final dir = Directory('${rootDir.path}/$name');
    await dir.create(recursive: true);
    return SessionPaths(dir);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _four(int value) => value.toString().padLeft(4, '0');
}
