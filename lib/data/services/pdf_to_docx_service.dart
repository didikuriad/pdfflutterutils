import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/operation_result.dart';
import '../../domain/utils/file_format_utils.dart';

/// Encodes [script] as UTF-16LE Base64 for PowerShell `-EncodedCommand`.
String encodePowerShellUtf16LeBase64(String script) {
  final units = script.codeUnits;
  final bytes = List<int>.filled(units.length * 2, 0);
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    bytes[i * 2] = unit & 0xFF;
    bytes[i * 2 + 1] = (unit >> 8) & 0xFF;
  }
  return base64Encode(bytes);
}

/// Service interface for converting PDF documents to `.docx` format.
abstract class PdfToDocxService {
  /// Returns `true` when the underlying converter backend is available.
  Future<bool> isAvailable();

  /// Converts the PDF at [inputPath] into a `.docx` file at [outputPath],
  /// returning the normalized output file path.
  Future<String> convertPdfToDocx({
    required String inputPath,
    required String outputPath,
  });
}

/// Converts PDF files to `.docx` using Microsoft Word COM automation via
/// PowerShell on Windows.
class WordComPdfToDocxService implements PdfToDocxService {
  /// Creates a [WordComPdfToDocxService].
  WordComPdfToDocxService({this.timeout = const Duration(minutes: 5)});

  /// Maximum duration allowed per file conversion before terminating PowerShell.
  final Duration timeout;

