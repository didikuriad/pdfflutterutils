import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_bindings;
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models/operation_result.dart';

pdfium_bindings.PDFium? _cachedPdfium;

pdfium_bindings.PDFium _getPdfium(String? modulePath) {
  return _cachedPdfium ??=
      pdfium_bindings.getPdfium(modulePath: modulePath);
}

/// Specification for one compressed PDF page to assemble.
class CompressedPageSpec {
  /// Creates a [CompressedPageSpec].
  const CompressedPageSpec({
    required this.widthPt,
    required this.heightPt,
    required this.jpegBytes,
  });

  /// Width in PDF points (1/72 inch).
  final double widthPt;

  /// Height in PDF points (1/72 inch).
  final double heightPt;

  /// Compressed JPEG image bytes representing the page content.
  final Uint8List jpegBytes;
}

typedef _CompressWorkerParam = ({
  List<CompressedPageSpec> pages,
  String? pdfiumModulePath,
});

/// Native PDF assembly worker running on a background worker isolate.
Uint8List _assembleCompressedPdfWorker(_CompressWorkerParam param) {
  final pdfium = _getPdfium(param.pdfiumModulePath);
  final doc = pdfium.FPDF_CreateNewDocument();
  if (doc == ffi.nullptr) {
    throw const PdfOperationException('Gagal membuat dokumen PDF baru.');
  }

  try {
    for (var i = 0; i < param.pages.length; i++) {
      final pageData = param.pages[i];
      final page = pdfium.FPDFPage_New(
        doc,
        i,
        pageData.widthPt,
        pageData.heightPt,
      );
      if (page == ffi.nullptr) {
        throw PdfOperationException(
          'Gagal membuat halaman ${i + 1} di dokumen PDF terkompresi.',
        );
      }

      final imgObj = pdfium.FPDFPageObj_NewImageObj(doc);
      if (imgObj == ffi.nullptr) {
        pdfium.FPDF_ClosePage(page);
        throw PdfOperationException(
          'Gagal membuat objek gambar untuk halaman ${i + 1}.',
        );
      }

      final jpegLength = pageData.jpegBytes.length;
      final buf = malloc<ffi.Uint8>(jpegLength);
      buf.asTypedList(jpegLength).setAll(0, pageData.jpegBytes);

      final fileAccess = malloc<pdfium_bindings.FPDF_FILEACCESS>();
      fileAccess.ref.m_FileLen = jpegLength;
      fileAccess.ref.m_Param = ffi.nullptr;

      final callable = ffi.NativeCallable<
        ffi.Int Function(
          ffi.Pointer<ffi.Void> param,
          ffi.UnsignedLong position,
          ffi.Pointer<ffi.UnsignedChar> pBuf,
          ffi.UnsignedLong size,
        )
      >.isolateLocal((
        ffi.Pointer<ffi.Void> param,
        int position,
        ffi.Pointer<ffi.UnsignedChar> pBuf,
        int size,
      ) {
        final toCopy = math.min(size, jpegLength - position);
        if (toCopy <= 0) return 0;
        final src = ffi.Pointer<ffi.Uint8>.fromAddress(buf.address + position);
        pBuf.cast<ffi.Uint8>().asTypedList(toCopy).setAll(
          0,
          src.asTypedList(toCopy),
        );
        return toCopy;
      }, exceptionalReturn: 0);

      fileAccess.ref.m_GetBlock = callable.nativeFunction;

      final pagePtrArray = calloc<pdfium_bindings.FPDF_PAGE>(1);
      pagePtrArray[0] = page;

      try {
        final loadResult = pdfium.FPDFImageObj_LoadJpegFileInline(
          pagePtrArray,
          1,
          imgObj,
          fileAccess,
        );
        if (loadResult == 0) {
          throw PdfOperationException(
            'Gagal memuat stream JPEG terkompresi ke halaman ${i + 1}.',
          );
        }

        pdfium.FPDFImageObj_SetMatrix(
          imgObj,
          pageData.widthPt,
          0.0,
          0.0,
          pageData.heightPt,
          0.0,
          0.0,
        );
        pdfium.FPDFPage_InsertObject(page, imgObj);
        pdfium.FPDFPage_GenerateContent(page);
      } finally {
        callable.close();
        calloc.free(pagePtrArray);
        malloc.free(fileAccess);
        malloc.free(buf);
        pdfium.FPDF_ClosePage(page);
      }
    }

    // Now save document as compact PDF copy (FPDF_NO_INCREMENTAL = 2).
    final byteBuffer = BytesBuilder();
    final writeCallable = ffi.NativeCallable<
      ffi.Int Function(
        ffi.Pointer<pdfium_bindings.FPDF_FILEWRITE> self,
        ffi.Pointer<ffi.Void> data,
        ffi.UnsignedLong size,
      )
    >.isolateLocal((
      ffi.Pointer<pdfium_bindings.FPDF_FILEWRITE> self,
      ffi.Pointer<ffi.Void> data,
      int size,
    ) {
      if (size <= 0) return 0;
      final bytes = data.cast<ffi.Uint8>().asTypedList(size);
      byteBuffer.add(bytes);
      return size;
    }, exceptionalReturn: 0);

    final fw = calloc<pdfium_bindings.FPDF_FILEWRITE>();
    fw.ref.version = 1;
    fw.ref.WriteBlock = writeCallable.nativeFunction;

    try {
      final saveResult = pdfium.FPDF_SaveAsCopy(doc, fw, 2);
      if (saveResult == 0) {
        throw const PdfOperationException(
          'Gagal mengodekan file PDF terkompresi.',
        );
      }
      return byteBuffer.toBytes();
    } finally {
      writeCallable.close();
      calloc.free(fw);
    }
  } finally {
    pdfium.FPDF_CloseDocument(doc);
  }
}

/// Assembles a list of [pages] (each with JPEG compressed payload) into a valid
/// standalone PDF byte buffer using PDFium on a background worker isolate.
Future<Uint8List> assembleCompressedPdf(List<CompressedPageSpec> pages) async {
  if (pages.isEmpty) {
    throw const PdfOperationException('Tidak ada halaman untuk dikompresi.');
  }

  return PdfrxEntryFunctions.instance.compute(
    _assembleCompressedPdfWorker,
    (
      pages: pages,
      pdfiumModulePath: Pdfrx.pdfiumModulePath,
    ),
  );
}
