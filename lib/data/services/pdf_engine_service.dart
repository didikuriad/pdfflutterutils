import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models/operation_result.dart';
import '../../domain/models/pdf_edit_overlay.dart';
import '../../domain/models/pdf_file_info.dart';
import '../../domain/models/pdf_rotation.dart';
import '../../domain/models/split_mode.dart';
import '../../domain/utils/file_format_utils.dart';
import 'pdfium_overlay_writer.dart';

/// Specification for one input document and its selected 1-based pages during merge.
class MergeSourceSpec {
  /// Creates a [MergeSourceSpec].
  const MergeSourceSpec({
    required this.filePath,
    required this.oneBasedPages,
  });

  /// Path to the source PDF file.
  final String filePath;

  /// Ordered 1-based page numbers to include from [filePath].
  final List<int> oneBasedPages;
}

/// Callback reporting progress `(completed, total)` during multi-part PDF operations.
typedef PdfProgressCallback = void Function(int completed, int total);

/// Abstraction for inspecting and manipulating PDF files.
abstract class PdfEngineService {
  /// Reads page count and file size metadata for [filePath].
  Future<PdfFileInfo> inspectFile(String filePath);

  /// Reads the visual page dimensions (in PDF points) for each page in [filePath].
  Future<List<PdfPageSize>> readPageSizes(String filePath);

  /// Reads the raw bytes of a PDF file at [filePath], or `null` if unavailable.
  Future<Uint8List?> readPdfBytes(String filePath);

  /// Merges [sources] in order and writes the resulting PDF to [outputPath].
  Future<PdfOperationResult> mergePdfs({
    required List<MergeSourceSpec> sources,
    required String outputPath,
  });

  /// Applies [pageRotations] (keyed by 1-based page number) to [inputPath] and
  /// saves the result to [outputPath].
  Future<PdfOperationResult> rotatePdf({
    required String inputPath,
    required Map<int, RotationQuarterTurns> pageRotations,
    required String outputPath,
  });

  /// Splits [inputPath] into [groups].
  ///
  /// When [singleOutputFilePath] is provided (for single-group extraction),
  /// writes directly to that file path; otherwise writes each group into
  /// [outputDirectory] using each group's `suggestedFileName`.
  Future<PdfOperationResult> splitPdf({
    required String inputPath,
    required List<SplitGroup> groups,
    required String outputDirectory,
    String? singleOutputFilePath,
    PdfProgressCallback? onProgress,
  });

  /// Embeds [overlays] onto pages of [inputPath] and saves the PDF to [outputPath].
  Future<PdfOperationResult> applyEdits({
    required String inputPath,
    required List<PdfEditOverlay> overlays,
    required String outputPath,
  });
}

