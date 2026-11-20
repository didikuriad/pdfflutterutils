import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_edit_overlay.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/features/edit/view_models/edit_pdf_view_model.dart';

import '../test_helpers/fakes.dart';

void main() {
  late FakePdfEngineService engine;
  late FakeFileDialogService dialogs;
  late EditPdfViewModel viewModel;
  late Directory tempDir;

  const sampleDoc = PdfFileInfo(
    path: r'C:\docs\kontrak.pdf',
    fileName: 'kontrak.pdf',
    pageCount: 3,
    fileSizeBytes: 4096,
  );

  setUp(() async {
    final setup = createFakeRepository();
    engine = setup.engine;
    dialogs = setup.dialogs;
    engine.filesByPath[sampleDoc.path] = sampleDoc;
    engine.pageSizesByPath[sampleDoc.path] = const <PdfPageSize>[
      PdfPageSize(width: 595, height: 842),
      PdfPageSize(width: 842, height: 595),
      PdfPageSize(width: 595, height: 842),
    ];
    tempDir = await Directory.systemTemp.createTemp('pdfutils_edit_vm_');
    viewModel = EditPdfViewModel(
      repository: setup.repository,
      imageDecoder: (bytes) async => (
        width: 200,
        height: 100,
        bgraBytes: Uint8List(200 * 100 * 4),
      ),
    );
  });

  tearDown(() async {
    viewModel.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads PDF file, reads page sizes, navigates pages, and manages zoom', () async {
    dialogs.nextPickedFile = sampleDoc.path;
    await viewModel.pickFile();

    expect(viewModel.sourceFile, sampleDoc);
    expect(viewModel.currentPage, 1);
    expect(viewModel.pageSizeFor(1), const PdfPageSize(width: 595, height: 842));
    expect(viewModel.pageSizeFor(2), const PdfPageSize(width: 842, height: 595));

    viewModel.nextPage();
    expect(viewModel.currentPage, 2);
    viewModel.previousPage();
    expect(viewModel.currentPage, 1);
    viewModel.goToPage(99);
    expect(viewModel.currentPage, 3);

    viewModel.zoomIn();
    expect(viewModel.zoom, closeTo(1.25, 0.001));
    viewModel.zoomOut();
    viewModel.zoomOut();
    expect(viewModel.zoom, closeTo(0.75, 0.001));
    viewModel.resetZoom();
    expect(viewModel.zoom, 1.0);
  });

  test('skips non-PDF dropped files and reports skipped count', () async {
    await viewModel.loadFromDroppedPaths(
      <String>[r'C:\docs\image.png', sampleDoc.path],
      ignoredNonPdfCount: 1,
    );

    expect(viewModel.sourceFile, sampleDoc);
    expect(viewModel.errorMessage, contains('2 file bukan PDF dilewati'));
  });

  test('supports adding text, whiteout, highlight, outline, strokes, signature, image, restyling, and undo/redo', () async {
    await viewModel.loadFile(sampleDoc.path);

    // 1. Add text with white backing, edit text, restyle color/font/bold
    final addedText = viewModel.addTextOverlay(
      x: 0.2,
      y: 0.3,
      text: 'Lampiran A',
      whiteBackground: true,
    );
    expect(addedText, isNotNull);
    expect(addedText!.backgroundColorArgb, 0xFFFFFFFF);
    expect(viewModel.canSave, isTrue);

    viewModel.updateSelectedText('Lampiran B', whiteBackground: false);
    final edited = viewModel.selectedOverlay! as PdfTextOverlay;
    expect(edited.text, 'Lampiran B');
    expect(edited.backgroundColorArgb, isNull);

    viewModel.setFontSize(20);
    viewModel.toggleTextBold();
    viewModel.setActiveColor(0xFFDC2626);
    final restyledText = viewModel.selectedOverlay! as PdfTextOverlay;
    expect(restyledText.fontSizePt, 20);
    expect(restyledText.isBold, isTrue);
    expect(restyledText.colorArgb, 0xFFDC2626);

    // 2. Add whiteout, highlight, and outline boxes
    final whiteout = viewModel.addRectOverlay(
      rect: NormalizedRect(left: 0.1, top: 0.1, width: 0.2, height: 0.05),
      kind: PdfRectOverlayKind.whiteout,
    );
    final highlight = viewModel.addRectOverlay(
      rect: NormalizedRect(left: 0.1, top: 0.5, width: 0.3, height: 0.04),
      kind: PdfRectOverlayKind.highlight,
    );
    final outline = viewModel.addRectOverlay(
      rect: NormalizedRect(left: 0.5, top: 0.2, width: 0.25, height: 0.15),
      kind: PdfRectOverlayKind.outline,
    );
    expect(whiteout?.kind, PdfRectOverlayKind.whiteout);
    expect(highlight?.kind, PdfRectOverlayKind.highlight);
    expect(outline?.kind, PdfRectOverlayKind.outline);

    // 3. Pen stroke + signature pad strokes
    final stroke = viewModel.addStrokeOverlay(
      strokes: <List<NormalizedPoint>>[
        <NormalizedPoint>[
          NormalizedPoint(0.1, 0.7),
          NormalizedPoint(0.25, 0.75),
        ],
      ],
    );
    expect(stroke, isNotNull);

    final signature = viewModel.insertSignatureStrokes(<List<NormalizedPoint>>[
      <NormalizedPoint>[
        NormalizedPoint(0.1, 0.2),
        NormalizedPoint(0.8, 0.7),
      ],
    ]);
    expect(signature?.isSignature, isTrue);
    expect(viewModel.activeTool, PdfEditTool.select);
    expect(viewModel.selectedOverlayId, signature!.id);

    // 4. Image insert preserves 2:1 aspect ratio cleanly centered
    final imgFile = File(p.join(tempDir.path, 'ttd.png'));
    await imgFile.writeAsBytes(const <int>[1, 2, 3, 4]);
    dialogs.nextPickedImage = imgFile.path;
    await viewModel.pickAndInsertImage();
    final insertedImg = viewModel.selectedOverlay! as PdfImageOverlay;
    expect(insertedImg.fileName, 'ttd.png');
    expect(insertedImg.rect.width, closeTo(0.35, 0.01));

    // 5. Live move/resize + single undo commit
    final snap = viewModel.captureSnapshot();
    viewModel.updateOverlayLive(insertedImg.translated(0.05, 0.05));
    viewModel.commitSnapshot(snap);
    expect(
      (viewModel.selectedOverlay! as PdfImageOverlay).rect.left,
      closeTo(insertedImg.rect.left + 0.05, 0.001),
    );

    final countAfterMove = viewModel.totalOverlayCount;
    expect(countAfterMove, 7);

    // Undo move -> reverts position while keeping overlay count
    viewModel.undo();
    expect(
      (viewModel.selectedOverlay! as PdfImageOverlay).rect.left,
      closeTo(insertedImg.rect.left, 0.001),
    );
    viewModel.redo();
    expect(
      (viewModel.selectedOverlay! as PdfImageOverlay).rect.left,
      closeTo(insertedImg.rect.left + 0.05, 0.001),
    );

    // Delete & clear per page vs all pages
    viewModel.goToPage(2);
    viewModel.addTextOverlay(x: 0.1, y: 0.1, text: 'Hal 2');
    expect(viewModel.overlayCountForPage(1), 7);
    expect(viewModel.overlayCountForPage(2), 1);

    viewModel.clearCurrentPageOverlays();
    expect(viewModel.overlayCountForPage(2), 0);
    expect(viewModel.overlayCountForPage(1), 7);

    viewModel.goToPage(1);
    viewModel.selectOverlay(edited.id);
    viewModel.deleteSelectedOverlay();
    expect(viewModel.overlayCountForPage(1), 6);

    viewModel.clearAllOverlays();
    expect(viewModel.totalOverlayCount, 0);
  });

  test('saves edited PDF to a new file and reloads cleanly when overwriting source path', () async {
    final realPdfPath = p.join(tempDir.path, 'asli.pdf');
    await File(realPdfPath).writeAsBytes(<int>[1, 2, 3]);
    engine.filesByPath[realPdfPath] = PdfFileInfo(
      path: realPdfPath,
      fileName: 'asli.pdf',
      pageCount: 2,
      fileSizeBytes: 3,
    );
    engine.pageSizesByPath[realPdfPath] = const <PdfPageSize>[
      PdfPageSize.a4,
      PdfPageSize.a4,
    ];

    await viewModel.loadFile(realPdfPath);
    viewModel.addTextOverlay(x: 0.2, y: 0.2, text: 'Revisi');
    final initialRev = viewModel.documentRevision;

    // 1. Save as new file -> keeps pending overlays in session
    final copyOut = p.join(tempDir.path, 'asli_edited.pdf');
    dialogs.nextSavePath = copyOut;
    await viewModel.saveEditedPdf();
    expect(engine.lastEditOutputPath, copyOut);
    expect(viewModel.totalOverlayCount, 1);
    expect(viewModel.documentRevision, initialRev);

    await viewModel.openLastOutputFolder();
    expect(dialogs.revealedPaths, <String>[copyOut]);

    // 2. Overwrite original source file -> clears applied overlays & increments revision
    dialogs.nextSavePath = realPdfPath;
    await viewModel.saveEditedPdf();
    expect(engine.lastEditOutputPath, realPdfPath);
    expect(viewModel.totalOverlayCount, 0);
    expect(viewModel.documentRevision, initialRev + 1);
  });

  test('exposes errorMessage cleanly when applyEdits throws PdfOperationException', () async {
    await viewModel.loadFile(sampleDoc.path);
    viewModel.addTextOverlay(x: 0.2, y: 0.2, text: 'Test');

    engine.editError = const PdfOperationException('File tujuan terkunci.');
    dialogs.nextSavePath = r'C:\docs\kontrak_edited.pdf';
    await viewModel.saveEditedPdf();

    expect(viewModel.errorMessage, 'File tujuan terkunci.');
    expect(viewModel.lastResult, isNull);
  });
}
