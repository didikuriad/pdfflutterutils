import 'package:material_ui/material_ui.dart';
import 'package:pdfutils/ui/core/controllers/desktop_window_controller.dart';
import 'package:pdfutils/ui/core/widgets/auto_hide_banner.dart';

/// Builder for a workspace tab receiving whether the tab is currently active.
typedef WorkspaceTabBuilder = Widget Function(BuildContext context, bool isActive);

/// Adaptive Material 3 desktop shell hosting Merge, Rotate, and Split workspaces.
class AppShell extends StatefulWidget {
  /// Creates an [AppShell].
  const AppShell({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.windowController,
    required this.mergeBuilder,
    required this.rotateBuilder,
    required this.splitBuilder,
    required this.compressBuilder,
    required this.convertDocxBuilder,
    required this.editBuilder,
    required this.viewerBuilder,
  });

  /// Whether dark theme is currently active.
  final bool isDarkMode;

  /// Callback toggling light and dark themes.
  final VoidCallback onToggleTheme;

  /// Controller managing window layout mode, auto-hide countdown, and tray.
  final DesktopWindowController windowController;

  /// Builder for the Merge tab.
  final WorkspaceTabBuilder mergeBuilder;

  /// Builder for the Rotate tab.
  final WorkspaceTabBuilder rotateBuilder;

  /// Builder for the Split tab.
  final WorkspaceTabBuilder splitBuilder;

  /// Builder for the PDF compression tab.
  final WorkspaceTabBuilder compressBuilder;

  /// Builder for the PDF to DOCX conversion tab.
  final WorkspaceTabBuilder convertDocxBuilder;

  /// Builder for the interactive PDF editor tab.
  final WorkspaceTabBuilder editBuilder;

  /// Builder for the PDF viewer tab.
  final WorkspaceTabBuilder viewerBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isSidebarVisible = true;

