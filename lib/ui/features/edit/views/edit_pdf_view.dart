import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/domain/models/pdf_edit_overlay.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/edit/view_models/edit_pdf_view_model.dart';

double _normalizedDistance(NormalizedPoint a, NormalizedPoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Workspace view for direct in-app PDF editing (text, whiteout, highlight,
/// freehand pen, boxes, signatures, and images).
class EditPdfView extends StatelessWidget {
  /// Creates an [EditPdfView].
  const EditPdfView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving interactive PDF editing state and commands.
  final EditPdfViewModel viewModel;

  /// Whether this tab is currently visible in the shell.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final sourceFile = viewModel.sourceFile;
        if (sourceFile == null) {
          return Column(
            children: [
              WorkspaceHeader(
                icon: Icons.edit_note_rounded,
                title: 'Edit PDF',
                subtitle:
                    'Tambahkan teks, whiteout penutup teks, highlight, tanda tangan, gambar, dan coretan di atas PDF.',
                actions: [
                  FilledButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Pilih PDF'),
                  ),
                ],
              ),
              const Divider(),
              if (viewModel.errorMessage != null || viewModel.lastResult != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 520 ? 14.0 : 24.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        14,
                        horizontalPadding,
                        0,
                      ),
                      child: StatusBanner(
                        errorMessage: viewModel.errorMessage,
                        result: viewModel.lastResult,
                        onOpenFolder: viewModel.openLastOutputFolder,
                        onDismiss: viewModel.dismissStatus,
                      ),
                    );
                  },
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PdfDropZone(
                    enableDrop: isActive,
                    icon: Icons.draw_outlined,
                    title: 'Tarik & lepas file PDF untuk diedit',
                    subtitle:
                        'Ketuk halaman untuk mengetik teks, gunakan Whiteout untuk menutupi teks lama, Highlight, Pena, Kotak, Tanda Tangan, atau sisipkan Gambar.',
                    buttonLabel: 'Buka File PDF',
                    onBrowsePressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    onFilesDropped: (paths, ignoredCount) {
                      viewModel.loadFromDroppedPaths(
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
          enableDrop: isActive,
          overlayMessage: 'Lepaskan file PDF untuk dibuka di editor',
          onFilesDropped: (paths, ignoredCount) {
            viewModel.loadFromDroppedPaths(
              paths,
              ignoredNonPdfCount: ignoredCount,
            );
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.edit_note_rounded,
                title: 'Edit PDF',
                subtitle:
                    '${sourceFile.fileName} • Hal ${viewModel.currentPage}/${sourceFile.pageCount} • ${viewModel.totalOverlayCount} anotasi',
                actions: [
                  OutlinedButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Ganti PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: viewModel.canSave
                        ? viewModel.saveEditedPdf
                        : null,
                    icon: viewModel.isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(
                      viewModel.isProcessing ? 'Menyimpan...' : 'Simpan PDF',
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),
              _EditToolbar(
                viewModel: viewModel,
                onOpenSignaturePad: () => _openSignatureDialog(context),
              ),
              _EditPropertiesBar(
                viewModel: viewModel,
                onEditSelectedText: (overlay) =>
                    _openEditTextDialog(context, overlay),
              ),
              if (viewModel.errorMessage != null || viewModel.lastResult != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 520 ? 12.0 : 20.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        8,
                        horizontalPadding,
                        0,
                      ),
                      child: StatusBanner(
                        errorMessage: viewModel.errorMessage,
                        result: viewModel.lastResult,
                        onOpenFolder: viewModel.openLastOutputFolder,
                        onDismiss: viewModel.dismissStatus,
                      ),
                    );
                  },
                ),
              Expanded(
                child: _LoadedPdfDocumentScope(
                  sourceKey:
                      '${sourceFile.path}#${viewModel.documentRevision}',
                  bytes: viewModel.sourceBytes,
                  builder: (context, document) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final showThumbRail = constraints.maxWidth >= 820;
                        final canvasColumn = Column(
                          children: [
                            Expanded(
                              child: _InteractivePdfCanvas(
                                viewModel: viewModel,
                                sourceFile: sourceFile,
                                document: document,
                                onRequestAddText: (point) =>
                                    _openNewTextDialog(context, point),
                                onRequestEditText: (overlay) =>
                                    _openEditTextDialog(context, overlay),
                              ),
                            ),
                            _EditorBottomBar(
                              viewModel: viewModel,
                              pageCount: sourceFile.pageCount,
                            ),
                          ],
                        );

                        if (!showThumbRail) {
                          return canvasColumn;
                        }

                        return Row(
                          children: [
                            _PageThumbnailsRail(
                              viewModel: viewModel,
                              sourceFile: sourceFile,
                              document: document,
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: canvasColumn),
                          ],
                        );
                      },
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

  Future<void> _openNewTextDialog(
    BuildContext context,
    NormalizedPoint point,
  ) async {
    final result = await _showTextInputDialog(
      context: context,
      title: 'Tambah Teks',
      confirmLabel: 'Tambah',
      initialText: '',
      initialWhiteBackground: viewModel.textWhiteBackground,
    );
    if (result == null || result.text.trim().isEmpty) return;
    viewModel.addTextOverlay(
      x: point.x,
      y: point.y,
      text: result.text,
      whiteBackground: result.whiteBackground,
    );
  }

  Future<void> _openEditTextDialog(
    BuildContext context,
    PdfTextOverlay overlay,
  ) async {
    final result = await _showTextInputDialog(
      context: context,
      title: 'Ubah Teks',
      confirmLabel: 'Simpan',
      initialText: overlay.text,
      initialWhiteBackground: overlay.backgroundColorArgb != null,
    );
    if (result == null) return;
    viewModel.updateSelectedText(
      result.text,
      whiteBackground: result.whiteBackground,
    );
  }

  Future<void> _openSignatureDialog(BuildContext context) async {
    final strokes = await _showSignaturePadDialog(context);
    if (strokes == null || strokes.isEmpty) return;
    viewModel.insertSignatureStrokes(strokes);
  }
}

class _EditToolbar extends StatelessWidget {
  const _EditToolbar({
    required this.viewModel,
    required this.onOpenSignaturePad,
  });

  final EditPdfViewModel viewModel;
  final VoidCallback onOpenSignaturePad;

  IconData _toolIcon(PdfEditTool tool) {
    return switch (tool) {
      PdfEditTool.select => Icons.near_me_outlined,
      PdfEditTool.text => Icons.title_rounded,
      PdfEditTool.whiteout => Icons.cleaning_services_outlined,
      PdfEditTool.highlight => Icons.highlight_rounded,
      PdfEditTool.pen => Icons.gesture_rounded,
      PdfEditTool.rectangle => Icons.crop_square_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabled = viewModel.isProcessing;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            for (final tool in PdfEditTool.values) ...[
              ChoiceChip(
                avatar: Icon(_toolIcon(tool), size: 16),
                label: Text(tool.label),
                selected: viewModel.activeTool == tool,
                visualDensity: VisualDensity.compact,
                onSelected: disabled ? null : (_) => viewModel.selectTool(tool),
              ),
              const SizedBox(width: 6),
            ],
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 12),
            ),
            ActionChip(
              avatar: const Icon(Icons.draw_rounded, size: 16),
              label: const Text('Tanda Tangan'),
              visualDensity: VisualDensity.compact,
              onPressed: disabled ? null : onOpenSignaturePad,
            ),
            const SizedBox(width: 6),
            ActionChip(
              avatar: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('Gambar'),
              visualDensity: VisualDensity.compact,
              onPressed: disabled ? null : viewModel.pickAndInsertImage,
            ),
            const SizedBox(
              height: 24,
              child: VerticalDivider(width: 12),
            ),
            IconButton(
              onPressed: viewModel.canUndo ? viewModel.undo : null,
              tooltip: 'Urungkan (Undo)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo_rounded, size: 20),
            ),
            IconButton(
              onPressed: viewModel.canRedo ? viewModel.redo : null,
              tooltip: 'Ulangi (Redo)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo_rounded, size: 20),
            ),
            IconButton(
              onPressed: !disabled && viewModel.selectedOverlay != null
                  ? viewModel.deleteSelectedOverlay
                  : null,
              tooltip: 'Hapus anotasi terpilih',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: viewModel.selectedOverlay != null && !disabled
                    ? colorScheme.error
                    : null,
              ),
            ),
            TextButton.icon(
              onPressed: !disabled && viewModel.currentPageOverlays.isNotEmpty
                  ? viewModel.clearCurrentPageOverlays
                  : null,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.layers_clear_outlined, size: 18),
              label: const Text('Bersihkan Hal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditPropertiesBar extends StatelessWidget {
  const _EditPropertiesBar({
    required this.viewModel,
    required this.onEditSelectedText,
  });

  final EditPdfViewModel viewModel;
  final ValueChanged<PdfTextOverlay> onEditSelectedText;

  static const List<int> _inkColors = <int>[
    0xFF111827,
    0xFF1D4ED8,
    0xFFDC2626,
    0xFF15803D,
    0xFFFFFFFF,
  ];

  static const List<int> _whiteoutColors = <int>[
    0xFFFFFFFF,
    0xFFFEFCE8,
    0xFFF3F4F6,
    0xFF111827,
  ];

  static const List<int> _highlightColors = <int>[
    0x66FACC15,
    0x664ADE80,
    0x6638BDF8,
    0x66F472B6,
  ];

  static const List<double> _strokeWidths = <double>[1.5, 2.5, 4.0, 6.0];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = viewModel.selectedOverlay;
    final tool = viewModel.activeTool;
    final disabled = viewModel.isProcessing;

    final isTextContext = selected is PdfTextOverlay ||
        (selected == null && tool == PdfEditTool.text);
    final isWhiteoutContext =
        (selected is PdfRectOverlay &&
                selected.kind == PdfRectOverlayKind.whiteout) ||
            (selected == null && tool == PdfEditTool.whiteout);
    final isHighlightContext =
        (selected is PdfRectOverlay &&
                selected.kind == PdfRectOverlayKind.highlight) ||
            (selected == null && tool == PdfEditTool.highlight);
    final isStrokeContext = selected is PdfStrokeOverlay ||
        (selected is PdfRectOverlay &&
            selected.kind == PdfRectOverlayKind.outline) ||
        (selected == null &&
            (tool == PdfEditTool.pen || tool == PdfEditTool.rectangle));

    final palette = isWhiteoutContext
        ? _whiteoutColors
        : isHighlightContext
            ? _highlightColors
            : (isTextContext || isStrokeContext)
                ? _inkColors
                : const <int>[];
    final activeColor = viewModel.effectiveColorArgb;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (palette.isNotEmpty) ...[
              Text(
                'Warna:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              for (final colorValue in palette) ...[
                _ColorSwatchButton(
                  colorArgb: colorValue,
                  selected: activeColor == colorValue,
                  onTap:
                      disabled ? null : () => viewModel.setActiveColor(colorValue),
                ),
                const SizedBox(width: 6),
              ],
            ],
            if (isTextContext) ...[
              const SizedBox(
                height: 22,
                child: VerticalDivider(width: 14),
              ),
              Text(
                'Ukuran:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                onPressed: disabled || viewModel.effectiveFontSizePt <= 8
                    ? null
                    : () =>
                        viewModel.setFontSize(viewModel.effectiveFontSizePt - 2),
                tooltip: 'Perkecil font',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              Text(
                '${viewModel.effectiveFontSizePt.round()} pt',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: disabled || viewModel.effectiveFontSizePt >= 48
                    ? null
                    : () =>
                        viewModel.setFontSize(viewModel.effectiveFontSizePt + 2),
                tooltip: 'Perbesar font',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
              const SizedBox(width: 4),
              FilterChip(
                label: const Text('Tebal'),
                selected: viewModel.effectiveIsTextBold,
                visualDensity: VisualDensity.compact,
                onSelected: disabled ? null : (_) => viewModel.toggleTextBold(),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Latar Putih'),
                selected: viewModel.effectiveTextWhiteBackground,
                visualDensity: VisualDensity.compact,
                onSelected: disabled
                    ? null
                    : (_) => viewModel.toggleTextWhiteBackground(),
              ),
              if (selected is PdfTextOverlay) ...[
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed:
                      disabled ? null : () => onEditSelectedText(selected),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Ubah Teks'),
                ),
              ] else ...[
                const SizedBox(width: 8),
                Text(
                  'Ketuk area halaman untuk mengetik teks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else if (isStrokeContext) ...[
              const SizedBox(
                height: 22,
                child: VerticalDivider(width: 14),
              ),
              Text(
                'Tebal Garis:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              for (final w in _strokeWidths) ...[
                ChoiceChip(
                  label: Text('${w == w.roundToDouble() ? w.round() : w}pt'),
                  selected:
                      (viewModel.effectiveStrokeWidthPt - w).abs() < 0.01,
                  visualDensity: VisualDensity.compact,
                  onSelected:
                      disabled ? null : (_) => viewModel.setStrokeWidth(w),
                ),
                const SizedBox(width: 6),
              ],
            ] else if (selected is PdfImageOverlay) ...[
              Icon(
                Icons.image_outlined,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '${selected.fileName} • Seret untuk pindah atau tarik sudut kanan-bawah untuk ubah ukuran',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (isWhiteoutContext || isHighlightContext) ...[
              const SizedBox(
                height: 22,
                child: VerticalDivider(width: 14),
              ),
              Text(
                isWhiteoutContext
                    ? 'Seret pada halaman untuk menutupi teks/bagian'
                    : 'Seret pada halaman untuk menandai teks',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              Text(
                selected == null
                    ? 'Ketuk anotasi untuk memilih, seret untuk memindah, atau tarik sudut kanan-bawah'
                    : 'Seret anotasi untuk memindah atau tarik sudut kanan-bawah untuk ubah ukuran',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.colorArgb,
    required this.selected,
    required this.onTap,
  });

  final int colorArgb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayColor = Color(withArgbAlpha(colorArgb, 0xFF));

    return Tooltip(
      message: 'Pilih warna',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: displayColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: selected ? 2.5 : 1.2,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: displayColor.computeLuminance() > 0.6
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _LoadedPdfDocumentScope extends StatefulWidget {
  const _LoadedPdfDocumentScope({
    required this.sourceKey,
    required this.bytes,
    required this.builder,
  });

  final String sourceKey;
  final Uint8List? bytes;
  final Widget Function(BuildContext context, PdfDocument? document) builder;

  @override
  State<_LoadedPdfDocumentScope> createState() =>
      _LoadedPdfDocumentScopeState();
}

class _LoadedPdfDocumentScopeState extends State<_LoadedPdfDocumentScope> {
  PdfDocumentRefData? _documentRef;

  @override
  void initState() {
    super.initState();
    _syncDocumentRef();
  }

  @override
  void didUpdateWidget(_LoadedPdfDocumentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey ||
        !identical(oldWidget.bytes, widget.bytes)) {
      _syncDocumentRef();
    }
  }

  void _syncDocumentRef() {
    final data = widget.bytes;
    _documentRef = data != null
        ? PdfDocumentRefData(
            data,
            sourceName: 'edit_${widget.sourceKey}',
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final hasOverride = PdfThumbnailOverride.maybeOf(context) != null;
    if (hasOverride || _documentRef == null) {
      return widget.builder(context, null);
    }

    return PdfDocumentViewBuilder(
      documentRef: _documentRef!,
      loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, error, _) => Center(
        child: Text('Gagal memuat pratinjau PDF: $error'),
      ),
      builder: (context, document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, document);
      },
    );
  }
}

class _PageThumbnailsRail extends StatelessWidget {
  const _PageThumbnailsRail({
    required this.viewModel,
    required this.sourceFile,
    required this.document,
  });

  final EditPdfViewModel viewModel;
  final PdfFileInfo sourceFile;
  final PdfDocument? document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 152,
      color: colorScheme.surfaceContainerLow,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        itemCount: sourceFile.pageCount,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final pageNum = index + 1;
          final isCurrent = pageNum == viewModel.currentPage;
          final count = viewModel.overlayCountForPage(pageNum);

          return InkWell(
            onTap: () => viewModel.goToPage(pageNum),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCurrent
                    ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCurrent
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: PdfPageThumbnail(
                        filePath: sourceFile.path,
                        pageNumber: pageNum,
                        document: document,
                        maximumDpi: 96,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hal $pageNum',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
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

class _EditorBottomBar extends StatelessWidget {
  const _EditorBottomBar({
    required this.viewModel,
    required this.pageCount,
  });

  final EditPdfViewModel viewModel;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: viewModel.currentPage > 1
                    ? viewModel.previousPage
                    : null,
                tooltip: 'Halaman sebelumnya',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              Text(
                'Hal ${viewModel.currentPage}/$pageCount',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: viewModel.currentPage < pageCount
                    ? viewModel.nextPage
                    : null,
                tooltip: 'Halaman berikutnya',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: viewModel.zoom > 0.5 ? viewModel.zoomOut : null,
                tooltip: 'Perkecil',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.zoom_out_rounded, size: 20),
              ),
              TextButton(
                onPressed: viewModel.zoom != 1.0 ? viewModel.resetZoom : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: Text('${(viewModel.zoom * 100).round()}%'),
              ),
              IconButton(
                onPressed: viewModel.zoom < 3.0 ? viewModel.zoomIn : null,
                tooltip: 'Perbesar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.zoom_in_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InteractivePdfCanvas extends StatefulWidget {
  const _InteractivePdfCanvas({
    required this.viewModel,
    required this.sourceFile,
    required this.document,
    required this.onRequestAddText,
    required this.onRequestEditText,
  });

  final EditPdfViewModel viewModel;
  final PdfFileInfo sourceFile;
  final PdfDocument? document;
  final ValueChanged<NormalizedPoint> onRequestAddText;
  final ValueChanged<PdfTextOverlay> onRequestEditText;

  @override
  State<_InteractivePdfCanvas> createState() => _InteractivePdfCanvasState();
}

class _InteractivePdfCanvasState extends State<_InteractivePdfCanvas> {
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();

  NormalizedPoint? _rectStart;
  NormalizedPoint? _rectEnd;
  List<NormalizedPoint>? _activePenPoints;
  int _penRevision = 0;

  Offset? _dragStartLocal;
  PdfEditOverlay? _dragStartOverlay;
  List<PdfEditOverlay>? _dragBeforeSnapshot;

  Offset? _resizeStartLocal;
  PdfEditOverlay? _resizeStartOverlay;
  List<PdfEditOverlay>? _resizeBeforeSnapshot;

  NormalizedPoint? _pendingDoubleTapPoint;

  @override
  void dispose() {
    _vScrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  NormalizedPoint _toNormalized(Offset localPos, double w, double h) {
    return NormalizedPoint(
      w > 0 ? localPos.dx / w : 0,
      h > 0 ? localPos.dy / h : 0,
    );
  }

  Rect _measureOverlayCanvasRect(
    PdfEditOverlay overlay,
    double canvasW,
    double canvasH,
    double scale,
  ) {
    switch (overlay) {
      case PdfRectOverlay():
        return Rect.fromLTWH(
          overlay.rect.left * canvasW,
          overlay.rect.top * canvasH,
          overlay.rect.width * canvasW,
          overlay.rect.height * canvasH,
        );
      case PdfImageOverlay():
        return Rect.fromLTWH(
          overlay.rect.left * canvasW,
          overlay.rect.top * canvasH,
          overlay.rect.width * canvasW,
          overlay.rect.height * canvasH,
        );
      case PdfStrokeOverlay():
        final b = overlay.bounds;
        return Rect.fromLTWH(
          b.left * canvasW,
          b.top * canvasH,
          b.width * canvasW,
          b.height * canvasH,
        );
      case PdfTextOverlay():
        final fontSizePx = overlay.fontSizePt * scale;
        final painter = TextPainter(
          text: TextSpan(
            text: overlay.text,
            style: TextStyle(
              fontSize: fontSizePx,
              height: 1.25,
              fontWeight: overlay.isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(40, (1.0 - overlay.x) * canvasW));
        final bgPadH = overlay.backgroundColorArgb != null ? 8.0 * scale : 4.0;
        final bgPadV = overlay.backgroundColorArgb != null ? 4.0 * scale : 2.0;
        return Rect.fromLTWH(
          overlay.x * canvasW,
          overlay.y * canvasH,
          math.max(24.0, painter.width + bgPadH),
          math.max(18.0, painter.height + bgPadV),
        );
    }
  }

  PdfEditOverlay? _hitTestOverlay(
    Offset localPos,
    double canvasW,
    double canvasH,
    double scale,
  ) {
    final pageOverlays = widget.viewModel.currentPageOverlays;
    for (var i = pageOverlays.length - 1; i >= 0; i--) {
      final overlay = pageOverlays[i];
      final rect =
          _measureOverlayCanvasRect(overlay, canvasW, canvasH, scale).inflate(6);
      if (rect.contains(localPos)) {
        return overlay;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final colorScheme = Theme.of(context).colorScheme;
    final pageSize = vm.pageSizeFor(vm.currentPage);
    final pageOverlays = vm.currentPageOverlays;
    final selected = vm.selectedOverlay;
    final activeTool = vm.activeTool;

    final cursor = switch (activeTool) {
      PdfEditTool.select => SystemMouseCursors.move,
      PdfEditTool.text => SystemMouseCursors.text,
      PdfEditTool.whiteout ||
      PdfEditTool.highlight ||
      PdfEditTool.pen ||
      PdfEditTool.rectangle =>
        SystemMouseCursors.precise,
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainer),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const padding = 16.0;
          final maxW = math.max(200.0, constraints.maxWidth - padding * 2);
          final maxH = math.max(240.0, constraints.maxHeight - padding * 2);
          final fitScale =
              math.min(maxW / pageSize.width, maxH / pageSize.height);
          final scale = fitScale * vm.zoom;
          final canvasW = pageSize.width * scale;
          final canvasH = pageSize.height * scale;

          final selectedBox = selected != null &&
                  selected.pageNumber == vm.currentPage
              ? _measureOverlayCanvasRect(selected, canvasW, canvasH, scale)
              : null;
          final isSelectedResizable = selected is PdfRectOverlay ||
              selected is PdfImageOverlay ||
              selected is PdfStrokeOverlay;

          return Scrollbar(
            controller: _vScrollController,
            child: SingleChildScrollView(
              controller: _vScrollController,
              child: SingleChildScrollView(
                controller: _hScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(padding),
                      child: MouseRegion(
                        cursor: cursor,
                        child: SizedBox(
                          key: const ValueKey<String>('edit_pdf_page_canvas'),
                          width: canvasW,
                          height: canvasH,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: PdfPageThumbnail(
                                        filePath: widget.sourceFile.path,
                                        pageNumber: vm.currentPage,
                                        document: widget.document,
                                        maximumDpi: 200,
                                      ),
                                    ),
                                  ),
                                  for (final overlay in pageOverlays)
                                    _buildOverlayLayer(
                                      overlay: overlay,
                                      canvasW: canvasW,
                                      canvasH: canvasH,
                                      scale: scale,
                                    ),
                                  if (_rectStart != null && _rectEnd != null)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _DraftRectPainter(
                                            rect: NormalizedRect.fromPoints(
                                              _rectStart!,
                                              _rectEnd!,
                                            ),
                                            tool: activeTool,
                                            colorArgb: vm.effectiveColorArgb ??
                                                0xFFDC2626,
                                            strokeWidthPx:
                                                vm.effectiveStrokeWidthPt *
                                                    scale,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_activePenPoints != null &&
                                      _activePenPoints!.isNotEmpty)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _StrokePainter(
                                            strokes: <List<NormalizedPoint>>[
                                              _activePenPoints!,
                                            ],
                                            colorArgb: vm.strokeColorArgb,
                                            strokeWidthPx:
                                                vm.strokeWidthPt * scale,
                                            revision: _penRevision,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (selectedBox != null)
                                    Positioned.fromRect(
                                      rect: selectedBox,
                                      child: IgnorePointer(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: colorScheme.primary,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (details) => _handleTapUp(
                                        details,
                                        canvasW,
                                        canvasH,
                                        scale,
                                      ),
                                      onDoubleTapDown:
                                          activeTool == PdfEditTool.select
                                              ? (details) =>
                                                  _pendingDoubleTapPoint =
                                                      _toNormalized(
                                                    details.localPosition,
                                                    canvasW,
                                                    canvasH,
                                                  )
                                              : null,
                                      onDoubleTap:
                                          activeTool == PdfEditTool.select
                                              ? () => _handleDoubleTap(
                                                    canvasW,
                                                    canvasH,
                                                    scale,
                                                  )
                                              : null,
                                      onPanStart: (details) => _handlePanStart(
                                        details,
                                        canvasW,
                                        canvasH,
                                        scale,
                                      ),
                                      onPanUpdate: (details) => _handlePanUpdate(
                                        details,
                                        canvasW,
                                        canvasH,
                                      ),
                                      onPanEnd: (_) => _handlePanEnd(),
                                      onPanCancel: _handlePanCancel,
                                    ),
                                  ),
                                  if (selectedBox != null && isSelectedResizable)
                                    Positioned(
                                      left: (selectedBox.right - 9)
                                          .clamp(0.0, canvasW - 18),
                                      top: (selectedBox.bottom - 9)
                                          .clamp(0.0, canvasH - 18),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onPanStart: (details) {
                                          _resizeStartLocal =
                                              details.globalPosition;
                                          _resizeStartOverlay = selected;
                                          _resizeBeforeSnapshot =
                                              vm.captureSnapshot();
                                        },
                                        onPanUpdate: (details) =>
                                            _handleResizeUpdate(
                                          details,
                                          canvasW,
                                          canvasH,
                                        ),
                                        onPanEnd: (_) {
                                          if (_resizeBeforeSnapshot != null) {
                                            vm.commitSnapshot(
                                              _resizeBeforeSnapshot!,
                                            );
                                          }
                                          _resizeStartLocal = null;
                                          _resizeStartOverlay = null;
                                          _resizeBeforeSnapshot = null;
                                        },
                                        onPanCancel: () {
                                          _resizeStartLocal = null;
                                          _resizeStartOverlay = null;
                                          _resizeBeforeSnapshot = null;
                                        },
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors
                                              .resizeDownRight,
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: colorScheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlayLayer({
    required PdfEditOverlay overlay,
    required double canvasW,
    required double canvasH,
    required double scale,
  }) {
    switch (overlay) {
      case PdfRectOverlay():
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _RectOverlayPainter(
                overlay: overlay,
                scale: scale,
              ),
            ),
          ),
        );
      case PdfStrokeOverlay():
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _StrokePainter(
                strokes: overlay.strokes,
                colorArgb: overlay.colorArgb,
                strokeWidthPx: overlay.strokeWidthPt * scale,
              ),
            ),
          ),
        );
      case PdfImageOverlay():
        final left = overlay.rect.left * canvasW;
        final top = overlay.rect.top * canvasH;
        final width = overlay.rect.width * canvasW;
        final height = overlay.rect.height * canvasH;
        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: IgnorePointer(
            child: Image.memory(
              overlay.imageBytes,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                color: Colors.grey.shade200,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        );
      case PdfTextOverlay():
        final fontSizePx = overlay.fontSizePt * scale;
        final left = overlay.x * canvasW;
        final top = overlay.y * canvasH;
        final hasBg = overlay.backgroundColorArgb != null;
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: Container(
              padding: hasBg
                  ? EdgeInsets.symmetric(
                      horizontal: 4 * scale,
                      vertical: 2 * scale,
                    )
                  : EdgeInsets.zero,
              color: hasBg ? Color(overlay.backgroundColorArgb!) : null,
              child: Text(
                overlay.text,
                style: TextStyle(
                  color: Color(overlay.colorArgb),
                  fontSize: fontSizePx,
                  height: 1.25,
                  fontWeight:
                      overlay.isBold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
    }
  }

  void _handleTapUp(
    TapUpDetails details,
    double canvasW,
    double canvasH,
    double scale,
  ) {
    final vm = widget.viewModel;
    if (vm.isProcessing) return;

    final point = _toNormalized(details.localPosition, canvasW, canvasH);
    switch (vm.activeTool) {
      case PdfEditTool.text:
        widget.onRequestAddText(point);
      case PdfEditTool.select:
        final hit = _hitTestOverlay(
          details.localPosition,
          canvasW,
          canvasH,
          scale,
        );
        vm.selectOverlay(hit?.id);
      case PdfEditTool.whiteout:
      case PdfEditTool.highlight:
      case PdfEditTool.pen:
      case PdfEditTool.rectangle:
        break;
    }
  }

  void _handleDoubleTap(
    double canvasW,
    double canvasH,
    double scale,
  ) {
    final vm = widget.viewModel;
    final pt = _pendingDoubleTapPoint;
    _pendingDoubleTapPoint = null;
    if (vm.isProcessing || vm.activeTool != PdfEditTool.select || pt == null) {
      return;
    }
    final hit = _hitTestOverlay(
      Offset(pt.x * canvasW, pt.y * canvasH),
      canvasW,
      canvasH,
      scale,
    );
    if (hit is PdfTextOverlay) {
      vm.selectOverlay(hit.id);
      widget.onRequestEditText(hit);
    }
  }

  void _handlePanStart(
    DragStartDetails details,
    double canvasW,
    double canvasH,
    double scale,
  ) {
    final vm = widget.viewModel;
    if (vm.isProcessing) return;

    final pt = _toNormalized(details.localPosition, canvasW, canvasH);
    switch (vm.activeTool) {
      case PdfEditTool.whiteout:
      case PdfEditTool.highlight:
      case PdfEditTool.rectangle:
        setState(() {
          _rectStart = pt;
          _rectEnd = pt;
        });
      case PdfEditTool.pen:
        setState(() {
          _activePenPoints = <NormalizedPoint>[pt];
          _penRevision++;
        });
      case PdfEditTool.select:
        final hit = _hitTestOverlay(
          details.localPosition,
          canvasW,
          canvasH,
          scale,
        );
        if (hit != null) {
          vm.selectOverlay(hit.id);
          _dragStartLocal = details.localPosition;
          _dragStartOverlay = hit;
          _dragBeforeSnapshot = vm.captureSnapshot();
        }
      case PdfEditTool.text:
        break;
    }
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    double canvasW,
    double canvasH,
  ) {
    final vm = widget.viewModel;
    final pt = _toNormalized(details.localPosition, canvasW, canvasH);

    switch (vm.activeTool) {
      case PdfEditTool.whiteout:
      case PdfEditTool.highlight:
      case PdfEditTool.rectangle:
        if (_rectStart != null) {
          setState(() => _rectEnd = pt);
        }
      case PdfEditTool.pen:
        final pts = _activePenPoints;
        if (pts != null && pts.isNotEmpty) {
          if (_normalizedDistance(pt, pts.last) >= 0.002) {
            setState(() {
              pts.add(pt);
              _penRevision++;
            });
          }
        }
      case PdfEditTool.select:
        if (_dragStartLocal != null && _dragStartOverlay != null) {
          final delta = details.localPosition - _dragStartLocal!;
          final dx = canvasW > 0 ? delta.dx / canvasW : 0.0;
          final dy = canvasH > 0 ? delta.dy / canvasH : 0.0;
          vm.updateOverlayLive(_dragStartOverlay!.translated(dx, dy));
        }
      case PdfEditTool.text:
        break;
    }
  }

  void _handlePanEnd() {
    final vm = widget.viewModel;
    switch (vm.activeTool) {
      case PdfEditTool.whiteout:
      case PdfEditTool.highlight:
      case PdfEditTool.rectangle:
        if (_rectStart != null && _rectEnd != null) {
          final rect = NormalizedRect.fromPoints(_rectStart!, _rectEnd!);
          final kind = switch (vm.activeTool) {
            PdfEditTool.whiteout => PdfRectOverlayKind.whiteout,
            PdfEditTool.highlight => PdfRectOverlayKind.highlight,
            _ => PdfRectOverlayKind.outline,
          };
          vm.addRectOverlay(rect: rect, kind: kind);
        }
        setState(() {
          _rectStart = null;
          _rectEnd = null;
        });
      case PdfEditTool.pen:
        final pts = _activePenPoints;
        if (pts != null && pts.isNotEmpty) {
          vm.addStrokeOverlay(strokes: <List<NormalizedPoint>>[pts]);
        }
        setState(() {
          _activePenPoints = null;
        });
      case PdfEditTool.select:
        if (_dragBeforeSnapshot != null) {
          vm.commitSnapshot(_dragBeforeSnapshot!);
        }
        _dragStartLocal = null;
        _dragStartOverlay = null;
        _dragBeforeSnapshot = null;
      case PdfEditTool.text:
        break;
    }
  }

  void _handlePanCancel() {
    if (_rectStart != null || _activePenPoints != null) {
      setState(() {
        _rectStart = null;
        _rectEnd = null;
        _activePenPoints = null;
      });
    }
    _dragStartLocal = null;
    _dragStartOverlay = null;
    _dragBeforeSnapshot = null;
  }

  void _handleResizeUpdate(
    DragUpdateDetails details,
    double canvasW,
    double canvasH,
  ) {
    final startLocal = _resizeStartLocal;
    final startOverlay = _resizeStartOverlay;
    if (startLocal == null || startOverlay == null) return;

    final delta = details.globalPosition - startLocal;
    final dx = canvasW > 0 ? delta.dx / canvasW : 0.0;
    final dy = canvasH > 0 ? delta.dy / canvasH : 0.0;

    switch (startOverlay) {
      case PdfRectOverlay():
        widget.viewModel.updateOverlayLive(
          startOverlay.copyWith(
            rect: startOverlay.rect.resized(
              startOverlay.rect.width + dx,
              startOverlay.rect.height + dy,
            ),
          ),
        );
      case PdfImageOverlay():
        widget.viewModel.updateOverlayLive(
          startOverlay.copyWith(
            rect: startOverlay.rect.resized(
              startOverlay.rect.width + dx,
              startOverlay.rect.height + dy,
            ),
          ),
        );
      case PdfStrokeOverlay():
        final b = startOverlay.bounds;
        final target = b.resized(b.width + dx, b.height + dy);
        widget.viewModel.updateOverlayLive(startOverlay.resizedTo(target));
      case PdfTextOverlay():
        break;
    }
  }
}

class _RectOverlayPainter extends CustomPainter {
  const _RectOverlayPainter({
    required this.overlay,
    required this.scale,
  });

  final PdfRectOverlay overlay;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      overlay.rect.left * size.width,
      overlay.rect.top * size.height,
      overlay.rect.width * size.width,
      overlay.rect.height * size.height,
    );
    final paint = Paint()..color = Color(overlay.colorArgb);
    switch (overlay.kind) {
      case PdfRectOverlayKind.whiteout:
      case PdfRectOverlayKind.highlight:
        paint.style = PaintingStyle.fill;
      case PdfRectOverlayKind.outline:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = overlay.strokeWidthPt * scale;
    }
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_RectOverlayPainter oldDelegate) {
    return oldDelegate.overlay != overlay || oldDelegate.scale != scale;
  }
}

class _DraftRectPainter extends CustomPainter {
  const _DraftRectPainter({
    required this.rect,
    required this.tool,
    required this.colorArgb,
    required this.strokeWidthPx,
  });

  final NormalizedRect rect;
  final PdfEditTool tool;
  final int colorArgb;
  final double strokeWidthPx;

  @override
  void paint(Canvas canvas, Size size) {
    final drawRect = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );

    if (tool == PdfEditTool.rectangle) {
      canvas.drawRect(
        drawRect,
        Paint()
          ..color = Color(colorArgb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidthPx,
      );
      return;
    }

    canvas.drawRect(
      drawRect,
      Paint()
        ..color = Color(colorArgb)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      drawRect,
      Paint()
        ..color = Colors.blueGrey.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DraftRectPainter oldDelegate) {
    return oldDelegate.rect != rect ||
        oldDelegate.tool != tool ||
        oldDelegate.colorArgb != colorArgb;
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.colorArgb,
    required this.strokeWidthPx,
    this.revision = 0,
  });

  final List<List<NormalizedPoint>> strokes;
  final int colorArgb;
  final double strokeWidthPx;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(colorArgb)
      ..strokeWidth = strokeWidthPx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final polyline in strokes) {
      if (polyline.isEmpty) continue;
      final path = Path()
        ..moveTo(
          polyline.first.x * size.width,
          polyline.first.y * size.height,
        );
      if (polyline.length == 1) {
        path.lineTo(
          polyline.first.x * size.width + 0.1,
          polyline.first.y * size.height,
        );
      } else {
        for (var i = 1; i < polyline.length; i++) {
          path.lineTo(
            polyline[i].x * size.width,
            polyline[i].y * size.height,
          );
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.strokes != strokes ||
        oldDelegate.colorArgb != colorArgb ||
        oldDelegate.strokeWidthPx != strokeWidthPx;
  }
}

Future<({String text, bool whiteBackground})?> _showTextInputDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  required String initialText,
  required bool initialWhiteBackground,
}) {
  return showDialog<({String text, bool whiteBackground})>(
    context: context,
    builder: (dialogContext) {
      return _TextInputDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialText: initialText,
        initialWhiteBackground: initialWhiteBackground,
      );
    },
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialText,
    required this.initialWhiteBackground,
  });

  final String title;
  final String confirmLabel;
  final String initialText;
  final bool initialWhiteBackground;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller;
  late bool _whiteBackground;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _whiteBackground = widget.initialWhiteBackground;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Isi teks',
                  hintText: 'Ketik teks untuk PDF...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _whiteBackground,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Latar putih (tutupi teks di bawah)'),
                onChanged: (value) {
                  setState(() => _whiteBackground = value ?? false);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop((
              text: _controller.text,
              whiteBackground: _whiteBackground,
            ));
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<List<List<NormalizedPoint>>?> _showSignaturePadDialog(
  BuildContext context,
) {
  return showDialog<List<List<NormalizedPoint>>>(
    context: context,
    builder: (dialogContext) => const _SignaturePadDialog(),
  );
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<List<NormalizedPoint>> _strokes = <List<NormalizedPoint>>[];
  List<NormalizedPoint>? _activeStroke;
  int _sigRevision = 0;

  void _startStroke(Offset localPos, Size boxSize) {
    final pt = NormalizedPoint(
      boxSize.width > 0 ? localPos.dx / boxSize.width : 0,
      boxSize.height > 0 ? localPos.dy / boxSize.height : 0,
    );
    setState(() {
      _activeStroke = <NormalizedPoint>[pt];
      _strokes.add(_activeStroke!);
      _sigRevision++;
    });
  }

  void _updateStroke(Offset localPos, Size boxSize) {
    final current = _activeStroke;
    if (current == null || current.isEmpty) return;
    final pt = NormalizedPoint(
      boxSize.width > 0 ? localPos.dx / boxSize.width : 0,
      boxSize.height > 0 ? localPos.dy / boxSize.height : 0,
    );
    if (_normalizedDistance(pt, current.last) >= 0.004) {
      setState(() {
        current.add(pt);
        _sigRevision++;
      });
    }
  }

  void _endStroke() {
    _activeStroke = null;
  }

  static const Size _padSize = Size(320, 180);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasStrokes = _strokes.any((s) => s.isNotEmpty);

    return AlertDialog(
      title: const Text('Buat Tanda Tangan'),
      scrollable: true,
      content: SizedBox(
        width: _padSize.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gambar tanda tangan Anda pada kotak putih di bawah ini.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: _padSize.width,
              height: _padSize.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _startStroke(details.localPosition, _padSize),
                    onPanUpdate: (details) =>
                        _updateStroke(details.localPosition, _padSize),
                    onPanEnd: (_) => _endStroke(),
                    onPanCancel: _endStroke,
                    child: CustomPaint(
                      painter: _StrokePainter(
                        strokes: _strokes,
                        colorArgb: 0xFF1D4ED8,
                        strokeWidthPx: 3.0,
                        revision: _sigRevision,
                      ),
                      child: hasStrokes
                          ? const SizedBox.expand()
                          : Center(
                              child: Text(
                                'Tulis tanda tangan di sini',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.black38,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: hasStrokes
              ? () => setState(() {
                    _strokes.clear();
                    _activeStroke = null;
                    _sigRevision++;
                  })
              : null,
          child: const Text('Bersihkan'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: hasStrokes
              ? () => Navigator.of(context).pop(
                    List<List<NormalizedPoint>>.from(_strokes),
                  )
              : null,
          child: const Text('Pasang Tanda Tangan'),
        ),
      ],
    );
  }
}
