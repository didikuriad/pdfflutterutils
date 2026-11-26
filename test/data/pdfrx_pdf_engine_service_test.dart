import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/data/services/pdf_engine_service.dart';
import 'package:pdfutils/domain/models/compress_pdf_options.dart';
import 'package:pdfutils/domain/models/operation_result.dart';
import 'package:pdfutils/domain/models/pdf_edit_overlay.dart';
import 'package:pdfutils/domain/models/pdf_rotation.dart';
import 'package:pdfutils/domain/models/split_mode.dart';

import '../test_helpers/fakes.dart';

/// Builds a valid uncompressed RGBA PNG containing a solid color block without
/// requiring external image encoding packages in tests.
Uint8List _createSolidPng2x2({
  required int r,
  required int g,
  required int b,
  int a = 255,
}) {
  final rawScanlines = BytesBuilder();
  for (var y = 0; y < 2; y++) {
    rawScanlines.addByte(0); // Filter type 0 (None)
    for (var x = 0; x < 2; x++) {
      rawScanlines.add(<int>[r, g, b, a]);
    }
  }
  final idatData = Uint8List.fromList(zlib.encode(rawScanlines.toBytes()));

  int crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >>> 1) ^ 0xEDB88320 : (crc >>> 1);
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  void writeChunk(BytesBuilder out, String type, List<int> payload) {
    final headerAndData = BytesBuilder()
      ..add(type.codeUnits)
      ..add(payload);
    final lenBytes = ByteData(4)..setUint32(0, payload.length);
    final crcBytes = ByteData(4)
      ..setUint32(0, crc32(headerAndData.toBytes()));
    out
      ..add(lenBytes.buffer.asUint8List())
      ..add(headerAndData.toBytes())
      ..add(crcBytes.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, 2) // width
    ..setUint32(4, 2) // height
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6) // color type RGBA
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace

  final png = BytesBuilder()
    ..add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  writeChunk(png, 'IHDR', ihdr.buffer.asUint8List());
  writeChunk(png, 'IDAT', idatData);
  writeChunk(png, 'IEND', const <int>[]);
  return png.toBytes();
}

