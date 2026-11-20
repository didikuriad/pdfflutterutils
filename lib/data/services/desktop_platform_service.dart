import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size, VoidCallback;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tray_manager/tray_manager.dart' as tm
    show
        ContextMenuTrigger,
        Image,
        ImageAsset,
        ListenerId,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon,
        TrayIconClickedEvent,
        TrayIconDoubleClickedEvent;
import 'package:window_manager/window_manager.dart'
    show
        ListenerId,
        NativeSizeToSize,
        SizeToNative,
        Window,
        WindowClosedEvent,
        WindowCloseRequestedEvent,
        WindowManager;

import '../../domain/models/app_window_mode.dart';

/// Abstraction over OS desktop window sizing, visibility, and system tray icon.
abstract class DesktopPlatformService {
  /// Initializes native window constraints and the system tray icon/menu.
  Future<void> initialize({
    required VoidCallback onTrayRestore,
    required VoidCallback onTrayToggleWindowMode,
    required VoidCallback onTrayStartAutoHide,
    required VoidCallback onTrayExit,
    required AppWindowMode initialMode,
  });

  /// Returns the current native window size in logical pixels, if available.
  Future<Size?> getWindowSize();

  /// Resizes and configures the window for [mode].
  Future<void> applyWindowMode(
    AppWindowMode mode, {
    Size? restoreDesktopSize,
  });

  /// Hides the application window from screen and taskbar into the system tray.
  Future<void> hideWindow();

  /// Restores, shows, and focuses the application window.
  Future<void> showAndFocusWindow();

  /// Updates tray tooltip and dynamic context menu labels.
  Future<void> updateTrayState({
    required AppWindowMode mode,
    required bool isWindowHidden,
    required int? autoHideSecondsRemaining,
  });

  /// Disposes tray resources and terminates the desktop application.
  Future<void> exitApplication();

  /// Releases native listeners, tray menu items, and tray icon handles.
  Future<void> dispose();
}

/// No-op implementation used on unsupported platforms or in widget tests.
class NoopDesktopPlatformService implements DesktopPlatformService {
  @override
  Future<void> initialize({
    required VoidCallback onTrayRestore,
    required VoidCallback onTrayToggleWindowMode,
    required VoidCallback onTrayStartAutoHide,
    required VoidCallback onTrayExit,
    required AppWindowMode initialMode,
  }) async {}

  @override
  Future<Size?> getWindowSize() async => null;

  @override
  Future<void> applyWindowMode(
    AppWindowMode mode, {
    Size? restoreDesktopSize,
  }) async {}

  @override
  Future<void> hideWindow() async {}

  @override
  Future<void> showAndFocusWindow() async {}

  @override
  Future<void> updateTrayState({
    required AppWindowMode mode,
    required bool isWindowHidden,
    required int? autoHideSecondsRemaining,
  }) async {}

  @override
  Future<void> exitApplication() async {}

  @override
  Future<void> dispose() async {}
}

/// Native desktop implementation backed by `window_manager` and `tray_manager`.
class NativeDesktopPlatformService implements DesktopPlatformService {
  Window? _window;
  ListenerId? _windowListenerId;

  // Keep strong references to every native tray/menu object so Dart GC does
  // not finalize handles and remove the tray icon from Windows hidden icons.
  tm.TrayIcon? _trayIcon;
  tm.Image? _trayImage;
  tm.ListenerId? _trayListenerId;
  tm.Menu? _trayMenu;
  tm.MenuItem? _showItem;
  tm.MenuItem? _modeToggleItem;
  tm.MenuItem? _autoHideItem;
  tm.MenuItem? _exitItem;
  final List<({tm.MenuItem item, tm.ListenerId id})> _menuItemListeners =
      <({tm.MenuItem item, tm.ListenerId id})>[];

  bool _isInitialized = false;
  bool _isDisposed = false;

