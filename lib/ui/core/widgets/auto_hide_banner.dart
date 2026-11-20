import 'package:material_ui/material_ui.dart';

/// Compact countdown banner shown while an auto-hide timer is running.
class AutoHideBanner extends StatelessWidget {
  /// Creates an [AutoHideBanner].
  const AutoHideBanner({
    super.key,
    required this.secondsRemaining,
    required this.onCancel,
  });

  /// Remaining seconds before the window hides to the system tray.
  final int secondsRemaining;

  /// Callback cancelling the pending auto-hide countdown.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        final message = isCompact
            ? 'Auto-hide ke tray dalam $secondsRemaining dtk'
            : 'Otomatis sembunyi ke taskbar tray dalam $secondsRemaining detik';

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 20,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onPrimaryContainer,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: const Text('Batal'),
              ),
            ],
          ),
        );
      },
    );
  }
}
