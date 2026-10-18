import 'package:flutter_test/flutter_test.dart';
import 'package:roadsense_logger/core/csv/csv.dart';

void main() {
  group('Csv.field', () {
    test('passes plain text through unchanged', () {
      expect(Csv.field('ACC'), 'ACC');
    });

    test('converts null to an empty field', () {
      expect(Csv.field(null), '');
    });

    test('quotes fields containing commas', () {
      expect(Csv.field('a,b'), '"a,b"');
    });

    test('doubles internal quotes and wraps in quotes', () {
      expect(Csv.field('say "hi"'), '"say ""hi"""');
    });

    test('quotes fields containing newlines', () {
      expect(Csv.field('line1\nline2'), '"line1\nline2"');
    });
  });

  group('Csv.row', () {
    test('joins fields with commas in given order', () {
      expect(Csv.row(['1', '2.5', null, 'x']), '1,2.5,,x');
    });
  });

  group('Csv.double', () {
    test('formats with trimmed decimals', () {
      expect(Csv.formatDouble(1.5), '1.5');
      expect(Csv.formatDouble(2.0), '2');
    });

    test('never uses scientific notation for small values', () {
      expect(Csv.formatDouble(1e-9), '0.000000001');
    });

    test('handles high-precision values', () {
      expect(Csv.formatDouble(0.1234567894), '0.123456789');
    });

    test('empty for null and non-finite', () {
      expect(Csv.formatDouble(null), '');
      expect(Csv.formatDouble(double.nan), '');
      expect(Csv.formatDouble(double.infinity), '');
    });

    test('normalizes negative zero', () {
      expect(Csv.formatDouble(-0.0), '0');
    });
  });

  group('Csv.int', () {
    test('formats integers, empty for null', () {
      expect(Csv.formatInt(1234567890123), '1234567890123');
      expect(Csv.formatInt(null), '');
    });
  });
}
