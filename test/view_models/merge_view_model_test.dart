import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/features/merge/view_models/merge_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late MergeViewModel viewModel;

  const fileA = PdfFileInfo(
    path: r'C:\docs\a.pdf',
    fileName: 'a.pdf',
    pageCount: 4,
    fileSizeBytes: 1024,
  );
  const fileB = PdfFileInfo(
    path: r'C:\docs\b.pdf',
    fileName: 'b.pdf',
    pageCount: 3,
    fileSizeBytes: 2048,
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[fileA.path] = fileA;
    engine.filesByPath[fileB.path] = fileB;
    viewModel = MergeViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('picks and adds multiple files, allowing duplicate files with unique ids', () async {
    dialogs.nextPickedFiles = <String>[fileA.path, fileB.path, fileA.path];
    await viewModel.pickAndAddFiles();

    expect(viewModel.items.length, 3);
    expect(viewModel.items.map((e) => e.id).toSet().length, 3);
    expect(viewModel.totalSelectedPages, 11);
    expect(viewModel.canMerge, isTrue);
  });

  test('ignores non-PDF dropped paths and reports skipped count', () async {
    await viewModel.addFilesFromPaths(
      <String>[fileA.path, r'C:\docs\readme.txt'],
      ignoredNonPdfCount: 1,
    );

    expect(viewModel.items.length, 1);
    expect(viewModel.errorMessage, contains('2 file bukan PDF dilewati'));
    expect(viewModel.canMerge, isFalse);
  });

  test('reorders, moves up/down, removes, and clears items', () async {
    await viewModel.addFilesFromPaths(<String>[fileA.path, fileB.path]);
    expect(viewModel.items.map((e) => e.file.fileName), <String>['a.pdf', 'b.pdf']);

    viewModel.moveDown(0);
    expect(viewModel.items.map((e) => e.file.fileName), <String>['b.pdf', 'a.pdf']);

    viewModel.moveUp(1);
    expect(viewModel.items.map((e) => e.file.fileName), <String>['a.pdf', 'b.pdf']);

    viewModel.reorder(0, 1);
    expect(viewModel.items.map((e) => e.file.fileName), <String>['b.pdf', 'a.pdf']);

    viewModel.removeAt(0);
    expect(viewModel.items.length, 1);

    viewModel.clearAll();
    expect(viewModel.items, isEmpty);
  });

  test('validates per-item page range and updates totalSelectedPages', () async {
    await viewModel.addFilesFromPaths(<String>[fileA.path, fileB.path]);
    final idA = viewModel.items.first.id;

    viewModel.updatePageRange(idA, '1-2, 4');
    expect(viewModel.rangeErrors[idA], isNull);
    expect(viewModel.totalSelectedPages, 6);
    expect(viewModel.canMerge, isTrue);

    viewModel.updatePageRange(idA, '1-99');
    expect(viewModel.rangeErrors[idA], isNotNull);
    expect(viewModel.canMerge, isFalse);
  });

  test('mergeAndSave sends specs to engine and handles cancel/errors', () async {
    await viewModel.addFilesFromPaths(<String>[fileA.path, fileB.path]);
    viewModel.updatePageRange(viewModel.items.first.id, '2-3');

    dialogs.nextSavePath = null;
    await viewModel.mergeAndSave();
    expect(engine.lastMergeSources, isNull);

    dialogs.nextSavePath = r'C:\docs\merged.pdf';
    await viewModel.mergeAndSave();
    expect(engine.lastMergeOutputPath, r'C:\docs\merged.pdf');
    expect(engine.lastMergeSources!.length, 2);
    expect(engine.lastMergeSources![0].oneBasedPages, <int>[2, 3]);
    expect(engine.lastMergeSources![1].oneBasedPages, <int>[1, 2, 3]);
    expect(viewModel.lastResult?.totalPagesProcessed, 5);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths, <String>[r'C:\docs\merged.pdf']);

    engine.mergeError = const PdfOperationException('Gagal menulis file.');
    await viewModel.mergeAndSave();
    expect(viewModel.errorMessage, 'Gagal menulis file.');
    expect(viewModel.lastResult, isNull);
  });
}
