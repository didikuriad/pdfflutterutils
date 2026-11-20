import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/split_mode.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/domain/utils/page_range_parser.dart';

/// ViewModel managing the PDF Split workspace.
class SplitViewModel extends ChangeNotifier {
  /// Creates a [SplitViewModel].
  SplitViewModel({required this._repository});

  final PdfRepository _repository;

  PdfFileInfo? _sourceFile;
  SplitMode _mode = SplitMode.customRanges;
  String _customRangeInput = '';
  bool _extractToSingleFile = false;
  int _pagesPerSplit = 2;
  String _outputPrefix = '';
  bool _isProcessing = false;
  double? _progress;
  String? _errorMessage;
  PdfOperationResult? _lastResult;

  /// Currently loaded PDF metadata, or `null` when none is loaded.
  PdfFileInfo? get sourceFile => _sourceFile;

  /// Active split strategy.
  SplitMode get mode => _mode;

  /// User-entered range expression for [SplitMode.customRanges].
  String get customRangeInput => _customRangeInput;

  /// Whether [SplitMode.customRanges] extracts all chosen pages into a single PDF.
  bool get extractToSingleFile => _extractToSingleFile;

  /// Number of pages per output PDF for [SplitMode.fixedPageCount].
  int get pagesPerSplit => _pagesPerSplit;

  /// Filename prefix used to name output files.
  String get outputPrefix => _outputPrefix;

  /// Whether a file inspection or split operation is running.
  bool get isProcessing => _isProcessing;

  /// Split completion progress in `[0.0, 1.0]`, or `null` when idle.
  double? get progress => _progress;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed split result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Computed split output plan, or `null` when no file is loaded or input is invalid.
  SplitOutputPlan? get outputPlan => _computePlan().plan;

  /// Live validation error message for current split parameters, if any.
  String? get validationError => _computePlan().error;

  /// Maps each 1-based page number to its 0-based group index in [outputPlan].
  Map<int, int> get pageToGroupIndex {
    final plan = outputPlan;
    if (plan == null) return const <int, int>{};

    final mapping = <int, int>{};
    for (var groupIndex = 0; groupIndex < plan.groups.length; groupIndex++) {
      for (final pageNum in plan.groups[groupIndex].pages) {
        mapping.putIfAbsent(pageNum, () => groupIndex);
      }
    }
    return Map<int, int>.unmodifiable(mapping);
  }

  /// Whether all prerequisites are satisfied to execute the split.
  bool get canSplit {
    final plan = outputPlan;
    return _sourceFile != null &&
        plan != null &&
        plan.groups.isNotEmpty &&
        validationError == null &&
        !_isProcessing;
  }

  /// Opens the native single-file picker and loads the chosen PDF.
  Future<void> pickFile() async {
    if (_isProcessing) return;
    final path = await _repository.pickPdfFile();
    if (path == null) return;
    await loadFile(path);
  }

  /// Handles dropped paths on the Split workspace, loading the first valid PDF.
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

  /// Inspects and loads [path] into the Split workspace.
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
    _progress = null;
    notifyListeners();

