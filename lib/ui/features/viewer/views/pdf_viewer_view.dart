import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/viewer/view_models/pdf_viewer_view_model.dart';

/// Workspace view providing a full-featured desktop PDF viewer with zoom,
/// page navigation, thumbnail sidebar, text selection, and text search.
class PdfViewerView extends StatefulWidget {
  /// Creates a [PdfViewerView].
  const PdfViewerView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving PDF viewer state and commands.
  final PdfViewerViewModel viewModel;

  /// Whether this tab is currently visible in the shell.
  final bool isActive;

  @override
  State<PdfViewerView> createState() => _PdfViewerViewState();
}

class _PdfViewerViewState extends State<PdfViewerView> {
  final PdfViewerController _viewerController = PdfViewerController();
  late final PdfTextSearcher _textSearcher;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pageInputController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  PdfDocument? _loadedDocument;
  int _lastSyncedRevision = -1;

  PdfViewerViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _textSearcher = PdfTextSearcher(_viewerController)
      ..addListener(_onSearcherChanged);
    _viewerController.addListener(_onViewerControllerChanged);
    _vm.addListener(_onViewModelChanged);
    _pageInputController.text = '${_vm.currentPage}';
  }

  @override
  void didUpdateWidget(covariant PdfViewerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
      _pageInputController.text = '${_vm.currentPage}';
    }
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _viewerController.removeListener(_onViewerControllerChanged);
    _textSearcher
      ..removeListener(_onSearcherChanged)
      ..dispose();
    _searchController.dispose();
    _pageInputController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearcherChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onViewerControllerChanged() {
    if (!mounted || !_viewerController.isReady) return;
    _vm.setZoom(_viewerController.currentZoom);
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (_lastSyncedRevision != _vm.documentRevision) {
      _lastSyncedRevision = _vm.documentRevision;
      _loadedDocument = null;
      _searchController.clear();
      _textSearcher.resetTextSearch();
    }
    final expectedPageText = '${_vm.currentPage}';
    if (_pageInputController.text != expectedPageText) {
      _pageInputController.text = expectedPageText;
    }
  }

  void _navigateToPage(int pageNumber) {
    final file = _vm.sourceFile;
    if (file == null) return;
    final clamped = pageNumber.clamp(1, file.pageCount);
    _vm.goToPage(clamped);
    if (_viewerController.isReady) {
      unawaited(_viewerController.goToPage(pageNumber: clamped));
    }
  }

  void _zoomIn() {
    if (_viewerController.isReady) {
      unawaited(_viewerController.zoomUp());
    } else {
      _vm.setZoom(_vm.zoom + 0.25);
    }
  }

  void _zoomOut() {
    if (_viewerController.isReady) {
      unawaited(_viewerController.zoomDown());
    } else {
      _vm.setZoom(_vm.zoom - 0.25);
    }
  }

  void _fitWidth() {
    if (_viewerController.isReady) {
      final page = _viewerController.pageNumber ?? _vm.currentPage;
      final matrix = _viewerController.calcMatrixFitWidthForPage(
        pageNumber: page,
      );
      if (matrix != null) {
        unawaited(_viewerController.goTo(matrix));
      }
    } else {
      _vm.setZoom(1.0);
    }
  }

  void _resetZoom() {
    if (_viewerController.isReady) {
      final center = _viewerController.centerPosition;
      unawaited(_viewerController.setZoom(center, 1.0));
    } else {
      _vm.setZoom(1.0);
    }
  }

  void _toggleSearch() {
    _vm.toggleSearch();
    if (_vm.isSearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    } else {
      _searchController.clear();
      _textSearcher.resetTextSearch();
    }
  }

  void _onSearchQueryChanged(String value) {
    _vm.setSearchQuery(value);
    if (value.trim().isEmpty) {
      _textSearcher.resetTextSearch();
    } else if (_viewerController.isReady) {
      _textSearcher.startTextSearch(
        value,
        caseInsensitive: true,
        goToFirstMatch: true,
      );
    }
  }

  void _submitPageInput(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed != null) {
      _navigateToPage(parsed);
    } else {
      _pageInputController.text = '${_vm.currentPage}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final sourceFile = _vm.sourceFile;

        if (sourceFile == null) {
          return Column(
            children: [
              WorkspaceHeader(
                icon: Icons.chrome_reader_mode_rounded,
                title: 'PDF Viewer',
                subtitle:
                    'Buka dan baca dokumen PDF dengan zoom, pencarian teks, dan pratinjau halaman.',
                actions: [
                  FilledButton.icon(
                    onPressed: _vm.isLoading ? null : _vm.pickFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Pilih PDF'),
                  ),
                ],
              ),
              const Divider(height: 1),
              if (_vm.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: StatusBanner(
                    errorMessage: _vm.errorMessage,
                    onDismiss: _vm.dismissError,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PdfDropZone(
                    enableDrop: widget.isActive,
                    icon: Icons.chrome_reader_mode_outlined,
                    title: 'Tarik & lepas file PDF untuk dibaca',
                    subtitle:
                        'Nikmati tampilan baca yang nyaman dengan zoom halus, seleksi teks, pencarian kata, dan navigasi halaman.',
                    buttonLabel: 'Buka File PDF',
                    onBrowsePressed: _vm.isLoading ? null : _vm.pickFile,
                    onFilesDropped: (paths, ignoredCount) {
                      _vm.loadFromDroppedPaths(
                        paths,
                        ignoredNonPdfCount: ignoredCount,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        }

        return PdfDropWrapper(
          enableDrop: widget.isActive,
          overlayMessage: 'Lepaskan file PDF baru untuk dibaca',
          onFilesDropped: (paths, ignoredCount) {
            _vm.loadFromDroppedPaths(
              paths,
              ignoredNonPdfCount: ignoredCount,
            );
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.chrome_reader_mode_rounded,
                title: 'PDF Viewer',
                subtitle:
                    '${sourceFile.fileName} • Hal ${_vm.currentPage}/${sourceFile.pageCount} • ${formatFileSize(sourceFile.fileSizeBytes)}',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _vm.isLoading ? null : _vm.pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Ganti PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _vm.openSourceFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Buka Folder'),
                  ),
                ],
              ),
              const Divider(height: 1),
              _ViewerToolbar(
                viewModel: _vm,
                pageInputController: _pageInputController,
                onPreviousPage: () => _navigateToPage(_vm.currentPage - 1),
                onNextPage: () => _navigateToPage(_vm.currentPage + 1),
                onSubmitPage: _submitPageInput,
                onZoomOut: _zoomOut,
                onZoomIn: _zoomIn,
                onFitWidth: _fitWidth,
                onResetZoom: _resetZoom,
                onToggleSearch: _toggleSearch,
              ),
              if (_vm.isSearchOpen)
                _ViewerSearchBar(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  searcher: _textSearcher,
                  onChanged: _onSearchQueryChanged,
                  onPreviousMatch: () {
                    if (_textSearcher.hasMatches) {
                      unawaited(_textSearcher.goToPrevMatch());
                    }
                  },
                  onNextMatch: () {
                    if (_textSearcher.hasMatches) {
                      unawaited(_textSearcher.goToNextMatch());
                    }
                  },
                  onClose: _toggleSearch,
                ),
              if (_vm.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: StatusBanner(
                    errorMessage: _vm.errorMessage,
                    onDismiss: _vm.dismissError,
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showSidebar =
                        _vm.showThumbnails && constraints.maxWidth >= 720;
                    final viewerCanvas = _buildViewerCanvas(
                      context,
                      sourceFile,
                    );

                    if (!showSidebar) {
                      return viewerCanvas;
                    }

                    return Row(
                      children: [
                        _ViewerThumbnailSidebar(
                          sourceFile: sourceFile,
                          document: _loadedDocument,
                          currentPage: _vm.currentPage,
                          onSelectPage: _navigateToPage,
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: viewerCanvas),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewerCanvas(BuildContext context, PdfFileInfo sourceFile) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasTestOverride = PdfThumbnailOverride.maybeOf(context) != null;

    if (hasTestOverride) {
      return Container(
        key: const ValueKey<String>('pdf_viewer_canvas'),
        color: colorScheme.surfaceContainerLowest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 420),
          child: Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: PdfPageThumbnail(
                      filePath: sourceFile.path,
                      pageNumber: _vm.currentPage,
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: colorScheme.surfaceContainerHigh,
                  child: Text(
                    'Halaman ${_vm.currentPage} dari ${sourceFile.pageCount} • ${(_vm.zoom * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('pdf_viewer_canvas'),
      color: colorScheme.surfaceContainerLowest,
      child: PdfViewer.file(
        sourceFile.path,
        key: ValueKey<String>(
          'viewer_${sourceFile.path}#${_vm.documentRevision}',
        ),
        controller: _viewerController,
        params: PdfViewerParams(
          backgroundColor: colorScheme.surfaceContainerLowest,
          enableKeyboardNavigation: true,
          scrollByMouseWheel: 1.0,
          textSelectionParams: const PdfTextSelectionParams(enabled: true),
          pagePaintCallbacks: [
            _textSearcher.pageTextMatchPaintCallback,
          ],
          onPageChanged: (pageNumber) {
            if (pageNumber != null) {
              _vm.setCurrentPageFromViewer(pageNumber);
            }
          },
          onViewerReady: (document, controller) {
            if (mounted) {
              setState(() {
                _loadedDocument = document;
              });
            }
            _vm.setZoom(controller.currentZoom);
          },
          loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          },
          errorBannerBuilder: (context, error, stackTrace, documentRef) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gagal memuat dokumen PDF',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          viewerOverlayBuilder: (context, size, handleLinkTap) => [
            PdfViewerScrollThumb(
              controller: _viewerController,
              orientation: ScrollbarOrientation.right,
              thumbSize: const Size(44, 28),
              thumbBuilder: (context, thumbSize, pageNumber, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.inverseSurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    pageNumber != null ? '$pageNumber' : '',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.viewModel,
    required this.pageInputController,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onSubmitPage,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onResetZoom,
    required this.onToggleSearch,
  });

  final PdfViewerViewModel viewModel;
  final TextEditingController pageInputController;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<String> onSubmitPage;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFitWidth;
  final VoidCallback onResetZoom;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pageCount = viewModel.sourceFile?.pageCount ?? 0;
    final zoomPercent = (viewModel.zoom * 100).round();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: _ViewerHorizontalScrollBar(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: viewModel.toggleThumbnails,
              tooltip: viewModel.showThumbnails
                  ? 'Sembunyikan panel halaman'
                  : 'Tampilkan panel halaman',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                viewModel.showThumbnails
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
                size: 20,
                color: viewModel.showThumbnails ? colorScheme.primary : null,
              ),
            ),
            const SizedBox(
              height: 22,
              child: VerticalDivider(width: 14),
            ),
            IconButton(
              onPressed: viewModel.canGoPrevious ? onPreviousPage : null,
              tooltip: 'Halaman sebelumnya',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
            ),
            SizedBox(
              width: 52,
              height: 30,
              child: TextField(
                controller: pageInputController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onSubmitted: onSubmitPage,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '/ $pageCount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: viewModel.canGoNext ? onNextPage : null,
              tooltip: 'Halaman berikutnya',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded, size: 22),
            ),
            const SizedBox(
              height: 22,
              child: VerticalDivider(width: 14),
            ),
            IconButton(
              onPressed: onZoomOut,
              tooltip: 'Perkecil (Zoom Out)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.zoom_out_rounded, size: 20),
            ),
            TextButton(
              onPressed: onResetZoom,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(54, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                '$zoomPercent%',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onZoomIn,
              tooltip: 'Perbesar (Zoom In)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.zoom_in_rounded, size: 20),
            ),
            IconButton(
              onPressed: onFitWidth,
              tooltip: 'Sesuaikan lebar halaman',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.fit_screen_outlined, size: 20),
            ),
            const SizedBox(
              height: 22,
              child: VerticalDivider(width: 14),
            ),
            IconButton(
              onPressed: onToggleSearch,
              tooltip: 'Cari teks dalam PDF',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.search_rounded,
                size: 20,
                color: viewModel.isSearchOpen ? colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerSearchBar extends StatelessWidget {
  const _ViewerSearchBar({
    required this.controller,
    required this.focusNode,
    required this.searcher,
    required this.onChanged,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PdfTextSearcher searcher;
  final ValueChanged<String> onChanged;
  final VoidCallback onPreviousMatch;
  final VoidCallback onNextMatch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = controller.text.trim().isNotEmpty;
    final matchCount = searcher.matches.length;
    final currentIdx = searcher.currentIndex;
    final statusText = !hasQuery
        ? ''
        : searcher.isSearching
            ? 'Mencari...'
            : matchCount == 0
                ? '0 hasil'
                : '${(currentIdx ?? 0) + 1} / $matchCount';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (_) => onNextMatch(),
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  hintText: 'Cari teks di dalam dokumen...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              statusText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            onPressed: searcher.hasMatches ? onPreviousMatch : null,
            tooltip: 'Hasil sebelumnya',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
          ),
          IconButton(
            onPressed: searcher.hasMatches ? onNextMatch : null,
            tooltip: 'Hasil berikutnya',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Tutup pencarian',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ViewerThumbnailSidebar extends StatelessWidget {
  const _ViewerThumbnailSidebar({
    required this.sourceFile,
    required this.document,
    required this.currentPage,
    required this.onSelectPage,
  });

  final PdfFileInfo sourceFile;
  final PdfDocument? document;
  final int currentPage;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 164,
      color: colorScheme.surfaceContainerLow,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: sourceFile.pageCount,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          final isSelected = pageNumber == currentPage;

          return InkWell(
            onTap: () => onSelectPage(pageNumber),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: PdfPageThumbnail(
                        filePath: sourceFile.path,
                        pageNumber: pageNumber,
                        document: document,
                        maximumDpi: 96,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hal $pageNumber',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ViewerHorizontalScrollBar extends StatefulWidget {
  const _ViewerHorizontalScrollBar({required this.child});

  final Widget child;

  @override
  State<_ViewerHorizontalScrollBar> createState() =>
      _ViewerHorizontalScrollBarState();
}

class _ViewerHorizontalScrollBarState
    extends State<_ViewerHorizontalScrollBar> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && _controller.hasClients) {
          final delta = event.scrollDelta.dy != 0
              ? event.scrollDelta.dy
              : event.scrollDelta.dx;
          if (delta != 0) {
            final target = (_controller.offset + delta)
                .clamp(0.0, _controller.position.maxScrollExtent);
            _controller.jumpTo(target);
          }
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: widget.child,
        ),
      ),
    );
  }
}
