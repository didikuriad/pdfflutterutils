import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../domain/utils/file_format_utils.dart';

/// Abstraction over native desktop file/directory dialogs and file manager actions.
abstract class FileDialogService {
  /// Prompts the user to pick a single PDF file, returning its path or `null`.
  Future<String?> pickPdfFile();

  /// Prompts the user to pick one or more PDF files.
  Future<List<String>> pickPdfFiles();

  /// Prompts the user to pick an image file for inserting into a PDF.
  Future<String?> pickImageFile();

  /// Prompts the user to choose a destination PDF file path.
  Future<String?> pickSavePdfPath({required String suggestedName});

  /// Prompts the user to choose a destination DOCX file path.
  Future<String?> pickSaveDocxPath({required String suggestedName});

  /// Prompts the user to pick an output directory for multi-file exports.
  Future<String?> pickOutputDirectory({String? confirmButtonText});

  /// Reveals [path] in the operating system's file explorer.
  Future<void> revealInFileManager(String path);
}

/// Native desktop implementation backed by `file_selector`.
class FileSelectorDialogService implements FileDialogService {
  static const XTypeGroup _pdfTypeGroup = XTypeGroup(
    label: 'Dokumen PDF',
    extensions: <String>['pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );

  static const XTypeGroup _docxTypeGroup = XTypeGroup(
    label: 'Dokumen Word (DOCX)',
    extensions: <String>['docx'],
    uniformTypeIdentifiers: <String>[
      'org.openxmlformats.wordprocessingml.document',
    ],
  );

  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Gambar',
    extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'bmp'],
  );

  @override
  Future<String?> pickPdfFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypeGroup],
      confirmButtonText: 'Pilih PDF',
    );
    return file?.path;
  }

  @override
  Future<List<String>> pickPdfFiles() async {
    final files = await openFiles(
      acceptedTypeGroups: const <XTypeGroup>[_pdfTypeGroup],
      confirmButtonText: 'Tambah PDF',
    );
    return files
        .map((file) => file.path)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<String?> pickImageFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_imageTypeGroup],
      confirmButtonText: 'Pilih Gambar',
    );
    return file?.path;
  }

  @override
  Future<String?> pickSavePdfPath({required String suggestedName}) =>
      _pickSavePath(
        suggestedName: suggestedName,
        typeGroup: _pdfTypeGroup,
        confirmButtonText: 'Simpan PDF',
        ensureExtension: ensurePdfExtension,
      );

  @override
  Future<String?> pickSaveDocxPath({required String suggestedName}) =>
      _pickSavePath(
        suggestedName: suggestedName,
        typeGroup: _docxTypeGroup,
        confirmButtonText: 'Simpan DOCX',
        ensureExtension: ensureDocxExtension,
      );

  Future<String?> _pickSavePath({
    required String suggestedName,
    required XTypeGroup typeGroup,
    required String confirmButtonText,
    required String Function(String) ensureExtension,
  }) async {
    final location = await getSaveLocation(
      suggestedName: ensureExtension(suggestedName),
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
      confirmButtonText: confirmButtonText,
    );
    if (location == null || location.path.isEmpty) {
      return null;
    }
    return ensureExtension(location.path);
  }

  @override
  Future<String?> pickOutputDirectory({String? confirmButtonText}) async {
    final dirPath = await getDirectoryPath(
      confirmButtonText: confirmButtonText ?? 'Pilih Folder Tujuan',
      canCreateDirectories: true,
    );
    if (dirPath == null || dirPath.isEmpty) {
      return null;
    }
    return p.normalize(dirPath);
  }

  @override
  Future<void> revealInFileManager(String path) async {
    final normalized = p.normalize(path);
    final isDir = FileSystemEntity.isDirectorySync(normalized);

    if (Platform.isWindows) {
      if (isDir) {
        await Process.start('explorer.exe', <String>[normalized]);
      } else {
        await Process.start('explorer.exe', <String>['/select,$normalized']);
      }
    } else if (Platform.isMacOS) {
      await Process.start(
        'open',
        isDir ? <String>[normalized] : <String>['-R', normalized],
      );
    } else if (Platform.isLinux) {
      final targetDir = isDir ? normalized : p.dirname(normalized);
      await Process.start('xdg-open', <String>[targetDir]);
    }
  }
}
