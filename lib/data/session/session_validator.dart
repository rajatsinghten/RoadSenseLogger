/// Session file validation before a session may be marked complete
/// (FR-003, FR-055).
library;

import 'dart:convert';
import 'dart:io';

import 'package:roadsense_logger/data/session/session_paths.dart';

class ValidationReport {
  const ValidationReport(this.problems);

  final List<String> problems;

  bool get isValid => problems.isEmpty;
}

class SessionValidator {
  /// Validates that all required data files exist and contain the expected
  /// number of data rows. `metadata.json` is only checked when
  /// [checkMetadata] is true (it is written last, as the completion marker).
  static Future<ValidationReport> validate(
    SessionPaths paths, {
    required int expectedImuRows,
    required int expectedGpsRows,
    required int expectedMergedRows,
    bool checkMetadata = false,
  }) async {
    final problems = <String>[];

    Future<void> checkRowCount(String file, int expected) async {
      final f = File(file);
      if (!f.existsSync()) {
        problems.add('$file is missing');
        return;
      }
      final lines = f.readAsLinesSync();
      if (lines.isEmpty || lines.last.trim().isEmpty) {
        lines.removeWhere((line) => line.trim().isEmpty);
      }
      final dataRows = lines.isEmpty ? 0 : lines.length - 1;
      if (dataRows != expected) {
        problems.add('$file has $dataRows data rows, expected $expected');
      }
    }

    if (!File(paths.videoFile).existsSync()) {
      problems.add('video.mp4 is missing');
    }
    await checkRowCount(paths.imuFile, expectedImuRows);
    await checkRowCount(paths.gpsFile, expectedGpsRows);
    await checkRowCount(paths.mergedFile, expectedMergedRows);

    if (checkMetadata) {
      final metadataFile = File(paths.metadataFile);
      if (!metadataFile.existsSync()) {
        problems.add('metadata.json is missing');
      } else {
        try {
          final json = jsonDecode(metadataFile.readAsStringSync());
          if (json is! Map<String, Object?>) {
            problems.add('metadata.json is not a JSON object');
          }
        } catch (error) {
          problems.add('metadata.json does not parse: $error');
        }
      }
    }

    return ValidationReport(problems);
  }
}
