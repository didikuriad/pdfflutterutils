import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfutils/domain/models/app_window_mode.dart';
import 'package:pdfutils/ui/core/controllers/desktop_window_controller.dart';

import '../test_helpers/fakes.dart';

void main() {
  testWidgets(
    'startup auto-hide counts down 5 seconds and hides window to tray',
    (tester) async {
      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideDuration: const Duration(seconds: 5),
        autoHideOnStartup: true,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(platform.initializeCount, 1);
      expect(controller.isAutoHideCountingDown, isTrue);
      expect(controller.autoHideSecondsRemaining, 5);
      expect(controller.isWindowHidden, isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(controller.autoHideSecondsRemaining, 3);
      expect(platform.hideCount, 0);

      await tester.pump(const Duration(seconds: 3));
      expect(controller.isAutoHideCountingDown, isFalse);
      expect(controller.autoHideSecondsRemaining, isNull);
      expect(controller.isWindowHidden, isTrue);
      expect(platform.hideCount, 1);
    },
  );

  testWidgets(
    'cancelling countdown stops auto-hide and keeps window visible',
    (tester) async {
      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideDuration: const Duration(seconds: 5),
        autoHideOnStartup: true,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.autoHideSecondsRemaining, 3);

      controller.cancelAutoHide();
      expect(controller.isAutoHideCountingDown, isFalse);
      expect(controller.autoHideSecondsRemaining, isNull);

      await tester.pump(const Duration(seconds: 10));
      expect(platform.hideCount, 0);
      expect(controller.isWindowHidden, isFalse);
    },
  );

  testWidgets(
    'restoring from tray shows window without auto-hide and cancels active countdown',
    (tester) async {
      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideDuration: const Duration(seconds: 5),
        autoHideOnStartup: true,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await tester.pump(const Duration(seconds: 5));
      expect(controller.isWindowHidden, isTrue);
      expect(platform.hideCount, 1);

      // Clicking tray icon restores app with NO auto-hide.
      platform.simulateTrayRestore();
      await tester.pump();
      expect(controller.isWindowHidden, isFalse);
      expect(controller.isAutoHideCountingDown, isFalse);
      expect(platform.showCount, 1);

      await tester.pump(const Duration(seconds: 15));
      expect(controller.isWindowHidden, isFalse);
      expect(platform.hideCount, 1);
    },
  );

  testWidgets(
    'toggleAutoHideCountdown starts 5s countdown after tray restore and can cancel',
    (tester) async {
      final platform = FakeDesktopPlatformService();
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideDuration: const Duration(seconds: 5),
        autoHideOnStartup: false,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.isAutoHideCountingDown, isFalse);

      // First click starts 5s countdown.
      controller.toggleAutoHideCountdown();
      expect(controller.isAutoHideCountingDown, isTrue);
      expect(controller.autoHideSecondsRemaining, 5);

      await tester.pump(const Duration(seconds: 1));
      expect(controller.autoHideSecondsRemaining, 4);

      // Second click cancels countdown.
      controller.toggleAutoHideCountdown();
      expect(controller.isAutoHideCountingDown, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(platform.hideCount, 0);

      // Starting again and letting 5s finish hides the window.
      controller.toggleAutoHideCountdown();
      await tester.pump(const Duration(seconds: 5));
      expect(controller.isWindowHidden, isTrue);
      expect(platform.hideCount, 1);
    },
  );

  testWidgets(
    'switches between desktop and compact modes while preserving desktop size',
    (tester) async {
      final platform = FakeDesktopPlatformService()
        ..currentWindowSize = const Size(1400, 900);
      final controller = DesktopWindowController(
        platformService: platform,
        autoHideOnStartup: false,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.windowMode, AppWindowMode.desktop);

      await controller.toggleWindowMode();
      expect(controller.windowMode, AppWindowMode.compact);
      expect(controller.isCompactMode, isTrue);
      expect(platform.appliedModes.last, AppWindowMode.compact);

      await controller.toggleWindowMode();
      expect(controller.windowMode, AppWindowMode.desktop);
      expect(controller.isCompactMode, isFalse);
      expect(platform.appliedModes.last, AppWindowMode.desktop);
      expect(platform.lastRestoreDesktopSize, const Size(1400, 900));

      // Tray toggle restores and switches mode without auto-hide.
      platform.simulateTrayToggleMode();
      await tester.pump();
      expect(controller.windowMode, AppWindowMode.compact);
      expect(platform.showCount, 1);

      // Exit cancels timers and notifies platform service.
      controller.startAutoHideCountdown();
      platform.simulateTrayExit();
      await tester.pump();
      expect(platform.exitCount, 1);
    },
  );
}