void main() {
  late PdfrxPdfEngineService service;
  late Directory tempDir;

  setUpAll(() async {
    await pdfrxInitialize();
  });

  setUp(() async {
    service = PdfrxPdfEngineService();
    tempDir = await Directory.systemTemp.createTemp('pdfutils_engine_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeSamplePdf(String fileName, int pageCount) async {
    final filePath = p.join(tempDir.path, fileName);
    await File(filePath).writeAsBytes(createMinimalPdfBytes(pageCount));
    return filePath;
  }

  test('inspectFile reads accurate pageCount and file size', () async {
    final path2 = await writeSamplePdf('two.pdf', 2);
    final path3 = await writeSamplePdf('three.pdf', 3);

    final info2 = await service.inspectFile(path2);
    final info3 = await service.inspectFile(path3);

    expect(info2.fileName, 'two.pdf');
    expect(info2.pageCount, 2);
    expect(info2.fileSizeBytes, greaterThan(0));

    expect(info3.fileName, 'three.pdf');
    expect(info3.pageCount, 3);
  });

  test('inspectFile throws PdfOperationException for missing or invalid files', () async {
    await expectLater(
      () => service.inspectFile(p.join(tempDir.path, 'missing.pdf')),
      throwsA(isA<PdfOperationException>()),
    );

    final badPath = p.join(tempDir.path, 'broken.pdf');
    await File(badPath).writeAsString('not a valid pdf');
    await expectLater(
      () => service.inspectFile(badPath),
      throwsA(isA<PdfOperationException>()),
    );
  });

  test('mergePdfs combines selected pages in exact order', () async {
    final pdfA = await writeSamplePdf('a.pdf', 2);
    final pdfB = await writeSamplePdf('b.pdf', 3);
    final outputPath = p.join(tempDir.path, 'merged.pdf');

    final result = await service.mergePdfs(
      sources: <MergeSourceSpec>[
        MergeSourceSpec(filePath: pdfA, oneBasedPages: const <int>[1, 2]),
        MergeSourceSpec(filePath: pdfB, oneBasedPages: const <int>[2, 3]),
      ],
      outputPath: outputPath,
    );

    expect(result.outputPaths, <String>[outputPath]);
    expect(result.totalPagesProcessed, 4);
    expect(await File(outputPath).exists(), isTrue);

    final mergedDoc = await PdfDocument.openFile(outputPath);
    try {
      expect(mergedDoc.pages.length, 4);
      // Sample pages have widths 595, 596 for pdfA and 595, 596, 597 for pdfB.
      expect(mergedDoc.pages[0].width, closeTo(595, 0.5));
      expect(mergedDoc.pages[1].width, closeTo(596, 0.5));
      expect(mergedDoc.pages[2].width, closeTo(596, 0.5));
      expect(mergedDoc.pages[3].width, closeTo(597, 0.5));
    } finally {
      await mergedDoc.dispose();
    }
  });

  test('rotatePdf persists page rotations and supports overwriting input path', () async {
    final inputPath = await writeSamplePdf('rotate_src.pdf', 3);
    final outputPath = p.join(tempDir.path, 'rotated.pdf');

    final result = await service.rotatePdf(
      inputPath: inputPath,
      pageRotations: const <int, RotationQuarterTurns>{
        1: RotationQuarterTurns.deg90,
        2: RotationQuarterTurns.deg180,
        3: RotationQuarterTurns.deg270,
      },
      outputPath: outputPath,
    );

    expect(result.totalPagesProcessed, 3);

    final rotatedDoc = await PdfDocument.openFile(outputPath);
    try {
      expect(rotatedDoc.pages.length, 3);
      expect(rotatedDoc.pages[0].rotation, PdfPageRotation.clockwise90);
      expect(rotatedDoc.pages[1].rotation, PdfPageRotation.clockwise180);
      expect(rotatedDoc.pages[2].rotation, PdfPageRotation.clockwise270);
    } finally {
      await rotatedDoc.dispose();
    }

    // Overwrite the same input path in-place to confirm handles are disposed before write.
    await service.rotatePdf(
      inputPath: outputPath,
      pageRotations: const <int, RotationQuarterTurns>{
        1: RotationQuarterTurns.deg90,
      },
      outputPath: outputPath,
    );

    final twiceRotatedDoc = await PdfDocument.openFile(outputPath);
    try {
      expect(twiceRotatedDoc.pages[0].rotation, PdfPageRotation.clockwise180);
    } finally {
      await twiceRotatedDoc.dispose();
    }
  });

  test('splitPdf exports multiple parts into directory and single-file extracts', () async {
    final inputPath = await writeSamplePdf('split_src.pdf', 5);
    final outDir = p.join(tempDir.path, 'split_out');

    final progressEvents = <(int, int)>[];
    final multiResult = await service.splitPdf(
      inputPath: inputPath,
      groups: const <SplitGroup>[
        SplitGroup(
          label: 'Bagian 1',
          pages: <int>[1, 2],
          suggestedFileName: 'part_1.pdf',
        ),
        SplitGroup(
          label: 'Bagian 2',
          pages: <int>[3, 4, 5],
          suggestedFileName: 'part_2.pdf',
        ),
      ],
      outputDirectory: outDir,
      onProgress: (completed, total) => progressEvents.add((completed, total)),
    );

    expect(progressEvents, <(int, int)>[(1, 2), (2, 2)]);
    expect(multiResult.outputPaths.length, 2);
    expect(multiResult.totalPagesProcessed, 5);

    final part1 = await PdfDocument.openFile(p.join(outDir, 'part_1.pdf'));
    final part2 = await PdfDocument.openFile(p.join(outDir, 'part_2.pdf'));
    try {
      expect(part1.pages.length, 2);
      expect(part2.pages.length, 3);
    } finally {
      await part1.dispose();
      await part2.dispose();
    }

    // Single output extraction
    final extractPath = p.join(tempDir.path, 'single_extract.pdf');
    final singleResult = await service.splitPdf(
      inputPath: inputPath,
      groups: const <SplitGroup>[
        SplitGroup(
          label: 'Ekstrak',
          pages: <int>[2, 4],
          suggestedFileName: 'ignored.pdf',
        ),
      ],
      outputDirectory: tempDir.path,
      singleOutputFilePath: extractPath,
    );

    expect(singleResult.outputPaths, <String>[extractPath]);
    final extracted = await PdfDocument.openFile(extractPath);
    try {
      expect(extracted.pages.length, 2);
    } finally {
      await extracted.dispose();
    }
  });

  test('readPageSizes returns accurate page dimensions for each page', () async {
    final path3 = await writeSamplePdf('sizes_three.pdf', 3);
    final sizes = await service.readPageSizes(path3);

    expect(sizes.length, 3);
    expect(sizes[0].width, closeTo(595, 0.5));
    expect(sizes[0].height, closeTo(842, 0.5));
    expect(sizes[1].width, closeTo(596, 0.5));
    expect(sizes[2].width, closeTo(597, 0.5));
  });

  test(
    'applyEdits embeds text, whiteout, highlight, outline, strokes, and BGRA image losslessly into PDF',
    () async {
      final inputPath = await writeSamplePdf('edit_src.pdf', 2);
      final outputPath = p.join(tempDir.path, 'edited.pdf');
      final bluePng = _createSolidPng2x2(r: 0, g: 80, b: 240);

      final overlays = <PdfEditOverlay>[
        PdfRectOverlay(
          id: 'r_white',
          pageNumber: 1,
          rect: NormalizedRect(left: 0.10, top: 0.10, width: 0.30, height: 0.08),
          kind: PdfRectOverlayKind.whiteout,
          colorArgb: 0xFFFFFFFF,
        ),
        const PdfTextOverlay(
          id: 't_note',
          pageNumber: 1,
          x: 0.12,
          y: 0.25,
          text: 'Catatan Penting',
          fontSizePt: 16,
          colorArgb: 0xFF111827,
          backgroundColorArgb: 0xFFFFFFFF,
          isBold: true,
        ),
        PdfRectOverlay(
          id: 'r_hl',
          pageNumber: 1,
          rect: NormalizedRect(left: 0.10, top: 0.40, width: 0.35, height: 0.08),
          kind: PdfRectOverlayKind.highlight,
          colorArgb: 0x66FACC15,
        ),
        PdfRectOverlay(
          id: 'r_box',
          pageNumber: 1,
          rect: NormalizedRect(left: 0.55, top: 0.10, width: 0.30, height: 0.15),
          kind: PdfRectOverlayKind.outline,
          colorArgb: 0xFFDC2626,
          strokeWidthPt: 3.0,
        ),
        PdfStrokeOverlay(
          id: 's_pen',
          pageNumber: 1,
          strokes: <List<NormalizedPoint>>[
            <NormalizedPoint>[
              NormalizedPoint(0.10, 0.60),
              NormalizedPoint(0.45, 0.60),
            ],
          ],
          colorArgb: 0xFF15803D,
          strokeWidthPt: 5.0,
        ),
        PdfImageOverlay(
          id: 'img_blue',
          pageNumber: 1,
          rect: NormalizedRect(left: 0.55, top: 0.55, width: 0.25, height: 0.20),
          imageBytes: bluePng,
          pixelWidth: 2,
          pixelHeight: 2,
          fileName: 'stamp.png',
        ),
      ];

      final result = await service.applyEdits(
        inputPath: inputPath,
        overlays: overlays,
        outputPath: outputPath,
      );

      expect(result.outputPaths, <String>[outputPath]);
      expect(result.totalPagesProcessed, 1);

      final editedDoc = await PdfDocument.openFile(outputPath);
      try {
        expect(editedDoc.pages.length, 2);
        final pageText = await editedDoc.pages[0].loadText();
        expect(pageText?.fullText, contains('Catatan Penting'));

        final rendered = await editedDoc.pages[0].render(
          fullWidth: 595,
          fullHeight: 842,
        );
        expect(rendered, isNotNull);
        try {
          // Sample pixel inside the embedded blue image (x ~ 0.675*595, y ~ 0.65*842)
          final ix = (0.675 * rendered!.width).round();
          final iy = (0.65 * rendered.height).round();
          final iOff = (iy * rendered.width + ix) * 4;
          final b = rendered.pixels[iOff];
          final g = rendered.pixels[iOff + 1];
          final r = rendered.pixels[iOff + 2];
          expect(b, greaterThan(180));
          expect(r, lessThan(40));
          expect(g, lessThan(130));

          // Sample pixel inside yellow highlight (x ~ 0.25*595, y ~ 0.44*842)
          final hx = (0.25 * rendered.width).round();
          final hy = (0.44 * rendered.height).round();
          final hOff = (hy * rendered.width + hx) * 4;
          final hb = rendered.pixels[hOff];
          final hr = rendered.pixels[hOff + 2];
          expect(hr, greaterThan(220));
          expect(hb, lessThan(220));
        } finally {
          rendered?.dispose();
        }
      } finally {
        await editedDoc.dispose();
      }
    },
  );

  test(
    'applyEdits works accurately on 90-degree rotated page and supports overwriting input file in-place',
    () async {
      final rawPath = await writeSamplePdf('rot_src.pdf', 1);
      final rotPath = p.join(tempDir.path, 'rotated_90.pdf');
      await service.rotatePdf(
        inputPath: rawPath,
        pageRotations: const <int, RotationQuarterTurns>{
          1: RotationQuarterTurns.deg90,
        },
        outputPath: rotPath,
      );

      final rotatedSizes = await service.readPageSizes(rotPath);
      expect(rotatedSizes.length, 1);
      expect(rotatedSizes.first.width, closeTo(842, 0.5));
      expect(rotatedSizes.first.height, closeTo(595, 0.5));

      final overlays = <PdfEditOverlay>[
        const PdfTextOverlay(
          id: 't_rot',
          pageNumber: 1,
          x: 0.12,
          y: 0.15,
          text: 'Teks Rotasi 90',
          fontSizePt: 14,
          colorArgb: 0xFF111827,
        ),
        PdfRectOverlay(
          id: 'r_bottom_right',
          pageNumber: 1,
          rect: NormalizedRect(left: 0.70, top: 0.70, width: 0.20, height: 0.20),
          kind: PdfRectOverlayKind.whiteout,
          colorArgb: 0xFF0044FF,
        ),
      ];

      await service.applyEdits(
        inputPath: rotPath,
        overlays: overlays,
        outputPath: rotPath,
      );

      final doc = await PdfDocument.openFile(rotPath);
      try {
        expect(doc.pages.length, 1);
        expect(doc.pages[0].rotation, PdfPageRotation.clockwise90);
        final pageText = await doc.pages[0].loadText();
        expect(pageText?.fullText, contains('Teks Rotasi 90'));

        final rendered = await doc.pages[0].render(
          fullWidth: 842,
          fullHeight: 595,
        );
        expect(rendered, isNotNull);
        try {
          // Visual bottom-right (x=0.80, y=0.80) must be solid blue.
          final bx = (0.80 * rendered!.width).round();
          final by = (0.80 * rendered.height).round();
          final bOff = (by * rendered.width + bx) * 4;
          expect(rendered.pixels[bOff], greaterThan(200)); // B
          expect(rendered.pixels[bOff + 2], lessThan(40)); // R

          // Visual top-right (x=0.80, y=0.20) must remain white background.
          final wx = (0.80 * rendered.width).round();
          final wy = (0.20 * rendered.height).round();
          final wOff = (wy * rendered.width + wx) * 4;
          expect(rendered.pixels[wOff], greaterThan(245));
          expect(rendered.pixels[wOff + 1], greaterThan(245));
          expect(rendered.pixels[wOff + 2], greaterThan(245));
        } finally {
          rendered?.dispose();
        }
      } finally {
        await doc.dispose();
      }
    },
  );

  test('compressPdf in visual mode compresses pages into a readable PDF', () async {
    final input = await writeSamplePdf('to_compress.pdf', 2);
    final output = p.join(tempDir.path, 'compressed.pdf');

    final result = await service.compressPdf(
      inputPath: input,
      outputPath: output,
      qualityLevel: CompressQualityLevel.medium,
      mode: CompressMode.visual,
    );

    expect(result.outputPaths, <String>[output]);
    expect(result.totalPagesProcessed, 2);
    expect(await File(output).exists(), isTrue);

    final info = await service.inspectFile(output);
    expect(info.pageCount, 2);
  });

  test('compressPdf in lossless mode optimizes document streams', () async {
    final input = await writeSamplePdf('lossless_input.pdf', 2);
    final output = p.join(tempDir.path, 'lossless_output.pdf');

    final result = await service.compressPdf(
      inputPath: input,
      outputPath: output,
      qualityLevel: CompressQualityLevel.low,
      mode: CompressMode.lossless,
    );

    expect(result.outputPaths, <String>[output]);
    expect(result.totalPagesProcessed, 2);
    expect(await File(output).exists(), isTrue);

    final info = await service.inspectFile(output);
    expect(info.pageCount, 2);
  });
}
