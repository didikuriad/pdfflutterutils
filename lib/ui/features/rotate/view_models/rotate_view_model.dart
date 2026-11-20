import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';

/// ViewModel managing the PDF Rotate workspace.
class RotateViewModel extends ChangeNotifier {
  /// Creates a [RotateViewModel].
  RotateViewModel({required this._repository});

  final PdfRepository _repository;

  PdfFileInfo? _sourceFile;
  final Map<int, RotationQuarterTurns> _pageRotations =
      <int, RotationQuarterTurns>{};
  final Set<int> _selectedPages = <int>{};
  bool _isProcessing = false;
  String? _errorMessage;
  PdfOperationResult? _lastResult;

  /// Currently loaded PDF metadata, or `null` when none is loaded.
  PdfFileInfo? get sourceFile => _sourceFile;

  /// Pending relative clockwise rotation per 1-based page number.
  Map<int, RotationQuarterTurns> get pageRotations =>
      Map<int, RotationQuarterTurns>.unmodifiable(_pageRotations);

  /// Currently selected 1-based page numbers for bulk rotation.
  Set<int> get selectedPages => Set<int>.unmodifiable(_selectedPages);

  /// Whether a file inspection or save operation is running.
  bool get isProcessing => _isProcessing;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed save result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Number of pages that currently have a non-zero pending rotation.
  int get rotatedPagesCount =>
      _pageRotations.values.where((rotation) => rotation.isRotated).length;

  /// Whether at least one page has a pending rotation.
  bool get hasChanges => rotatedPagesCount > 0;

  /// Whether the loaded PDF can be saved right now.
  bool get canSave => _sourceFile != null && !_isProcessing;

  /// Returns the pending rotation for 1-based [pageNumber].
  RotationQuarterTurns rotationForPage(int pageNumber) =>
      _pageRotations[pageNumber] ?? RotationQuarterTurns.deg0;

  /// Opens the native single-file picker and loads the chosen PDF.
  Future<void> pickFile() async {
    if (_isProcessing) return;
    final path = await _repository.pickPdfFile();
    if (path == null) return;
    await loadFile(path);
  }

  /// Handles dropped paths on the Rotate workspace, loading the first valid PDF.
  Future<void> loadFromDroppedPaths(
    List<String> paths, {
    int ignoredNonPdfCount = 0,
  }) async {
    if (_isProcessing) return;
    final pdfPaths = paths.where(isPdfPath).toList(growable: false);
    if (pdfPaths.isEmpty) {
      if (ignoredNonPdfCount > 0 || paths.isNotEmpty) {
        _errorMessage = 'Hanya file PDF yang didukung.';
        _lastResult = null;
        notifyListeners();
      }
      return;
    }
    await loadFile(pdfPaths.first);
  }

