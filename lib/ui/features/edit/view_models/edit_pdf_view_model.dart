import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/data/services/pdfium_overlay_writer.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_edit_overlay.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';

/// Signature for decoding compressed image files into straight-alpha BGRA buffers.
typedef ImageDecoder = Future<({int width, int height, Uint8List bgraBytes})>
    Function(Uint8List encodedBytes);

/// ViewModel managing the interactive in-app PDF editor workspace.
class EditPdfViewModel extends ChangeNotifier {
  /// Creates an [EditPdfViewModel].
  EditPdfViewModel({
    required this._repository,
    ImageDecoder? imageDecoder,
  }) : _imageDecoder = imageDecoder ?? decodeImageToStraightBgra;

  static const int _maxUndoEntries = 50;

  final PdfRepository _repository;
  final ImageDecoder _imageDecoder;

  PdfFileInfo? _sourceFile;
  Uint8List? _sourceBytes;
  List<PdfPageSize> _pageSizes = const <PdfPageSize>[];
  int _documentRevision = 0;

  int _currentPage = 1;
  double _zoom = 1.0;
  PdfEditTool _activeTool = PdfEditTool.text;

  int _textColorArgb = 0xFF111827;
  double _fontSizePt = 14.0;
  bool _isTextBold = false;
  bool _textWhiteBackground = false;
  int _whiteoutColorArgb = 0xFFFFFFFF;
  int _highlightColorArgb = 0x66FACC15;
  int _strokeColorArgb = 0xFF1D4ED8;
  double _strokeWidthPt = 2.5;
  int _outlineColorArgb = 0xFFDC2626;
  double _outlineStrokeWidthPt = 2.0;

  List<PdfEditOverlay> _overlays = <PdfEditOverlay>[];
  final List<List<PdfEditOverlay>> _undoStack = <List<PdfEditOverlay>>[];
  final List<List<PdfEditOverlay>> _redoStack = <List<PdfEditOverlay>>[];
  String? _selectedOverlayId;
  int _nextId = 1;

  bool _isProcessing = false;
  String? _errorMessage;
  PdfOperationResult? _lastResult;
  bool _disposed = false;

  /// Active PDF metadata, or `null` when no file is loaded.
  PdfFileInfo? get sourceFile => _sourceFile;

  /// Cached file bytes used for previewing without locking the file on disk.
  Uint8List? get sourceBytes => _sourceBytes;

  /// Monotonically increasing revision triggered when loading or overwriting a document.
  int get documentRevision => _documentRevision;

  /// Per-page dimensions (in PDF points) for the active document.
  List<PdfPageSize> get pageSizes => List<PdfPageSize>.unmodifiable(_pageSizes);

  /// 1-based page currently displayed on the canvas.
  int get currentPage => _currentPage;

  /// Current canvas zoom factor (`0.5` .. `3.0`).
  double get zoom => _zoom;

  /// Currently selected editing tool.
  PdfEditTool get activeTool => _activeTool;

  /// Default text fill color.
  int get textColorArgb => _textColorArgb;

  /// Default font size in PDF points.
  double get fontSizePt => _fontSizePt;

  /// Default bold setting for newly created text overlays.
  bool get isTextBold => _isTextBold;

  /// Whether newly placed text automatically includes a white opaque backing.
  bool get textWhiteBackground => _textWhiteBackground;

  /// Default whiteout rectangle fill color.
  int get whiteoutColorArgb => _whiteoutColorArgb;

  /// Default translucent highlight color.
  int get highlightColorArgb => _highlightColorArgb;

  /// Default pen/signature stroke color.
  int get strokeColorArgb => _strokeColorArgb;

  /// Default pen/signature stroke width in PDF points.
  double get strokeWidthPt => _strokeWidthPt;

  /// Default outline rectangle stroke color.
  int get outlineColorArgb => _outlineColorArgb;

  /// Default outline rectangle stroke width in PDF points.
  double get outlineStrokeWidthPt => _outlineStrokeWidthPt;

  /// Unmodifiable list of all pending overlays across all pages.
  List<PdfEditOverlay> get overlays =>
      List<PdfEditOverlay>.unmodifiable(_overlays);

