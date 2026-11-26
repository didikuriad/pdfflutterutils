import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size, VoidCallback;

import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/data/services/desktop_platform_service.dart';
import 'package:pdfutils/data/services/file_dialog_service.dart';
import 'package:pdfutils/data/services/pdf_engine_service.dart';
import 'package:pdfutils/data/services/pdf_to_docx_service.dart';
import 'package:pdfutils/domain/models/app_window_mode.dart';
import 'package:pdfutils/domain/models/compress_pdf_options.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_edit_overlay.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';
import 'package:pdfutils/domain/models/split_mode.dart';

/// Generates a minimal, spec-compliant PDF 1.4 byte payload with [pageCount] pages.
///
/// Each page has distinct width `595 + pageIndex` and height `842` points so
/// callers can even distinguish pages if needed.
Uint8List createMinimalPdfBytes(int pageCount) {
  assert(pageCount >= 1, 'pageCount must be at least 1');

  final buffer = BytesBuilder();
  void writeAscii(String text) {
    buffer.add(latin1.encode(text));
  }

  writeAscii('%PDF-1.4\n');

  final totalObjects = 2 + pageCount * 2;
  final offsets = List<int>.filled(totalObjects + 1, 0);

  void writeObject(int id, String body) {
    offsets[id] = buffer.length;
    writeAscii('$id 0 obj\n$body\nendobj\n');
  }

  final kidsRefs = <String>[
    for (var i = 0; i < pageCount; i++) '${3 + i * 2} 0 R',
  ].join(' ');

  writeObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  writeObject(2, '<< /Type /Pages /Kids [$kidsRefs] /Count $pageCount >>');

  for (var i = 0; i < pageCount; i++) {
    final pageId = 3 + i * 2;
    final contentId = pageId + 1;
    final width = 595 + i;
    const height = 842;
    final streamContent = 'q 0.9 g 50 50 100 100 re f Q';

    writeObject(
      pageId,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] /Contents $contentId 0 R >>',
    );
    writeObject(
      contentId,
      '<< /Length ${streamContent.length} >>\nstream\n$streamContent\nendstream',
    );
  }

  final xrefOffset = buffer.length;
  writeAscii('xref\n0 ${totalObjects + 1}\n');
  writeAscii('0000000000 65535 f \n');
  for (var id = 1; id <= totalObjects; id++) {
    final padded = offsets[id].toString().padLeft(10, '0');
    writeAscii('$padded 00000 n \n');
  }
  writeAscii(
    'trailer\n<< /Size ${totalObjects + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
  );

  return buffer.toBytes();
}

