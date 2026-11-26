import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/compress_pdf_options.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/features/compress/view_models/compress_pdf_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late CompressPdfViewModel viewModel;

  const sampleDoc = PdfFileInfo(
    path: r'C:\docs\laporan.pdf',
    fileName: 'laporan.pdf',
    pageCount: 4,
    fileSizeBytes: 10485760, // 10 MB
  );

  setUp(() {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[sampleDoc.path] = sampleDoc;
    viewModel = CompressPdfViewModel(repository: setup.repository);
  });

  tearDown(() {
    viewModel.dispose();
  });

  test('loads PDF via picker and resets state when cleared', () async {
    dialogs.nextPickedFile = sampleDoc.path;
    await viewModel.pickFile();

    expect(viewModel.sourceFile, sampleDoc);
    expect(viewModel.canCompress, isTrue);
    expect(viewModel.qualityLevel, CompressQualityLevel.medium);
    expect(viewModel.mode, CompressMode.visual);

    viewModel.clearSource();
    expect(viewModel.sourceFile, isNull);
    expect(viewModel.canCompress, isFalse);
  });

  test('switches compression quality levels and modes', () async {
    await viewModel.setSourcePath(sampleDoc.path);

    viewModel.setQualityLevel(CompressQualityLevel.high);
    expect(viewModel.qualityLevel, CompressQualityLevel.high);

    viewModel.setQualityLevel(CompressQualityLevel.low);
    expect(viewModel.qualityLevel, CompressQualityLevel.low);

    viewModel.setMode(CompressMode.lossless);
    expect(viewModel.mode, CompressMode.lossless);

    viewModel.setMode(CompressMode.visual);
    expect(viewModel.mode, CompressMode.visual);
  });

  test('compresses PDF and captures savings metrics', () async {
    await viewModel.setSourcePath(sampleDoc.path);

    dialogs.nextSavePath = r'C:\docs\laporan_compressed.pdf';
    viewModel.setQualityLevel(CompressQualityLevel.high);

    await viewModel.compressAndSave();

    expect(engine.lastCompressInputPath, sampleDoc.path);
    expect(engine.lastCompressOutputPath, r'C:\docs\laporan_compressed.pdf');
    expect(engine.lastCompressQualityLevel, CompressQualityLevel.high);
    expect(engine.lastCompressMode, CompressMode.visual);
    expect(viewModel.lastResult, isNotNull);
    expect(viewModel.errorMessage, isNull);
  });

  test('handles compression error gracefully', () async {
    await viewModel.setSourcePath(sampleDoc.path);

    engine.compressError =
        const PdfOperationException('Gagal mengompresi stream gambar PDF.');
    dialogs.nextSavePath = r'C:\docs\laporan_compressed.pdf';

    await viewModel.compressAndSave();

    expect(viewModel.lastResult, isNull);
    expect(
      viewModel.errorMessage,
      'Gagal mengompresi stream gambar PDF.',
    );

    viewModel.dismissStatus();
    expect(viewModel.errorMessage, isNull);
  });

  test('openLastOutputFolder delegates to repository revealInFileManager', () async {
    await viewModel.setSourcePath(sampleDoc.path);
    dialogs.nextSavePath = r'C:\docs\laporan_compressed.pdf';
    await viewModel.compressAndSave();

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths, contains(r'C:\docs\laporan_compressed.pdf'));
  });
}
