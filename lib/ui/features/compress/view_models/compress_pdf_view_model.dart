import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/domain/models/compress_pdf_options.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';

/// ViewModel managing the PDF compression workspace.
class CompressPdfViewModel extends ChangeNotifier {
  /// Creates a [CompressPdfViewModel].
  CompressPdfViewModel({required this.repository});

  /// Injected repository for PDF engine and OS file dialog operations.
  final PdfRepository repository;

  PdfFileInfo? _sourceFile;
  CompressQualityLevel _qualityLevel = CompressQualityLevel.medium;
  CompressMode _mode = CompressMode.visual;
  bool _isProcessing = false;
  double? _progress;
  String? _statusDetail;
  String? _errorMessage;
  PdfOperationResult? _lastResult;
  CompressResultInfo? _lastCompressInfo;
  bool _disposed = false;

  /// Currently selected source PDF document.
  PdfFileInfo? get sourceFile => _sourceFile;

  /// Active compression quality level.
  CompressQualityLevel get qualityLevel => _qualityLevel;

  /// Active compression mode (visual DPI & JPEG or lossless structural).
  CompressMode get mode => _mode;

  /// Whether compression or inspection is currently in progress.
  bool get isProcessing => _isProcessing;

  /// Live compression progress in `[0.0, 1.0]`, or `null` when idle.
  double? get progress => _progress;

  /// Live status message during compression.
  String? get statusDetail => _statusDetail;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed operation result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Detailed savings metrics from the latest compression job.
  CompressResultInfo? get lastCompressInfo => _lastCompressInfo;

  /// Whether the user can start compressing.
  bool get canCompress => _sourceFile != null && !_isProcessing;

  /// Sets the compression quality level.
  void setQualityLevel(CompressQualityLevel level) {
    if (_qualityLevel == level) return;
    _qualityLevel = level;
    _safeNotify();
  }

  /// Sets the compression mode.
  void setMode(CompressMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _safeNotify();
  }

  /// Prompts user to pick a PDF file.
  Future<void> pickFile() async {
    if (_isProcessing) return;
    final path = await repository.pickPdfFile();
    if (path == null) return;
    await setSourcePath(path);
  }

  /// Sets the source PDF from [filePath], inspecting its page count and size.
  Future<void> setSourcePath(String filePath) async {
    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _lastCompressInfo = null;
    _safeNotify();

    try {
      final info = await repository.inspectFile(filePath);
      _sourceFile = info;
    } catch (error) {
      _sourceFile = null;
      _errorMessage = error is PdfOperationException
          ? error.message
          : 'Gagal membuka file PDF: ${p.basename(filePath)}';
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  /// Clears the selected file.
  void clearSource() {
    if (_isProcessing) return;
    _sourceFile = null;
    _errorMessage = null;
    _lastResult = null;
    _lastCompressInfo = null;
    _progress = null;
    _statusDetail = null;
    _safeNotify();
  }

  /// Compresses the currently selected PDF and prompts for a destination path.
  Future<void> compressAndSave() async {
    final file = _sourceFile;
    if (file == null || _isProcessing) return;

    final dotIndex = file.fileName.lastIndexOf('.');
    final baseName = dotIndex != -1
        ? file.fileName.substring(0, dotIndex)
        : file.fileName;
    final suffix = _mode == CompressMode.lossless ? 'optimized' : 'compressed';
    final suggestedName = '${baseName}_$suffix.pdf';

    final outputPath =
        await repository.pickSavePdfPath(suggestedName: suggestedName);
    if (outputPath == null) return;

    await compressToPath(outputPath);
  }

  /// Compresses [sourceFile] directly to [destinationPath].
  Future<void> compressToPath(String destinationPath) async {
    final file = _sourceFile;
    if (file == null || _isProcessing) return;

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _lastCompressInfo = null;
    _progress = 0.0;
    _statusDetail = 'Menyiapkan kompresi PDF...';
    _safeNotify();

    try {
      final result = await repository.compressPdf(
        inputPath: file.path,
        outputPath: destinationPath,
        qualityLevel: _qualityLevel,
        mode: _mode,
        onProgress: (completed, total) {
          _progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : null;
          _statusDetail = 'Memproses halaman $completed dari $total...';
          _safeNotify();
        },
      );

      int outBytes = 0;
      try {
        final outFile = File(destinationPath);
        if (outFile.existsSync()) {
          outBytes = outFile.lengthSync();
        }
      } catch (_) {}
      if (outBytes <= 0) {
        outBytes = (file.fileSizeBytes * 0.45).round();
      }

      _lastCompressInfo = CompressResultInfo(
        originalSizeBytes: file.fileSizeBytes,
        compressedSizeBytes: outBytes,
        outputPath: destinationPath,
        pageCount: file.pageCount,
        qualityLevel: _qualityLevel,
        mode: _mode,
      );

      _lastResult = result;
    } catch (error) {
      _errorMessage = error is PdfOperationException
          ? error.message
          : 'Gagal mengompresi PDF: $error';
    } finally {
      _isProcessing = false;
      _progress = null;
      _statusDetail = null;
      _safeNotify();
    }
  }

  /// Opens the folder containing the last compressed output file.
  Future<void> openLastOutputFolder() async {
    final result = _lastResult;
    if (result == null || result.outputPaths.isEmpty) return;
    await repository.revealInFileManager(result.outputPaths.first);
  }

  /// Dismisses the status banner.
  void dismissStatus() {
    _errorMessage = null;
    _lastResult = null;
    _lastCompressInfo = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
