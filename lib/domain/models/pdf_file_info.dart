/// Metadata for an inspected local PDF document.
class PdfFileInfo {
  /// Creates an immutable [PdfFileInfo].
  const PdfFileInfo({
    required this.path,
    required this.fileName,
    required this.pageCount,
    required this.fileSizeBytes,
  });

  /// Absolute or normalized path to the PDF file on disk.
  final String path;

  /// Base file name including extension (e.g., `dokumen.pdf`).
  final String fileName;

  /// Total number of pages in the PDF document.
  final int pageCount;

  /// Size of the file in bytes.
  final int fileSizeBytes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PdfFileInfo &&
        other.path == path &&
        other.fileName == fileName &&
        other.pageCount == pageCount &&
        other.fileSizeBytes == fileSizeBytes;
  }

  @override
  int get hashCode => Object.hash(path, fileName, pageCount, fileSizeBytes);
}
