import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';

/// ViewModel managing state and commands for the interactive PDF Viewer tab.
class PdfViewerViewModel extends ChangeNotifier {
  /// Creates a [PdfViewerViewModel].
  PdfViewerViewModel({required this.repository});

  /// Shared PDF repository used for file picking and inspection.
  final PdfRepository repository;

  PdfFileInfo? _sourceFile;
  int _currentPage = 1;
  double _zoom = 1.0;
  bool _showThumbnails = true;
  bool _isSearchOpen = false;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;
  int _documentRevision = 0;
  bool _disposed = false;

  /// Currently opened PDF document metadata, or `null` when empty.
  PdfFileInfo? get sourceFile => _sourceFile;

  /// Active 1-based page number currently visible in the viewer.
  int get currentPage => _currentPage;

  /// Current zoom scale (`1.0` = 100%).
  double get zoom => _zoom;

  /// Whether the left page thumbnail sidebar is expanded on wide screens.
  bool get showThumbnails => _showThumbnails;

  /// Whether the in-document text search bar is open.
  bool get isSearchOpen => _isSearchOpen;

  /// Active text search query.
  String get searchQuery => _searchQuery;

  /// Whether a PDF file is currently being inspected/loaded.
  bool get isLoading => _isLoading;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Monotonically increasing revision used to force viewer reload on file switch.
  int get documentRevision => _documentRevision;

  /// Whether navigation to the previous page is available.
  bool get canGoPrevious => _sourceFile != null && _currentPage > 1;

  /// Whether navigation to the next page is available.
  bool get canGoNext =>
      _sourceFile != null && _currentPage < _sourceFile!.pageCount;

  /// Opens the native file picker to select a PDF to view.
  Future<void> pickFile() async {
    if (_isLoading) return;
    final path = await repository.pickPdfFile();
    if (path == null) return;
    await setSourcePath(path);
  }

  /// Loads the first valid PDF from drag-and-drop [paths].
  Future<void> loadFromDroppedPaths(
    List<String> paths, {
    int ignoredNonPdfCount = 0,
  }) async {
    if (_isLoading) return;
    if (paths.isEmpty) {
      if (ignoredNonPdfCount > 0) {
        _errorMessage = 'Hanya file PDF (.pdf) yang dapat dibuka di PDF Viewer.';
        _safeNotify();
      }
      return;
    }
    await setSourcePath(paths.first);
  }

  /// Inspects and opens the PDF located at [filePath].
  Future<void> setSourcePath(String filePath) async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      final info = await repository.inspectFile(filePath);
      _sourceFile = info;
      _currentPage = 1;
      _zoom = 1.0;
      _searchQuery = '';
      _isSearchOpen = false;
      _documentRevision++;
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Gagal membuka file PDF: ${p.basename(filePath)}';
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Closes the active PDF document and resets viewer state.
  void clearSource() {
    if (_isLoading) return;
    _sourceFile = null;
    _currentPage = 1;
    _zoom = 1.0;
    _searchQuery = '';
    _isSearchOpen = false;
    _errorMessage = null;
    _safeNotify();
  }

  /// Navigates to a 1-based [pageNumber], clamped to the document's bounds.
  void goToPage(int pageNumber) {
    final file = _sourceFile;
    if (file == null) return;
    final clamped = pageNumber.clamp(1, file.pageCount);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    _safeNotify();
  }

  /// Moves to the previous page if available.
  void previousPage() => goToPage(_currentPage - 1);

  /// Moves to the next page if available.
  void nextPage() => goToPage(_currentPage + 1);

  /// Syncs [currentPage] when the user scrolls the native viewer.
  void setCurrentPageFromViewer(int pageNumber) {
    final file = _sourceFile;
    if (file == null) return;
    final clamped = pageNumber.clamp(1, file.pageCount);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    _safeNotify();
  }

  /// Syncs [zoom] scale from viewer gestures or zoom buttons.
  void setZoom(double value) {
    final clamped = value.clamp(0.25, 5.0);
    if ((clamped - _zoom).abs() < 0.005) return;
    _zoom = clamped;
    _safeNotify();
  }

  /// Toggles visibility of the left thumbnail sidebar.
  void toggleThumbnails() {
    _showThumbnails = !_showThumbnails;
    _safeNotify();
  }

  /// Toggles the in-document text search bar.
  void toggleSearch() {
    _isSearchOpen = !_isSearchOpen;
    if (!_isSearchOpen) {
      _searchQuery = '';
    }
    _safeNotify();
  }

  /// Updates the active search query string.
  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    _safeNotify();
  }

  /// Reveals the currently open PDF in the OS file manager.
  Future<void> openSourceFolder() async {
    final path = _sourceFile?.path;
    if (path == null) return;
    await repository.revealInFileManager(path);
  }

  /// Dismisses the current error banner.
  void dismissError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
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
