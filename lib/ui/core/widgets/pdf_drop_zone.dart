import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/utils/file_format_utils.dart';

/// Callback invoked when valid PDF file paths are dropped.
typedef PdfFilesDroppedCallback = void Function(
  List<String> pdfPaths,
  int ignoredCount,
);

/// Extracts `.pdf` paths from [DropDoneDetails] and counts ignored non-PDF files.
({List<String> pdfPaths, int ignoredCount}) extractDroppedPdfPaths(
  DropDoneDetails details,
) {
  final pdfPaths = <String>[];
  var ignoredCount = 0;

  for (final file in details.files) {
    final filePath = file.path;
    if (filePath.isEmpty) continue;
    if (isPdfPath(filePath)) {
      pdfPaths.add(filePath);
    } else {
      ignoredCount++;
    }
  }

  return (pdfPaths: pdfPaths, ignoredCount: ignoredCount);
}

/// Interactive empty-state dropzone accepting PDF files via drag-and-drop or browse.
class PdfDropZone extends StatefulWidget {
  /// Creates a [PdfDropZone].
  const PdfDropZone({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onBrowsePressed,
    required this.onFilesDropped,
    this.enableDrop = true,
    this.icon = Icons.upload_file_rounded,
  });

  /// Primary heading displayed inside the dropzone.
  final String title;

  /// Supporting instructions displayed below [title].
  final String subtitle;

  /// Label for the browse button.
  final String buttonLabel;

  /// Callback when the user clicks the browse button.
  final VoidCallback? onBrowsePressed;

  /// Callback when one or more files are dropped onto the zone.
  final PdfFilesDroppedCallback onFilesDropped;

  /// Whether OS drag-and-drop events should be handled.
  final bool enableDrop;

  /// Hero icon shown at the top of the dropzone.
  final IconData icon;

  @override
  State<PdfDropZone> createState() => _PdfDropZoneState();
}

class _PdfDropZoneState extends State<PdfDropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DropTarget(
      enable: widget.enableDrop,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final parsed = extractDroppedPdfPaths(details);
        widget.onFilesDropped(parsed.pdfPaths, parsed.ignoredCount);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 520;
          return Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 20 : 32,
                    vertical: isCompact ? 24 : 44,
                  ),
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _isDragging
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: _isDragging ? 2 : 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isCompact ? 56 : 68,
                        height: isCompact ? 56 : 68,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? colorScheme.primary.withValues(alpha: 0.14)
                              : colorScheme.primaryContainer.withValues(
                                  alpha: 0.65,
                                ),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.icon,
                          size: isCompact ? 28 : 32,
                          color: colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: isCompact ? 14 : 20),
                      Text(
                        _isDragging ? 'Lepaskan file PDF di sini' : widget.title,
                        textAlign: TextAlign.center,
                        style: (isCompact
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleLarge)
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: isCompact ? 18 : 24),
                      FilledButton.icon(
                        onPressed: widget.onBrowsePressed,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(widget.buttonLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Wraps a populated workspace so users can drop additional/replacement PDFs anywhere.
class PdfDropWrapper extends StatefulWidget {
  /// Creates a [PdfDropWrapper].
  const PdfDropWrapper({
    super.key,
    required this.enableDrop,
    required this.onFilesDropped,
    required this.child,
    this.overlayMessage = 'Lepaskan file PDF untuk memuat',
  });

  /// Whether drag-and-drop is enabled (false when tab is hidden in `IndexedStack`).
  final bool enableDrop;

  /// Callback when files are dropped.
  final PdfFilesDroppedCallback onFilesDropped;

  /// Wrapped workspace content.
  final Widget child;

  /// Overlay text displayed while dragging over the workspace.
  final String overlayMessage;

  @override
  State<PdfDropWrapper> createState() => _PdfDropWrapperState();
}

class _PdfDropWrapperState extends State<PdfDropWrapper> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DropTarget(
      enable: widget.enableDrop,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final parsed = extractDroppedPdfPaths(details);
        widget.onFilesDropped(parsed.pdfPaths, parsed.ignoredCount);
      },
      child: Stack(
        children: [
          widget.child,
          if (_isDragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.primary, width: 2),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.overlayMessage,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