  bool get _isDesktopSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Future<void> initialize({
    required VoidCallback onTrayRestore,
    required VoidCallback onTrayToggleWindowMode,
    required VoidCallback onTrayStartAutoHide,
    required VoidCallback onTrayExit,
    required AppWindowMode initialMode,
  }) async {
    if (!_isDesktopSupported || _isInitialized || _isDisposed) return;

    _tryNative(() {
      final window = _resolveWindow();
      if (window != null) {
        window.title = 'PDF Utils';
        window.minimumSize = const Size(
          AppWindowMode.minimumWidth,
          AppWindowMode.minimumHeight,
        ).toNative();

        _windowListenerId = window.addListener((event) {
          if (event is WindowCloseRequestedEvent ||
              event is WindowClosedEvent) {
            unawaited(_disposeTrayResources());
          }
        });
      }

      _setupTray(
        onTrayRestore: onTrayRestore,
        onTrayToggleWindowMode: onTrayToggleWindowMode,
        onTrayStartAutoHide: onTrayStartAutoHide,
        onTrayExit: onTrayExit,
        initialMode: initialMode,
      );
    });

    _isInitialized = true;
  }

  void _setupTray({
    required VoidCallback onTrayRestore,
    required VoidCallback onTrayToggleWindowMode,
    required VoidCallback onTrayStartAutoHide,
    required VoidCallback onTrayExit,
    required AppWindowMode initialMode,
  }) {
    final trayIcon = tm.TrayIcon.create();
    if (trayIcon == null) return;

    final trayImage = _loadTrayImage();
    if (trayImage != null) {
      _trayImage = trayImage;
      trayIcon.icon = trayImage;
    }
    trayIcon.setTooltip('PDF Utils');

    final menu = tm.Menu.create();
    if (menu != null) {
      final showItem = tm.MenuItem.createWithLabelAndType(
        'Tampilkan PDF Utils',
        tm.MenuItemType.normal,
      );
      if (showItem != null) {
        _attachMenuClick(showItem, onTrayRestore);
        menu.addItem(showItem);
        _showItem = showItem;
      }

      final modeItem = tm.MenuItem.createWithLabelAndType(
        _modeToggleLabel(initialMode),
        tm.MenuItemType.normal,
      );
      if (modeItem != null) {
        _attachMenuClick(modeItem, onTrayToggleWindowMode);
        menu.addItem(modeItem);
        _modeToggleItem = modeItem;
      }

      final autoHideItem = tm.MenuItem.createWithLabelAndType(
        'Auto Hide (5 detik)',
        tm.MenuItemType.normal,
      );
      if (autoHideItem != null) {
        _attachMenuClick(autoHideItem, onTrayStartAutoHide);
        menu.addItem(autoHideItem);
        _autoHideItem = autoHideItem;
      }

      menu.addSeparator();

      final exitItem = tm.MenuItem.createWithLabelAndType(
        'Keluar',
        tm.MenuItemType.normal,
      );
      if (exitItem != null) {
        _attachMenuClick(exitItem, onTrayExit);
        menu.addItem(exitItem);
        _exitItem = exitItem;
      }

      trayIcon.setContextMenu(menu);
      trayIcon.setContextMenuTrigger(tm.ContextMenuTrigger.rightClicked);
      _trayMenu = menu;
    }

    _trayListenerId = trayIcon.addListener((event) {
      switch (event) {
        case tm.TrayIconClickedEvent():
        case tm.TrayIconDoubleClickedEvent():
          onTrayRestore();
        default:
          break;
      }
    });

    trayIcon.setVisible(true);
    _trayIcon = trayIcon;
  }

  void _attachMenuClick(tm.MenuItem item, VoidCallback handler) {
    final listenerId = item.addListener((event) {
      if (event is tm.MenuItemClickedEvent) {
        handler();
      }
    });
    _menuItemListeners.add((item: item, id: listenerId));
  }

  tm.Image? _loadTrayImage() {
    if (Platform.isWindows) {
      return tm.ImageAsset.fromAsset('assets/icons/app_icon.ico') ??
          tm.ImageAsset.fromAsset('assets/icons/app_icon.png');
    }
    return tm.ImageAsset.fromAsset('assets/icons/app_icon.png') ??
        tm.ImageAsset.fromAsset('assets/icons/app_icon.ico');
  }

  @override
  Future<Size?> getWindowSize() async {
    if (!_isDesktopSupported) return null;
    return _tryNative<Size?>(() {
      final window = _resolveWindow();
      if (window == null) return null;
      return window.size.toSize();
    });
  }

