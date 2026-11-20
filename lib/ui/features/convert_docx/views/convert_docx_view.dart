import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/convert_docx/view_models/convert_docx_view_model.dart';

/// Workspace view for converting PDF files to `.docx` via Microsoft Word COM.
class ConvertDocxView extends StatelessWidget {
  /// Creates a [ConvertDocxView].
  const ConvertDocxView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving conversion state and commands.
  final ConvertDocxViewModel viewModel;

  /// Whether this tab is currently visible in the shell.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final items = viewModel.items;
        final wordUnavailable = viewModel.isWordAvailable == false;

        if (items.isEmpty) {
          return Column(
            children: [
              WorkspaceHeader(
                icon: Icons.description_rounded,
                title: 'PDF ke DOCX',
                subtitle:
                    'Konversi dokumen PDF menjadi file Microsoft Word (.docx) secara offline.',
                actions: [
                  FilledButton.icon(
                    onPressed: viewModel.isProcessing
                        ? null
                        : viewModel.pickAndAddFiles,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah PDF'),
                  ),
                ],
              ),
              const Divider(),
              if (wordUnavailable)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: _WordUnavailableCard(),
                ),
              if (viewModel.errorMessage != null || viewModel.lastResult != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
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
                    icon: Icons.article_outlined,
                    title: 'Tarik & lepas file PDF untuk dikonversi',
                    subtitle:
                        'Pilih 1 atau lebih file PDF untuk diubah menjadi dokumen Word (.docx) menggunakan Microsoft Word.',
                    buttonLabel: 'Pilih File PDF',
                    onBrowsePressed: viewModel.isProcessing
                        ? null
                        : viewModel.pickAndAddFiles,
                    onFilesDropped: (paths, ignoredCount) {
                      viewModel.addFilesFromPaths(
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
          overlayMessage:
              'Lepaskan file PDF untuk ditambahkan ke daftar konversi DOCX',
          onFilesDropped: (paths, ignoredCount) {
            viewModel.addFilesFromPaths(
              paths,
              ignoredNonPdfCount: ignoredCount,
            );
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.description_rounded,
                title: 'PDF ke DOCX',
                subtitle:
                    '${items.length} file siap dikonversi • Menggunakan otomasi Microsoft Word',
                actions: [
                  OutlinedButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.clearAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Hapus Semua'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: viewModel.isProcessing
                        ? null
                        : viewModel.pickAndAddFiles,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Tambah PDF'),
                  ),
                ],
              ),
              const Divider(),
              if (wordUnavailable)
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
                      child: const _WordUnavailableCard(),
                    );
                  },
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 520;
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        isPhone ? 14 : 24,
                        isPhone ? 12 : 16,
                        isPhone ? 14 : 24,
                        isPhone ? 12 : 16,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _ConvertDocxItemCard(
                          item: items[index],
                          isProcessing: viewModel.isProcessing,
                          onRemove: () => viewModel.removeAt(index),
                        );
                      },
                    );
                  },
                ),
              ),
              _ConvertDocxActionBar(viewModel: viewModel),
            ],
          ),
        );
      },
    );
  }
}

class _WordUnavailableCard extends StatelessWidget {
  const _WordUnavailableCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Microsoft Word tidak terdeteksi. Fitur PDF ke DOCX membutuhkan Microsoft Word terpasang di Windows.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvertDocxItemCard extends StatelessWidget {
  const _ConvertDocxItemCard({
    required this.item,
    required this.isProcessing,
    required this.onRemove,
  });

  final PdfFileInfo item;
  final bool isProcessing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final folderPath = p.dirname(item.path);
    final targetName = buildDocxFileName(item.fileName);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = constraints.maxWidth < 520;

            final thumbnail = Container(
              width: isPhone ? 42 : 48,
              height: isPhone ? 56 : 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: PdfPageThumbnail(
                filePath: item.path,
                pageNumber: 1,
                maximumDpi: 96,
              ),
            );

            final infoCluster = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  folderPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InfoPill(
                      icon: Icons.description_outlined,
                      label: '${item.pageCount} halaman',
                    ),
                    _InfoPill(
                      icon: Icons.sd_storage_outlined,
                      label: formatFileSize(item.fileSizeBytes),
                    ),
                    _InfoPill(
                      icon: Icons.arrow_forward_rounded,
                      label: targetName,
                      accent: true,
                    ),
                  ],
                ),
              ],
            );

            final removeButton = IconButton(
              onPressed: isProcessing ? null : onRemove,
              tooltip: 'Hapus dari daftar',
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: colorScheme.error,
              ),
            );

            return Row(
              crossAxisAlignment:
                  isPhone ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                thumbnail,
                SizedBox(width: isPhone ? 10 : 14),
                Expanded(child: infoCluster),
                const SizedBox(width: 4),
                removeButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = accent
        ? colorScheme.primaryContainer.withValues(alpha: 0.6)
        : colorScheme.surfaceContainer;
    final fgColor = accent
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fgColor,
                    fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConvertDocxActionBar extends StatelessWidget {
  const _ConvertDocxActionBar({required this.viewModel});

  final ConvertDocxViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = viewModel.items;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 520;

        final summaryBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${items.length} file • Total ${viewModel.totalPages} halaman',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              viewModel.statusDetail ??
                  (items.length == 1
                      ? 'Hasil akan disimpan sebagai dokumen Word (.docx).'
                      : 'Semua file akan dikonversi ke folder tujuan.'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        final convertButton = FilledButton.icon(
          onPressed: viewModel.canConvert ? viewModel.convertAndSave : null,
          icon: viewModel.isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.description_rounded),
          label: Text(
            viewModel.isProcessing
                ? 'Mengonversi...'
                : (items.length == 1
                    ? 'Konversi & Simpan DOCX'
                    : 'Konversi Semua ke DOCX'),
          ),
        );

        return Container(
          padding: EdgeInsets.fromLTRB(
            isPhone ? 16 : 24,
            isPhone ? 12 : 14,
            isPhone ? 16 : 24,
            isPhone ? 14 : 18,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (viewModel.isProcessing && viewModel.progress != null) ...[
                LinearProgressIndicator(value: viewModel.progress),
                const SizedBox(height: 10),
              ],
              if (viewModel.errorMessage != null ||
                  viewModel.lastResult != null) ...[
                StatusBanner(
                  errorMessage: viewModel.errorMessage,
                  result: viewModel.lastResult,
                  onOpenFolder: viewModel.openLastOutputFolder,
                  onDismiss: viewModel.dismissStatus,
                ),
                const SizedBox(height: 12),
              ],
              if (isPhone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    summaryBlock,
                    const SizedBox(height: 10),
                    convertButton,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: summaryBlock),
                    const SizedBox(width: 16),
                    convertButton,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
