import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models/operation_result.dart';
import '../../domain/models/pdf_edit_overlay.dart';

pdfium_bindings.PDFium? _cachedPdfium;

pdfium_bindings.PDFium _loadPdfium(String? modulePath) {
  return _cachedPdfium ??=
      pdfium_bindings.getPdfium(modulePath: modulePath);
}

typedef _WorkerOverlayJob = ({
  int nativeDocHandle,
  String? pdfiumModulePath,
  Map<int, List<PdfEditOverlay>> groupedByPage,
  Map<String, ({int width, int height, Uint8List bgraBytes})> decodedImages,
});

/// Decodes compressed image bytes (PNG/JPEG/WebP/BMP) into straight-alpha BGRA
/// pixel bytes compatible with `FPDFBitmap_BGRA`.
Future<({int width, int height, Uint8List bgraBytes})>
    decodeImageToStraightBgra(Uint8List encodedBytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(encodedBytes);
    final frame = await codec.getNextFrame();
    image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (byteData == null) {
      throw const PdfOperationException(
        'Gagal membaca piksel gambar untuk disisipkan ke PDF.',
      );
    }

    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final bgra = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      bgra[i] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i];
      bgra[i + 3] = rgba[i + 3];
    }
    return (width: image.width, height: image.height, bgraBytes: bgra);
  } catch (error) {
    if (error is PdfOperationException) rethrow;
    throw PdfOperationException(
      'Format gambar tidak didukung atau file gambar rusak.',
      error,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Writes non-destructive vector shapes, text, strokes, and images directly into
/// [document]'s native PDFium pages.
Future<void> applyOverlaysToPdfDocument({
  required PdfDocument document,
  required List<PdfEditOverlay> overlays,
}) async {
  if (overlays.isEmpty) return;

  final decodedImages =
      <String, ({int width, int height, Uint8List bgraBytes})>{};
  for (final overlay in overlays) {
    if (overlay is PdfImageOverlay) {
      if (overlay.preDecodedBgraBytes != null) {
        decodedImages[overlay.id] = (
          width: overlay.pixelWidth,
          height: overlay.pixelHeight,
          bgraBytes: overlay.preDecodedBgraBytes!,
        );
      } else {
        decodedImages[overlay.id] =
            await decodeImageToStraightBgra(overlay.imageBytes);
      }
    }
  }

  final groupedByPage = <int, List<PdfEditOverlay>>{};
  for (final overlay in overlays) {
    groupedByPage
        .putIfAbsent(overlay.pageNumber, () => <PdfEditOverlay>[])
        .add(overlay);
  }

  final nativeDocHandle =
      await document.useNativeDocumentHandle((handle) => handle);
  final errorMessage = await PdfrxEntryFunctions.instance.compute(
    _applyOverlaysOnWorkerIsolate,
    (
      nativeDocHandle: nativeDocHandle,
      pdfiumModulePath: Pdfrx.pdfiumModulePath,
      groupedByPage: groupedByPage,
      decodedImages: decodedImages,
    ),
  );
  if (errorMessage != null) {
    throw PdfOperationException(errorMessage);
  }
}

String? _applyOverlaysOnWorkerIsolate(_WorkerOverlayJob job) {
  try {
    final pdfium = _loadPdfium(job.pdfiumModulePath);
    final fpdfDoc =
        pdfium_bindings.FPDF_DOCUMENT.fromAddress(job.nativeDocHandle);

    pdfium_bindings.FPDF_FONT? regularFont;
    pdfium_bindings.FPDF_FONT? boldFont;

    pdfium_bindings.FPDF_FONT getFont({required bool bold}) {
      if (bold) {
        if (boldFont != null) return boldFont!;
        return using((arena) {
          final fontName = 'Helvetica-Bold'.toNativeUtf8(allocator: arena);
          final loaded =
              pdfium.FPDFText_LoadStandardFont(fpdfDoc, fontName.cast());
          if (loaded == ffi.nullptr) {
            throw const PdfOperationException(
              'Gagal memuat font standar Helvetica-Bold PDFium.',
            );
          }
          boldFont = loaded;
          return loaded;
        });
      }
      if (regularFont != null) return regularFont!;
      return using((arena) {
        final fontName = 'Helvetica'.toNativeUtf8(allocator: arena);
        final loaded =
            pdfium.FPDFText_LoadStandardFont(fpdfDoc, fontName.cast());
        if (loaded == ffi.nullptr) {
          throw const PdfOperationException(
            'Gagal memuat font standar Helvetica PDFium.',
          );
        }
        regularFont = loaded;
        return loaded;
      });
    }

    try {
      for (final entry in job.groupedByPage.entries) {
        final pageIndex = entry.key - 1;
        final page = pdfium.FPDF_LoadPage(fpdfDoc, pageIndex);
        if (page == ffi.nullptr) {
          throw PdfOperationException(
            'Gagal membuka halaman ${entry.key} untuk diedit.',
          );
        }

        try {
          using((arena) {
            final pageW = pdfium.FPDF_GetPageWidthF(page);
            final pageH = pdfium.FPDF_GetPageHeightF(page);
            if (pageW <= 0 || pageH <= 0) {
              throw PdfOperationException(
                'Ukuran halaman ${entry.key} tidak valid.',
              );
            }

            final basis = _computeVisualToRawBasis(
              pdfium: pdfium,
              page: page,
              pageW: pageW,
              pageH: pageH,
              arena: arena,
            );
            final pageArrayPtr = arena<pdfium_bindings.FPDF_PAGE>();
            pageArrayPtr.value = page;

            for (final overlay in entry.value) {
              switch (overlay) {
                case PdfRectOverlay():
                  _insertRectOverlay(
                    pdfium: pdfium,
                    page: page,
                    pageW: pageW,
                    pageH: pageH,
                    basis: basis,
                    overlay: overlay,
                  );
                case PdfStrokeOverlay():
                  _insertStrokeOverlay(
                    pdfium: pdfium,
                    page: page,
                    pageW: pageW,
                    pageH: pageH,
                    basis: basis,
                    overlay: overlay,
                  );
                case PdfTextOverlay():
                  _insertTextOverlay(
                    pdfium: pdfium,
                    fpdfDoc: fpdfDoc,
                    page: page,
                    pageW: pageW,
                    pageH: pageH,
                    basis: basis,
                    getFont: getFont,
                    overlay: overlay,
                    arena: arena,
                  );
                case PdfImageOverlay():
                  final decoded = job.decodedImages[overlay.id]!;
                  _insertImageOverlay(
                    pdfium: pdfium,
                    fpdfDoc: fpdfDoc,
                    page: page,
                    pageArrayPtr: pageArrayPtr,
                    pageW: pageW,
                    pageH: pageH,
                    basis: basis,
                    overlay: overlay,
                    decoded: decoded,
                  );
              }
            }

            if (pdfium.FPDFPage_GenerateContent(page) == 0) {
              throw PdfOperationException(
                'Gagal memperbarui konten halaman ${entry.key}.',
              );
            }
          });
        } finally {
          pdfium.FPDF_ClosePage(page);
        }
      }
    } finally {
      if (regularFont != null) {
        pdfium.FPDFFont_Close(regularFont!);
      }
      if (boldFont != null) {
        pdfium.FPDFFont_Close(boldFont!);
      }
    }
    return null;
  } on PdfOperationException catch (error) {
    return error.message;
  }
}

typedef _AffineBasis = ({
  double ux,
  double uy,
  double vx,
  double vy,
  double ox,
  double oy,
});

_AffineBasis _computeVisualToRawBasis({
  required pdfium_bindings.PDFium pdfium,
  required pdfium_bindings.FPDF_PAGE page,
  required double pageW,
  required double pageH,
  required Arena arena,
}) {
  final sizeX = (pageW * 1000).round().clamp(1, 100000000);
  final sizeY = (pageH * 1000).round().clamp(1, 100000000);

  final px = arena<ffi.Double>();
  final py = arena<ffi.Double>();

  if (pdfium.FPDF_DeviceToPage(page, 0, 0, sizeX, sizeY, 0, 0, sizeY, px, py) ==
      0) {
    return (ux: 1, uy: 0, vx: 0, vy: 1, ox: 0, oy: 0);
  }
  final ox = px.value;
  final oy = py.value;

  if (pdfium.FPDF_DeviceToPage(
          page, 0, 0, sizeX, sizeY, 0, sizeX, sizeY, px, py) ==
      0) {
    return (ux: 1, uy: 0, vx: 0, vy: 1, ox: 0, oy: 0);
  }
  final ux = (px.value - ox) / pageW;
  final uy = (py.value - oy) / pageW;

  if (pdfium.FPDF_DeviceToPage(page, 0, 0, sizeX, sizeY, 0, 0, 0, px, py) == 0) {
    return (ux: 1, uy: 0, vx: 0, vy: 1, ox: 0, oy: 0);
  }
  final vx = (px.value - ox) / pageH;
  final vy = (py.value - oy) / pageH;

  return (ux: ux, uy: uy, vx: vx, vy: vy, ox: ox, oy: oy);
}

void _insertRectOverlay({
  required pdfium_bindings.PDFium pdfium,
  required pdfium_bindings.FPDF_PAGE page,
  required double pageW,
  required double pageH,
  required _AffineBasis basis,
  required PdfRectOverlay overlay,
}) {
  final vx0 = overlay.rect.left * pageW;
  final vy0 = (1.0 - overlay.rect.bottom) * pageH;
  final vw = overlay.rect.width * pageW;
  final vh = overlay.rect.height * pageH;
  if (vw <= 0.1 || vh <= 0.1) return;

  final rectObj = pdfium.FPDFPageObj_CreateNewRect(vx0, vy0, vw, vh);
  if (rectObj == ffi.nullptr) {
    throw const PdfOperationException('Gagal membuat objek kotak di PDF.');
  }

  final r = argbRed(overlay.colorArgb);
  final g = argbGreen(overlay.colorArgb);
  final b = argbBlue(overlay.colorArgb);
  final a = argbAlpha(overlay.colorArgb);

  switch (overlay.kind) {
    case PdfRectOverlayKind.whiteout:
    case PdfRectOverlayKind.highlight:
      pdfium.FPDFPageObj_SetFillColor(rectObj, r, g, b, a);
      pdfium.FPDFPath_SetDrawMode(
        rectObj,
        pdfium_bindings.FPDF_FILLMODE_WINDING,
        0,
      );
    case PdfRectOverlayKind.outline:
      pdfium.FPDFPageObj_SetStrokeColor(rectObj, r, g, b, a);
      pdfium.FPDFPageObj_SetStrokeWidth(rectObj, overlay.strokeWidthPt);
      pdfium.FPDFPageObj_SetLineJoin(
        rectObj,
        pdfium_bindings.FPDF_LINEJOIN_MITER,
      );
      pdfium.FPDFPath_SetDrawMode(
        rectObj,
        pdfium_bindings.FPDF_FILLMODE_NONE,
        1,
      );
  }

  pdfium.FPDFPageObj_Transform(
    rectObj,
    basis.ux,
    basis.uy,
    basis.vx,
    basis.vy,
    basis.ox,
    basis.oy,
  );
  pdfium.FPDFPage_InsertObject(page, rectObj);
}

void _insertStrokeOverlay({
  required pdfium_bindings.PDFium pdfium,
  required pdfium_bindings.FPDF_PAGE page,
  required double pageW,
  required double pageH,
  required _AffineBasis basis,
  required PdfStrokeOverlay overlay,
}) {
  final r = argbRed(overlay.colorArgb);
  final g = argbGreen(overlay.colorArgb);
  final b = argbBlue(overlay.colorArgb);
  final a = argbAlpha(overlay.colorArgb);

  for (final polyline in overlay.strokes) {
    if (polyline.isEmpty) continue;
    final p0x = polyline.first.x * pageW;
    final p0y = (1.0 - polyline.first.y) * pageH;

    final pathObj = pdfium.FPDFPageObj_CreateNewPath(p0x, p0y);
    if (pathObj == ffi.nullptr) {
      throw const PdfOperationException('Gagal membuat goresan pena di PDF.');
    }

    if (polyline.length == 1) {
      pdfium.FPDFPath_LineTo(pathObj, p0x + 0.1, p0y);
    } else {
      for (var i = 1; i < polyline.length; i++) {
        pdfium.FPDFPath_LineTo(
          pathObj,
          polyline[i].x * pageW,
          (1.0 - polyline[i].y) * pageH,
        );
      }
    }

    pdfium.FPDFPageObj_SetStrokeColor(pathObj, r, g, b, a);
    pdfium.FPDFPageObj_SetStrokeWidth(pathObj, overlay.strokeWidthPt);
    pdfium.FPDFPageObj_SetLineCap(pathObj, pdfium_bindings.FPDF_LINECAP_ROUND);
    pdfium.FPDFPageObj_SetLineJoin(
      pathObj,
      pdfium_bindings.FPDF_LINEJOIN_ROUND,
    );
    pdfium.FPDFPath_SetDrawMode(
      pathObj,
      pdfium_bindings.FPDF_FILLMODE_NONE,
      1,
    );
    pdfium.FPDFPageObj_Transform(
      pathObj,
      basis.ux,
      basis.uy,
      basis.vx,
      basis.vy,
      basis.ox,
      basis.oy,
    );
    pdfium.FPDFPage_InsertObject(page, pathObj);
  }
}

void _insertTextOverlay({
  required pdfium_bindings.PDFium pdfium,
  required pdfium_bindings.FPDF_DOCUMENT fpdfDoc,
  required pdfium_bindings.FPDF_PAGE page,
  required double pageW,
  required double pageH,
  required _AffineBasis basis,
  required pdfium_bindings.FPDF_FONT Function({required bool bold}) getFont,
  required PdfTextOverlay overlay,
  required Arena arena,
}) {
  if (overlay.text.trim().isEmpty) return;

  final font = getFont(bold: overlay.isBold);
  final lines = overlay.text.replaceAll('\r\n', '\n').split('\n');
  final startX = overlay.x * pageW;
  final firstBaselineY =
      (1.0 - overlay.y) * pageH - overlay.fontSizePt * 0.88;
  final lineHeight = overlay.fontSizePt * 1.25;

  final textObjects = <pdfium_bindings.FPDF_PAGEOBJECT>[];
  var hasBounds = false;
  var minL = double.infinity;
  var minB = double.infinity;
  var maxR = double.negativeInfinity;
  var maxT = double.negativeInfinity;

  final lPtr = arena<ffi.Float>();
  final bPtr = arena<ffi.Float>();
  final rPtr = arena<ffi.Float>();
  final tPtr = arena<ffi.Float>();

  final r = argbRed(overlay.colorArgb);
  final g = argbGreen(overlay.colorArgb);
  final b = argbBlue(overlay.colorArgb);
  final a = argbAlpha(overlay.colorArgb);

  try {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;

      final textObj = pdfium.FPDFPageObj_CreateTextObj(
        fpdfDoc,
        font,
        overlay.fontSizePt,
      );
      if (textObj == ffi.nullptr) {
        throw const PdfOperationException('Gagal membuat objek teks di PDF.');
      }

      final wideText =
          line.toNativeUtf16(allocator: arena).cast<pdfium_bindings.FPDF_WCHAR>();
      if (pdfium.FPDFText_SetText(textObj, wideText) == 0) {
        pdfium.FPDFPageObj_Destroy(textObj);
        throw const PdfOperationException(
          'Gagal mengatur isi teks untuk objek PDF.',
        );
      }

      pdfium.FPDFPageObj_SetFillColor(textObj, r, g, b, a);
      final baselineY = firstBaselineY - i * lineHeight;
      pdfium.FPDFPageObj_Transform(textObj, 1, 0, 0, 1, startX, baselineY);

      if (pdfium.FPDFPageObj_GetBounds(textObj, lPtr, bPtr, rPtr, tPtr) != 0) {
        hasBounds = true;
        minL = math.min(minL, lPtr.value);
        minB = math.min(minB, bPtr.value);
        maxR = math.max(maxR, rPtr.value);
        maxT = math.max(maxT, tPtr.value);
      }

      textObjects.add(textObj);
    }

    if (textObjects.isEmpty) return;

    if (overlay.backgroundColorArgb != null && hasBounds) {
      final bgColor = overlay.backgroundColorArgb!;
      final bgObj = pdfium.FPDFPageObj_CreateNewRect(
        minL - 4,
        minB - 2,
        math.max(1.0, (maxR - minL) + 8),
        math.max(1.0, (maxT - minB) + 4),
      );
      if (bgObj != ffi.nullptr) {
        pdfium.FPDFPageObj_SetFillColor(
          bgObj,
          argbRed(bgColor),
          argbGreen(bgColor),
          argbBlue(bgColor),
          argbAlpha(bgColor),
        );
        pdfium.FPDFPath_SetDrawMode(
          bgObj,
          pdfium_bindings.FPDF_FILLMODE_WINDING,
          0,
        );
        pdfium.FPDFPageObj_Transform(
          bgObj,
          basis.ux,
          basis.uy,
          basis.vx,
          basis.vy,
          basis.ox,
          basis.oy,
        );
        pdfium.FPDFPage_InsertObject(page, bgObj);
      }
    }

    while (textObjects.isNotEmpty) {
      final textObj = textObjects.removeAt(0);
      pdfium.FPDFPageObj_Transform(
        textObj,
        basis.ux,
        basis.uy,
        basis.vx,
        basis.vy,
        basis.ox,
        basis.oy,
      );
      pdfium.FPDFPage_InsertObject(page, textObj);
    }
  } finally {
    for (final orphan in textObjects) {
      pdfium.FPDFPageObj_Destroy(orphan);
    }
  }
}

void _insertImageOverlay({
  required pdfium_bindings.PDFium pdfium,
  required pdfium_bindings.FPDF_DOCUMENT fpdfDoc,
  required pdfium_bindings.FPDF_PAGE page,
  required ffi.Pointer<pdfium_bindings.FPDF_PAGE> pageArrayPtr,
  required double pageW,
  required double pageH,
  required _AffineBasis basis,
  required PdfImageOverlay overlay,
  required ({int width, int height, Uint8List bgraBytes}) decoded,
}) {
  final vx0 = overlay.rect.left * pageW;
  final vy0 = (1.0 - overlay.rect.bottom) * pageH;
  final vw = overlay.rect.width * pageW;
  final vh = overlay.rect.height * pageH;
  if (vw <= 0.1 || vh <= 0.1 || decoded.width <= 0 || decoded.height <= 0) {
    return;
  }

  final buf = calloc<ffi.Uint8>(decoded.bgraBytes.length);
  pdfium_bindings.FPDF_BITMAP bitmap = ffi.nullptr;
  pdfium_bindings.FPDF_PAGEOBJECT imgObj = ffi.nullptr;
  var inserted = false;

  try {
    buf.asTypedList(decoded.bgraBytes.length).setAll(0, decoded.bgraBytes);
    bitmap = pdfium.FPDFBitmap_CreateEx(
      decoded.width,
      decoded.height,
      pdfium_bindings.FPDFBitmap_BGRA,
      buf.cast(),
      decoded.width * 4,
    );
    if (bitmap == ffi.nullptr) {
      throw const PdfOperationException(
        'Gagal membuat bitmap gambar untuk PDF.',
      );
    }

    imgObj = pdfium.FPDFPageObj_NewImageObj(fpdfDoc);
    if (imgObj == ffi.nullptr) {
      throw const PdfOperationException(
        'Gagal membuat objek gambar di PDF.',
      );
    }

    if (pdfium.FPDFImageObj_SetBitmap(pageArrayPtr, 1, imgObj, bitmap) == 0) {
      throw const PdfOperationException(
        'Gagal menyematkan bitmap gambar ke objek PDF.',
      );
    }

    pdfium.FPDFImageObj_SetMatrix(
      imgObj,
      basis.ux * vw,
      basis.uy * vw,
      basis.vx * vh,
      basis.vy * vh,
      basis.ox + basis.ux * vx0 + basis.vx * vy0,
      basis.oy + basis.uy * vx0 + basis.vy * vy0,
    );
    pdfium.FPDFPage_InsertObject(page, imgObj);
    inserted = true;
  } finally {
    if (!inserted && imgObj != ffi.nullptr) {
      pdfium.FPDFPageObj_Destroy(imgObj);
    }
    if (bitmap != ffi.nullptr) {
      pdfium.FPDFBitmap_Destroy(bitmap);
    }
    calloc.free(buf);
  }
}
