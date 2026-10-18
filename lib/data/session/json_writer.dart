/// JSON file writing for `metadata.json` and `diagnostics.json` (DATA-004/5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:roadsense_logger/core/errors/app_failure.dart';

/// Writes [data] as pretty-printed UTF-8 JSON to [path].
Future<void> writeJsonFile(String path, Map<String, Object?> data) async {
  try {
    final file = File(path);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  } catch (error) {
    throw StorageFailure('Failed to write $path', cause: error);
  }
}
