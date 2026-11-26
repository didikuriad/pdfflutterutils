import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfutils/app.dart';
import 'package:pdfutils/domain/models/app_window_mode.dart';
import 'package:pdfutils/domain/models/pdf_file_info.dart';
import 'package:pdfutils/ui/core/controllers/desktop_window_controller.dart';

import '../test_helpers/fakes.dart';

Widget _fakeThumbnail(BuildContext context, String filePath, int pageNumber) {
  return Center(
    key: ValueKey<String>('thumb_${filePath}_$pageNumber'),
    child: Text('P$pageNumber'),
  );
}

void main() {
  testWidgets(
    'switches tabs, toggles theme, and preserves state across Merge, Rotate, Split, PDF ke DOCX, and Edit PDF',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fake = createFakeRepository();
      fake.engine.filesByPath[r'C:\docs\satu.pdf'] = const PdfFileInfo(
        path: r'C:\docs\satu.pdf',
        fileName: 'satu.pdf',
        pageCount: 3,
        fileSizeBytes: 2048,
      );
      fake.engine.filesByPath[r'C:\docs\dua.pdf'] = const PdfFileInfo(
        path: r'C:\docs\dua.pdf',
        fileName: 'dua.pdf',
        pageCount: 2,
        fileSizeBytes: 1024,
      );

      await tester.pumpWidget(
        PdfUtilsApp(
          repository: fake.repository,
          thumbnailBuilder: _fakeThumbnail,
        ),
      );

      // Initial Merge empty state
      expect(find.text('Gabung PDF'), findsWidgets);
      expect(find.text('Pilih File PDF'), findsOneWidget);

      // Desktop sidebar shows Mode Kecil (HP) and Auto Hide buttons
      expect(find.text('Mode Kecil (HP)'), findsOneWidget);
      expect(find.text('Auto Hide'), findsOneWidget);

      // Toggle dark theme and back
      expect(find.text('Mode Gelap'), findsOneWidget);
      await tester.tap(find.text('Mode Gelap'));
      await tester.pumpAndSettle();
      expect(find.text('Mode Terang'), findsOneWidget);

      // Add 2 PDFs on Merge tab
      fake.dialogs.nextPickedFiles = <String>[
        r'C:\docs\satu.pdf',
        r'C:\docs\dua.pdf',
      ];
      await tester.tap(find.text('Pilih File PDF'));
      await tester.pumpAndSettle();

      expect(find.text('satu.pdf'), findsOneWidget);
      expect(find.text('dua.pdf'), findsOneWidget);
      expect(find.text('2 file • Total 5 halaman'), findsOneWidget);

      // Execute Merge
      fake.dialogs.nextSavePath = r'C:\docs\gabungan.pdf';
      await tester.tap(find.text('Gabungkan & Simpan PDF'));
      await tester.pumpAndSettle();
      expect(fake.engine.lastMergeOutputPath, r'C:\docs\gabungan.pdf');
      expect(find.text('Buka Folder'), findsOneWidget);

      // Switch to Rotate tab
      await tester.tap(find.text('Putar PDF').first);
      await tester.pumpAndSettle();
      expect(find.text('Buka File PDF'), findsOneWidget);

      fake.dialogs.nextPickedFile = r'C:\docs\satu.pdf';
      await tester.tap(find.text('Buka File PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Hal 1'), findsOneWidget);
      expect(find.text('Hal 3'), findsOneWidget);

      await tester.tap(find.text('Ganjil'));
      await tester.pump();
      await tester.tap(find.text('+90° Kanan'));
      await tester.pumpAndSettle();
      expect(find.text('+90°'), findsNWidgets(2));

      // Switch to Split tab
      await tester.tap(find.text('Pisah PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\satu.pdf';
      await tester.tap(find.text('Buka File PDF'));
      await tester.pumpAndSettle();

      // Switch to Per Hal mode and verify preview
      await tester.tap(find.text('Per Hal'));
      await tester.pumpAndSettle();
      expect(find.text('satu_hal_001.pdf'), findsOneWidget);
      expect(find.text('3 file'), findsOneWidget);

      // Switch to Kompres PDF tab, pick PDF, select options and compress
      await tester.tap(find.text('Kompres PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\satu.pdf';
      await tester.tap(find.text('Buka File PDF').last);
      await tester.pumpAndSettle();
      expect(find.text('Pengaturan Kompresi'), findsOneWidget);
      expect(find.text('Sedang (Rekomendasi)'), findsWidgets);

      await tester.tap(find.text('Tinggi (Ukuran Minimum)').last);
      await tester.pumpAndSettle();

      fake.dialogs.nextSavePath = r'C:\docs\satu_compressed.pdf';
      await tester.tap(find.text('Kompres & Simpan PDF'));
      await tester.pumpAndSettle();
      expect(fake.engine.lastCompressInputPath, r'C:\docs\satu.pdf');
      expect(fake.engine.lastCompressOutputPath, r'C:\docs\satu_compressed.pdf');
      expect(find.text('Buka Folder'), findsWidgets);

      // Switch to PDF ke DOCX tab, add PDF, and convert
      await tester.tap(find.text('PDF ke DOCX').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFiles = <String>[r'C:\docs\satu.pdf'];
      await tester.tap(find.text('Pilih File PDF').last);
      await tester.pumpAndSettle();
      expect(find.text('satu.docx'), findsOneWidget);

      fake.dialogs.nextSaveDocxPath = r'C:\docs\satu.docx';
      await tester.tap(find.text('Konversi & Simpan DOCX'));
      await tester.pumpAndSettle();
      expect(fake.docx.convertedJobs.length, 1);
      expect(fake.docx.convertedJobs.first.outputPath, r'C:\docs\satu.docx');
      expect(find.text('Buka Folder'), findsWidgets);

      // Switch to Edit PDF tab, open a PDF, verify signature pad & save flow
      await tester.tap(find.text('Edit PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\satu.pdf';
      await tester.tap(find.text('Buka File PDF').last);
      await tester.pumpAndSettle();
      expect(find.text('Whiteout'), findsOneWidget);
      expect(find.text('Tanda Tangan'), findsOneWidget);

      await tester.ensureVisible(find.text('Tanda Tangan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanda Tangan'));
      await tester.pumpAndSettle();
      expect(find.text('Buat Tanda Tangan'), findsOneWidget);
      await tester.tap(find.text('Batal').last);
      await tester.pumpAndSettle();

      // Switch back to Merge tab -> state is preserved via IndexedStack
      await tester.tap(find.text('Gabung PDF').first);
      await tester.pumpAndSettle();
      expect(find.text('satu.pdf'), findsWidgets);
      expect(find.text('dua.pdf'), findsOneWidget);
    },
  );

  testWidgets(
    'renders cleanly in Mode Kecil (HP) 412x780 across Merge, Rotate, Split, PDF ke DOCX, and Edit PDF without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(
        AppWindowMode.compactWidth,
        AppWindowMode.compactHeight,
      );
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fake = createFakeRepository();
      fake.engine.filesByPath[r'C:\docs\laporan_panjang_sekali.pdf'] =
          const PdfFileInfo(
        path: r'C:\docs\laporan_panjang_sekali.pdf',
        fileName: 'laporan_panjang_sekali.pdf',
        pageCount: 4,
        fileSizeBytes: 3072,
      );
      fake.engine.filesByPath[r'C:\docs\lampiran.pdf'] = const PdfFileInfo(
        path: r'C:\docs\lampiran.pdf',
        fileName: 'lampiran.pdf',
        pageCount: 2,
        fileSizeBytes: 1024,
      );

      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideOnStartup: false,
      );
      await controller.initialize();
      await controller.setWindowMode(AppWindowMode.compact);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        PdfUtilsApp(
          repository: fake.repository,
          windowController: controller,
          thumbnailBuilder: _fakeThumbnail,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Auto Hide'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Populated Merge in phone size
      fake.dialogs.nextPickedFiles = <String>[
        r'C:\docs\laporan_panjang_sekali.pdf',
        r'C:\docs\lampiran.pdf',
      ];
      await tester.tap(find.text('Pilih File PDF'));
      await tester.pumpAndSettle();
      expect(find.text('laporan_panjang_sekali.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Populated Rotate in phone size
      await tester.tap(find.text('Putar PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\laporan_panjang_sekali.pdf';
      await tester.tap(find.text('Buka File PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Hal 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Populated Split in phone size
      await tester.tap(find.text('Pisah PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\laporan_panjang_sekali.pdf';
      await tester.tap(find.text('Buka File PDF'));
      await tester.pumpAndSettle();
      // Switch to Per Hal mode in phone size
      await tester.tap(find.text('Per Hal'));
      await tester.pumpAndSettle();
      expect(find.text('laporan_panjang_sekali_hal_001.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Populated Kompres PDF in phone size
      await tester.tap(find.text('Kompres PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\laporan_panjang_sekali.pdf';
      await tester.tap(find.text('Buka File PDF').last);
      await tester.pumpAndSettle();
      expect(find.text('Pengaturan Kompresi'), findsOneWidget);
      expect(tester.takeException(), isNull);
      fake.dialogs.nextSavePath = r'C:\docs\laporan_compressed.pdf';
      await tester.tap(find.text('Kompres & Simpan PDF'));
      await tester.pumpAndSettle();
      expect(fake.engine.lastCompressInputPath, r'C:\docs\laporan_panjang_sekali.pdf');
      expect(find.text('Buka Folder'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Populated PDF ke DOCX in phone size
      await tester.tap(find.text('PDF ke DOCX').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFiles = <String>[
        r'C:\docs\laporan_panjang_sekali.pdf',
      ];
      await tester.tap(find.text('Pilih File PDF').last);
      await tester.pumpAndSettle();
      expect(find.text('laporan_panjang_sekali.docx'), findsOneWidget);
      fake.dialogs.nextSaveDocxPath = r'C:\docs\laporan_panjang_sekali.docx';
      await tester.tap(find.text('Konversi & Simpan DOCX'));
      await tester.pumpAndSettle();
      expect(fake.docx.convertedJobs.length, 1);
      expect(find.text('Buka Folder'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Populated Edit PDF in phone size
      await tester.tap(find.text('Edit PDF').first);
      await tester.pumpAndSettle();
      fake.dialogs.nextPickedFile = r'C:\docs\laporan_panjang_sekali.pdf';
      await tester.tap(find.text('Buka File PDF').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('edit_pdf_page_canvas')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // Switch tools and tap canvas in Teks mode -> add text -> Simpan PDF
      await tester.tap(find.text('Whiteout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teks'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('edit_pdf_page_canvas')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tambah Teks'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Revisi 1');
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();
      expect(find.text('Revisi 1'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fake.dialogs.nextSavePath = r'C:\docs\laporan_edited.pdf';
      await tester.tap(find.text('Simpan PDF').last);
      await tester.pumpAndSettle();
      expect(fake.engine.lastEditOverlays?.length, 1);
      expect(find.text('Buka Folder'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Toggle back to Mode Desktop via AppBar icon
      await tester.tap(find.byTooltip('Mode Desktop'));
      await tester.pumpAndSettle();
      expect(controller.windowMode, AppWindowMode.desktop);
      expect(platform.appliedModes.last, AppWindowMode.desktop);
    },
  );

  testWidgets(
    'supports startup auto-hide banner, tray restore without auto-hide, and in-app Auto Hide button',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fake = createFakeRepository();
      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideDuration: const Duration(seconds: 5),
        autoHideOnStartup: true,
      );
      await controller.initialize();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        PdfUtilsApp(
          repository: fake.repository,
          windowController: controller,
          thumbnailBuilder: _fakeThumbnail,
        ),
      );
      await tester.pump();

      // Startup countdown banner & sidebar button reflect 5s countdown
      expect(
        find.text('Otomatis sembunyi ke taskbar tray dalam 5 detik'),
        findsOneWidget,
      );
      expect(find.text('Batal (5d)'), findsOneWidget);

      // Let 5 seconds elapse -> hides window to tray
      await tester.pump(const Duration(seconds: 5));
      expect(platform.hideCount, 1);
      expect(controller.isWindowHidden, isTrue);
      expect(find.text('Auto Hide'), findsOneWidget);

      // Clicking tray icon restores app with NO auto-hide
      platform.simulateTrayRestore();
      await tester.pump();
      expect(platform.showCount, 1);
      expect(controller.isWindowHidden, isFalse);
      expect(controller.isAutoHideCountingDown, isFalse);

      await tester.pump(const Duration(seconds: 10));
      expect(platform.hideCount, 1);

      // Clicking Auto Hide button in app starts countdown, and Batal cancels it
      await tester.tap(find.text('Auto Hide'));
      await tester.pump();
      expect(find.text('Batal (5d)'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pump();
      expect(controller.isAutoHideCountingDown, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(platform.hideCount, 1);
    },
  );

  testWidgets('renders cleanly on compact rail and narrow window sizes without overflow', (
    tester,
  ) async {
    final fake = createFakeRepository();
    await tester.pumpWidget(
      PdfUtilsApp(
        repository: fake.repository,
        thumbnailBuilder: _fakeThumbnail,
      ),
    );

    // Compact rail breakpoint (640 <= width < 960)
    tester.view.physicalSize = const Size(760, 700);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Narrow breakpoint (< 640)
    tester.view.physicalSize = const Size(500, 700);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.reset();
  });
}
