import 'package:material_ui/material_ui.dart';

/// Standard desktop header displayed at the top of each PDF tool workspace.
class WorkspaceHeader extends StatelessWidget {
  /// Creates a [WorkspaceHeader].
  const WorkspaceHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
  });

  /// Leading tool icon.
  final IconData icon;

  /// Feature title.
  final String title;

  /// Concise description or active file metadata.
  final String subtitle;

  /// Trailing action buttons.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        final iconBox = Container(
          width: isPhone ? 38 : 44,
          height: isPhone ? 38 : 44,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(isPhone ? 10 : 12),
          ),
          child: Icon(
            icon,
            color: colorScheme.onPrimaryContainer,
            size: isPhone ? 20 : 22,
          ),
        );

        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (isPhone
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: isPhone ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        if (isPhone) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: textBlock),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              iconBox,
              const SizedBox(width: 14),
              Expanded(child: textBlock),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