/// [PdfEngineService] backed by `pdfrx` (PDFium).
class PdfrxPdfEngineService implements PdfEngineService {
  @override
  Future<PdfFileInfo> inspectFile(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw PdfOperationException(
        'File tidak ditemukan: ${p.basename(normalizedPath)}',
      );
    }

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(normalizedPath);
      final fileSize = await file.length();
      return PdfFileInfo(
        path: normalizedPath,
        fileName: p.basename(normalizedPath),
        pageCount: document.pages.length,
        fileSizeBytes: fileSize,
      );
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal membaca PDF "${p.basename(normalizedPath)}".',
      );
    } finally {
      await document?.dispose();
    }
  }

  @override
  Future<List<PdfPageSize>> readPageSizes(String filePath) async {
    final normalizedPath = p.normalize(filePath);
    if (!await File(normalizedPath).exists()) {
      throw PdfOperationException(
        'File tidak ditemukan: ${p.basename(normalizedPath)}',
      );
    }

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(normalizedPath);
      return <PdfPageSize>[
        for (final page in document.pages)
          PdfPageSize(width: page.width, height: page.height),
      ];
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal membaca ukuran halaman "${p.basename(normalizedPath)}".',
      );
    } finally {
      await document?.dispose();
    }
  }

  @override
  Future<Uint8List?> readPdfBytes(String filePath) async {
    final file = File(p.normalize(filePath));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<PdfOperationResult> mergePdfs({
    required List<MergeSourceSpec> sources,
    required String outputPath,
  }) async {
    if (sources.isEmpty) {
      throw const PdfOperationException('Tidak ada file PDF untuk digabungkan.');
    }

    final normalizedOutput = ensurePdfExtension(p.normalize(outputPath));
    final openedDocs = <String, PdfDocument>{};
    PdfDocument? outputDoc;
    late final Uint8List encodedBytes;
    var totalPages = 0;

    try {
      outputDoc = await PdfDocument.createNew(
        sourceName: 'merge_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      final assembledPages = <PdfPage>[];

      for (final spec in sources) {
        final normalizedInput = p.normalize(spec.filePath);
        final canonicalKey = p.canonicalize(normalizedInput);
        var sourceDoc = openedDocs[canonicalKey];
        if (sourceDoc == null) {
          if (!await File(normalizedInput).exists()) {
            throw PdfOperationException(
              'File sumber tidak ditemukan: ${p.basename(normalizedInput)}',
            );
          }
          sourceDoc = await PdfDocument.openFile(normalizedInput);
          openedDocs[canonicalKey] = sourceDoc;
        }

        final pageCount = sourceDoc.pages.length;
        for (final pageNum in spec.oneBasedPages) {
          if (pageNum < 1 || pageNum > pageCount) {
            throw PdfOperationException(
              'Halaman $pageNum tidak tersedia di "${p.basename(normalizedInput)}" (total $pageCount halaman).',
            );
          }
          assembledPages.add(sourceDoc.pages[pageNum - 1]);
          totalPages++;
        }
      }

      if (assembledPages.isEmpty) {
        throw const PdfOperationException(
          'Minimal satu halaman harus dipilih untuk digabungkan.',
        );
      }

      outputDoc.pages = assembledPages;
      encodedBytes = await outputDoc.encodePdf();
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal menggabungkan file PDF.',
      );
    } finally {
      // Dispose all PDFium handles before writing output to avoid Windows file locks.
      await outputDoc?.dispose();
      for (final doc in openedDocs.values) {
        await doc.dispose();
      }
    }

    await _writePdfBytes(normalizedOutput, encodedBytes);
    return PdfOperationResult(
      outputPaths: <String>[normalizedOutput],
      totalPagesProcessed: totalPages,
      message:
          'Berhasil menggabungkan ${sources.length} file ($totalPages halaman) ke ${p.basename(normalizedOutput)}.',
    );
  }

  @override
  Future<PdfOperationResult> rotatePdf({
    required String inputPath,
    required Map<int, RotationQuarterTurns> pageRotations,
    required String outputPath,
  }) async {
    final normalizedInput = p.normalize(inputPath);
    final normalizedOutput = ensurePdfExtension(p.normalize(outputPath));
    if (!await File(normalizedInput).exists()) {
      throw PdfOperationException(
        'File sumber tidak ditemukan: ${p.basename(normalizedInput)}',
      );
    }

    PdfDocument? sourceDoc;
    PdfDocument? outputDoc;
    late final Uint8List encodedBytes;
    var pageCount = 0;

    try {
      sourceDoc = await PdfDocument.openFile(normalizedInput);
      pageCount = sourceDoc.pages.length;
      outputDoc = await PdfDocument.createNew(
        sourceName: 'rotate_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );

      final updatedPages = <PdfPage>[];
      for (var i = 0; i < pageCount; i++) {
        final pageNumber = i + 1;
        final basePage = sourceDoc.pages[i];
        final delta = pageRotations[pageNumber] ?? RotationQuarterTurns.deg0;
        updatedPages.add(_applyRotation(basePage, delta));
      }

      outputDoc.pages = updatedPages;
      encodedBytes = await outputDoc.encodePdf();
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal memutar halaman PDF "${p.basename(normalizedInput)}".',
      );
    } finally {
      await outputDoc?.dispose();
      await sourceDoc?.dispose();
    }

    await _writePdfBytes(normalizedOutput, encodedBytes);
    final rotatedCount = pageRotations.entries
        .where((entry) =>
            entry.key >= 1 && entry.key <= pageCount && entry.value.isRotated)
        .length;

    return PdfOperationResult(
      outputPaths: <String>[normalizedOutput],
      totalPagesProcessed: pageCount,
      message:
          'Berhasil menyimpan ${p.basename(normalizedOutput)} ($rotatedCount halaman diputar dari total $pageCount halaman).',
    );
  }

  @override
  Future<PdfOperationResult> splitPdf({
    required String inputPath,
    required List<SplitGroup> groups,
    required String outputDirectory,
    String? singleOutputFilePath,
    PdfProgressCallback? onProgress,
  }) async {
    if (groups.isEmpty) {
      throw const PdfOperationException(
        'Tidak ada bagian halaman yang dipilih untuk dipisah.',
      );
    }

    final normalizedInput = p.normalize(inputPath);
    if (!await File(normalizedInput).exists()) {
      throw PdfOperationException(
        'File sumber tidak ditemukan: ${p.basename(normalizedInput)}',
      );
    }

    final canonicalInput = p.canonicalize(normalizedInput);
    final outputPaths = <String>[];
    final deferredWrites = <({String path, Uint8List bytes})>[];
    var totalPagesProcessed = 0;

    PdfDocument? sourceDoc;
    try {
      sourceDoc = await PdfDocument.openFile(normalizedInput);
      final sourcePageCount = sourceDoc.pages.length;
      final totalGroups = groups.length;

      for (var i = 0; i < totalGroups; i++) {
        final group = groups[i];
        if (group.pages.isEmpty) {
          throw PdfOperationException(
            '${group.label} tidak memiliki halaman.',
          );
        }

        final targetPath = singleOutputFilePath != null && totalGroups == 1
            ? ensurePdfExtension(p.normalize(singleOutputFilePath))
            : ensurePdfExtension(
                p.join(p.normalize(outputDirectory), group.suggestedFileName),
              );

        PdfDocument? partDoc;
        late final Uint8List encodedBytes;
        try {
          partDoc = await PdfDocument.createNew(
            sourceName:
                'split_${i}_${DateTime.now().microsecondsSinceEpoch}.pdf',
          );
          final selectedPages = <PdfPage>[];
          for (final pageNum in group.pages) {
            if (pageNum < 1 || pageNum > sourcePageCount) {
              throw PdfOperationException(
                'Halaman $pageNum di luar jumlah halaman dokumen (1-$sourcePageCount).',
              );
            }
            selectedPages.add(sourceDoc.pages[pageNum - 1]);
          }
          partDoc.pages = selectedPages;
          encodedBytes = await partDoc.encodePdf();
        } finally {
          await partDoc?.dispose();
        }

        if (p.canonicalize(targetPath) == canonicalInput) {
          deferredWrites.add((path: targetPath, bytes: encodedBytes));
        } else {
          await _writePdfBytes(targetPath, encodedBytes);
        }

        outputPaths.add(targetPath);
        totalPagesProcessed += group.pages.length;
        onProgress?.call(i + 1, totalGroups);
      }
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal memisahkan file PDF "${p.basename(normalizedInput)}".',
      );
    } finally {
      await sourceDoc?.dispose();
    }

    for (final pending in deferredWrites) {
      await _writePdfBytes(pending.path, pending.bytes);
    }

    final summary = outputPaths.length == 1
        ? 'Berhasil mengekstrak $totalPagesProcessed halaman ke ${p.basename(outputPaths.first)}.'
        : 'Berhasil memisah PDF menjadi ${outputPaths.length} file ($totalPagesProcessed halaman).';

    return PdfOperationResult(
      outputPaths: outputPaths,
      totalPagesProcessed: totalPagesProcessed,
      message: summary,
    );
  }

  @override
  Future<PdfOperationResult> applyEdits({
    required String inputPath,
    required List<PdfEditOverlay> overlays,
    required String outputPath,
  }) async {
    if (overlays.isEmpty) {
      throw const PdfOperationException(
        'Belum ada anotasi atau perubahan untuk disimpan.',
      );
    }

    final normalizedInput = p.normalize(inputPath);
    final normalizedOutput = ensurePdfExtension(p.normalize(outputPath));
    if (!await File(normalizedInput).exists()) {
      throw PdfOperationException(
        'File sumber tidak ditemukan: ${p.basename(normalizedInput)}',
      );
    }

    PdfDocument? sourceDoc;
    late final Uint8List encodedBytes;
    var touchedPages = 0;

    try {
      sourceDoc = await PdfDocument.openFile(normalizedInput);
      final pageCount = sourceDoc.pages.length;
      final uniquePages = <int>{};
      for (final overlay in overlays) {
        if (overlay.pageNumber < 1 || overlay.pageNumber > pageCount) {
          throw PdfOperationException(
            'Halaman ${overlay.pageNumber} tidak tersedia pada "${p.basename(normalizedInput)}".',
          );
        }
        uniquePages.add(overlay.pageNumber);
      }
      touchedPages = uniquePages.length;

      await applyOverlaysToPdfDocument(
        document: sourceDoc,
        overlays: overlays,
      );
      encodedBytes = await sourceDoc.encodePdf();
    } catch (error) {
      throw _mapError(
        error,
        fallback: 'Gagal menyimpan perubahan pada "${p.basename(normalizedInput)}".',
      );
    } finally {
      // Dispose before writing so overwriting the open source file succeeds on Windows.
      await sourceDoc?.dispose();
    }

    await _writePdfBytes(normalizedOutput, encodedBytes);
    return PdfOperationResult(
      outputPaths: <String>[normalizedOutput],
      totalPagesProcessed: touchedPages,
      message:
          'Berhasil menyimpan ${p.basename(normalizedOutput)} (${overlays.length} anotasi pada $touchedPages halaman).',
    );
  }

  PdfPage _applyRotation(PdfPage page, RotationQuarterTurns delta) {
    return switch (delta) {
      RotationQuarterTurns.deg0 => page,
      RotationQuarterTurns.deg90 => page.rotatedCW90(),
      RotationQuarterTurns.deg180 => page.rotated180(),
      RotationQuarterTurns.deg270 => page.rotatedCCW90(),
    };
  }

  Future<void> _writePdfBytes(String targetPath, Uint8List bytes) async {
    try {
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (error) {
      throw PdfOperationException(
        'Gagal menyimpan file "${p.basename(targetPath)}". Pastikan file tidak sedang dibuka di aplikasi lain.',
        error,
      );
    }
  }

  PdfOperationException _mapError(Object error, {required String fallback}) {
    if (error is PdfOperationException) return error;
    if (error is PdfPasswordException) {
      return PdfOperationException(
        'PDF dilindungi kata sandi dan tidak dapat diproses tanpa dekripsi.',
        error,
      );
    }
    if (error is PdfException) {
      final detail = error.message.trim();
      return PdfOperationException(
        detail.isEmpty ? fallback : '$fallback ($detail)',
        error,
      );
    }
    if (error is FileSystemException) {
      return PdfOperationException(
        'Kesalahan akses file: ${error.message}',
        error,
      );
    }
    return PdfOperationException(fallback, error);
  }
}
