import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/features/viewer/view_models/pdf_viewer_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late PdfViewerViewModel viewModel;

  const sampleDoc = PdfFileInfo(
    path: r'C:\docs\panduan.pdf',
    fileName: 'panduan.pdf',
    pageCount: 5,
    fileSizeBytes: 5120,
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[sampleDoc.path] = sampleDoc;
    viewModel = PdfViewerViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('picks a PDF, navigates pages with clamping, and clears source',
      () async {
    dialogs.nextPickedFile = sampleDoc.path;
    await viewModel.pickFile();

    expect(viewModel.sourceFile, sampleDoc);
    expect(viewModel.currentPage, 1);
    expect(viewModel.canGoPrevious, isFalse);
    expect(viewModel.canGoNext, isTrue);

    viewModel.nextPage();
    expect(viewModel.currentPage, 2);
    expect(viewModel.canGoPrevious, isTrue);

    viewModel.goToPage(99);
    expect(viewModel.currentPage, 5);
    expect(viewModel.canGoNext, isFalse);

    viewModel.goToPage(0);
    expect(viewModel.currentPage, 1);

    viewModel.clearSource();
    expect(viewModel.sourceFile, isNull);
    expect(viewModel.currentPage, 1);
  });

  test('clamps zoom, toggles sidebar and search bar state', () async {
    await viewModel.setSourcePath(sampleDoc.path);

    viewModel.setZoom(1.5);
    expect(viewModel.zoom, 1.5);

    viewModel.setZoom(10.0);
    expect(viewModel.zoom, 5.0);

    viewModel.setZoom(0.05);
    expect(viewModel.zoom, 0.25);

    expect(viewModel.showThumbnails, isTrue);
    viewModel.toggleThumbnails();
    expect(viewModel.showThumbnails, isFalse);

    expect(viewModel.isSearchOpen, isFalse);
    viewModel.toggleSearch();
    expect(viewModel.isSearchOpen, isTrue);
    viewModel.setSearchQuery('flutter');
    expect(viewModel.searchQuery, 'flutter');

    viewModel.toggleSearch();
    expect(viewModel.isSearchOpen, isFalse);
    expect(viewModel.searchQuery, isEmpty);
  });

  test('handles dropped non-PDF files and inspect errors gracefully', () async {
    await viewModel.loadFromDroppedPaths(
      const <String>[],
      ignoredNonPdfCount: 2,
    );
    expect(viewModel.errorMessage, contains('Hanya file PDF'));

    viewModel.dismissError();
    expect(viewModel.errorMessage, isNull);

    engine.inspectErrorsByPath[r'C:\docs\rusak.pdf'] =
        const PdfOperationException('File PDF rusak.');
    await viewModel.setSourcePath(r'C:\docs\rusak.pdf');
    expect(viewModel.sourceFile, isNull);
    expect(viewModel.errorMessage, 'File PDF rusak.');
  });

  test('openSourceFolder delegates to revealInFileManager', () async {
    await viewModel.setSourcePath(sampleDoc.path);
    await viewModel.openSourceFolder();
    expect(dialogs.revealedPaths, <String>[sampleDoc.path]);
  });
}
