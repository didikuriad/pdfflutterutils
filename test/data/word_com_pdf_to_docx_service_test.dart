import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfutils/data/services/pdf_to_docx_service.dart';
import 'package:pdfutils/domain/models/operation_result.dart';

import '../test_helpers/fakes.dart';

void main() {
  test('encodePowerShellUtf16LeBase64 encodes ASCII script as UTF-16LE base64', () {
    final encoded = encodePowerShellUtf16LeBase64('OK');
    // 'O' (0x4F 0x00), 'K' (0x4B 0x00) in UTF-16LE.
    expect(base64Decode(encoded), equals(<int>[0x4F, 0x00, 0x4B, 0x00]));
  });

  test('WordComPdfToDocxService throws PdfOperationException when input file is missing', () async {
    if (!Platform.isWindows) return;
    final service = WordComPdfToDocxService();
    await expectLater(
      () => service.convertPdfToDocx(
        inputPath: r'C:\nonexistent_pdfutils_dir\missing.pdf',
        outputPath: r'C:\nonexistent_pdfutils_dir\missing.docx',
      ),
      throwsA(isA<PdfOperationException>()),
    );
  });

  test(
    'WordComPdfToDocxService converts real text PDF into valid DOCX via Microsoft Word COM',
    () async {
      if (!Platform.isWindows) return;

      final service = WordComPdfToDocxService(
        timeout: const Duration(seconds: 90),
      );
    if (!await service.isAvailable()) {
      return;
    }

    final rootTemp = await Directory.systemTemp.createTemp('pdfutils_word_');
    addTearDown(() async {
      if (await rootTemp.exists()) {
        await rootTemp.delete(recursive: true);
      }
    });

    // Include spaces in folder and filenames to verify environment variable passing.
    final nestedDir = Directory(p.join(rootTemp.path, 'pdf utils test'));
    await nestedDir.create(recursive: true);

    final inputPdfPath = p.join(nestedDir.path, 'sample report.pdf');
    final outputDocxPath = p.join(nestedDir.path, 'sample report.docx');
    await File(inputPdfPath)
        .writeAsBytes(createMinimalTextPdfBytes('Hello PDF Utils'));

    final createdPath = await service.convertPdfToDocx(
      inputPath: inputPdfPath,
      outputPath: outputDocxPath,
    );

    expect(createdPath, p.absolute(p.normalize(outputDocxPath)));
    final outFile = File(createdPath);
    expect(await outFile.exists(), isTrue);

    final bytes = await outFile.readAsBytes();
    expect(bytes.length, greaterThan(100));
    // Verify DOCX ZIP local file header magic bytes ('PK\x03\x04').
    expect(bytes.sublist(0, 4), equals(<int>[0x50, 0x4B, 0x03, 0x04]));

      // Verify DOCX OOXML content entry name exists inside the ZIP archive bytes.
      final asciiView = latin1.decode(bytes);
      expect(asciiView, contains('word/document.xml'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