/// Generates a minimal, spec-compliant PDF 1.4 containing literal ASCII text [text]
/// using the standard `/Helvetica` Type1 font for Word COM conversion testing.
Uint8List createMinimalTextPdfBytes(String text) {
  final escapedText = text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  final streamContent = 'BT /F1 18 Tf 72 720 Td ($escapedText) Tj ET';

  final buffer = BytesBuilder();
  void writeAscii(String value) {
    buffer.add(latin1.encode(value));
  }

  writeAscii('%PDF-1.4\n');
  final offsets = List<int>.filled(6, 0);

  void writeObject(int id, String body) {
    offsets[id] = buffer.length;
    writeAscii('$id 0 obj\n$body\nendobj\n');
  }

  writeObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  writeObject(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  writeObject(
    3,
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
  );
  writeObject(
    4,
    '<< /Length ${streamContent.length} >>\nstream\n$streamContent\nendstream',
  );
  writeObject(
    5,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  );

  final xrefOffset = buffer.length;
  writeAscii('xref\n0 6\n');
  writeAscii('0000000000 65535 f \n');
  for (var id = 1; id <= 5; id++) {
    final padded = offsets[id].toString().padLeft(10, '0');
    writeAscii('$padded 00000 n \n');
  }
  writeAscii(
    'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n',
  );

  return buffer.toBytes();
}

/// Fake [PdfEngineService] recording invocations and returning configured responses.
class FakePdfEngineService implements PdfEngineService {
  final Map<String, PdfFileInfo> filesByPath = <String, PdfFileInfo>{};
  final Map<String, List<PdfPageSize>> pageSizesByPath =
      <String, List<PdfPageSize>>{};
  final Map<String, Uint8List> pdfBytesByPath = <String, Uint8List>{};
  final Map<String, Object> inspectErrorsByPath = <String, Object>{};

  Object? mergeError;
  Object? rotateError;
  Object? splitError;
  Object? editError;
  Object? compressError;

  List<MergeSourceSpec>? lastMergeSources;
  String? lastMergeOutputPath;

  String? lastRotateInputPath;
  Map<int, RotationQuarterTurns>? lastPageRotations;
  String? lastRotateOutputPath;

  String? lastSplitInputPath;
  List<SplitGroup>? lastSplitGroups;
  String? lastSplitOutputDirectory;
  String? lastSplitSingleOutputPath;

  String? lastEditInputPath;
  List<PdfEditOverlay>? lastEditOverlays;
  String? lastEditOutputPath;

  String? lastCompressInputPath;
  String? lastCompressOutputPath;
  CompressQualityLevel? lastCompressQualityLevel;
  CompressMode? lastCompressMode;

  @override
  Future<PdfFileInfo> inspectFile(String filePath) async {
    final error = inspectErrorsByPath[filePath];
    if (error != null) throw error;
    final info = filesByPath[filePath];
    if (info == null) {
      throw PdfOperationException('File tidak ditemukan: $filePath');
    }
    return info;
  }

  @override
  Future<List<PdfPageSize>> readPageSizes(String filePath) async {
    final configured = pageSizesByPath[filePath];
    if (configured != null) return configured;
    final info = await inspectFile(filePath);
    return List<PdfPageSize>.filled(info.pageCount, PdfPageSize.a4);
  }

  @override
  Future<Uint8List?> readPdfBytes(String filePath) async =>
      pdfBytesByPath[filePath];

  @override
  Future<PdfOperationResult> mergePdfs({
    required List<MergeSourceSpec> sources,
    required String outputPath,
  }) async {
    if (mergeError != null) throw mergeError!;
    lastMergeSources = List<MergeSourceSpec>.from(sources);
    lastMergeOutputPath = outputPath;
    final totalPages = sources.fold<int>(
      0,
      (sum, spec) => sum + spec.oneBasedPages.length,
    );
    return PdfOperationResult(
      outputPaths: <String>[outputPath],
      totalPagesProcessed: totalPages,
      message: 'Berhasil menggabungkan ${sources.length} file ($totalPages halaman).',
    );
  }

  @override
  Future<PdfOperationResult> rotatePdf({
    required String inputPath,
    required Map<int, RotationQuarterTurns> pageRotations,
    required String outputPath,
  }) async {
    if (rotateError != null) throw rotateError!;
    lastRotateInputPath = inputPath;
    lastPageRotations = Map<int, RotationQuarterTurns>.from(pageRotations);
    lastRotateOutputPath = outputPath;
    final info = filesByPath[inputPath];
    final totalPages = info?.pageCount ?? 0;
    return PdfOperationResult(
      outputPaths: <String>[outputPath],
      totalPagesProcessed: totalPages,
      message: 'Berhasil menyimpan $outputPath.',
    );
  }

  @override
  Future<PdfOperationResult> splitPdf({
    required String inputPath,
    required List<SplitGroup> groups,
    required String outputDirectory,
    String? singleOutputFilePath,
    PdfProgressCallback? onProgress,
  }) async {
    if (splitError != null) throw splitError!;
    lastSplitInputPath = inputPath;
    lastSplitGroups = List<SplitGroup>.from(groups);
    lastSplitOutputDirectory = outputDirectory;
    lastSplitSingleOutputPath = singleOutputFilePath;

    final outputs = <String>[];
    var totalPages = 0;
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (singleOutputFilePath != null && groups.length == 1) {
        outputs.add(singleOutputFilePath);
      } else {
        outputs.add('$outputDirectory/${group.suggestedFileName}');
      }
      totalPages += group.pages.length;
      onProgress?.call(i + 1, groups.length);
    }

    return PdfOperationResult(
      outputPaths: outputs,
      totalPagesProcessed: totalPages,
      message: 'Berhasil memisah PDF menjadi ${outputs.length} file.',
    );
  }

  @override
  Future<PdfOperationResult> applyEdits({
    required String inputPath,
    required List<PdfEditOverlay> overlays,
    required String outputPath,
  }) async {
    if (editError != null) throw editError!;
    lastEditInputPath = inputPath;
    lastEditOverlays = List<PdfEditOverlay>.from(overlays);
    lastEditOutputPath = outputPath;
    final touchedPages = overlays.map((o) => o.pageNumber).toSet().length;
    return PdfOperationResult(
      outputPaths: <String>[outputPath],
      totalPagesProcessed: touchedPages,
      message:
          'Berhasil menyimpan $outputPath (${overlays.length} anotasi pada $touchedPages halaman).',
    );
  }

  @override
  Future<PdfOperationResult> compressPdf({
    required String inputPath,
    required String outputPath,
    required CompressQualityLevel qualityLevel,
    required CompressMode mode,
    PdfProgressCallback? onProgress,
  }) async {
    if (compressError != null) throw compressError!;
    lastCompressInputPath = inputPath;
    lastCompressOutputPath = outputPath;
    lastCompressQualityLevel = qualityLevel;
    lastCompressMode = mode;
    final info = await inspectFile(inputPath);
    onProgress?.call(info.pageCount, info.pageCount);
    return PdfOperationResult(
      outputPaths: <String>[outputPath],
      totalPagesProcessed: info.pageCount,
      message:
          'Berhasil mengompresi ${info.fileName} menjadi $outputPath (${qualityLevel.label}).',
    );
  }
}

