import 'pdf_file_info.dart';

/// Represents a queued PDF entry in the Merge workspace.
class MergeItem {
  /// Creates an immutable [MergeItem].
  const MergeItem({
    required this.id,
    required this.file,
    this.pageRangeInput = '',
  });

  /// Unique entry identifier allowing the same PDF file to be added multiple times.
  final String id;

  /// Inspected source file metadata.
  final PdfFileInfo file;

  /// Optional 1-based page selection expression (e.g. `1-3, 5`).
  /// Empty string means all pages in the file are included.
  final String pageRangeInput;

  /// Returns a copy of this [MergeItem] with updated fields.
  MergeItem copyWith({
    String? id,
    PdfFileInfo? file,
    String? pageRangeInput,
  }) {
    return MergeItem(
      id: id ?? this.id,
      file: file ?? this.file,
      pageRangeInput: pageRangeInput ?? this.pageRangeInput,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MergeItem &&
        other.id == id &&
        other.file == file &&
        other.pageRangeInput == pageRangeInput;
  }

  @override
  int get hashCode => Object.hash(id, file, pageRangeInput);
}
