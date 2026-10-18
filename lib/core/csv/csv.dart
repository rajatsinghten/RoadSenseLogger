/// RFC 4180 CSV serialization helpers (DATA-007).
///
/// Missing values are serialized as empty fields — never as zero.
library;

class Csv {
  const Csv._();

  /// Formats one field: quotes text containing commas, quotes or newlines and
  /// doubles internal quotes. `null` becomes an empty field.
  static String field(String? value) {
    if (value == null || value.isEmpty) return '';
    final needsQuoting =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuoting) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Joins fields into one CSV row (without trailing newline).
  static String row(Iterable<String?> fields) => fields.map(field).join(',');

  /// Formats an integer value, or empty when null.
  static String formatInt(int? value) => value == null ? '' : value.toString();

  /// Formats a double with up to [maxDecimals] decimals, trimming trailing
  /// zeros. Never uses scientific notation. Empty when null or non-finite.
  static String formatDouble(double? value, {int maxDecimals = 9}) {
    if (value == null || !value.isFinite) return '';
    var text = value.toStringAsFixed(maxDecimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    if (text == '-0') return '0';
    return text;
  }
}
