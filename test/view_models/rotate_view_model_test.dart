import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';
import 'package:pdfutils/ui/features/rotate/view_models/rotate_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late RotateViewModel viewModel;

  const doc = PdfFileInfo(
    path: r'C:\docs\scan.pdf',
    fileName: 'scan.pdf',
    pageCount: 5,
    fileSizeBytes: 4096,
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[doc.path] = doc;
    viewModel = RotateViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('loads PDF via picker and resets state when cleared', () async {
    dialogs.nextPickedFile = doc.path;
    await viewModel.pickFile();

    expect(viewModel.sourceFile, doc);
    expect(viewModel.canSave, isTrue);
    expect(viewModel.hasChanges, isFalse);

    viewModel.rotatePageCW(1);
    expect(viewModel.hasChanges, isTrue);

    viewModel.clearFile();
    expect(viewModel.sourceFile, isNull);
    expect(viewModel.pageRotations, isEmpty);
    expect(viewModel.selectedPages, isEmpty);
  });

  test('selection helpers select all, odd, even, toggle, and clear', () async {
    await viewModel.loadFile(doc.path);

    viewModel.selectOddPages();
    expect(viewModel.selectedPages, <int>{1, 3, 5});

    viewModel.selectEvenPages();
    expect(viewModel.selectedPages, <int>{2, 4});

    viewModel.togglePageSelection(3);
    expect(viewModel.selectedPages, <int>{2, 3, 4});

    viewModel.selectAll();
    expect(viewModel.selectedPages, <int>{1, 2, 3, 4, 5});

    viewModel.clearSelection();
    expect(viewModel.selectedPages, isEmpty);
  });

  test('rotates selected pages or all pages when none selected, and resets', () async {
    await viewModel.loadFile(doc.path);

    // No selection -> applies to all 5 pages.
    viewModel.rotateTargetCW();
    expect(viewModel.rotatedPagesCount, 5);
    expect(viewModel.rotationForPage(3), RotationQuarterTurns.deg90);

    // Rotating 3 more times CW returns to 0° and clears rotation map.
    viewModel.rotateTarget180();
    viewModel.rotateTargetCW();
    expect(viewModel.hasChanges, isFalse);

    // With selection -> applies only to selected pages.
    viewModel.selectOddPages();
    viewModel.rotateTargetCCW();
    expect(viewModel.rotationForPage(1), RotationQuarterTurns.deg270);
    expect(viewModel.rotationForPage(2), RotationQuarterTurns.deg0);
    expect(viewModel.rotationForPage(5), RotationQuarterTurns.deg270);

    viewModel.resetRotations();
    expect(viewModel.hasChanges, isFalse);
  });

  test('saveRotatedPdf forwards rotations and handles errors', () async {
    await viewModel.loadFile(doc.path);
    viewModel.rotatePageCW(2);
    viewModel.rotatePage180(4);

    dialogs.nextSavePath = r'C:\docs\scan_rotated.pdf';
    await viewModel.saveRotatedPdf();

    expect(engine.lastRotateInputPath, doc.path);
    expect(engine.lastRotateOutputPath, r'C:\docs\scan_rotated.pdf');
    expect(engine.lastPageRotations, <int, RotationQuarterTurns>{
      2: RotationQuarterTurns.deg90,
      4: RotationQuarterTurns.deg180,
    });
    expect(viewModel.lastResult?.totalPagesProcessed, 5);

    engine.rotateError = const PdfOperationException('Gagal simpan.');
    await viewModel.saveRotatedPdf();
    expect(viewModel.errorMessage, 'Gagal simpan.');
  });
}
