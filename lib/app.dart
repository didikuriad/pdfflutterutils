import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdfutils/data/repositories/pdf_repository.dart';
import 'package:pdfutils/data/services/desktop_platform_service.dart';
import 'package:pdfutils/ui/core/controllers/desktop_window_controller.dart';
import 'package:pdfutils/ui/core/theme/app_theme.dart';
import 'package:pdfutils/ui/core/widgets/app_shell.dart';
import 'package:pdfutils/ui/core/widgets/pdf_page_thumbnail.dart';
import 'package:pdfutils/ui/features/compress/view_models/compress_pdf_view_model.dart';
import 'package:pdfutils/ui/features/compress/views/compress_pdf_view.dart';
import 'package:pdfutils/ui/features/convert_docx/view_models/convert_docx_view_model.dart';
import 'package:pdfutils/ui/features/convert_docx/views/convert_docx_view.dart';
import 'package:pdfutils/ui/features/edit/view_models/edit_pdf_view_model.dart';
import 'package:pdfutils/ui/features/edit/views/edit_pdf_view.dart';
import 'package:pdfutils/ui/features/merge/view_models/merge_view_model.dart';
import 'package:pdfutils/ui/features/merge/views/merge_view.dart';
import 'package:pdfutils/ui/features/rotate/view_models/rotate_view_model.dart';
import 'package:pdfutils/ui/features/rotate/views/rotate_view.dart';
import 'package:pdfutils/ui/features/split/view_models/split_view_model.dart';
import 'package:pdfutils/ui/features/split/views/split_view.dart';

/// Root desktop application widget for PDF Utils.
class PdfUtilsApp extends StatefulWidget {
  /// Creates a [PdfUtilsApp].
  const PdfUtilsApp({
    super.key,
    required this.repository,
    this.windowController,
    this.thumbnailBuilder,
    this.initialThemeMode = ThemeMode.light,
  });

  /// Shared PDF repository injected into feature ViewModels.
  final PdfRepository repository;

  /// Optional controller for desktop window sizing, auto-hide, and system tray.
  final DesktopWindowController? windowController;

  /// Optional override for thumbnail rendering (used in widget tests).
  final PdfThumbnailBuilder? thumbnailBuilder;

  /// Initial theme mode for the application.
  final ThemeMode initialThemeMode;

  @override
  State<PdfUtilsApp> createState() => _PdfUtilsAppState();
}

class _PdfUtilsAppState extends State<PdfUtilsApp> {
  late final MergeViewModel _mergeViewModel;
  late final RotateViewModel _rotateViewModel;
  late final SplitViewModel _splitViewModel;
  late final CompressPdfViewModel _compressViewModel;
  late final ConvertDocxViewModel _convertDocxViewModel;
  late final EditPdfViewModel _editPdfViewModel;
  DesktopWindowController? _ownedWindowController;
  late ThemeMode _themeMode;

  DesktopWindowController get _effectiveWindowController =>
      widget.windowController ?? _ownedWindowController!;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
    _mergeViewModel = MergeViewModel(repository: widget.repository);
    _rotateViewModel = RotateViewModel(repository: widget.repository);
    _splitViewModel = SplitViewModel(repository: widget.repository);
    _compressViewModel = CompressPdfViewModel(repository: widget.repository);
    _convertDocxViewModel = ConvertDocxViewModel(repository: widget.repository);
    unawaited(_convertDocxViewModel.checkAvailability());
    _editPdfViewModel = EditPdfViewModel(repository: widget.repository);
    if (widget.windowController == null) {
      _ownedWindowController = DesktopWindowController(
        platformService: NoopDesktopPlatformService(),
        autoHideOnStartup: false,
      );
    }
  }

  @override
  void dispose() {
    _mergeViewModel.dispose();
    _rotateViewModel.dispose();
    _splitViewModel.dispose();
    _compressViewModel.dispose();
    _convertDocxViewModel.dispose();
    _editPdfViewModel.dispose();
    _ownedWindowController?.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget shell = AppShell(
      isDarkMode: _themeMode == ThemeMode.dark,
      onToggleTheme: _toggleTheme,
      windowController: _effectiveWindowController,
      mergeBuilder: (context, isActive) => MergeView(
        viewModel: _mergeViewModel,
        isActive: isActive,
      ),
      rotateBuilder: (context, isActive) => RotateView(
        viewModel: _rotateViewModel,
        isActive: isActive,
      ),
      splitBuilder: (context, isActive) => SplitView(
        viewModel: _splitViewModel,
        isActive: isActive,
      ),
      compressBuilder: (context, isActive) => CompressPdfView(
        viewModel: _compressViewModel,
        isActive: isActive,
      ),
      convertDocxBuilder: (context, isActive) => ConvertDocxView(
        viewModel: _convertDocxViewModel,
        isActive: isActive,
      ),
      editBuilder: (context, isActive) => EditPdfView(
        viewModel: _editPdfViewModel,
        isActive: isActive,
      ),
    );

    if (widget.thumbnailBuilder != null) {
      shell = PdfThumbnailOverride(
        builder: widget.thumbnailBuilder!,
        child: shell,
      );
    }

    return MaterialApp(
      title: 'PDF Utils',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: shell,
    );
  }
}
