import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/domain/models/merge_item.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/merge/view_models/merge_view_model.dart';

/// Workspace view for combining multiple PDF files in a custom order.
class MergeView extends StatelessWidget {
  /// Creates a [MergeView].
  const MergeView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving merge state and commands.
  final MergeViewModel viewModel;

  /// Whether this tab is currently visible in the shell.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final items = viewModel.items;
        if (items.isEmpty) {
          return Column(
            children: [
              WorkspaceHeader(
                icon: Icons.merge_type_rounded,
                title: 'Gabung PDF',
                subtitle:
                    'Gabungkan beberapa file PDF menjadi satu dokumen sesuai urutan Anda.',
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
                    icon: Icons.library_add_rounded,
                    title: 'Tarik & lepas file PDF di sini',
                    subtitle:
                        'Pilih minimal 2 dokumen PDF untuk digabungkan, atur urutannya, atau tentukan rentang halaman tertentu.',
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

        final rangeErrors = viewModel.rangeErrors;
        return PdfDropWrapper(
          enableDrop: isActive,
          overlayMessage: 'Lepaskan file PDF untuk ditambahkan ke daftar gabung',
          onFilesDropped: (paths, ignoredCount) {
            viewModel.addFilesFromPaths(
              paths,
              ignoredNonPdfCount: ignoredCount,
            );
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.merge_type_rounded,
                title: 'Gabung PDF',
                subtitle:
                    '${items.length} file dalam antrean • Tarik pegangan untuk mengubah urutan atau lepas PDF baru ke layar',
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
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone = constraints.maxWidth < 520;
                    return ReorderableListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        isPhone ? 14 : 24,
                        isPhone ? 12 : 16,
                        isPhone ? 14 : 24,
                        isPhone ? 12 : 16,
                      ),
                      buildDefaultDragHandles: false,
                      itemCount: items.length,
                      onReorderItem: viewModel.reorder,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Padding(
                          key: ValueKey<String>(item.id),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MergeItemCard(
                            item: item,
                            index: index,
                            totalCount: items.length,
                            rangeError: rangeErrors[item.id],
                            isProcessing: viewModel.isProcessing,
                            onRangeChanged: (value) =>
                                viewModel.updatePageRange(item.id, value),
                            onMoveUp: () => viewModel.moveUp(index),
                            onMoveDown: () => viewModel.moveDown(index),
                            onRemove: () => viewModel.removeAt(index),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              _MergeActionBar(viewModel: viewModel),
            ],
          ),
        );
      },
    );
  }
}

class _MergeItemCard extends StatelessWidget {
  const _MergeItemCard({
    required this.item,
    required this.index,
    required this.totalCount,
    required this.rangeError,
    required this.isProcessing,
    required this.onRangeChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final MergeItem item;
  final int index;
  final int totalCount;
  final String? rangeError;
  final bool isProcessing;
  final ValueChanged<String> onRangeChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final folderPath = p.dirname(item.file.path);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = constraints.maxWidth < 520;
            final isCompact = constraints.maxWidth < 720;

            final leadingCluster = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Seret untuk mengurutkan',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: isPhone ? 8 : 12),
                Container(
                  width: isPhone ? 42 : 48,
                  height: isPhone ? 56 : 64,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: PdfPageThumbnail(
                    filePath: item.file.path,
                    pageNumber: 1,
                    maximumDpi: 96,
                  ),
                ),
              ],
            );

            final infoCluster = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.file.fileName,
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
                    _MetadataPill(
                      icon: Icons.description_outlined,
                      label: '${item.file.pageCount} halaman',
                    ),
                    _MetadataPill(
                      icon: Icons.sd_storage_outlined,
                      label: formatFileSize(item.file.fileSizeBytes),
                    ),
                  ],
                ),
              ],
            );

            final rangeField = SizedBox(
              width: isCompact ? double.infinity : 210,
              child: _PageRangeField(
                itemId: item.id,
                value: item.pageRangeInput,
                maxPages: item.file.pageCount,
                errorText: rangeError,
                enabled: !isProcessing,
                onChanged: onRangeChanged,
              ),
            );

            final actionsRow = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: isProcessing || index == 0 ? null : onMoveUp,
                  tooltip: 'Naikkan urutan',
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
                IconButton(
                  onPressed: isProcessing || index == totalCount - 1
                      ? null
                      : onMoveDown,
                  tooltip: 'Turunkan urutan',
                  icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                ),
                IconButton(
                  onPressed: isProcessing ? null : onRemove,
                  tooltip: 'Hapus dari daftar',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: colorScheme.error,
                  ),
                ),
              ],
            );

            if (isPhone) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leadingCluster,
                      const SizedBox(width: 10),
                      Expanded(child: infoCluster),
                    ],
                  ),
                  const SizedBox(height: 10),
                  rangeField,
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: actionsRow,
                  ),
                ],
              );
            }

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      leadingCluster,
                      const SizedBox(width: 12),
                      Expanded(child: infoCluster),
                      actionsRow,
                    ],
                  ),
                  const SizedBox(height: 10),
                  rangeField,
                ],
              );
            }

            return Row(
              children: [
                leadingCluster,
                const SizedBox(width: 14),
                Expanded(child: infoCluster),
                const SizedBox(width: 12),
                rangeField,
                const SizedBox(width: 8),
                actionsRow,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PageRangeField extends StatefulWidget {
  const _PageRangeField({
    required this.itemId,
    required this.value,
    required this.maxPages,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  final String itemId;
  final String value;
  final int maxPages;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_PageRangeField> createState() => _PageRangeFieldState();
}

class _PageRangeFieldState extends State<_PageRangeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _PageRangeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: 'Rentang halaman',
        hintText: 'Semua (1-${widget.maxPages})',
        errorText: widget.errorText,
        errorMaxLines: 2,
      ),
    );
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MergeActionBar extends StatelessWidget {
  const _MergeActionBar({required this.viewModel});

  final MergeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = viewModel.items;
    final needsMoreFiles = items.length < 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 520;

        final summaryBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${items.length} file • Total ${viewModel.totalSelectedPages} halaman',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (needsMoreFiles)
              Text(
                'Tambahkan minimal 1 file PDF lagi untuk menggabungkan.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );

        final mergeButton = FilledButton.icon(
          onPressed: viewModel.canMerge ? viewModel.mergeAndSave : null,
          icon: viewModel.isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_alt_rounded),
          label: Text(
            viewModel.isProcessing
                ? 'Menggabungkan...'
                : 'Gabungkan & Simpan PDF',
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
                    mergeButton,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: summaryBlock),
                    const SizedBox(width: 16),
                    mergeButton,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