    try {
      final info = await _repository.inspectFile(path);
      if (info.pageCount < 1) {
        _errorMessage = 'Dokumen PDF tidak memiliki halaman.';
        return;
      }
      _sourceFile = info;
      _outputPrefix = sanitizeFileNamePrefix(
        p.basenameWithoutExtension(info.fileName),
      );
      _customRangeInput = '';
      if (_pagesPerSplit > info.pageCount) {
        _pagesPerSplit = info.pageCount.clamp(1, 2);
      }
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Gagal membuka file PDF.';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Unloads the active PDF and clears configuration state.
  void clearFile() {
    _sourceFile = null;
    _customRangeInput = '';
    _outputPrefix = '';
    _progress = null;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Changes the active [SplitMode].
  void setMode(SplitMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Updates the custom range input expression.
  void setCustomRangeInput(String value) {
    if (_customRangeInput == value) return;
    _customRangeInput = value;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Sets whether [SplitMode.customRanges] outputs one combined extracted file.
  void setExtractToSingleFile(bool value) {
    if (_extractToSingleFile == value) return;
    _extractToSingleFile = value;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Sets the chunk size (minimum 1) for [SplitMode.fixedPageCount].
  void setPagesPerSplit(int value) {
    final maxPages = _sourceFile?.pageCount ?? 9999;
    final clamped = value.clamp(1, maxPages < 1 ? 1 : maxPages);
    if (_pagesPerSplit == clamped) return;
    _pagesPerSplit = clamped;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Updates the output filename prefix.
  void setOutputPrefix(String prefix) {
    if (_outputPrefix == prefix) return;
    _outputPrefix = prefix;
    notifyListeners();
  }

  /// Toggles 1-based [pageNumber] in [customRangeInput] when using [SplitMode.customRanges].
  void togglePageInCustomRange(int pageNumber) {
    final file = _sourceFile;
    if (file == null || _mode != SplitMode.customRanges || _isProcessing) {
      return;
    }
    if (pageNumber < 1 || pageNumber > file.pageCount) return;

    final selected = <int>{};
    if (_customRangeInput.trim().isNotEmpty) {
      try {
        final groups = parseSplitRangeGroups(
          _customRangeInput,
          maxPages: file.pageCount,
        );
        for (final group in groups) {
          selected.addAll(group);
        }
      } on FormatException {
        // Ignore unparseable partial draft and start toggling cleanly.
      }
    }

    if (!selected.remove(pageNumber)) {
      selected.add(pageNumber);
    }

    _customRangeInput = formatPagesAsRange(selected);
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Prompts for an output file or folder and executes the split plan.
  Future<void> splitAndSave() async {
    final file = _sourceFile;
    final plan = outputPlan;
    if (file == null || plan == null || !canSplit) return;

    String? singleFilePath;
    String? outputDirectory;

    if (plan.isSingleOutput) {
      singleFilePath = await _repository.pickSavePdfPath(
        suggestedName: plan.groups.first.suggestedFileName,
      );
      if (singleFilePath == null) return;
      outputDirectory = p.dirname(singleFilePath);
    } else {
      outputDirectory = await _repository.pickOutputDirectory(
        confirmButtonText: 'Pilih Folder Output',
      );
      if (outputDirectory == null) return;
    }

    _isProcessing = true;
    _progress = 0;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    try {
      _lastResult = await _repository.splitPdf(
        inputPath: file.path,
        groups: plan.groups,
        outputDirectory: outputDirectory,
        singleOutputFilePath: singleFilePath,
        onProgress: (completed, total) {
          _progress = total > 0 ? completed / total : null;
          notifyListeners();
        },
      );
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan saat memisahkan PDF.';
    } finally {
      _isProcessing = false;
      _progress = null;
      notifyListeners();
    }
  }

  /// Opens the output file or folder from the last completed split.
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
    notifyListeners();
  }

  ({SplitOutputPlan? plan, String? error}) _computePlan() {
    final file = _sourceFile;
    if (file == null) {
      return (plan: null, error: null);
    }

    final prefixSource = _outputPrefix.trim().isEmpty
        ? p.basenameWithoutExtension(file.fileName)
        : _outputPrefix;
    final safePrefix = sanitizeFileNamePrefix(prefixSource);

    try {
      final List<List<int>> rawGroups;
      switch (_mode) {
        case SplitMode.customRanges:
          final parsed = parseSplitRangeGroups(
            _customRangeInput,
            maxPages: file.pageCount,
          );
          if (_extractToSingleFile) {
            rawGroups = <List<int>>[
              <int>[for (final group in parsed) ...group],
            ];
          } else {
            rawGroups = parsed;
          }
        case SplitMode.everyPage:
          rawGroups = buildEveryPageGroups(file.pageCount);
        case SplitMode.fixedPageCount:
          rawGroups = buildFixedChunkGroups(file.pageCount, _pagesPerSplit);
      }

      final totalParts = rawGroups.length;
      final groups = List<SplitGroup>.generate(totalParts, (index) {
        final pages = rawGroups[index];
        final label = _mode == SplitMode.customRanges && _extractToSingleFile
            ? 'Ekstrak'
            : 'Bagian ${index + 1}';
        return SplitGroup(
          label: label,
          pages: List<int>.unmodifiable(pages),
          suggestedFileName: buildSplitFileName(
            safePrefix,
            index + 1,
            totalParts,
            pages,
          ),
        );
      });

      return (
        plan: SplitOutputPlan(groups: List<SplitGroup>.unmodifiable(groups)),
        error: null,
      );
    } on FormatException catch (error) {
      return (plan: null, error: error.message);
    }
  }
}
