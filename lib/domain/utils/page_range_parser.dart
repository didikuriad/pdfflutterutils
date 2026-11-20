/// Parses and formats 1-based PDF page range expressions.
///
/// Supported syntax examples:
/// - `1-3` -> `[1, 2, 3]`
/// - `1-3, 5, 7-9` -> `[1, 2, 3, 5, 7, 8, 9]`
///
/// All functions throw [FormatException] with Indonesian messages when input
/// violates syntax or page bounds.
library;

/// Parses a comma-separated list of 1-based page numbers or ranges into an
/// ordered flat list of page indices.
///
/// When [input] is empty or contains only whitespace, returns all pages
/// `[1, 2, ..., maxPages]`.
List<int> parsePageList(String input, {required int maxPages}) {
  if (maxPages < 1) {
    throw const FormatException('Dokumen tidak memiliki halaman.');
  }

  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return List<int>.generate(maxPages, (index) => index + 1);
  }

  final groups = parseSplitRangeGroups(trimmed, maxPages: maxPages);
  return <int>[for (final group in groups) ...group];
}

/// Parses a comma-separated split specification where each token becomes one
/// output group of 1-based page numbers (e.g., `"1-3, 4-6, 7"`).
///
/// Throws [FormatException] if [input] is empty or contains invalid tokens.
List<List<int>> parseSplitRangeGroups(String input, {required int maxPages}) {
  if (maxPages < 1) {
    throw const FormatException('Dokumen tidak memiliki halaman.');
  }

  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException(
      'Masukkan rentang halaman, misalnya: 1-3, 4-6',
    );
  }

  final rawTokens = trimmed.split(',');
  final groups = <List<int>>[];

  for (final rawToken in rawTokens) {
    final token = rawToken.trim();
    if (token.isEmpty) {
      throw const FormatException(
        'Format rentang tidak valid: ditemukan tanda koma berlebih.',
      );
    }

    groups.add(_parseRangeToken(token, maxPages: maxPages));
  }

  return groups;
}

List<int> _parseRangeToken(String token, {required int maxPages}) {
  if (token.contains('-')) {
    final parts = token.split('-');
    if (parts.length != 2 ||
        parts[0].trim().isEmpty ||
        parts[1].trim().isEmpty) {
      throw FormatException('Format rentang tidak valid: "$token".');
    }

    final start = int.tryParse(parts[0].trim());
    final end = int.tryParse(parts[1].trim());
    if (start == null || end == null) {
      throw FormatException('Nomor halaman harus berupa angka: "$token".');
    }

    if (start < 1 || end > maxPages) {
      throw FormatException(
        'Rentang "$token" di luar jumlah halaman (1-$maxPages).',
      );
    }

    if (start > end) {
      throw FormatException(
        'Halaman awal harus lebih kecil atau sama dengan akhir pada "$token".',
      );
    }

    return List<int>.generate(end - start + 1, (offset) => start + offset);
  }

  final page = int.tryParse(token);
  if (page == null) {
    throw FormatException('Nomor halaman tidak valid: "$token".');
  }
  if (page < 1 || page > maxPages) {
    throw FormatException(
      'Halaman $page di luar jumlah halaman dokumen (1-$maxPages).',
    );
  }
  return <int>[page];
}

/// Builds one output group per page: `[[1], [2], ..., [maxPages]]`.
List<List<int>> buildEveryPageGroups(int maxPages) {
  if (maxPages < 1) {
    throw const FormatException('Dokumen tidak memiliki halaman.');
  }
  return List<List<int>>.generate(maxPages, (index) => <int>[index + 1]);
}

/// Splits `1..maxPages` into sequential groups of at most [chunkSize] pages.
List<List<int>> buildFixedChunkGroups(int maxPages, int chunkSize) {
  if (maxPages < 1) {
    throw const FormatException('Dokumen tidak memiliki halaman.');
  }
  if (chunkSize < 1) {
    throw const FormatException('Jumlah halaman per file minimal 1.');
  }

  final groups = <List<int>>[];
  for (var start = 1; start <= maxPages; start += chunkSize) {
    final end = (start + chunkSize - 1).clamp(1, maxPages);
    groups.add(
      List<int>.generate(end - start + 1, (offset) => start + offset),
    );
  }
  return groups;
}

/// Formats a collection of 1-based page numbers into a compact range string
/// such as `"1-3, 5, 7-8"`.
String formatPagesAsRange(Iterable<int> pages) {
  final sorted = pages.where((page) => page >= 1).toSet().toList()..sort();
  if (sorted.isEmpty) {
    return '';
  }

  final segments = <String>[];
  var rangeStart = sorted.first;
  var rangeEnd = sorted.first;

  for (var i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    if (current == rangeEnd + 1) {
      rangeEnd = current;
    } else {
      segments.add(_formatSegment(rangeStart, rangeEnd));
      rangeStart = current;
      rangeEnd = current;
    }
  }
  segments.add(_formatSegment(rangeStart, rangeEnd));
  return segments.join(', ');
}

String _formatSegment(int start, int end) {
  return start == end ? '$start' : '$start-$end';
}