  /// Ordered overlays belonging to [currentPage].
  List<PdfEditOverlay> get currentPageOverlays =>
      List<PdfEditOverlay>.unmodifiable(
        _overlays.where((item) => item.pageNumber == _currentPage),
      );

  /// Number of overlays placed on [pageNumber] (1-based).
  int overlayCountForPage(int pageNumber) =>
      _overlays.where((item) => item.pageNumber == pageNumber).length;

  /// Total overlay count across all pages.
  int get totalOverlayCount => _overlays.length;

  /// Currently selected overlay ID, if any.
  String? get selectedOverlayId => _selectedOverlayId;

  /// Currently selected overlay instance, or `null` when none is selected.
  PdfEditOverlay? get selectedOverlay {
    final targetId = _selectedOverlayId;
    if (targetId == null) return null;
    for (final overlay in _overlays) {
      if (overlay.id == targetId) return overlay;
    }
    return null;
  }

  /// Active color reflecting the selected overlay (when applicable) or current tool.
  int? get effectiveColorArgb {
    final selected = selectedOverlay;
    if (selected != null) {
      return switch (selected) {
        PdfTextOverlay() => selected.colorArgb,
        PdfRectOverlay() => selected.colorArgb,
        PdfStrokeOverlay() => selected.colorArgb,
        PdfImageOverlay() => null,
      };
    }
    return switch (_activeTool) {
      PdfEditTool.text => _textColorArgb,
      PdfEditTool.whiteout => _whiteoutColorArgb,
      PdfEditTool.highlight => _highlightColorArgb,
      PdfEditTool.pen => _strokeColorArgb,
      PdfEditTool.rectangle => _outlineColorArgb,
      PdfEditTool.select => null,
    };
  }

  /// Active font size reflecting the selected [PdfTextOverlay] or default setting.
  double get effectiveFontSizePt {
    final selected = selectedOverlay;
    return selected is PdfTextOverlay ? selected.fontSizePt : _fontSizePt;
  }

  /// Active bold flag reflecting the selected [PdfTextOverlay] or default setting.
  bool get effectiveIsTextBold {
    final selected = selectedOverlay;
    return selected is PdfTextOverlay ? selected.isBold : _isTextBold;
  }

  /// Active white-backing flag reflecting the selected [PdfTextOverlay] or default setting.
  bool get effectiveTextWhiteBackground {
    final selected = selectedOverlay;
    return selected is PdfTextOverlay
        ? selected.backgroundColorArgb != null
        : _textWhiteBackground;
  }

  /// Active stroke width reflecting a selected stroke/outline overlay or tool default.
  double get effectiveStrokeWidthPt {
    final selected = selectedOverlay;
    if (selected is PdfStrokeOverlay) return selected.strokeWidthPt;
    if (selected is PdfRectOverlay &&
        selected.kind == PdfRectOverlayKind.outline) {
      return selected.strokeWidthPt;
    }
    return _activeTool == PdfEditTool.rectangle
        ? _outlineStrokeWidthPt
        : _strokeWidthPt;
  }

  /// Whether an undo step is available.
  bool get canUndo => _undoStack.isNotEmpty && !_isProcessing;

  /// Whether a redo step is available.
  bool get canRedo => _redoStack.isNotEmpty && !_isProcessing;

  /// Whether a file load, image decode, or PDF save operation is active.
  bool get isProcessing => _isProcessing;

  /// Latest user-facing error message, if any.
  String? get errorMessage => _errorMessage;

  /// Latest completed save operation result, if any.
  PdfOperationResult? get lastResult => _lastResult;

  /// Whether changes are ready to be saved to a PDF file.
  bool get canSave =>
      _sourceFile != null && _overlays.isNotEmpty && !_isProcessing;

  /// Page dimensions (in PDF points) for [pageNumber] (1-based), defaulting to A4.
  PdfPageSize pageSizeFor(int pageNumber) {
    final index = pageNumber - 1;
    if (index >= 0 && index < _pageSizes.length) {
      return _pageSizes[index];
    }
    return PdfPageSize.a4;
  }

  /// Prompts the user to pick one PDF file and opens it in the editor.
  Future<void> pickFile() async {
    if (_isProcessing) return;
    final path = await _repository.pickPdfFile();
    if (path == null) return;
    await loadFile(path);
  }