  @override
  Future<void> applyWindowMode(
    AppWindowMode mode, {
    Size? restoreDesktopSize,
  }) async {
    if (!_isDesktopSupported) return;
    _tryNative(() {
      final window = _resolveWindow();
      if (window == null) return;

      window.minimumSize = const Size(
        AppWindowMode.minimumWidth,
        AppWindowMode.minimumHeight,
      ).toNative();

      if (window.isFullScreen) {
        window.isFullScreen = false;
      }
      if (window.isMaximizedVertically) {
        window.setMaximizedVertically(false);
      }
      if (window.isMaximized) {
        window.unmaximize();
      }
      if (window.isMinimized) {
        window.restore();
      }

      final targetSize = mode == AppWindowMode.compact
          ? const Size(
              AppWindowMode.compactWidth,
              AppWindowMode.compactHeight,
            )
          : (restoreDesktopSize ??
              const Size(
                AppWindowMode.desktopWidth,
                AppWindowMode.desktopHeight,
              ));

      window.setSize(targetSize.toNative(), false);
      window.center();
    });
  }

  @override
  Future<void> hideWindow() async {
    if (!_isDesktopSupported) return;
    _tryNative(() {
      _resolveWindow()?.hide();
    });
  }

  @override
  Future<void> showAndFocusWindow() async {
    if (!_isDesktopSupported) return;
    _tryNative(() {
      final window = _resolveWindow();
      if (window == null) return;
      if (window.isMinimized) {
        window.restore();
      }
      window.show();
      window.focus();
    });
  }

  @override
  Future<void> updateTrayState({
    required AppWindowMode mode,
    required bool isWindowHidden,
    required int? autoHideSecondsRemaining,
  }) async {
    if (!_isDesktopSupported) return;
    _tryNative(() {
      _modeToggleItem?.label = _modeToggleLabel(mode);
      _autoHideItem?.isEnabled = !isWindowHidden;
      _autoHideItem?.label = autoHideSecondsRemaining != null
          ? 'Auto Hide (${autoHideSecondsRemaining}d)'
          : 'Auto Hide (5 detik)';

      final tooltip = switch ((isWindowHidden, autoHideSecondsRemaining)) {
        (true, _) => 'PDF Utils (Tersembunyi — klik untuk buka)',
        (false, final int seconds) =>
          'PDF Utils (Auto-hide dalam $seconds detik)',
        (false, null) => 'PDF Utils (${mode.label})',
      };
      _trayIcon?.setTooltip(tooltip);
    });
  }

  @override
  Future<void> exitApplication() async {
    if (!_isDesktopSupported) return;
    await dispose();
    var closed = false;
    _tryNative(() {
      final window = _resolveWindow();
      if (window != null && Window.isCloseSupported()) {
        closed = window.close();
      }
    });
    if (!closed) {
      exit(0);
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _disposeTrayResources();
    _tryNative(() {
      final windowListenerId = _windowListenerId;
      if (windowListenerId != null) {
        _window?.removeListener(windowListenerId);
      }
      _windowListenerId = null;
      _window = null;
    });
  }

  Future<void> _disposeTrayResources() async {
    _tryNative(() {
      final trayListenerId = _trayListenerId;
      if (trayListenerId != null) {
        _trayIcon?.removeListener(trayListenerId);
      }
      _trayListenerId = null;

      _trayIcon?.setVisible(false);
      _trayIcon?.setContextMenu(null);
      _trayIcon?.dispose();
      _trayIcon = null;

      for (final entry in _menuItemListeners) {
        entry.item.removeListener(entry.id);
      }
      _menuItemListeners.clear();

      _showItem?.dispose();
      _showItem = null;
      _modeToggleItem?.dispose();
      _modeToggleItem = null;
      _autoHideItem?.dispose();
      _autoHideItem = null;
      _exitItem?.dispose();
      _exitItem = null;

      _trayMenu?.dispose();
      _trayMenu = null;

      _trayImage?.dispose();
      _trayImage = null;
    });
  }

  Window? _resolveWindow() {
    return _window ??= WindowManager.instance.getCurrent();
  }

  String _modeToggleLabel(AppWindowMode mode) {
    return mode == AppWindowMode.compact
        ? 'Beralih ke Mode Desktop'
        : 'Beralih ke Mode Kecil (HP)';
  }

  T? _tryNative<T>(T Function() action) {
    try {
      return action();
    } on ArgumentError {
      return null;
    } on UnsupportedError {
      return null;
    }
  }
}
