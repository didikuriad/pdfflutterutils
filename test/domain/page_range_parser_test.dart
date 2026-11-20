import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/utils/page_range_parser.dart';

void main() {
  group('parsePageList', () {
    test('returns all pages when input is empty or whitespace', () {
      expect(parsePageList('', maxPages: 4), equals(<int>[1, 2, 3, 4]));
      expect(parsePageList('   ', maxPages: 3), equals(<int>[1, 2, 3]));
    });

    test('parses single pages and inclusive ranges in order', () {
      expect(
        parsePageList('1-3, 5, 7-9', maxPages: 10),
        equals(<int>[1, 2, 3, 5, 7, 8, 9]),
      );
      expect(
        parsePageList('4, 2-3', maxPages: 5),
        equals(<int>[4, 2, 3]),
      );
    });

    test('throws FormatException for invalid syntax or out-of-bounds pages', () {
      expect(() => parsePageList('0-2', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('1-6', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('4-2', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('1, , 3', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('abc', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('1-2-3', maxPages: 5), throwsFormatException);
      expect(() => parsePageList('', maxPages: 0), throwsFormatException);
    });
  });

  group('parseSplitRangeGroups', () {
    test('splits each comma-separated token into a separate group', () {
      expect(
        parseSplitRangeGroups('1-3, 4-6, 7', maxPages: 8),
        equals(<List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
          <int>[7],
        ]),
      );
    });

    test('rejects empty or invalid range input', () {
      expect(
        () => parseSplitRangeGroups('', maxPages: 5),
        throwsFormatException,
      );
      expect(
        () => parseSplitRangeGroups('   ', maxPages: 5),
        throwsFormatException,
      );
      expect(
        () => parseSplitRangeGroups('1-3,', maxPages: 5),
        throwsFormatException,
      );
      expect(
        () => parseSplitRangeGroups('3-9', maxPages: 5),
        throwsFormatException,
      );
    });
  });

  group('buildEveryPageGroups', () {
    test('creates one single-page group per page', () {
      expect(
        buildEveryPageGroups(3),
        equals(<List<int>>[
          <int>[1],
          <int>[2],
          <int>[3],
        ]),
      );
    });

    test('throws when maxPages < 1', () {
      expect(() => buildEveryPageGroups(0), throwsFormatException);
    });
  });

  group('buildFixedChunkGroups', () {
    test('chunks pages into fixed sizes with smaller trailing remainder', () {
      expect(
        buildFixedChunkGroups(7, 3),
        equals(<List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
          <int>[7],
        ]),
      );
      expect(
        buildFixedChunkGroups(4, 5),
        equals(<List<int>>[
          <int>[1, 2, 3, 4],
        ]),
      );
    });

    test('rejects chunkSize < 1', () {
      expect(() => buildFixedChunkGroups(5, 0), throwsFormatException);
    });
  });

  group('formatPagesAsRange', () {
    test('compacts sorted unique pages into range syntax', () {
      expect(formatPagesAsRange(<int>[]), equals(''));
      expect(
        formatPagesAsRange(<int>[5, 1, 3, 2, 7, 8, 5]),
        equals('1-3, 5, 7-8'),
      );
      expect(formatPagesAsRange(<int>[4]), equals('4'));
    });
  });
}