  static const List<({String label, IconData icon, IconData selectedIcon})>
      _destinations = [
    (
      label: 'Gabung PDF',
      icon: Icons.merge_type_outlined,
      selectedIcon: Icons.merge_type_rounded,
    ),
    (
      label: 'Putar PDF',
      icon: Icons.rotate_right_outlined,
      selectedIcon: Icons.rotate_right_rounded,
    ),
    (
      label: 'Pisah PDF',
      icon: Icons.call_split_outlined,
      selectedIcon: Icons.call_split_rounded,
    ),
    (
      label: 'Kompres PDF',
      icon: Icons.compress_outlined,
      selectedIcon: Icons.compress_rounded,
    ),
    (
      label: 'PDF ke DOCX',
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
    ),
    (
      label: 'Edit PDF',
      icon: Icons.edit_outlined,
      selectedIcon: Icons.edit_rounded,
    ),
    (
      label: 'PDF Viewer',
      icon: Icons.chrome_reader_mode_outlined,
      selectedIcon: Icons.chrome_reader_mode_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.windowController,
      builder: (context, _) {
        final wc = widget.windowController;
        final countdownSeconds = wc.autoHideSecondsRemaining;

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final isWide = maxWidth >= 960;
            final isCompactRail = maxWidth >= 640 && maxWidth < 960;

            final workspaceStack = IndexedStack(
              index: _selectedIndex,
              children: [
                widget.mergeBuilder(context, _selectedIndex == 0),
                widget.rotateBuilder(context, _selectedIndex == 1),
                widget.splitBuilder(context, _selectedIndex == 2),
                widget.compressBuilder(context, _selectedIndex == 3),
                widget.convertDocxBuilder(context, _selectedIndex == 4),
                widget.editBuilder(context, _selectedIndex == 5),
                widget.viewerBuilder(context, _selectedIndex == 6),
              ],
            );

            final workspaceBody = Column(
              children: [
                if (countdownSeconds != null)
                  AutoHideBanner(
                    secondsRemaining: countdownSeconds,
                    onCancel: wc.cancelAutoHide,
                  ),
                Expanded(child: workspaceStack),
              ],
            );

            if (isWide || isCompactRail) {
              final colorScheme = Theme.of(context).colorScheme;
              return Scaffold(
                body: Row(
                  children: [
                    if (_isSidebarVisible) ...[
                      _DesktopRail(
                        selectedIndex: _selectedIndex,
                        extended: isWide,
                        isDarkMode: widget.isDarkMode,
                        isCompactMode: wc.isCompactMode,
                        autoHideSecondsRemaining: countdownSeconds,
                        onDestinationSelected: (index) {
                          setState(() => _selectedIndex = index);
                        },
                        onToggleSidebar: () {
                          setState(() => _isSidebarVisible = false);
                        },
                        onToggleWindowMode: wc.toggleWindowMode,
                        onToggleAutoHide: wc.toggleAutoHideCountdown,
                        onToggleTheme: widget.onToggleTheme,
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: Stack(
                        children: [
                          workspaceBody,
                          if (!_isSidebarVisible)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Tooltip(
                                  message: 'Tampilkan Sidebar',
                                  child: Material(
                                    color: colorScheme.surfaceContainerHigh
                                        .withValues(alpha: 0.95),
                                    elevation: 2,
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(12),
                                    ),
                                    child: InkWell(
                                      borderRadius:
                                          const BorderRadius.horizontal(
                                        right: Radius.circular(12),
                                      ),
                                      onTap: () {
                                        setState(() => _isSidebarVisible = true);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            top: BorderSide(
                                              color: colorScheme.outlineVariant,
                                            ),
                                            right: BorderSide(
                                              color: colorScheme.outlineVariant,
                                            ),
                                            bottom: BorderSide(
                                              color: colorScheme.outlineVariant,
                                            ),
                                          ),
                                          borderRadius:
                                              const BorderRadius.horizontal(
                                            right: Radius.circular(12),
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 20,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 12,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 16,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'PDF Utils',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (countdownSeconds != null)
                    FilledButton.tonalIcon(
                      onPressed: wc.toggleAutoHideCountdown,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(Icons.timer_off_outlined, size: 16),
                      label: Text('Batal (${countdownSeconds}d)'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: wc.toggleAutoHideCountdown,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(Icons.visibility_off_outlined, size: 16),
                      label: const Text('Auto Hide'),
                    ),
                  IconButton(
                    onPressed: wc.toggleWindowMode,
                    tooltip: wc.isCompactMode
                        ? 'Mode Desktop'
                        : 'Mode Kecil (HP)',
                    icon: Icon(
                      wc.isCompactMode
                          ? Icons.desktop_windows_rounded
                          : Icons.smartphone_rounded,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onToggleTheme,
                    tooltip: widget.isDarkMode ? 'Mode Terang' : 'Mode Gelap',
                    icon: Icon(
                      widget.isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                  ),
                ],
              ),
              body: workspaceBody,
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => _selectedIndex = index);
                },
                destinations: [
                  for (final item in _destinations)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selectedIndex,
    required this.extended,
    required this.isDarkMode,
    required this.isCompactMode,
    required this.autoHideSecondsRemaining,
    required this.onDestinationSelected,
    required this.onToggleSidebar,
    required this.onToggleWindowMode,
    required this.onToggleAutoHide,
    required this.onToggleTheme,
  });

  final int selectedIndex;
  final bool extended;
  final bool isDarkMode;
  final bool isCompactMode;
  final int? autoHideSecondsRemaining;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleWindowMode;
  final VoidCallback onToggleAutoHide;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCountingDown = autoHideSecondsRemaining != null;

    return NavigationRail(
      extended: extended,
      minExtendedWidth: 220,
      backgroundColor: colorScheme.surfaceContainerLow,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: extended ? 12 : 8,
          vertical: extended ? 16 : 10,
        ),
        child: extended
            ? SizedBox(
                width: 196,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 20,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PDF Utils',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Merge • Rotate • Split',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleSidebar,
                      tooltip: 'Sembunyikan Sidebar',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.menu_open_rounded, size: 20),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 20,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  IconButton(
                    onPressed: onToggleSidebar,
                    tooltip: 'Sembunyikan Sidebar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.menu_open_rounded, size: 20),
                  ),
                ],
              ),
      ),
      destinations: [
        for (final item in _AppShellState._destinations)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.label),
          ),
      ],
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
            child: SingleChildScrollView(
              child: extended
                  ? SizedBox(
                      width: 196,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onToggleWindowMode,
                            icon: Icon(
                              isCompactMode
                                  ? Icons.desktop_windows_outlined
                                  : Icons.smartphone_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isCompactMode ? 'Mode Desktop' : 'Mode Kecil (HP)',
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (isCountingDown)
                            FilledButton.tonalIcon(
                              onPressed: onToggleAutoHide,
                              icon:
                                  const Icon(Icons.timer_off_outlined, size: 18),
                              label: Text('Batal (${autoHideSecondsRemaining}d)'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: onToggleAutoHide,
                              icon: const Icon(
                                Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              label: const Text('Auto Hide'),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: onToggleTheme,
                            icon: Icon(
                              isDarkMode
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              size: 18,
                            ),
                            label:
                                Text(isDarkMode ? 'Mode Terang' : 'Mode Gelap'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: onToggleWindowMode,
                          tooltip: isCompactMode
                              ? 'Beralih ke Mode Desktop'
                              : 'Beralih ke Mode Kecil (HP)',
                          icon: Icon(
                            isCompactMode
                                ? Icons.desktop_windows_outlined
                                : Icons.smartphone_rounded,
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          onPressed: onToggleAutoHide,
                          tooltip: isCountingDown
                              ? 'Batalkan auto-hide (${autoHideSecondsRemaining}d)'
                              : 'Mulai auto-hide 5 detik ke tray',
                          icon: Icon(
                            isCountingDown
                                ? Icons.timer_off_outlined
                                : Icons.visibility_off_outlined,
                            color: isCountingDown ? colorScheme.primary : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          onPressed: onToggleTheme,
                          tooltip: isDarkMode ? 'Mode Terang' : 'Mode Gelap',
                          icon: Icon(
                            isDarkMode
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
