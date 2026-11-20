import 'package:path/path.dart' as p;

/// Returns `true` if [filePath] has a `.pdf` extension (case-insensitive).
bool isPdfPath(String filePath) {
  if (filePath.trim().isEmpty) return false;
  return p.extension(filePath).toLowerCase() == '.pdf';
}

/// Appends `.pdf` to [filePath] if it does not already end with a `.pdf` extension.
String ensurePdfExtension(String filePath) =>
    _ensureExtension(filePath, '.pdf');

/// Appends `.docx` to [filePath] if it does not already end with a `.docx` extension.
String ensureDocxExtension(String filePath) =>
    _ensureExtension(filePath, '.docx');

String _ensureExtension(String filePath, String extension) {
  final trimmed = filePath.trim();
  if (trimmed.isEmpty) return trimmed;
  if (p.extension(trimmed).toLowerCase() == extension.toLowerCase()) {
    return trimmed;
  }
  return '$trimmed$extension';
}

/// Builds a sanitized `.docx` filename from a source [pdfFileName].
String buildDocxFileName(String pdfFileName) {
  final stem = sanitizeFileNamePrefix(p.basenameWithoutExtension(pdfFileName));
  return '$stem.docx';
}

/// Builds a sanitized `_edited.pdf` filename from a source [pdfFileName].
String buildEditedPdfFileName(String pdfFileName) {
  final stem = sanitizeFileNamePrefix(p.basenameWithoutExtension(pdfFileName));
  return '${stem}_edited.pdf';
}

/// Formats a byte count into a readable string (B, KB, MB, or GB).
String formatFileSize(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

/// Strips Windows/POSIX invalid filename characters from [raw] and falls back
/// to `'split'` when nothing usable remains.
String sanitizeFileNamePrefix(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._\s]+|[._\s]+$'), '');
  return cleaned.isEmpty ? 'split' : cleaned;
}

/// Generates a deterministic, filesystem-safe filename for a split output part.
///
/// [partIndex] is 1-based (`1..totalParts`).
String buildSplitFileName(
  String prefix,
  int partIndex,
  int totalParts,
  List<int> pages,
) {
  final safePrefix = sanitizeFileNamePrefix(prefix);
  final padWidth = totalParts.toString().length.clamp(2, 4);
  final partPadded = partIndex.toString().padLeft(padWidth, '0');

  if (pages.isEmpty) {
    return '${safePrefix}_part_$partPadded.pdf';
  }

  final isContiguousSinglePage = pages.length == 1;
  if (isContiguousSinglePage && totalParts > 1 && pages.first == partIndex) {
    final pagePadded = pages.first.toString().padLeft(
          totalParts.toString().length.clamp(3, 5),
          '0',
        );
    return '${safePrefix}_hal_$pagePadded.pdf';
  }

  final rangeSuffix = _compactPageSummary(pages);
  return '${safePrefix}_part_${partPadded}_hal_$rangeSuffix.pdf';
}

String _compactPageSummary(List<int> pages) {
  if (pages.length == 1) {
    return '${pages.first}';
  }

  var isContiguous = true;
  for (var i = 1; i < pages.length; i++) {
    if (pages[i] != pages[i - 1] + 1) {
      isContiguous = false;
      break;
    }
  }
  if (isContiguous) {
    return '${pages.first}-${pages.last}';
  }
  if (pages.length <= 3) {
    return pages.join('-');
  }
  return '${pages.first}-${pages.last}_${pages.length}h';
}
