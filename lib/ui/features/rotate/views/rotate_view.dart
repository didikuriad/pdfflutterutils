import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/rotate/view_models/rotate_view_model.dart';

/// Workspace view for rotating individual or bulk PDF pages.
class RotateView extends StatelessWidget {
  /// Creates a [RotateView].
  const RotateView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving rotate state and commands.
  final RotateViewModel viewModel;

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
                icon: Icons.rotate_right_rounded,
                title: 'Putar PDF',
                subtitle:
                    'Putar halaman tertentu atau seluruh dokumen PDF secara lossless.',
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: StatusBanner(
                    errorMessage: viewModel.errorMessage,
                    result: viewModel.lastResult,
                    onOpenFolder: viewModel.openLastOutputFolder,
                    onDismiss: viewModel.dismissStatus,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: PdfDropZone(
                    enableDrop: isActive,
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    title: 'Tarik & lepas file PDF untuk diputar',
                    subtitle:
                        'Lihat pratinjau setiap halaman, pilih halaman ganjil/genap atau tertentu, lalu putar ke kiri, kanan, atau 180°.',
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
          overlayMessage: 'Lepaskan file PDF untuk mengganti dokumen aktif',
          onFilesDropped: (paths, ignoredCount) {
            viewModel.loadFromDroppedPaths(
              paths,
              ignoredNonPdfCount: ignoredCount,
            );
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.rotate_right_rounded,
                title: 'Putar PDF',
                subtitle:
                    '${sourceFile.fileName} • ${sourceFile.pageCount} halaman • ${formatFileSize(sourceFile.fileSizeBytes)}',
                actions: [
                  OutlinedButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Ganti PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: viewModel.canSave
                        ? viewModel.saveRotatedPdf
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
              const Divider(),
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
                    child: _RotateToolbar(viewModel: viewModel),
                  );
                },
              ),
              if (viewModel.errorMessage != null || viewModel.lastResult != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding =
                        constraints.maxWidth < 520 ? 14.0 : 24.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
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
                child: _RotatePagesGrid(
                  viewModel: viewModel,
                  sourceFile: sourceFile,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RotateToolbar extends StatelessWidget {
  const _RotateToolbar({required this.viewModel});

  final RotateViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedCount = viewModel.selectedPages.length;
    final targetLabel = selectedCount > 0
        ? 'Terapkan ke $selectedCount halaman terpilih'
        : 'Terapkan ke semua halaman (${viewModel.sourceFile?.pageCount ?? 0})';
    final disabled = viewModel.isProcessing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Pilihan:',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                ActionChip(
                  label: const Text('Pilih Semua'),
                  onPressed: disabled ? null : viewModel.selectAll,
                ),
                ActionChip(
                  label: const Text('Ganjil'),
                  onPressed: disabled ? null : viewModel.selectOddPages,
                ),
                ActionChip(
                  label: const Text('Genap'),
                  onPressed: disabled ? null : viewModel.selectEvenPages,
                ),
                ActionChip(
                  label: const Text('Batal Pilih'),
                  onPressed: disabled || selectedCount == 0
                      ? null
                      : viewModel.clearSelection,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  targetLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: disabled ? null : viewModel.rotateTargetCCW,
                  icon: const Icon(Icons.rotate_left_rounded, size: 18),
                  label: const Text('-90° Kiri'),
                ),
                OutlinedButton.icon(
                  onPressed: disabled ? null : viewModel.rotateTargetCW,
                  icon: const Icon(Icons.rotate_right_rounded, size: 18),
                  label: const Text('+90° Kanan'),
                ),
                OutlinedButton.icon(
                  onPressed: disabled ? null : viewModel.rotateTarget180,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('180°'),
                ),
                TextButton.icon(
                  onPressed:
                      disabled || !viewModel.hasChanges
                          ? null
                          : viewModel.resetRotations,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RotatePagesGrid extends StatelessWidget {
  const _RotatePagesGrid({
    required this.viewModel,
    required this.sourceFile,
  });

  final RotateViewModel viewModel;
  final PdfFileInfo sourceFile;

  @override
  Widget build(BuildContext context) {
    final hasOverride = PdfThumbnailOverride.maybeOf(context) != null;
    if (hasOverride) {
      return _buildGrid(context, document: null);
    }

    return PdfDocumentViewBuilder.file(
      sourceFile.path,
      loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, error, _) => Center(
        child: Text('Gagal memuat pratinjau PDF: $error'),
      ),
      builder: (context, document) {
        if (document == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildGrid(context, document: document);
      },
    );
  }

  Widget _buildGrid(BuildContext context, {required PdfDocument? document}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        return GridView.builder(
          padding: EdgeInsets.all(isPhone ? 14 : 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isPhone ? 185 : 230,
            mainAxisSpacing: isPhone ? 12 : 16,
            crossAxisSpacing: isPhone ? 12 : 16,
            childAspectRatio: 0.70,
          ),
          itemCount: sourceFile.pageCount,
          itemBuilder: (context, index) {
            final pageNumber = index + 1;
            final isSelected = viewModel.selectedPages.contains(pageNumber);
            final rotation = viewModel.rotationForPage(pageNumber);
            return _RotatePageCard(
              filePath: sourceFile.path,
              pageNumber: pageNumber,
              document: document,
              isSelected: isSelected,
              rotation: rotation,
              disabled: viewModel.isProcessing,
              onToggleSelect: () => viewModel.togglePageSelection(pageNumber),
              onRotateCCW: () => viewModel.rotatePageCCW(pageNumber),
              onRotateCW: () => viewModel.rotatePageCW(pageNumber),
            );
          },
        );
      },
    );
  }
}

class _RotatePageCard extends StatelessWidget {
  const _RotatePageCard({
    required this.filePath,
    required this.pageNumber,
    required this.document,
    required this.isSelected,
    required this.rotation,
    required this.disabled,
    required this.onToggleSelect,
    required this.onRotateCCW,
    required this.onRotateCW,
  });

  final String filePath;
  final int pageNumber;
  final PdfDocument? document;
  final bool isSelected;
  final RotationQuarterTurns rotation;
  final bool disabled;
  final VoidCallback onToggleSelect;
  final VoidCallback onRotateCCW;
  final VoidCallback onRotateCW;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : rotation.isRotated
                  ? colorScheme.tertiary
                  : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: disabled ? null : (_) => onToggleSelect(),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Text(
                    'Hal $pageNumber',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (rotation.isRotated) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      rotation.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: disabled ? null : onToggleSelect,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRect(
                  child: Center(
                    child: AnimatedRotation(
                      turns: rotation.quarterTurns / 4,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: 140,
                          height: 190,
                          child: PdfPageThumbnail(
                            filePath: filePath,
                            pageNumber: pageNumber,
                            document: document,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: disabled ? null : onRotateCCW,
                  tooltip: 'Putar kiri 90°',
                  icon: const Icon(Icons.rotate_left_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: disabled ? null : onRotateCW,
                  tooltip: 'Putar kanan 90°',
                  icon: const Icon(Icons.rotate_right_rounded, size: 19),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