  static const String _wordConvertScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$inputPath = $env:PDFUTILS_INPUT
$outputPath = $env:PDFUTILS_OUTPUT

$registryBackups = New-Object System.Collections.Generic.List[object]
$word = $null
$doc = $null
try {
  foreach ($ver in @('16.0', '15.0')) {
    if (Test-Path -Path "HKCU:\Software\Microsoft\Office\$ver") {
      $optionsPath = "HKCU:\Software\Microsoft\Office\$ver\Word\Options"
      if (-not (Test-Path -Path $optionsPath)) {
        New-Item -Path $optionsPath -Force | Out-Null
      }
      $existing = Get-ItemProperty -Path $optionsPath -Name 'DisableConvertPDFWarning' -ErrorAction SilentlyContinue
      $hadValue = ($null -ne $existing) -and ($null -ne $existing.PSObject.Properties['DisableConvertPDFWarning'])
      $prevValue = if ($hadValue) { $existing.DisableConvertPDFWarning } else { $null }
      if ((-not $hadValue) -or ([int]$prevValue -ne 1)) {
        $registryBackups.Add([pscustomobject]@{
          Path = $optionsPath
          HadValue = $hadValue
          PrevValue = $prevValue
        })
        New-ItemProperty -Path $optionsPath -Name 'DisableConvertPDFWarning' -PropertyType DWord -Value 1 -Force | Out-Null
      }
    }
  }

  $beforePids = @(Get-Process -Name 'WINWORD' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  $word = New-Object -ComObject Word.Application
  $afterPids = @(Get-Process -Name 'WINWORD' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  $newPids = @($afterPids | Where-Object { $beforePids -notcontains $_ })
  if ($newPids.Count -eq 1) {
    Write-Output "PDFUTILS_WORD_PID=$($newPids[0])"
  }

  $word.Visible = $false
  $word.DisplayAlerts = 0
  try { $word.Options.ConfirmConversions = $false } catch {}
  try { $word.AutomationSecurity = 3 } catch {}

  $fileName = [object]$inputPath
  $confirmConversions = [object]$false
  $readOnly = [object]$true
  $addToRecentFiles = [object]$false
  $passwordDocument = [object]''
  $passwordTemplate = [object]''
  $revert = [object]$false
  $writePasswordDocument = [object]''
  $writePasswordTemplate = [object]''
  $doc = $word.Documents.Open(
    [ref]$fileName,
    [ref]$confirmConversions,
    [ref]$readOnly,
    [ref]$addToRecentFiles,
    [ref]$passwordDocument,
    [ref]$passwordTemplate,
    [ref]$revert,
    [ref]$writePasswordDocument,
    [ref]$writePasswordTemplate
  )

  $outFileName = [object]$outputPath
  $wdFormatXMLDocument = [object]16
  $doc.SaveAs2([ref]$outFileName, [ref]$wdFormatXMLDocument)
  Write-Output 'OK'
} finally {
  $wdDoNotSaveChanges = [object]0
  if ($null -ne $doc) {
    try { $doc.Close([ref]$wdDoNotSaveChanges) } catch {}
    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) } catch {}
  }
  if ($null -ne $word) {
    try { $word.Quit([ref]$wdDoNotSaveChanges) } catch {}
    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) } catch {}
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
  foreach ($backup in $registryBackups) {
    try {
      if ($backup.HadValue) {
        Set-ItemProperty -Path $backup.Path -Name 'DisableConvertPDFWarning' -Value $backup.PrevValue -Force -ErrorAction SilentlyContinue
      } else {
        Remove-ItemProperty -Path $backup.Path -Name 'DisableConvertPDFWarning' -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}
''';

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isWindows) return false;

    for (final key in const <String>[
      r'HKLM\SOFTWARE\Classes\Word.Application',
      r'HKCU\SOFTWARE\Classes\Word.Application',
    ]) {
      try {
        final result = await Process.run('reg', <String>['query', key]);
        if (result.exitCode == 0) {
          return true;
        }
      } on ProcessException {
        return false;
      }
    }
    return false;
  }

  @override
  Future<String> convertPdfToDocx({
    required String inputPath,
    required String outputPath,
  }) async {
    if (!Platform.isWindows) {
      throw const PdfOperationException(
        'Konversi melalui Microsoft Word hanya tersedia di Windows.',
      );
    }

    final absInput = p.absolute(p.normalize(inputPath));
    final absOutput = ensureDocxExtension(p.absolute(p.normalize(outputPath)));
    final inputFile = File(absInput);
    if (!await inputFile.exists()) {
      throw PdfOperationException(
        'File sumber tidak ditemukan: ${p.basename(absInput)}',
      );
    }

    try {
      await File(absOutput).parent.create(recursive: true);
    } catch (error) {
      throw PdfOperationException(
        'Gagal menyiapkan folder tujuan untuk "${p.basename(absOutput)}".',
        error,
      );
    }

    final encodedScript = encodePowerShellUtf16LeBase64(_wordConvertScript);
    late final Process process;
    try {
      process = await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          encodedScript,
        ],
        environment: <String, String>{
          'PDFUTILS_INPUT': absInput,
          'PDFUTILS_OUTPUT': absOutput,
        },
      );
    } catch (error) {
      throw PdfOperationException(
        'Gagal menjalankan PowerShell untuk otomasi Microsoft Word.',
        error,
      );
    }

    int? spawnedWordPid;
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
      if (line.startsWith('PDFUTILS_WORD_PID=')) {
        spawnedWordPid =
            int.tryParse(line.substring('PDFUTILS_WORD_PID='.length).trim());
      } else {
        if (stdoutBuffer.isNotEmpty) stdoutBuffer.writeln();
        stdoutBuffer.write(line);
      }
    });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stderrBuffer.write);

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      unawaited(stdoutDone.catchError((_) {}));
      unawaited(stderrDone.catchError((_) {}));
      if (spawnedWordPid != null) {
        try {
          await Process.run(
            'taskkill',
            <String>['/PID', '$spawnedWordPid', '/F'],
          );
        } catch (_) {}
      }
      throw PdfOperationException(
        'Konversi "${p.basename(absInput)}" melebihi batas waktu.',
      );
    }

    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    final stdoutText = stdoutBuffer.toString();
    final stderrText = stderrBuffer.toString();

    if (exitCode != 0) {
      final combined = '$stderrText\n$stdoutText'.trim();
      throw PdfOperationException(_mapWordComError(combined, absInput));
    }

    final outputFile = File(absOutput);
    if (!await outputFile.exists() || await outputFile.length() == 0) {
      throw PdfOperationException(
        'File DOCX hasil konversi tidak terbentuk untuk "${p.basename(absInput)}".',
      );
    }

    return absOutput;
  }

  String _mapWordComError(String details, String inputPath) {
    final lower = details.toLowerCase();
    final fileName = p.basename(inputPath);

    if (lower.contains('word.application') &&
        (lower.contains('cannot create') ||
            lower.contains('80040154') ||
            lower.contains('class not registered') ||
            lower.contains('comobject'))) {
      return 'Microsoft Word tidak terpasang atau COM Word tidak tersedia di sistem ini.';
    }
    if (lower.contains('password') ||
        lower.contains('encrypted') ||
        lower.contains('protected')) {
      return 'PDF "$fileName" dilindungi kata sandi dan tidak dapat dikonversi oleh Microsoft Word.';
    }
    if (lower.contains('being used') ||
        lower.contains('access is denied') ||
        lower.contains('cannot access the file') ||
        lower.contains('digunakan') ||
        lower.contains('read-only')) {
      return 'File output DOCX sedang dibuka di Microsoft Word atau terkunci. Tutup file tersebut lalu coba lagi.';
    }
    if (details.isEmpty) {
      return 'Gagal mengonversi "$fileName" ke DOCX menggunakan Microsoft Word.';
    }
    return 'Gagal mengonversi "$fileName" ke DOCX: ${details.split('\n').first.trim()}';
  }
}
