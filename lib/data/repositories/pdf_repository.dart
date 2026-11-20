import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/models/operation_result.dart';
import '../../domain/models/pdf_edit_overlay.dart';
import '../../domain/models/pdf_file_info.dart';
import '../../domain/models/pdf_rotation.dart';
import '../../domain/models/split_mode.dart';
import '../../domain/utils/file_format_utils.dart';
import '../services/file_dialog_service.dart';
import '../services/pdf_engine_service.dart';
import '../services/pdf_to_docx_service.dart';

/// Coordinates PDF file inspection, manipulation, conversion, and OS dialogs.
class PdfRepository {
  /// Creates a [PdfRepository].
  PdfRepository({
    required this._engineService,
    required this._dialogService,
    PdfToDocxService? pdfToDocxService,
  }) : _pdfToDocxService = pdfToDocxService ?? WordComPdfToDocxService();

  final PdfEngineService _engineService;
  final FileDialogService _dialogService;
  final PdfToDocxService _pdfToDocxService;

  /// Prompts the user to select one PDF file.
  Future<String?> pickPdfFile() => _dialogService.pickPdfFile();

  /// Prompts the user to select multiple PDF files.
  Future<List<String>> pickPdfFiles() => _dialogService.pickPdfFiles();

  /// Prompts the user to select an image file to insert onto a PDF page.
  Future<String?> pickImageFile() => _dialogService.pickImageFile();

  /// Prompts the user for a destination PDF file path.
  Future<String?> pickSavePdfPath({required String suggestedName}) =>
      _dialogService.pickSavePdfPath(suggestedName: suggestedName);

  /// Prompts the user for a destination DOCX file path.
  Future<String?> pickSaveDocxPath({required String suggestedName}) =>
      _dialogService.pickSaveDocxPath(suggestedName: suggestedName);

  /// Prompts the user for an output directory.
  Future<String?> pickOutputDirectory({String? confirmButtonText}) =>
      _dialogService.pickOutputDirectory(confirmButtonText: confirmButtonText);

  /// Reveals [path] in the OS file explorer.
  Future<void> revealInFileManager(String path) =>
      _dialogService.revealInFileManager(path);

  /// Checks whether local PDF-to-DOCX conversion is available.
  Future<bool> isDocxConversionAvailable() => _pdfToDocxService.isAvailable();

  /// Reads page count and size metadata for a PDF at [filePath].
  Future<PdfFileInfo> inspectFile(String filePath) =>
      _engineService.inspectFile(filePath);

  /// Reads page dimensions (in PDF points) for each page of [filePath].
  Future<List<PdfPageSize>> readPageSizes(String filePath) =>
      _engineService.readPageSizes(filePath);

  /// Reads the raw PDF bytes at [filePath], or `null` when unavailable.
  Future<Uint8List?> readPdfBytes(String filePath) =>
      _engineService.readPdfBytes(filePath);

  /// Merges [sources] into [outputPath].
  Future<PdfOperationResult> mergePdfs({
    required List<MergeSourceSpec> sources,
    required String outputPath,
  }) =>
      _engineService.mergePdfs(sources: sources, outputPath: outputPath);

  /// Rotates pages of [inputPath] according to [pageRotations] and saves to [outputPath].
  Future<PdfOperationResult> rotatePdf({
    required String inputPath,
    required Map<int, RotationQuarterTurns> pageRotations,
    required String outputPath,
  }) =>
      _engineService.rotatePdf(
        inputPath: inputPath,
        pageRotations: pageRotations,
        outputPath: outputPath,
      );

  /// Splits [inputPath] into [groups].
  Future<PdfOperationResult> splitPdf({
    required String inputPath,
    required List<SplitGroup> groups,
    required String outputDirectory,
    String? singleOutputFilePath,
    PdfProgressCallback? onProgress,
  }) =>
      _engineService.splitPdf(
        inputPath: inputPath,
        groups: groups,
        outputDirectory: outputDirectory,
        singleOutputFilePath: singleOutputFilePath,
        onProgress: onProgress,
      );

  /// Applies edit [overlays] to [inputPath] and writes the PDF to [outputPath].
  Future<PdfOperationResult> applyEdits({
    required String inputPath,
    required List<PdfEditOverlay> overlays,
    required String outputPath,
  }) =>
      _engineService.applyEdits(
        inputPath: inputPath,
        overlays: overlays,
        outputPath: outputPath,
      );

  /// Converts one or more PDF [files] into `.docx` documents.
  Future<PdfOperationResult> convertPdfsToDocx({
    required List<PdfFileInfo> files,
    required String outputDirectory,
    String? singleOutputFilePath,
    PdfProgressCallback? onProgress,
  }) async {
    if (files.isEmpty) {
      throw const PdfOperationException(
        'Tidak ada file PDF yang dipilih untuk dikonversi.',
      );
    }

    final outputPaths = <String>[];
    final usedFileNames = <String>{};
    var totalPages = 0;

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final targetPath = files.length == 1 && singleOutputFilePath != null
          ? ensureDocxExtension(p.normalize(singleOutputFilePath))
          : p.join(
              p.normalize(outputDirectory),
              _allocateUniqueDocxName(file.fileName, usedFileNames),
            );

      final createdPath = await _pdfToDocxService.convertPdfToDocx(
        inputPath: file.path,
        outputPath: targetPath,
      );
      outputPaths.add(createdPath);
      totalPages += file.pageCount;
      onProgress?.call(i + 1, files.length);
    }

    final message = outputPaths.length == 1
        ? 'Berhasil mengonversi ${p.basename(files.first.fileName)} ($totalPages halaman) ke ${p.basename(outputPaths.first)}.'
        : 'Berhasil mengonversi ${outputPaths.length} file PDF ($totalPages halaman) ke DOCX.';

    return PdfOperationResult(
      outputPaths: outputPaths,
      totalPagesProcessed: totalPages,
      message: message,
    );
  }

  String _allocateUniqueDocxName(String pdfFileName, Set<String> usedNames) {
    final baseName = buildDocxFileName(pdfFileName);
    final lowerBase = baseName.toLowerCase();
    if (usedNames.add(lowerBase)) {
      return baseName;
    }

    final stem = p.basenameWithoutExtension(baseName);
    var suffix = 2;
    while (true) {
      final candidate = '${stem}_$suffix.docx';
      if (usedNames.add(candidate.toLowerCase())) {
        return candidate;
      }
      suffix++;
    }
  }
}
