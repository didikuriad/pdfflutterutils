/// Result returned after a PDF merge, rotate, or split operation completes.
class PdfOperationResult {
  /// Creates an immutable [PdfOperationResult].
  const PdfOperationResult({
    required this.outputPaths,
    required this.totalPagesProcessed,
    required this.message,
  });

  /// Paths to all output PDF files created on disk.
  final List<String> outputPaths;

  /// Total number of pages processed into the output file(s).
  final int totalPagesProcessed;

  /// Human-readable Indonesian summary of the completed operation.
  final String message;
}

/// Exception thrown when inspecting or manipulating a PDF fails.
class PdfOperationException implements Exception {
  /// Creates a [PdfOperationException] with an Indonesian user-facing [message].
  const PdfOperationException(this.message, [this.cause]);

  /// Clear user-facing description of the error.
  final String message;

  /// Optional underlying exception or error object for diagnostics.
  final Object? cause;

  @override
  String toString() => message;
}
