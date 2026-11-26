/// Preset levels for PDF compression.
enum CompressQualityLevel {
  /// Low compression (highest quality, ~150 DPI, JPEG 82%).
  /// Crisp visual quality, ideal for documents with fine graphics and printing.
  low(
    label: 'Rendah (Kualitas Tinggi)',
    badge: 'Kualitas Tinggi',
    description: 'Visual sangat tajam, cocok untuk berkas penting & cetak.',
    targetDpi: 150,
    jpegQuality: 82,
  ),

  /// Medium compression (balanced, ~120 DPI, JPEG 72%).
  /// Recommended standard for general distribution, WhatsApp, and email.
  medium(
    label: 'Sedang (Rekomendasi)',
    badge: 'Rekomendasi',
    description: 'Keseimbangan terbaik antara ukuran file dan kejernihan.',
    targetDpi: 120,
    jpegQuality: 72,
  ),

  /// High compression (maximum reduction, ~96 DPI, JPEG 55%).
  /// Aggressive compression for strict upload limits (CPNS, BUMN, jobs).
  high(
    label: 'Tinggi (Ukuran Minimum)',
    badge: 'Ukuran Minimum',
    description: 'Ukuran file sekecil mungkin untuk batas upload ketat.',
    targetDpi: 96,
    jpegQuality: 55,
  );

  const CompressQualityLevel({
    required this.label,
    required this.badge,
    required this.description,
    required this.targetDpi,
    required this.jpegQuality,
  });

  /// Indonesian display label.
  final String label;

  /// Short badge title.
  final String badge;

  /// User-friendly explanation of trade-off.
  final String description;

  /// Target rasterization DPI.
  final int targetDpi;

  /// JPEG compression quality percentage (1-100).
  final int jpegQuality;
}

/// Compression mode for PDF processing.
enum CompressMode {
  /// Compresses images and rasterizes pages with the selected DPI & JPEG quality.
  visual(
    label: 'Kompresi Ukuran (DPI & Gambar)',
    description: 'Mengompresi dan menyesuaikan resolusi gambar/halaman.',
  ),

  /// Lossless structural optimization (compacts xref, removes dead streams without altering pixels).
  lossless(
    label: 'Optimalisasi Lossless (Struktur Dokumen)',
    description: 'Menata ulang objek dan stream tanpa mengubah piksel sedikit pun.',
  );

  const CompressMode({
    required this.label,
    required this.description,
  });

  /// Indonesian display label.
  final String label;

  /// Description of the mode behavior.
  final String description;
}

/// Details of a finished compression job.
class CompressResultInfo {
  /// Creates a [CompressResultInfo].
  const CompressResultInfo({
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.outputPath,
    required this.pageCount,
    required this.qualityLevel,
    required this.mode,
  });

  /// Original file size in bytes.
  final int originalSizeBytes;

  /// Compressed file size in bytes.
  final int compressedSizeBytes;

  /// Destination file path.
  final String outputPath;

  /// Total pages in document.
  final int pageCount;

  /// Quality level used.
  final CompressQualityLevel qualityLevel;

  /// Compression mode used.
  final CompressMode mode;

  /// Bytes saved (`original - compressed`), or 0 if file did not shrink.
  int get bytesSaved {
    final diff = originalSizeBytes - compressedSizeBytes;
    return diff > 0 ? diff : 0;
  }

  /// Percentage saved (0.0 to 100.0).
  double get savingsPercent {
    if (originalSizeBytes <= 0) return 0.0;
    final diff = originalSizeBytes - compressedSizeBytes;
    if (diff <= 0) return 0.0;
    return (diff / originalSizeBytes) * 100.0;
  }

  /// Whether the file actually shrunk in size.
  bool get didReduceSize => compressedSizeBytes < originalSizeBytes;
}
