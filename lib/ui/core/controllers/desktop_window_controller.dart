import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:pdfutils/data/services/desktop_platform_service.dart';
import 'package:pdfutils/domain/models/app_window_mode.dart';

/// Manages desktop window sizing mode, startup/manual auto-hide countdown,
/// and system tray restore behavior.
class DesktopWindowController extends ChangeNotifier {
  /// Creates a [DesktopWindowController].
  DesktopWindowController({
    required this._platformService,
    this.autoHideDuration = const Duration(seconds: 5),
    this.autoHideOnStartup = true,
  });

  final DesktopPlatformService _platformService;

  /// Countdown duration before auto-hiding the window to the tray.
  final Duration autoHideDuration;

  /// Whether the first launch automatically triggers the auto-hide countdown.
  final bool autoHideOnStartup;

  AppWindowMode _windowMode = AppWindowMode.desktop;
  Size _lastDesktopSize = const Size(
    AppWindowMode.desktopWidth,
    AppWindowMode.desktopHeight,
  );
  bool _isWindowHidden = false;
  int? _autoHideSecondsRemaining;
  Timer? _autoHideTimer;
  bool _initialized = false;
  bool _disposed = false;

  /// Current window layout mode (`desktop` or `compact`).
  AppWindowMode get windowMode => _windowMode;

  /// Whether compact phone-size mode (`412 x 780`) is active.
  bool get isCompactMode => _windowMode == AppWindowMode.compact;

  /// Whether the window is currently hidden to the system tray.
  bool get isWindowHidden => _isWindowHidden;

  /// Remaining seconds before auto-hide executes, or `null` when inactive.
  int? get autoHideSecondsRemaining => _autoHideSecondsRemaining;

  /// Whether an auto-hide countdown is actively running.
  bool get isAutoHideCountingDown => _autoHideSecondsRemaining != null;

  /// Initializes native desktop window hooks, system tray icon, and optional
  /// startup auto-hide countdown.
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    await _platformService.initialize(
      onTrayRestore: () => unawaited(showFromTray()),
      onTrayToggleWindowMode: () => unawaited(toggleWindowModeFromTray()),
      onTrayStartAutoHide: startAutoHideCountdown,
      onTrayExit: () => unawaited(exitApp()),
      initialMode: _windowMode,
    );

    if (autoHideOnStartup) {
      startAutoHideCountdown();
    } else {
      await _syncTrayState();
    }
  }

  /// Starts (or restarts) the 5-second cancellable auto-hide countdown.
  void startAutoHideCountdown() {
    if (_disposed) return;

    _autoHideTimer?.cancel();
    final initialSeconds =
        autoHideDuration.inSeconds < 1 ? 1 : autoHideDuration.inSeconds;
    _autoHideSecondsRemaining = initialSeconds;
    _safeNotify();
    unawaited(_syncTrayState());

    _autoHideTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }

      final next = (_autoHideSecondsRemaining ?? 1) - 1;
      if (next <= 0) {
        timer.cancel();
        _autoHideTimer = null;
        _autoHideSecondsRemaining = null;
        _isWindowHidden = true;
        _safeNotify();
        unawaited(_platformService.hideWindow());
        unawaited(_syncTrayState());
      } else {
        _autoHideSecondsRemaining = next;
        _safeNotify();
        unawaited(_syncTrayState());
      }
    });
  }

  /// Cancels any active auto-hide countdown and keeps the window visible.
  void cancelAutoHide() {
    if (_disposed) return;
    final hadCountdown =
        _autoHideTimer != null || _autoHideSecondsRemaining != null;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _autoHideSecondsRemaining = null;
    if (hadCountdown) {
      _safeNotify();
      unawaited(_syncTrayState());
    }
  }

  /// Starts the auto-hide countdown when idle, or cancels it if active.
  void toggleAutoHideCountdown() {
    if (isAutoHideCountingDown) {
      cancelAutoHide();
    } else {
      startAutoHideCountdown();
    }
  }

  /// Restores the window from the system tray with **no auto-hide**.
  Future<void> showFromTray() async {
    if (_disposed) return;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _autoHideSecondsRemaining = null;
    _isWindowHidden = false;
    _safeNotify();

    await _platformService.showAndFocusWindow();
    await _syncTrayState();
  }

  /// Switches the window between [AppWindowMode.desktop] and [AppWindowMode.compact].
  Future<void> setWindowMode(AppWindowMode mode) async {
    if (_disposed || _windowMode == mode) return;

    if (mode == AppWindowMode.compact &&
        _windowMode == AppWindowMode.desktop) {
      final currentSize = await _platformService.getWindowSize();
      if (currentSize != null &&
          currentSize.width >= 640 &&
          currentSize.height >= 480) {
        _lastDesktopSize = currentSize;
      }
    }

    _windowMode = mode;
    _safeNotify();

    await _platformService.applyWindowMode(
      mode,
      restoreDesktopSize: _lastDesktopSize,
    );
    await _syncTrayState();
  }

  /// Toggles between [AppWindowMode.desktop] and [AppWindowMode.compact].
  Future<void> toggleWindowMode() {
    final nextMode = _windowMode == AppWindowMode.desktop
        ? AppWindowMode.compact
        : AppWindowMode.desktop;
    return setWindowMode(nextMode);
  }

  /// Restores the window from tray (cancelling auto-hide) and toggles window mode.
  Future<void> toggleWindowModeFromTray() async {
    await showFromTray();
    await toggleWindowMode();
  }

  /// Stops timers and exits the desktop application cleanly.
  Future<void> exitApp() async {
    if (_disposed) return;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _autoHideSecondsRemaining = null;
    await _platformService.exitApplication();
  }

  Future<void> _syncTrayState() {
    if (_disposed) return Future<void>.value();
    return _platformService.updateTrayState(
      mode: _windowMode,
      isWindowHidden: _isWindowHidden,
      autoHideSecondsRemaining: _autoHideSecondsRemaining,
    );
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    unawaited(_platformService.dispose());
    super.dispose();
  }
}
