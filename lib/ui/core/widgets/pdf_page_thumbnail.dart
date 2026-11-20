import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

/// Custom builder signature for rendering a PDF page thumbnail (used in tests).
typedef PdfThumbnailBuilder = Widget Function(
  BuildContext context,
  String filePath,
  int pageNumber,
);

/// Supplies a custom [PdfThumbnailBuilder] down the widget tree.
///
/// Used in widget tests to replace native PDFium rendering with lightweight
/// deterministic previews.
class PdfThumbnailOverride extends InheritedWidget {
  /// Creates a [PdfThumbnailOverride].
  const PdfThumbnailOverride({
    super.key,
    required this.builder,
    required super.child,
  });

  /// Custom thumbnail builder to use instead of `pdfrx`.
  final PdfThumbnailBuilder builder;

  /// Returns the nearest [PdfThumbnailBuilder] override, if any.
  static PdfThumbnailBuilder? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PdfThumbnailOverride>()
        ?.builder;
  }

  @override
  bool updateShouldNotify(PdfThumbnailOverride oldWidget) {
    return oldWidget.builder != builder;
  }
}

/// Renders a crisp thumbnail for a single 1-based [pageNumber] of a PDF.
///
/// When [document] is supplied (such as inside Rotate or Split page grids),
/// reuses that single opened [PdfDocument] instead of opening the file per card.
class PdfPageThumbnail extends StatelessWidget {
  /// Creates a [PdfPageThumbnail].
  const PdfPageThumbnail({
    super.key,
    required this.filePath,
    required this.pageNumber,
    this.document,
    this.maximumDpi = 120,
  });

  /// Path to the PDF file.
  final String filePath;

  /// 1-based page index to display.
  final int pageNumber;

  /// Optional already-opened [PdfDocument] shared across multiple page cards.
  final PdfDocument? document;

  /// Maximum rasterization DPI for thumbnail memory efficiency.
  final double maximumDpi;

  @override
  Widget build(BuildContext context) {
    final overrideBuilder = PdfThumbnailOverride.maybeOf(context);
    if (overrideBuilder != null) {
      return overrideBuilder(context, filePath, pageNumber);
    }

    if (document != null) {
      return _buildPageView(context, document!);
    }

    return PdfDocumentViewBuilder.file(
      filePath,
      loadingBuilder: (context) => _ThumbnailPlaceholder(
        icon: Icons.picture_as_pdf_outlined,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorBuilder: (context, error, stackTrace) => const _ThumbnailPlaceholder(
        icon: Icons.broken_image_outlined,
      ),
      builder: (context, loadedDoc) {
        if (loadedDoc == null) {
          return const _ThumbnailPlaceholder(
            icon: Icons.picture_as_pdf_outlined,
          );
        }
        return _buildPageView(context, loadedDoc);
      },
    );
  }

  Widget _buildPageView(BuildContext context, PdfDocument doc) {
    if (pageNumber < 1 || pageNumber > doc.pages.length) {
      return const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined);
    }

    return Container(
      color: Colors.white,
      child: PdfPageView(
        document: doc,
        pageNumber: pageNumber,
        maximumDpi: maximumDpi,
        decoration: const BoxDecoration(color: Colors.white),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({
    required this.icon,
    this.child,
  });

  final IconData icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: child ??
            Icon(
              icon,
              size: 24,
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
