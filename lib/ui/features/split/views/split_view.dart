import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/split_mode.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/split/view_models/split_view_model.dart';

/// Workspace view for splitting or extracting pages from a PDF document.
class SplitView extends StatelessWidget {
  /// Creates a [SplitView].
  const SplitView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving split configuration and execution.
  final SplitViewModel viewModel;

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
                icon: Icons.call_split_rounded,
                title: 'Pisah PDF',
                subtitle:
                    'Pisahkan dokumen PDF berdasarkan rentang halaman, per halaman, atau per jumlah halaman.',
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
                    icon: Icons.content_cut_rounded,
                    title: 'Tarik & lepas file PDF untuk dipisah',
                    subtitle:
                        'Pilih rentang halaman kustom, pecah menjadi satu file per halaman, atau bagi setiap N halaman.',
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
                icon: Icons.call_split_rounded,
                title: 'Pisah PDF',
                subtitle:
                    '${sourceFile.fileName} • ${sourceFile.pageCount} halaman • ${formatFileSize(sourceFile.fileSizeBytes)}',
                actions: [
                  OutlinedButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Ganti PDF'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isSideBySide = constraints.maxWidth >= 900;
                    if (isSideBySide) {
                      return Row(
                        children: [
                          Expanded(
                            child: _SplitPagesGrid(
                              viewModel: viewModel,
                              sourceFile: sourceFile,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 368,
                            child: _SplitConfigPanel(
                              viewModel: viewModel,
                              sourceFile: sourceFile,
                              scrollable: true,
                            ),
                          ),
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _SplitConfigPanel(
                            viewModel: viewModel,
                            sourceFile: sourceFile,
                            scrollable: false,
                          ),
                          const Divider(),
                          _SplitPagesGrid(
                            viewModel: viewModel,
                            sourceFile: sourceFile,
                            scrollable: false,
                          ),
                        ],
                      ),
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
}

class _SplitPagesGrid extends StatelessWidget {
  const _SplitPagesGrid({
    required this.viewModel,
    required this.sourceFile,
    this.scrollable = true,
  });

  final SplitViewModel viewModel;
  final PdfFileInfo sourceFile;
  final bool scrollable;

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
    final pageGroups = viewModel.pageToGroupIndex;
    final plan = viewModel.outputPlan;
    final isInteractive =
        viewModel.mode == SplitMode.customRanges && !viewModel.isProcessing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        return GridView.builder(
          shrinkWrap: !scrollable,
          physics: scrollable ? null : const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(isPhone ? 14 : 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isPhone ? 185 : 220,
            mainAxisSpacing: isPhone ? 12 : 14,
            crossAxisSpacing: isPhone ? 12 : 14,
            childAspectRatio: 0.72,
          ),
          itemCount: sourceFile.pageCount,
          itemBuilder: (context, index) {
            final pageNumber = index + 1;
            final groupIndex = pageGroups[pageNumber];
            final groupLabel = (groupIndex != null &&
                    plan != null &&
                    groupIndex < plan.groups.length)
                ? plan.groups[groupIndex].label
                : null;

            return _SplitPageCard(
              filePath: sourceFile.path,
              pageNumber: pageNumber,
              document: document,
              groupIndex: groupIndex,
              groupLabel: groupLabel,
              isInteractive: isInteractive,
              onTap: isInteractive
                  ? () => viewModel.togglePageInCustomRange(pageNumber)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _SplitPageCard extends StatelessWidget {
  const _SplitPageCard({
    required this.filePath,
    required this.pageNumber,
    required this.document,
    required this.groupIndex,
    required this.groupLabel,
    required this.isInteractive,
    required this.onTap,
  });

  final String filePath;
  final int pageNumber;
  final PdfDocument? document;
  final int? groupIndex;
  final String? groupLabel;
  final bool isInteractive;
  final VoidCallback? onTap;

  static const List<Color> _groupPalette = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF0D9488),
    Color(0xFFD97706),
    Color(0xFFDB2777),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isIncluded = groupIndex != null;
    final accentColor = isIncluded
        ? _groupPalette[groupIndex! % _groupPalette.length]
        : colorScheme.outlineVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isIncluded ? accentColor : colorScheme.outlineVariant,
          width: isIncluded ? 1.8 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: isIncluded || groupIndex == null && !isInteractive ? 1 : 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(
                  children: [
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
                    if (groupLabel != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            groupLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: PdfPageThumbnail(
                    filePath: filePath,
                    pageNumber: pageNumber,
                    document: document,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitConfigPanel extends StatefulWidget {
  const _SplitConfigPanel({
    required this.viewModel,
    required this.sourceFile,
    required this.scrollable,
  });

  final SplitViewModel viewModel;
  final PdfFileInfo sourceFile;
  final bool scrollable;

  @override
  State<_SplitConfigPanel> createState() => _SplitConfigPanelState();
}

class _SplitConfigPanelState extends State<_SplitConfigPanel> {
  late final TextEditingController _rangeController;
  late final TextEditingController _prefixController;

  @override
  void initState() {
    super.initState();
    _rangeController =
        TextEditingController(text: widget.viewModel.customRangeInput);
    _prefixController =
        TextEditingController(text: widget.viewModel.outputPrefix);
  }

  @override
  void didUpdateWidget(covariant _SplitConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rangeValue = widget.viewModel.customRangeInput;
    if (rangeValue != _rangeController.text) {
      _rangeController.value = TextEditingValue(
        text: rangeValue,
        selection: TextSelection.collapsed(offset: rangeValue.length),
      );
    }

    final prefixValue = widget.viewModel.outputPrefix;
    if (prefixValue != _prefixController.text) {
      _prefixController.value = TextEditingValue(
        text: prefixValue,
        selection: TextSelection.collapsed(offset: prefixValue.length),
      );
    }
  }

  @override
  void dispose() {
    _rangeController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final plan = vm.outputPlan;

    final isPhone = MediaQuery.sizeOf(context).width < 600;
    final body = Padding(
      padding: EdgeInsets.all(isPhone ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mode Pemisahan',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<SplitMode>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<SplitMode>>[
              ButtonSegment<SplitMode>(
                value: SplitMode.customRanges,
                label: Text('Rentang'),
              ),
              ButtonSegment<SplitMode>(
                value: SplitMode.everyPage,
                label: Text('Per Hal'),
              ),
              ButtonSegment<SplitMode>(
                value: SplitMode.fixedPageCount,
                label: Text('Per N Hal'),
              ),
            ],
            selected: <SplitMode>{vm.mode},
            onSelectionChanged: vm.isProcessing
                ? null
                : (selection) {
                    if (selection.isNotEmpty) {
                      vm.setMode(selection.first);
                    }
                  },
          ),
          const SizedBox(height: 16),
          if (vm.mode == SplitMode.customRanges) ...[
            TextField(
              controller: _rangeController,
              enabled: !vm.isProcessing,
              onChanged: vm.setCustomRangeInput,
              decoration: InputDecoration(
                labelText: 'Rentang halaman',
                hintText: 'Contoh: 1-3, 4-6, 7',
                helperText:
                    'Klik kartu halaman di kiri atau ketik rentang (maks ${widget.sourceFile.pageCount}).',
                helperMaxLines: 2,
                errorText: vm.validationError,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: vm.extractToSingleFile,
              onChanged: vm.isProcessing ? null : vm.setExtractToSingleFile,
              title: const Text('Gabung ke 1 file ekstrak'),
              subtitle: const Text(
                'Jika nonaktif, setiap rentang disimpan sebagai file terpisah.',
              ),
            ),
          ] else if (vm.mode == SplitMode.everyPage) ...[
            Card(
              color: colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Setiap halaman (1-${widget.sourceFile.pageCount}) akan disimpan menjadi 1 file PDF terpisah.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Halaman per file',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: vm.isProcessing || vm.pagesPerSplit <= 1
                      ? null
                      : () => vm.setPagesPerSplit(vm.pagesPerSplit - 1),
                  icon: const Icon(Icons.remove_rounded, size: 18),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '${vm.pagesPerSplit}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: vm.isProcessing ||
                          vm.pagesPerSplit >= widget.sourceFile.pageCount
                      ? null
                      : () => vm.setPagesPerSplit(vm.pagesPerSplit + 1),
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _prefixController,
            enabled: !vm.isProcessing,
            onChanged: vm.setOutputPrefix,
            decoration: const InputDecoration(
              labelText: 'Awalan nama file output',
              hintText: 'dokumen',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Preview Output',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (plan != null)
                Text(
                  '${plan.groups.length} file',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: plan == null || plan.groups.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      vm.validationError ?? 'Belum ada output yang direncanakan.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: plan.groups.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final group = plan.groups[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          group.suggestedFileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${group.label} • ${group.pages.length} halaman',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (vm.isProcessing && vm.progress != null) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: vm.progress),
          ],
          if (vm.errorMessage != null || vm.lastResult != null) ...[
            const SizedBox(height: 14),
            StatusBanner(
              errorMessage: vm.errorMessage,
              result: vm.lastResult,
              onOpenFolder: vm.openLastOutputFolder,
              onDismiss: vm.dismissStatus,
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: vm.canSplit ? vm.splitAndSave : null,
            icon: vm.isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.call_split_rounded),
            label: Text(
              vm.isProcessing
                  ? 'Memisahkan PDF...'
                  : (plan?.isSingleOutput == true
                      ? 'Ekstrak & Simpan PDF'
                      : 'Pisah & Simpan PDF'),
            ),
          ),
        ],
      ),
    );

    if (widget.scrollable) {
      return Material(
        color: colorScheme.surfaceContainerLow,
        child: SingleChildScrollView(child: body),
      );
    }

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: body,
    );
  }
}
