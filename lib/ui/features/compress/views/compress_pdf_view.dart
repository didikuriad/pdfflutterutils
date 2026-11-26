import 'package:material_ui/material_ui.dart';
import 'package:pdfutils/domain/models/compress_pdf_options.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';
import 'package:pdfutils/ui/core/widgets/pdf_drop_zone.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/core/widgets/status_banner.dart';
import 'package:pdfutils/ui/core/widgets/workspace_header.dart';
import 'package:pdfutils/ui/features/compress/view_models/compress_pdf_view_model.dart';

/// Workspace view for compressing PDF documents.
class CompressPdfView extends StatelessWidget {
  /// Creates a [CompressPdfView].
  const CompressPdfView({
    super.key,
    required this.viewModel,
    required this.isActive,
  });

  /// ViewModel driving compression state and operations.
  final CompressPdfViewModel viewModel;

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
                icon: Icons.compress_rounded,
                title: 'Kompres PDF',
                subtitle:
                    'Kecilkan ukuran file PDF dengan menjaga keterbacaan teks dan ketajaman gambar.',
                actions: [
                  FilledButton.icon(
                    onPressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Pilih PDF'),
                  ),
                ],
              ),
              const Divider(height: 1),
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
                    icon: Icons.compress_rounded,
                    title: 'Tarik & lepas file PDF untuk dikompresi',
                    subtitle:
                        'Pilih tingkat kompresi (Rendah, Sedang, atau Tinggi) untuk memperkecil ukuran file PDF agar mudah dikirim atau diunggah.',
                    buttonLabel: 'Buka File PDF',
                    onBrowsePressed:
                        viewModel.isProcessing ? null : viewModel.pickFile,
                    onFilesDropped: (paths, ignoredCount) {
                      if (paths.isNotEmpty) {
                        viewModel.setSourcePath(paths.first);
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        }

        return PdfDropWrapper(
          enableDrop: isActive,
          overlayMessage: 'Lepaskan file PDF baru untuk mengganti',
          onFilesDropped: (paths, ignoredCount) {
            if (paths.isNotEmpty) {
              viewModel.setSourcePath(paths.first);
            }
          },
          child: Column(
            children: [
              WorkspaceHeader(
                icon: Icons.compress_rounded,
                title: 'Kompres PDF',
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
                    onPressed: viewModel.canCompress
                        ? viewModel.compressAndSave
                        : null,
                    icon: viewModel.isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compress_rounded),
                    label: Text(
                      viewModel.isProcessing
                          ? 'Mengompresi...'
                          : 'Kompres & Simpan PDF',
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),
              if (viewModel.isProcessing)
                LinearProgressIndicator(
                  value: viewModel.progress,
                  minHeight: 4,
                ),
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
              if (viewModel.lastCompressInfo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: _SavingsReportCard(info: viewModel.lastCompressInfo!),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CompressionOptionsCard(
                            viewModel: viewModel,
                            sourceFile: sourceFile,
                          ),
                          const SizedBox(height: 20),
                          _DocumentPreviewCard(sourceFile: sourceFile),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavingsReportCard extends StatelessWidget {
  const _SavingsReportCard({required this.info});

  final CompressResultInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isReduced = info.didReduceSize;

    return Card(
      elevation: 0,
      color: isReduced
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isReduced
              ? colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 420;
            final badge = isReduced
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '-${info.savingsPercent.round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null;

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isReduced
                            ? Icons.task_alt_rounded
                            : Icons.info_outline_rounded,
                        color: isReduced
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isReduced
                              ? 'Hemat: ${info.savingsPercent.toStringAsFixed(1)}%'
                              : 'File Sudah Optimal',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isReduced
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                      ),
                      ?badge,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${formatFileSize(info.originalSizeBytes)} ➔ ${formatFileSize(info.compressedSizeBytes)} (${info.didReduceSize ? 'Hemat ${formatFileSize(info.bytesSaved)}' : 'Tetap'})',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Icon(
                  isReduced
                      ? Icons.task_alt_rounded
                      : Icons.info_outline_rounded,
                  color: isReduced
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReduced
                            ? 'Penghematan Ukuran: ${info.savingsPercent.toStringAsFixed(1)}%'
                            : 'File Sudah Optimal',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isReduced
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ukuran asli ${formatFileSize(info.originalSizeBytes)} ➔ Hasil ${formatFileSize(info.compressedSizeBytes)} (${info.didReduceSize ? 'Hemat ${formatFileSize(info.bytesSaved)}' : 'Ukuran tidak berubah'})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  badge,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompressionOptionsCard extends StatelessWidget {
  const _CompressionOptionsCard({
    required this.viewModel,
    required this.sourceFile,
  });

  final CompressPdfViewModel viewModel;
  final PdfFileInfo sourceFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabled = viewModel.isProcessing;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pengaturan Kompresi',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Metode Kompresi:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in CompressMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: viewModel.mode == mode,
                    onSelected: disabled ? null : (_) => viewModel.setMode(mode),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (viewModel.mode == CompressMode.visual) ...[
              Text(
                'Tingkat Kompresi & Kualitas:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 620;
                  if (isCompact) {
                    return Column(
                      children: [
                        for (final level in CompressQualityLevel.values) ...[
                          _QualityLevelTile(
                            level: level,
                            selected: viewModel.qualityLevel == level,
                            disabled: disabled,
                            onTap: () => viewModel.setQualityLevel(level),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      for (final level in CompressQualityLevel.values) ...[
                        Expanded(
                          child: _QualityLevelTile(
                            level: level,
                            selected: viewModel.qualityLevel == level,
                            disabled: disabled,
                            onTap: () => viewModel.setQualityLevel(level),
                          ),
                        ),
                        if (level != CompressQualityLevel.values.last)
                          const SizedBox(width: 10),
                      ],
                    ],
                  );
                },
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Optimalisasi Lossless menata ulang struktur PDF, mengompresi stream objek, dan menghapus riwayat revisi usang tanpa menurunkan ketajaman gambar atau teks sama sekali.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QualityLevelTile extends StatelessWidget {
  const _QualityLevelTile({
    required this.level,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final CompressQualityLevel level;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.7)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      level.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${level.targetDpi} DPI • Mutu JPEG ${level.jpegQuality}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                level.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentPreviewCard extends StatelessWidget {
  const _DocumentPreviewCard({required this.sourceFile});

  final PdfFileInfo sourceFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pagesToShow = sourceFile.pageCount > 6 ? 6 : sourceFile.pageCount;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.preview_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Pratinjau Halaman Dokumen',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Total ${sourceFile.pageCount} halaman',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pagesToShow,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final pageNum = index + 1;
                  return Container(
                    width: 130,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            child: PdfPageThumbnail(
                              filePath: sourceFile.path,
                              pageNumber: pageNum,
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Hal $pageNum',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (sourceFile.pageCount > 6) ...[
              const SizedBox(height: 10),
              Text(
                'Menampilkan 6 dari ${sourceFile.pageCount} halaman. Semua ${sourceFile.pageCount} halaman akan dikompresi.',
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
