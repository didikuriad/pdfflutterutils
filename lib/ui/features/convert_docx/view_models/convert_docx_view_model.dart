import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';

/// ViewModel managing the PDF to DOCX conversion workspace.
class ConvertDocxViewModel extends ChangeNotifier {
  /// Creates a [ConvertDocxViewModel].
  ConvertDocxViewModel({required this._repository});

  final PdfRepository _repository;

  final List<PdfFileInfo> _items = <PdfFileInfo>[];
  bool? _isWordAvailable;
  bool _isProcessing = false;
  double? _progress;
  String? _statusDetail;
  String? _errorMessage;
  PdfOperationResult? _lastResult;
  bool _disposed = false;

  /// Ordered list of queued PDF documents to convert.
  List<PdfFileInfo> get items => List<PdfFileInfo>.unmodifiable(_items);

  /// Cached availability of Microsoft Word COM on Windows (`null` if unchecked).
  bool? get isWordAvailable => _isWordAvailable;

  /// Whether file inspection or Word COM conversion is currently running.
  bool get isProcessing => _isProcessing;

  /// Conversion progress in `[0.0, 1.0]`, or `null` when idle.
  double? get progress => _progress;

  /// Live status text during batch conversion.
  String? get statusDetail => _statusDetail;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed conversion result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Total page count across all queued PDF files.
  int get totalPages =>
      _items.fold<int>(0, (sum, item) => sum + item.pageCount);

  /// Whether conversion can currently be triggered.
  bool get canConvert =>
      _items.isNotEmpty && !_isProcessing && (_isWordAvailable ?? true);

  /// Checks whether Microsoft Word COM is available on the host.
  Future<void> checkAvailability() async {
    try {
      final available = await _repository.isDocxConversionAvailable();
      _isWordAvailable = available;
    } catch (_) {
      _isWordAvailable = false;
    }
    _safeNotify();
  }

  /// Opens the native multi-file picker and appends any chosen PDFs.
  Future<void> pickAndAddFiles() async {
    if (_isProcessing) return;
    final paths = await _repository.pickPdfFiles();
    if (paths.isEmpty) return;
    await addFilesFromPaths(paths);
  }

  /// Inspects and appends PDF files from [paths].
  Future<void> addFilesFromPaths(
    List<String> paths, {
    int ignoredNonPdfCount = 0,
  }) async {
    if (_isProcessing) return;

    final pdfPaths = paths.where(isPdfPath).toList(growable: false);
    final skippedNonPdf =
        ignoredNonPdfCount + (paths.length - pdfPaths.length);

    if (pdfPaths.isEmpty) {
      if (skippedNonPdf > 0) {
        _errorMessage =
            'Hanya file PDF yang didukung ($skippedNonPdf file bukan PDF dilewati).';
        _lastResult = null;
        _safeNotify();
      }
      return;
    }

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _safeNotify();

    final failedNames = <String>[];
    var addedCount = 0;

    try {
      for (final filePath in pdfPaths) {
        try {
          final info = await _repository.inspectFile(filePath);
          if (info.pageCount < 1) {
            failedNames.add('${info.fileName} (kosong)');
            continue;
          }
          _items.add(info);
          addedCount++;
        } on PdfOperationException catch (error) {
          failedNames.add(error.message);
        }
      }

      if (failedNames.isNotEmpty || skippedNonPdf > 0) {
        final notes = <String>[];
        if (skippedNonPdf > 0) {
          notes.add('$skippedNonPdf file bukan PDF dilewati');
        }
        if (failedNames.isNotEmpty) {
          notes.add(failedNames.join('; '));
        }
        if (addedCount > 0) {
          notes.insert(0, '$addedCount file ditambahkan');
        }
        _errorMessage = notes.join('. ');
      }
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  /// Removes item at [index].
  void removeAt(int index) {
    if (_isProcessing || index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    _safeNotify();
  }

  /// Clears all queued PDF files and status banners.
  void clearAll() {
    if (_isProcessing) return;
    _items.clear();
    _errorMessage = null;
    _lastResult = null;
    _progress = null;
    _statusDetail = null;
    _safeNotify();
  }

  /// Prompts for output location and converts all queued PDFs to `.docx`.
  Future<void> convertAndSave() async {
    if (_items.isEmpty || _isProcessing) return;

    if (_isWordAvailable == null) {
      await checkAvailability();
    }
    if (_isWordAvailable == false) {
      _errorMessage =
          'Microsoft Word tidak terdeteksi di komputer ini. Fitur ini membutuhkan Microsoft Word pada Windows.';
      _lastResult = null;
      _safeNotify();
      return;
    }

    final queuedFiles = List<PdfFileInfo>.unmodifiable(_items);
    String? singleOutputFilePath;
    String outputDirectory;

    if (queuedFiles.length == 1) {
      singleOutputFilePath = await _repository.pickSaveDocxPath(
        suggestedName: buildDocxFileName(queuedFiles.first.fileName),
      );
      if (singleOutputFilePath == null) return;
      outputDirectory = p.dirname(singleOutputFilePath);
    } else {
      final selectedDir = await _repository.pickOutputDirectory(
        confirmButtonText: 'Pilih Folder Output DOCX',
      );
      if (selectedDir == null) return;
      outputDirectory = selectedDir;
    }

    _isProcessing = true;
    _progress = 0;
    _statusDetail =
        'Mengonversi ${queuedFiles.first.fileName} (1/${queuedFiles.length})...';
    _errorMessage = null;
    _lastResult = null;
    _safeNotify();

    try {
      _lastResult = await _repository.convertPdfsToDocx(
        files: queuedFiles,
        outputDirectory: outputDirectory,
        singleOutputFilePath: singleOutputFilePath,
        onProgress: (completed, total) {
          _progress = total > 0 ? completed / total : null;
          if (completed < queuedFiles.length) {
            _statusDetail =
                'Mengonversi ${queuedFiles[completed].fileName} (${completed + 1}/$total)...';
          } else {
            _statusDetail = 'Menyelesaikan konversi...';
          }
          _safeNotify();
        },
      );
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan saat mengonversi PDF ke DOCX.';
    } finally {
      _isProcessing = false;
      _progress = null;
      _statusDetail = null;
      _safeNotify();
    }
  }

  /// Reveals the created `.docx` file or output directory in File Explorer.
  Future<void> openLastOutputFolder() async {
    final paths = _lastResult?.outputPaths;
    if (paths == null || paths.isEmpty) return;
    final target = paths.length == 1 ? paths.first : p.dirname(paths.first);
    await _repository.revealInFileManager(target);
  }

  /// Dismisses the active error or success banner.
  void dismissStatus() {
    if (_errorMessage == null && _lastResult == null) return;
    _errorMessage = null;
    _lastResult = null;
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