/// Fake [FileDialogService] returning preconfigured selections.
class FakeFileDialogService implements FileDialogService {
  String? nextPickedFile;
  List<String> nextPickedFiles = const <String>[];
  String? nextPickedImage;
  String? nextSavePath;
  String? nextSaveDocxPath;
  String? nextOutputDirectory;
  final List<String> revealedPaths = <String>[];

  @override
  Future<String?> pickPdfFile() async => nextPickedFile;

  @override
  Future<List<String>> pickPdfFiles() async => nextPickedFiles;

  @override
  Future<String?> pickImageFile() async => nextPickedImage;

  @override
  Future<String?> pickSavePdfPath({required String suggestedName}) async =>
      nextSavePath;

  @override
  Future<String?> pickSaveDocxPath({required String suggestedName}) async =>
      nextSaveDocxPath;

  @override
  Future<String?> pickOutputDirectory({String? confirmButtonText}) async =>
      nextOutputDirectory;

  @override
  Future<void> revealInFileManager(String path) async {
    revealedPaths.add(path);
  }
}

/// Fake [PdfToDocxService] recording conversion requests in unit and widget tests.
class FakePdfToDocxService implements PdfToDocxService {
  bool available = true;
  Object? conversionError;
  final List<({String inputPath, String outputPath})> convertedJobs =
      <({String inputPath, String outputPath})>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> convertPdfToDocx({
    required String inputPath,
    required String outputPath,
  }) async {
    if (conversionError != null) throw conversionError!;
    convertedJobs.add((inputPath: inputPath, outputPath: outputPath));
    return outputPath;
  }
}

/// Convenience factory creating a [PdfRepository] backed by fakes.
({
  PdfRepository repository,
  FakePdfEngineService engine,
  FakeFileDialogService dialogs,
  FakePdfToDocxService docx,
}) createFakeRepository() {
  final engine = FakePdfEngineService();
  final dialogs = FakeFileDialogService();
  final docx = FakePdfToDocxService();
  final repository = PdfRepository(
    engineService: engine,
    dialogService: dialogs,
    pdfToDocxService: docx,
  );
  return (repository: repository, engine: engine, dialogs: dialogs, docx: docx);
}

/// Fake [DesktopPlatformService] recording window/tray calls and allowing
/// simulated tray interactions in tests.
class FakeDesktopPlatformService implements DesktopPlatformService {
  int initializeCount = 0;
  int hideCount = 0;
  int showCount = 0;
  int exitCount = 0;
  int disposeCount = 0;

  Size? currentWindowSize = const Size(1360, 860);
  final List<AppWindowMode> appliedModes = <AppWindowMode>[];
  Size? lastRestoreDesktopSize;
  final List<
      ({
        AppWindowMode mode,
        bool isWindowHidden,
        int? autoHideSecondsRemaining,
      })> trayStates = <({
    AppWindowMode mode,
    bool isWindowHidden,
    int? autoHideSecondsRemaining,
  })>[];

  VoidCallback? _onTrayRestore;
  VoidCallback? _onTrayToggleWindowMode;
  VoidCallback? _onTrayStartAutoHide;
  VoidCallback? _onTrayExit;

  @override
  Future<void> initialize({
    required VoidCallback onTrayRestore,
    required VoidCallback onTrayToggleWindowMode,
    required VoidCallback onTrayStartAutoHide,
    required VoidCallback onTrayExit,
    required AppWindowMode initialMode,
  }) async {
    initializeCount++;
    _onTrayRestore = onTrayRestore;
    _onTrayToggleWindowMode = onTrayToggleWindowMode;
    _onTrayStartAutoHide = onTrayStartAutoHide;
    _onTrayExit = onTrayExit;
  }

  @override
  Future<Size?> getWindowSize() async => currentWindowSize;

  @override
  Future<void> applyWindowMode(
    AppWindowMode mode, {
    Size? restoreDesktopSize,
  }) async {
    appliedModes.add(mode);
    lastRestoreDesktopSize = restoreDesktopSize;
    currentWindowSize = mode == AppWindowMode.compact
        ? const Size(AppWindowMode.compactWidth, AppWindowMode.compactHeight)
        : (restoreDesktopSize ??
            const Size(
              AppWindowMode.desktopWidth,
              AppWindowMode.desktopHeight,
            ));
  }

  @override
  Future<void> hideWindow() async {
    hideCount++;
  }

  @override
  Future<void> showAndFocusWindow() async {
    showCount++;
  }

  @override
  Future<void> updateTrayState({
    required AppWindowMode mode,
    required bool isWindowHidden,
    required int? autoHideSecondsRemaining,
  }) async {
    trayStates.add((
      mode: mode,
      isWindowHidden: isWindowHidden,
      autoHideSecondsRemaining: autoHideSecondsRemaining,
    ));
  }

  @override
  Future<void> exitApplication() async {
    exitCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  void simulateTrayRestore() => _onTrayRestore?.call();
  void simulateTrayToggleMode() => _onTrayToggleWindowMode?.call();
  void simulateTrayStartAutoHide() => _onTrayStartAutoHide?.call();
  void simulateTrayExit() => _onTrayExit?.call();
}