  /// Inspects and loads [path] into the Rotate workspace, resetting prior edits.
  Future<void> loadFile(String path) async {
    if (_isProcessing) return;
    if (!isPdfPath(path)) {
      _errorMessage = 'Hanya file PDF yang didukung.';
      _lastResult = null;
      notifyListeners();
      return;
    }

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final info = await _repository.inspectFile(path);
      if (info.pageCount < 1) {
        _errorMessage = 'Dokumen PDF tidak memiliki halaman.';
        return;
      }
      _sourceFile = info;
      _pageRotations.clear();
      _selectedPages.clear();
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Gagal membuka file PDF.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Unloads the active PDF and resets rotation/selection state.
  void clearFile() {
    _sourceFile = null;
    _pageRotations.clear();
    _selectedPages.clear();
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Toggles selection of 1-based [pageNumber].
  void togglePageSelection(int pageNumber) {
    final total = _sourceFile?.pageCount ?? 0;
    if (pageNumber < 1 || pageNumber > total) return;

    if (!_selectedPages.remove(pageNumber)) {
      _selectedPages.add(pageNumber);
    }
    notifyListeners();
  }

  /// Selects all pages of the loaded PDF.
  void selectAll() {
    final total = _sourceFile?.pageCount ?? 0;
    if (total < 1) return;
    _selectedPages
      ..clear()
      ..addAll(List<int>.generate(total, (index) => index + 1));
    notifyListeners();
  }

  /// Clears page selection.
  void clearSelection() {
    if (_selectedPages.isEmpty) return;
    _selectedPages.clear();
    notifyListeners();
  }

  /// Selects all odd-numbered pages (1, 3, 5, ...).
  void selectOddPages() {
    final total = _sourceFile?.pageCount ?? 0;
    if (total < 1) return;
    _selectedPages
      ..clear()
      ..addAll(
        [for (var page = 1; page <= total; page += 2) page],
      );
    notifyListeners();
  }

  /// Selects all even-numbered pages (2, 4, 6, ...).
  void selectEvenPages() {
    final total = _sourceFile?.pageCount ?? 0;
    if (total < 1) return;
    _selectedPages
      ..clear()
      ..addAll(
        [for (var page = 2; page <= total; page += 2) page],
      );
    notifyListeners();
  }

  /// Rotates a single 1-based [pageNumber] 90° clockwise.
  void rotatePageCW(int pageNumber) =>
      _rotatePages(<int>[pageNumber], (r) => r.rotateCW90());

  /// Rotates a single 1-based [pageNumber] 90° counter-clockwise.
  void rotatePageCCW(int pageNumber) =>
      _rotatePages(<int>[pageNumber], (r) => r.rotateCCW90());

  /// Rotates a single 1-based [pageNumber] by 180°.
  void rotatePage180(int pageNumber) =>
      _rotatePages(<int>[pageNumber], (r) => r.rotate180());

  /// Rotates selected pages (or all pages when none selected) 90° clockwise.
  void rotateTargetCW() =>
      _rotatePages(_targetPageNumbers(), (r) => r.rotateCW90());

  /// Rotates selected pages (or all pages when none selected) 90° counter-clockwise.
  void rotateTargetCCW() =>
      _rotatePages(_targetPageNumbers(), (r) => r.rotateCCW90());

  /// Rotates selected pages (or all pages when none selected) by 180°.
  void rotateTarget180() =>
      _rotatePages(_targetPageNumbers(), (r) => r.rotate180());

  /// Resets all pending rotations back to 0°.
  void resetRotations() {
    if (_pageRotations.isEmpty) return;
    _pageRotations.clear();
    _errorMessage = null;
    notifyListeners();
  }

  /// Prompts for a destination file and writes the rotated PDF to disk.
  Future<void> saveRotatedPdf() async {
    final file = _sourceFile;
    if (file == null || _isProcessing) return;

    final stem = p.basenameWithoutExtension(file.fileName);
    final outputPath = await _repository.pickSavePdfPath(
      suggestedName: '${stem}_rotated.pdf',
    );
    if (outputPath == null) return;

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      _lastResult = await _repository.rotatePdf(
        inputPath: file.path,
        pageRotations: Map<int, RotationQuarterTurns>.unmodifiable(
          _pageRotations,
        ),
        outputPath: outputPath,
      );
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan saat menyimpan PDF yang diputar.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Opens the folder containing the last saved rotated PDF.
  Future<void> openLastOutputFolder() async {
    final paths = _lastResult?.outputPaths;
    if (paths == null || paths.isEmpty) return;
    await _repository.revealInFileManager(paths.first);
  }

  /// Dismisses the active error or success banner.
  void dismissStatus() {
    if (_errorMessage == null && _lastResult == null) return;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  Iterable<int> _targetPageNumbers() {
    final total = _sourceFile?.pageCount ?? 0;
    if (total < 1) return const <int>[];
    if (_selectedPages.isNotEmpty) {
      return _selectedPages.toList(growable: false);
    }
    return List<int>.generate(total, (index) => index + 1);
  }

  void _rotatePages(
    Iterable<int> pages,
    RotationQuarterTurns Function(RotationQuarterTurns current) transform,
  ) {
    final total = _sourceFile?.pageCount ?? 0;
    if (total < 1 || _isProcessing) return;

    var changed = false;
    for (final pageNumber in pages) {
      if (pageNumber < 1 || pageNumber > total) continue;
      final current = rotationForPage(pageNumber);
      final next = transform(current);
      if (next == RotationQuarterTurns.deg0) {
        _pageRotations.remove(pageNumber);
      } else {
        _pageRotations[pageNumber] = next;
      }
      changed = true;
    }

    if (changed) {
      _errorMessage = null;
      _lastResult = null;
      notifyListeners();
    }
  }
}
