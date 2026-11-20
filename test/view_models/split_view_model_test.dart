import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/split_mode.dart';
import 'package:pdfutils/ui/features/split/view_models/split_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late SplitViewModel viewModel;

  const doc = PdfFileInfo(
    path: r'C:\docs\laporan_2026.pdf',
    fileName: 'laporan_2026.pdf',
    pageCount: 6,
    fileSizeBytes: 8192,
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[doc.path] = doc;
    viewModel = SplitViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('loads file with sanitized output prefix and empty range validation', () async {
    await viewModel.loadFile(doc.path);

    expect(viewModel.sourceFile, doc);
    expect(viewModel.outputPrefix, 'laporan_2026');
    expect(viewModel.mode, SplitMode.customRanges);
    expect(viewModel.canSplit, isFalse);
    expect(viewModel.validationError, isNotNull);
  });

  test('customRanges supports multi-group splitting and single-file extraction', () async {
    await viewModel.loadFile(doc.path);
    viewModel.setCustomRangeInput('1-2, 4-5, 6');

    expect(viewModel.canSplit, isTrue);
    final multiPlan = viewModel.outputPlan!;
    expect(multiPlan.groups.length, 3);
    expect(multiPlan.isSingleOutput, isFalse);
    expect(multiPlan.groups[0].pages, <int>[1, 2]);
    expect(multiPlan.groups[1].pages, <int>[4, 5]);
    expect(multiPlan.groups[2].pages, <int>[6]);
    expect(viewModel.pageToGroupIndex[4], 1);

    viewModel.setExtractToSingleFile(true);
    final singlePlan = viewModel.outputPlan!;
    expect(singlePlan.groups.length, 1);
    expect(singlePlan.isSingleOutput, isTrue);
    expect(singlePlan.groups.first.pages, <int>[1, 2, 4, 5, 6]);
  });

  test('togglePageInCustomRange updates custom range string cleanly', () async {
    await viewModel.loadFile(doc.path);

    viewModel.togglePageInCustomRange(1);
    viewModel.togglePageInCustomRange(2);
    viewModel.togglePageInCustomRange(5);
    expect(viewModel.customRangeInput, '1-2, 5');

    viewModel.togglePageInCustomRange(2);
    expect(viewModel.customRangeInput, '1, 5');
  });

  test('everyPage and fixedPageCount modes build expected groups', () async {
    await viewModel.loadFile(doc.path);

    viewModel.setMode(SplitMode.everyPage);
    expect(viewModel.outputPlan!.groups.length, 6);
    expect(
      viewModel.outputPlan!.groups.first.suggestedFileName,
      'laporan_2026_hal_001.pdf',
    );

    viewModel.setMode(SplitMode.fixedPageCount);
    viewModel.setPagesPerSplit(4);
    expect(viewModel.outputPlan!.groups.length, 2);
    expect(viewModel.outputPlan!.groups[0].pages, <int>[1, 2, 3, 4]);
    expect(viewModel.outputPlan!.groups[1].pages, <int>[5, 6]);
  });

  test('splitAndSave uses save file dialog for 1 output and directory picker for multiple', () async {
    await viewModel.loadFile(doc.path);

    // Single output via custom extract
    viewModel.setCustomRangeInput('1-3');
    dialogs.nextSavePath = r'C:\out\extracted.pdf';
    await viewModel.splitAndSave();
    expect(engine.lastSplitSingleOutputPath, r'C:\out\extracted.pdf');
    expect(viewModel.lastResult?.outputPaths, <String>[r'C:\out\extracted.pdf']);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths.last, r'C:\out\extracted.pdf');

    // Multi output via everyPage
    viewModel.setMode(SplitMode.everyPage);
    dialogs.nextOutputDirectory = r'C:\out\parts';
    await viewModel.splitAndSave();
    expect(engine.lastSplitSingleOutputPath, isNull);
    expect(engine.lastSplitOutputDirectory, r'C:\out\parts');
    expect(viewModel.lastResult?.outputPaths.length, 6);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths.last, r'C:\out\parts');
  });
}
