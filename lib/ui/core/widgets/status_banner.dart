import 'package:material_ui/material_ui.dart';

import '../../../domain/models/operation_result.dart';

/// Displays operation success or error feedback with an optional folder action.
class StatusBanner extends StatelessWidget {
  /// Creates a [StatusBanner].
  const StatusBanner({
    super.key,
    this.errorMessage,
    this.result,
    this.onOpenFolder,
    this.onDismiss,
  });

  /// Error text to display; takes precedence over [result] when non-null.
  final String? errorMessage;

  /// Successful operation result to display.
  final PdfOperationResult? result;

  /// Optional callback to open the output file or folder in the file explorer.
  final VoidCallback? onOpenFolder;

  /// Callback to close the banner.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final isError = errorMessage != null && errorMessage!.trim().isNotEmpty;
    if (!isError && result == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bgColor = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final fgColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;
    final borderColor = isError
        ? colorScheme.error.withValues(alpha: 0.4)
        : colorScheme.secondary.withValues(alpha: 0.4);

    final primaryText = isError ? errorMessage! : result!.message;
    final subtitlePath = !isError && result!.outputPaths.isNotEmpty
        ? (result!.outputPaths.length == 1
            ? result!.outputPaths.first
            : '${result!.outputPaths.length} file disimpan')
        : null;

    final leadingIcon = Icon(
      isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
      color: fgColor,
      size: 20,
    );

    Widget buildTextBlock({required bool isCompact}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            primaryText,
            maxLines: isCompact ? 3 : null,
            overflow: isCompact ? TextOverflow.ellipsis : null,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: fgColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitlePath != null)
            Text(
              subtitlePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fgColor.withValues(alpha: 0.85),
              ),
            ),
        ],
      );
    }

    Widget? buildOpenFolderButton({required bool isCompact}) {
      if (isError || onOpenFolder == null) return null;
      return TextButton.icon(
        onPressed: onOpenFolder,
        style: TextButton.styleFrom(
          foregroundColor: fgColor,
          visualDensity: isCompact ? VisualDensity.compact : null,
        ),
        icon: const Icon(Icons.folder_open_rounded, size: 18),
        label: const Text('Buka Folder'),
      );
    }

    Widget? buildDismissButton({required bool isCompact}) {
      if (onDismiss == null) return null;
      return IconButton(
        onPressed: onDismiss,
        tooltip: 'Tutup',
        visualDensity: isCompact ? VisualDensity.compact : null,
        icon: Icon(Icons.close_rounded, size: 18, color: fgColor),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final openFolderButton = buildOpenFolderButton(isCompact: isCompact);
        final dismissButton = buildDismissButton(isCompact: isCompact);

        return Container(
          padding: isCompact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: leadingIcon,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: buildTextBlock(isCompact: true)),
                        ?dismissButton,
                      ],
                    ),
                    if (openFolderButton != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: openFolderButton,
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    leadingIcon,
                    const SizedBox(width: 10),
                    Expanded(child: buildTextBlock(isCompact: false)),
                    if (openFolderButton != null) ...[
                      const SizedBox(width: 8),
                      openFolderButton,
                    ],
                    ?dismissButton,
                  ],
                ),
        );
      },
    );
  }
}
