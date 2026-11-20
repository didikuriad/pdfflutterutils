import 'package:flutter/foundation.dart';
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/data/services/pdf_engine_service.dart';
import 'package:pdfutils/domain/models/merge_item.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/domain/utils/page_range_parser.dart';

/// ViewModel managing the PDF Merge workspace.
class MergeViewModel extends ChangeNotifier {
  /// Creates a [MergeViewModel].
  MergeViewModel({required this._repository});

  final PdfRepository _repository;

  final List<MergeItem> _items = <MergeItem>[];
  int _nextItemId = 1;
  bool _isProcessing = false;
  String? _errorMessage;
  PdfOperationResult? _lastResult;

  /// Ordered list of queued PDF items to merge.
  List<MergeItem> get items => List<MergeItem>.unmodifiable(_items);

  /// Whether an inspect or merge operation is currently in progress.
  bool get isProcessing => _isProcessing;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed operation result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Per-item page range validation error messages keyed by `MergeItem.id`.
  Map<String, String?> get rangeErrors {
    final errors = <String, String?>{};
    for (final item in _items) {
      errors[item.id] = _validateRange(item);
    }
    return Map<String, String?>.unmodifiable(errors);
  }

  /// Total number of pages that will be written to the merged PDF.
  int get totalSelectedPages {
    var total = 0;
    for (final item in _items) {
      try {
        total += parsePageList(
          item.pageRangeInput,
          maxPages: item.file.pageCount,
        ).length;
      } on FormatException {
        // Ignore invalid ranges in the live page total until fixed.
      }
    }
    return total;
  }

  /// Whether all prerequisites are satisfied to merge and save.
  bool get canMerge {
    if (_items.length < 2 || _isProcessing) return false;
    return rangeErrors.values.every((error) => error == null);
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
        notifyListeners();
      }
      return;
    }

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

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
          _items.add(
            MergeItem(
              id: 'merge_${_nextItemId++}',
              file: info,
            ),
          );
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
      notifyListeners();
    }
  }

  /// Reorders an item from [oldIndex] to [newIndex] (using `onReorderItem` index semantics).
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    if (oldIndex == newIndex) return;

    final moved = _items.removeAt(oldIndex);
    _items.insert(newIndex, moved);
    notifyListeners();
  }

  /// Moves item at [index] one position earlier in the merge order.
  void moveUp(int index) {
    if (index <= 0 || index >= _items.length) return;
    final moved = _items.removeAt(index);
    _items.insert(index - 1, moved);
    notifyListeners();
  }

  /// Moves item at [index] one position later in the merge order.
  void moveDown(int index) {
    if (index < 0 || index >= _items.length - 1) return;
    final moved = _items.removeAt(index);
    _items.insert(index + 1, moved);
    notifyListeners();
  }

  /// Removes item at [index].
  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    notifyListeners();
  }

  /// Updates the optional page range expression for the item with [id].
  void updatePageRange(String id, String rangeInput) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    if (_items[index].pageRangeInput == rangeInput) return;

    _items[index] = _items[index].copyWith(pageRangeInput: rangeInput);
    _errorMessage = null;
    notifyListeners();
  }

  /// Clears all queued PDF files and status banners.
  void clearAll() {
    _items.clear();
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Prompts for an output PDF path, merges queued documents, and saves to disk.
  Future<void> mergeAndSave() async {
    if (!canMerge) return;

    final outputPath = await _repository.pickSavePdfPath(
      suggestedName: 'gabungan.pdf',
    );
    if (outputPath == null) return;

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      final specs = <MergeSourceSpec>[];
      for (final item in _items) {
        final pages = parsePageList(
          item.pageRangeInput,
          maxPages: item.file.pageCount,
        );
        specs.add(
          MergeSourceSpec(
            filePath: item.file.path,
            oneBasedPages: pages,
          ),
        );
      }

      _lastResult = await _repository.mergePdfs(
        sources: specs,
        outputPath: outputPath,
      );
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan saat menggabungkan PDF.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Opens the directory containing the last merged output file.
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

  String? _validateRange(MergeItem item) {
    try {
      parsePageList(item.pageRangeInput, maxPages: item.file.pageCount);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}
