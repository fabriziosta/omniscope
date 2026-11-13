import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Exclusive choice row (theme, density, etc.).
class SettingsSelectableOptionTile extends StatelessWidget {
  const SettingsSelectableOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final foreground = selected
        ? theme.colorScheme.secondaryForeground
        : theme.colorScheme.foreground;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              border: Border.all(color: theme.colorScheme.border),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.large.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.muted.copyWith(
                            color: selected
                                ? theme.colorScheme.secondaryForeground
                                    .withValues(alpha: 0.8)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      LucideIcons.check,
                      size: 18,
                      color: theme.colorScheme.secondaryForeground,
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

/// Enable/disable data source row.
class SettingsDataSourceToggleTile extends StatelessWidget {
  const SettingsDataSourceToggleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.border),
          borderRadius: theme.radius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.large),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShadSwitch(
                value: enabled,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + title card used for connections and credential rows.
class SettingsConnectionCard extends StatelessWidget {
  const SettingsConnectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackTrailing =
              trailing != null && constraints.maxWidth < 480;
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: theme.radius,
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.large),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.muted),
                  ],
                ),
              ),
              if (!stackTrailing && trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing!,
                  ),
                ),
              ],
            ],
          );
          if (!stackTrailing) return header;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: trailing!,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Quiet group caption inside a settings body — below the pane [h4] header.
class SettingsSubsectionLabel extends StatelessWidget {
  const SettingsSubsectionLabel(
    this.title, {
    super.key,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.mutedForeground,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: theme.textTheme.small.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}
