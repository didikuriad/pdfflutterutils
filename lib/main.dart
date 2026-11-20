import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfutils/app.dart';
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/data/services/desktop_platform_service.dart';
import 'package:pdfutils/data/services/file_dialog_service.dart';
import 'package:pdfutils/data/services/pdf_engine_service.dart';
import 'package:pdfutils/data/services/pdf_to_docx_service.dart';
import 'package:pdfutils/ui/core/controllers/desktop_window_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final windowController = DesktopWindowController(
    platformService: NativeDesktopPlatformService(),
    autoHideDuration: const Duration(seconds: 5),
    autoHideOnStartup: true,
  );
  await windowController.initialize();

  final repository = PdfRepository(
    engineService: PdfrxPdfEngineService(),
    dialogService: FileSelectorDialogService(),
    pdfToDocxService: WordComPdfToDocxService(),
  );

  runApp(
    PdfUtilsApp(
      repository: repository,
      windowController: windowController,
    ),
  );
}