  /// Handles dropped paths and loads the first valid `.pdf` file.
  Future<void> loadFromDroppedPaths(
    List<String> paths, {
    int ignoredNonPdfCount = 0,
  }) async {
    if (_isProcessing) return;
    final pdfPaths = paths.where(isPdfPath).toList(growable: false);
    final skippedCount =
        ignoredNonPdfCount + (paths.length - pdfPaths.length);

    if (pdfPaths.isEmpty) {
      if (skippedCount > 0) {
        _errorMessage =
            'Hanya file PDF yang didukung ($skippedCount file bukan PDF dilewati).';
        _safeNotify();
      }
      return;
    }

    await loadFile(pdfPaths.first);
    if (skippedCount > 0 && _errorMessage == null) {
      _errorMessage =
          '$skippedCount file bukan PDF dilewati. Menampilkan ${p.basename(pdfPaths.first)}.';
      _safeNotify();
    }
  }

  /// Inspects and opens [filePath] in the editor, resetting prior unsaved overlays.
  Future<void> loadFile(String filePath) async {
    if (_isProcessing) return;

    final normalizedPath = p.normalize(filePath);
    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _safeNotify();

    try {
      final info = await _repository.inspectFile(normalizedPath);
      if (info.pageCount < 1) {
        throw const PdfOperationException(
          'Dokumen PDF kosong dan tidak memiliki halaman.',
        );
      }

      final sizes = await _repository.readPageSizes(normalizedPath);
      final bytes = await _repository.readPdfBytes(normalizedPath);

      _sourceFile = info;
      _sourceBytes = bytes;
      _pageSizes = sizes;
      _currentPage = 1;
      _zoom = 1.0;
      _overlays = <PdfEditOverlay>[];
      _undoStack.clear();
      _redoStack.clear();
      _selectedOverlayId = null;
      _documentRevision++;
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Gagal membuka file PDF "${p.basename(normalizedPath)}".';
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  /// Switches the active editing tool and clears selection when leaving [PdfEditTool.select].
  void selectTool(PdfEditTool tool) {
    if (_activeTool == tool &&
        (tool == PdfEditTool.select || _selectedOverlayId == null)) {
      return;
    }
    _activeTool = tool;
    if (tool != PdfEditTool.select) {
      _selectedOverlayId = null;
    }
    _safeNotify();
  }

  /// Navigates to 1-based [pageNumber], clearing active selection.
  void goToPage(int pageNumber) {
    final totalPages = _sourceFile?.pageCount ?? 0;
    if (totalPages < 1) return;
    final clamped = pageNumber.clamp(1, totalPages);
    if (clamped == _currentPage) return;
    _currentPage = clamped;
    _selectedOverlayId = null;
    _safeNotify();
  }

  /// Moves to the previous page if available.
  void previousPage() => goToPage(_currentPage - 1);

  /// Moves to the next page if available.
  void nextPage() => goToPage(_currentPage + 1);

  /// Increases canvas zoom in 25% increments up to 300%.
  void zoomIn() {
    final next = (_zoom + 0.25).clamp(0.5, 3.0);
    if (next == _zoom) return;
    _zoom = next;
    _safeNotify();
  }

  /// Decreases canvas zoom in 25% increments down to 50%.
  void zoomOut() {
    final next = (_zoom - 0.25).clamp(0.5, 3.0);
    if (next == _zoom) return;
    _zoom = next;
    _safeNotify();
  }

  /// Resets canvas zoom to 100%.
  void resetZoom() {
    if (_zoom == 1.0) return;
    _zoom = 1.0;
    _safeNotify();
  }

  /// Selects overlay by [id] (or clears selection when `null`).
  void selectOverlay(String? id) {
    if (_selectedOverlayId == id) return;
    _selectedOverlayId = id;
    _safeNotify();
  }

  /// Adds a new [PdfTextOverlay] on [currentPage] and selects it.
  PdfTextOverlay? addTextOverlay({
    required double x,
    required double y,
    required String text,
    bool? whiteBackground,
  }) {
    if (_sourceFile == null || text.trim().isEmpty) return null;

    final before = captureSnapshot();
    final useWhiteBg = whiteBackground ?? _textWhiteBackground;
    final overlay = PdfTextOverlay(
      id: 'ov_${_nextId++}',
      pageNumber: _currentPage,
      x: x.clamp(0.0, 0.96),
      y: y.clamp(0.0, 0.96),
      text: text.trimRight(),
      fontSizePt: _fontSizePt,
      colorArgb: _textColorArgb,
      backgroundColorArgb: useWhiteBg ? 0xFFFFFFFF : null,
      isBold: _isTextBold,
    );

    _overlays = <PdfEditOverlay>[..._overlays, overlay];
    _selectedOverlayId = overlay.id;
    _errorMessage = null;
    _lastResult = null;
    _pushUndo(before);
    _safeNotify();
    return overlay;
  }

  /// Updates the text content and whiteout backing of the currently selected [PdfTextOverlay].
  void updateSelectedText(String newText, {bool? whiteBackground}) {
    final selected = selectedOverlay;
    if (selected is! PdfTextOverlay) return;
    if (newText.trim().isEmpty) {
      deleteSelectedOverlay();
      return;
    }

    final useWhiteBg =
        whiteBackground ?? (selected.backgroundColorArgb != null);
    final updated = selected.copyWith(
      text: newText.trimRight(),
      backgroundColorArgb: useWhiteBg ? 0xFFFFFFFF : null,
      clearBackground: !useWhiteBg,
    );
    _replaceWithUndo(updated);
  }

  /// Adds a whiteout, highlight, or outline rectangle overlay on [currentPage].
  PdfRectOverlay? addRectOverlay({
    required NormalizedRect rect,
    required PdfRectOverlayKind kind,
  }) {
    if (_sourceFile == null) return null;
    if (rect.width < 0.005 || rect.height < 0.005) return null;

    final before = captureSnapshot();
    final colorArgb = switch (kind) {
      PdfRectOverlayKind.whiteout => _whiteoutColorArgb,
      PdfRectOverlayKind.highlight => _highlightColorArgb,
      PdfRectOverlayKind.outline => _outlineColorArgb,
    };

    final overlay = PdfRectOverlay(
      id: 'ov_${_nextId++}',
      pageNumber: _currentPage,
      rect: rect,
      kind: kind,
      colorArgb: colorArgb,
      strokeWidthPt: kind == PdfRectOverlayKind.outline
          ? _outlineStrokeWidthPt
          : 2.0,
    );

    _overlays = <PdfEditOverlay>[..._overlays, overlay];
    _selectedOverlayId = overlay.id;
    _errorMessage = null;
    _lastResult = null;
    _pushUndo(before);
    _safeNotify();
    return overlay;
  }

  /// Adds a freehand vector stroke overlay on [currentPage].
  PdfStrokeOverlay? addStrokeOverlay({
    required List<List<NormalizedPoint>> strokes,
    bool isSignature = false,
  }) {
    if (_sourceFile == null) return null;
    final cleanStrokes = strokes
        .where((s) => s.isNotEmpty)
        .map((s) => List<NormalizedPoint>.unmodifiable(s))
        .toList(growable: false);
    if (cleanStrokes.isEmpty) return null;

    final before = captureSnapshot();
    final overlay = PdfStrokeOverlay(
      id: 'ov_${_nextId++}',
      pageNumber: _currentPage,
      strokes: cleanStrokes,
      colorArgb: _strokeColorArgb,
      strokeWidthPt: _strokeWidthPt,
      isSignature: isSignature,
    );

    _overlays = <PdfEditOverlay>[..._overlays, overlay];
    if (isSignature) {
      _selectedOverlayId = overlay.id;
      _activeTool = PdfEditTool.select;
    } else {
      _selectedOverlayId = null;
    }
    _errorMessage = null;
    _lastResult = null;
    _pushUndo(before);
    _safeNotify();
    return overlay;
  }

  /// Normalizes signature pad strokes (`[0..1] x [0..1]`) and places them centered
  /// on [currentPage].
  PdfStrokeOverlay? insertSignatureStrokes(
    List<List<NormalizedPoint>> padStrokes,
  ) {
    if (_sourceFile == null) return null;
    final nonEmpty = padStrokes.where((s) => s.isNotEmpty).toList(growable: false);
    if (nonEmpty.isEmpty) return null;

    var minX = 1.0;
    var minY = 1.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final polyline in nonEmpty) {
      for (final pt in polyline) {
        if (pt.x < minX) minX = pt.x;
        if (pt.y < minY) minY = pt.y;
        if (pt.x > maxX) maxX = pt.x;
        if (pt.y > maxY) maxY = pt.y;
      }
    }

    final spanX = math.max(0.05, maxX - minX);
    final spanY = math.max(0.05, maxY - minY);
    final pageSize = pageSizeFor(_currentPage);

    // Signature dialog pad has ~2:1 width:height proportion.
    final sigVisualRatio = (spanX * 2.0) / spanY;
    const targetWidth = 0.32;
    final desiredHeight =
        ((targetWidth * pageSize.width) / sigVisualRatio) / pageSize.height;
    final targetHeight = desiredHeight.clamp(0.05, 0.28);
    final left = (1.0 - targetWidth) / 2.0;
    final top = (1.0 - targetHeight) / 2.0;

    final mappedStrokes = <List<NormalizedPoint>>[
      for (final polyline in nonEmpty)
        <NormalizedPoint>[
          for (final pt in polyline)
            NormalizedPoint(
              left + ((pt.x - minX) / spanX) * targetWidth,
              top + ((pt.y - minY) / spanY) * targetHeight,
            ),
        ],
    ];

    return addStrokeOverlay(strokes: mappedStrokes, isSignature: true);
  }

  /// Opens the native image picker and inserts the chosen image centered on [currentPage].
  Future<void> pickAndInsertImage() async {
    if (_sourceFile == null || _isProcessing) return;

    final imagePath = await _repository.pickImageFile();
    if (imagePath == null) return;

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _safeNotify();

    try {
      final bytes = await File(p.normalize(imagePath)).readAsBytes();
      final decoded = await _imageDecoder(bytes);
      if (decoded.width <= 0 || decoded.height <= 0) {
        throw const PdfOperationException(
          'Ukuran gambar tidak valid untuk disisipkan ke PDF.',
        );
      }

      final pageSize = pageSizeFor(_currentPage);
      var targetWidth = 0.35;
      var targetHeight =
          ((targetWidth * pageSize.width) * (decoded.height / decoded.width)) /
              pageSize.height;
      if (targetHeight > 0.70) {
        targetHeight = 0.70;
        targetWidth = ((targetHeight * pageSize.height) *
                (decoded.width / decoded.height)) /
            pageSize.width;
      }
      targetWidth = targetWidth.clamp(0.05, 0.85);
      targetHeight = targetHeight.clamp(0.05, 0.70);

      final rect = NormalizedRect(
        left: (1.0 - targetWidth) / 2.0,
        top: (1.0 - targetHeight) / 2.0,
        width: targetWidth,
        height: targetHeight,
      );

      final before = captureSnapshot();
      final overlay = PdfImageOverlay(
        id: 'ov_${_nextId++}',
        pageNumber: _currentPage,
        rect: rect,
        imageBytes: bytes,
        pixelWidth: decoded.width,
        pixelHeight: decoded.height,
        fileName: p.basename(imagePath),
        preDecodedBgraBytes: decoded.bgraBytes,
      );

      _overlays = <PdfEditOverlay>[..._overlays, overlay];
      _selectedOverlayId = overlay.id;
      _activeTool = PdfEditTool.select;
      _pushUndo(before);
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage =
          'Gagal membaca gambar "${p.basename(imagePath)}" untuk disisipkan ke PDF.';
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  /// Captures an immutable list snapshot before starting an interactive drag/resize.
  List<PdfEditOverlay> captureSnapshot() => List<PdfEditOverlay>.from(_overlays);

  /// Updates an existing overlay in-place during live drag/resize without pushing undo history.
  void updateOverlayLive(PdfEditOverlay updated) {
    final index = _overlays.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    final copy = List<PdfEditOverlay>.from(_overlays);
    copy[index] = updated;
    _overlays = copy;
    _safeNotify();
  }

  /// Commits a finished live drag/resize operation by pushing [beforeSnapshot] if changed.
  void commitSnapshot(List<PdfEditOverlay> beforeSnapshot) {
    if (_listsIdentical(beforeSnapshot, _overlays)) return;
    _pushUndo(beforeSnapshot);
    _lastResult = null;
    _safeNotify();
  }

  /// Updates the active color for the selected overlay (if compatible) or active tool.
  void setActiveColor(int argb) {
    final selected = selectedOverlay;
    if (selected != null) {
      switch (selected) {
        case PdfTextOverlay():
          _textColorArgb = argb;
          _replaceWithUndo(selected.copyWith(colorArgb: argb));
          return;
        case PdfRectOverlay():
          final adjusted = selected.kind == PdfRectOverlayKind.highlight
              ? withArgbAlpha(argb, 0x66)
              : withArgbAlpha(argb, 0xFF);
          switch (selected.kind) {
            case PdfRectOverlayKind.whiteout:
              _whiteoutColorArgb = adjusted;
            case PdfRectOverlayKind.highlight:
              _highlightColorArgb = adjusted;
            case PdfRectOverlayKind.outline:
              _outlineColorArgb = adjusted;
          }
          _replaceWithUndo(selected.copyWith(colorArgb: adjusted));
          return;
        case PdfStrokeOverlay():
          _strokeColorArgb = argb;
          _replaceWithUndo(selected.copyWith(colorArgb: argb));
          return;
        case PdfImageOverlay():
          break;
      }
    }

    switch (_activeTool) {
      case PdfEditTool.text:
        _textColorArgb = argb;
      case PdfEditTool.whiteout:
        _whiteoutColorArgb = withArgbAlpha(argb, 0xFF);
      case PdfEditTool.highlight:
        _highlightColorArgb = withArgbAlpha(argb, 0x66);
      case PdfEditTool.pen:
        _strokeColorArgb = argb;
      case PdfEditTool.rectangle:
        _outlineColorArgb = withArgbAlpha(argb, 0xFF);
      case PdfEditTool.select:
        break;
    }
    _safeNotify();
  }

  /// Sets text font size (in points), applying immediately to any selected text overlay.
  void setFontSize(double fontSizePt) {
    final clamped = fontSizePt.clamp(8.0, 48.0);
    _fontSizePt = clamped;
    final selected = selectedOverlay;
    if (selected is PdfTextOverlay) {
      _replaceWithUndo(selected.copyWith(fontSizePt: clamped));
      return;
    }
    _safeNotify();
  }

  /// Toggles bold text formatting for new or selected text overlays.
  void toggleTextBold() {
    final selected = selectedOverlay;
    if (selected is PdfTextOverlay) {
      final next = !selected.isBold;
      _isTextBold = next;
      _replaceWithUndo(selected.copyWith(isBold: next));
      return;
    }
    _isTextBold = !_isTextBold;
    _safeNotify();
  }

  /// Toggles opaque white backing behind text for new or selected text overlays.
  void toggleTextWhiteBackground() {
    final selected = selectedOverlay;
    if (selected is PdfTextOverlay) {
      final enable = selected.backgroundColorArgb == null;
      _textWhiteBackground = enable;
      _replaceWithUndo(
        selected.copyWith(
          backgroundColorArgb: enable ? 0xFFFFFFFF : null,
          clearBackground: !enable,
        ),
      );
      return;
    }
    _textWhiteBackground = !_textWhiteBackground;
    _safeNotify();
  }

  /// Updates stroke width (in points) for pen/signature strokes or box outlines.
  void setStrokeWidth(double widthPt) {
    final clamped = widthPt.clamp(1.0, 12.0);
    final selected = selectedOverlay;
    if (selected is PdfStrokeOverlay) {
      _strokeWidthPt = clamped;
      _replaceWithUndo(selected.copyWith(strokeWidthPt: clamped));
      return;
    }
    if (selected is PdfRectOverlay &&
        selected.kind == PdfRectOverlayKind.outline) {
      _outlineStrokeWidthPt = clamped;
      _replaceWithUndo(selected.copyWith(strokeWidthPt: clamped));
      return;
    }
    if (_activeTool == PdfEditTool.rectangle) {
      _outlineStrokeWidthPt = clamped;
    } else {
      _strokeWidthPt = clamped;
    }
    _safeNotify();
  }

  /// Deletes the currently selected overlay.
  void deleteSelectedOverlay() {
    final targetId = _selectedOverlayId;
    if (targetId == null || _isProcessing) return;
    final index = _overlays.indexWhere((item) => item.id == targetId);
    if (index < 0) return;

    final before = captureSnapshot();
    final next = List<PdfEditOverlay>.from(_overlays)..removeAt(index);
    _overlays = next;
    _selectedOverlayId = null;
    _pushUndo(before);
    _safeNotify();
  }

  /// Clears all overlays on [currentPage] with undo support.
  void clearCurrentPageOverlays() {
    if (_isProcessing || currentPageOverlays.isEmpty) return;
    final before = captureSnapshot();
    _overlays = _overlays
        .where((item) => item.pageNumber != _currentPage)
        .toList(growable: false);
    _selectedOverlayId = null;
    _pushUndo(before);
    _safeNotify();
  }

  /// Clears all overlays across the entire document with undo support.
  void clearAllOverlays() {
    if (_isProcessing || _overlays.isEmpty) return;
    final before = captureSnapshot();
    _overlays = <PdfEditOverlay>[];
    _selectedOverlayId = null;
    _pushUndo(before);
    _safeNotify();
  }

  /// Undoes the latest overlay mutation.
  void undo() {
    if (!canUndo) return;
    _redoStack.add(captureSnapshot());
    _overlays = _undoStack.removeLast();
    _reconcileSelection();
    _safeNotify();
  }

  /// Re-applies the latest undone overlay mutation.
  void redo() {
    if (!canRedo) return;
    _undoStack.add(captureSnapshot());
    _overlays = _redoStack.removeLast();
    _reconcileSelection();
    _safeNotify();
  }

  /// Prompts for a save path and embeds all overlays losslessly into the output PDF.
  Future<void> saveEditedPdf() async {
    final file = _sourceFile;
    if (file == null || _overlays.isEmpty || _isProcessing) return;

    final outputPath = await _repository.pickSavePdfPath(
      suggestedName: buildEditedPdfFileName(file.fileName),
    );
    if (outputPath == null) return;

    _isProcessing = true;
    _errorMessage = null;
    _lastResult = null;
    _safeNotify();

    try {
      final result = await _repository.applyEdits(
        inputPath: file.path,
        overlays: List<PdfEditOverlay>.unmodifiable(_overlays),
        outputPath: outputPath,
      );
      _lastResult = result;

      final canonicalOut = p.canonicalize(p.normalize(outputPath));
      final canonicalSrc = p.canonicalize(p.normalize(file.path));
      if (canonicalOut == canonicalSrc) {
        await _reloadAfterOverwrite(file.path);
      }
    } on PdfOperationException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Terjadi kesalahan saat menyimpan perubahan PDF.';
    } finally {
      _isProcessing = false;
      _safeNotify();
    }
  }

  Future<void> _reloadAfterOverwrite(String path) async {
    final normalizedPath = p.normalize(path);
    final refreshedInfo = await _repository.inspectFile(normalizedPath);
    final refreshedSizes = await _repository.readPageSizes(normalizedPath);
    final refreshedBytes = await _repository.readPdfBytes(normalizedPath);

    _sourceFile = refreshedInfo;
    _sourceBytes = refreshedBytes;
    _pageSizes = refreshedSizes;
    _currentPage = _currentPage.clamp(1, math.max(1, refreshedInfo.pageCount));
    _overlays = <PdfEditOverlay>[];
    _undoStack.clear();
    _redoStack.clear();
    _selectedOverlayId = null;
    _documentRevision++;
  }

  /// Reveals the last saved PDF in the operating system's file explorer.
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
    _safeNotify();
  }

  void _replaceWithUndo(PdfEditOverlay updated) {
    final index = _overlays.indexWhere((item) => item.id == updated.id);
    if (index < 0) return;
    final before = captureSnapshot();
    final copy = List<PdfEditOverlay>.from(_overlays);
    copy[index] = updated;
    _overlays = copy;
    _pushUndo(before);
    _lastResult = null;
    _safeNotify();
  }

  void _pushUndo(List<PdfEditOverlay> snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > _maxUndoEntries) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _reconcileSelection() {
    if (_selectedOverlayId == null) return;
    final stillExists = _overlays.any((item) => item.id == _selectedOverlayId);
    if (!stillExists) {
      _selectedOverlayId = null;
    }
  }

  bool _listsIdentical(List<PdfEditOverlay> a, List<PdfEditOverlay> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
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
