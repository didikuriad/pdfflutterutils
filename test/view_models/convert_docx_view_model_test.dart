import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/features/convert_docx/view_models/convert_docx_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late FakePdfToDocxService docx;
  late ConvertDocxViewModel viewModel;

  const fileA = PdfFileInfo(
    path: r'C:\docs\a\laporan.pdf',
    fileName: 'laporan.pdf',
    pageCount: 4,
    fileSizeBytes: 2048,
  );
  const fileB = PdfFileInfo(
    path: r'C:\docs\b\laporan.pdf',
    fileName: 'laporan.pdf',
    pageCount: 2,
    fileSizeBytes: 1024,
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    docx = setup.docx;
    engine.filesByPath[fileA.path] = fileA;
    engine.filesByPath[fileB.path] = fileB;
    viewModel = ConvertDocxViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('checks Word availability and disables conversion when unavailable', () async {
    docx.available = false;
    await viewModel.checkAvailability();
    expect(viewModel.isWordAvailable, isFalse);

    await viewModel.addFilesFromPaths(<String>[fileA.path]);
    expect(viewModel.canConvert, isFalse);

    await viewModel.convertAndSave();
    expect(viewModel.errorMessage, contains('Microsoft Word tidak terdeteksi'));
    expect(docx.convertedJobs, isEmpty);
  });

  test('skips non-PDF dropped files and converts a single PDF via save dialog', () async {
    await viewModel.checkAvailability();
    expect(viewModel.isWordAvailable, isTrue);

    await viewModel.addFilesFromPaths(
      <String>[fileA.path, r'C:\docs\notes.txt'],
      ignoredNonPdfCount: 1,
    );
    expect(viewModel.items.length, 1);
    expect(viewModel.errorMessage, contains('2 file bukan PDF dilewati'));
    expect(viewModel.totalPages, 4);
    expect(viewModel.canConvert, isTrue);

    // Cancel save dialog -> no conversion happens.
    dialogs.nextSaveDocxPath = null;
    await viewModel.convertAndSave();
    expect(docx.convertedJobs, isEmpty);

    // Confirm save path -> converts single file.
    dialogs.nextSaveDocxPath = r'C:\out\laporan.docx';
    await viewModel.convertAndSave();
    expect(docx.convertedJobs.length, 1);
    expect(docx.convertedJobs.first.outputPath, r'C:\out\laporan.docx');
    expect(viewModel.lastResult?.outputPaths, <String>[r'C:\out\laporan.docx']);
    expect(viewModel.lastResult?.totalPagesProcessed, 4);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths, <String>[r'C:\out\laporan.docx']);
  });

  test('batch converts multiple PDFs to output folder and deduplicates colliding filenames', () async {
    await viewModel.checkAvailability();
    dialogs.nextPickedFiles = <String>[fileA.path, fileB.path];
    await viewModel.pickAndAddFiles();
    expect(viewModel.items.length, 2);
    expect(viewModel.totalPages, 6);

    dialogs.nextOutputDirectory = r'C:\out_docx';
    await viewModel.convertAndSave();

    expect(docx.convertedJobs.length, 2);
    expect(docx.convertedJobs[0].outputPath, endsWith('laporan.docx'));
    expect(docx.convertedJobs[1].outputPath, endsWith('laporan_2.docx'));
    expect(viewModel.lastResult?.outputPaths.length, 2);
    expect(viewModel.lastResult?.totalPagesProcessed, 6);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths.last, r'C:\out_docx');
  });

  test('handles conversion error and removeAt/clearAll cleanly', () async {
    await viewModel.checkAvailability();
    await viewModel.addFilesFromPaths(<String>[fileA.path, fileB.path]);
    viewModel.removeAt(1);
    expect(viewModel.items.length, 1);

    docx.conversionError = const PdfOperationException('Gagal membuka COM Word.');
    dialogs.nextSaveDocxPath = r'C:\out\gagal.docx';
    await viewModel.convertAndSave();
    expect(viewModel.errorMessage, 'Gagal membuka COM Word.');
    expect(viewModel.lastResult, isNull);

    viewModel.clearAll();
    expect(viewModel.items, isEmpty);
    expect(viewModel.errorMessage, isNull);
  });
}
