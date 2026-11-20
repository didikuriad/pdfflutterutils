/// Strategy used when splitting a PDF document.
enum SplitMode {
  /// Split according to user-entered page ranges (e.g., `1-3, 4-6, 7`).
  customRanges,

  /// Split into individual single-page PDF files.
  everyPage,

  /// Split into fixed chunks of N pages each.
  fixedPageCount,
}

/// Describes one output PDF produced by a split operation.
class SplitGroup {
  /// Creates an immutable [SplitGroup].
  const SplitGroup({
    required this.label,
    required this.pages,
    required this.suggestedFileName,
  });

  /// Display label for UI badges (e.g. `Bagian 1`).
  final String label;

  /// Ordered 1-based page numbers from the source PDF.
  final List<int> pages;

  /// Suggested output filename (including `.pdf` extension).
  final String suggestedFileName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SplitGroup) return false;
    if (other.label != label ||
        other.suggestedFileName != suggestedFileName ||
        other.pages.length != pages.length) {
      return false;
    }
    for (var i = 0; i < pages.length; i++) {
      if (other.pages[i] != pages[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(label, suggestedFileName, Object.hashAll(pages));
}

/// Planned output specification before executing a PDF split.
class SplitOutputPlan {
  /// Creates an immutable [SplitOutputPlan].
  const SplitOutputPlan({required this.groups});

  /// Ordered output groups to generate.
  final List<SplitGroup> groups;

  /// Whether the split produces exactly one output file (suitable for Save File dialog).
  bool get isSingleOutput => groups.length == 1;
}
