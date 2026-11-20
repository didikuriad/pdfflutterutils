import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/utils/file_format_utils.dart';

void main() {
  group('isPdfPath and ensurePdfExtension', () {
    test('detects .pdf paths case-insensitively', () {
      expect(isPdfPath(r'C:\docs\laporan.pdf'), isTrue);
      expect(isPdfPath('/tmp/SCAN.PDF'), isTrue);
      expect(isPdfPath('notes.txt'), isFalse);
      expect(isPdfPath(''), isFalse);
    });

    test('appends .pdf only when missing', () {
      expect(ensurePdfExtension('output'), 'output.pdf');
      expect(ensurePdfExtension('output.pdf'), 'output.pdf');
      expect(ensurePdfExtension('OUTPUT.PDF'), 'OUTPUT.PDF');
    });
  });

  group('formatFileSize', () {
    test('formats bytes, KB, MB, and GB cleanly', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(1572864), '1.5 MB');
      expect(formatFileSize(1073741824), '1.00 GB');
    });
  });

  group('sanitizeFileNamePrefix and buildSplitFileName', () {
    test('strips invalid filename characters and falls back to split', () {
      expect(sanitizeFileNamePrefix('laporan:2026*final?'), 'laporan_2026_final');
      expect(sanitizeFileNamePrefix('***'), 'split');
      expect(sanitizeFileNamePrefix('   '), 'split');
    });

    test('builds descriptive split filenames for ranges and single pages', () {
      expect(
        buildSplitFileName('dokumen', 1, 3, <int>[1, 2, 3]),
        'dokumen_part_01_hal_1-3.pdf',
      );
      expect(
        buildSplitFileName('dokumen', 2, 12, <int>[2]),
        'dokumen_hal_002.pdf',
      );
      expect(
        buildSplitFileName('dokumen', 1, 1, <int>[2, 4]),
        'dokumen_part_01_hal_2-4.pdf',
      );
    });
  });

  group('ensureDocxExtension and buildDocxFileName', () {
    test('appends .docx only when missing', () {
      expect(ensureDocxExtension('hasil'), 'hasil.docx');
      expect(ensureDocxExtension('hasil.docx'), 'hasil.docx');
      expect(ensureDocxExtension('HASIL.DOCX'), 'HASIL.DOCX');
    });

    test('builds sanitized docx filename from pdf filename', () {
      expect(buildDocxFileName('laporan 2026.pdf'), 'laporan 2026.docx');
      expect(buildDocxFileName('a:b*c.pdf'), 'a_b_c.docx');
    });
  });
}
