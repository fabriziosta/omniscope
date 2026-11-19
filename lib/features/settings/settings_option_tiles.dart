import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Vertical gap between stacked settings option rows.
const double settingsOptionGap = 4;

/// Section break between settings subsections.
const double settingsSectionGap = 14;

/// Exclusive choice row (theme, density, mandate, etc.).
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.p.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle,
                            style: theme.textTheme.small.copyWith(
                              color: selected
                                  ? theme.colorScheme.secondaryForeground
                                      .withValues(alpha: 0.8)
                                  : theme.colorScheme.mutedForeground,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      LucideIcons.check,
                      size: 16,
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

/// Compact exclusive choices in a wrapping chip row (short labels).
///
/// Prefer this when the subsection description already carries the detail and
/// each option is a short label (Brightness, Lists, Numbers, Charts).
class SettingsChoiceChips<T> extends StatelessWidget {
  const SettingsChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final option in options)
          _SettingsChoiceChip(
            label: option.$2,
            selected: option.$1 == value,
            onTap: () => onChanged(option.$1),
          ),
      ],
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  const _SettingsChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.secondary : null,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.border,
              ),
              borderRadius: theme.radius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.small.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(
                      LucideIcons.check,
                      size: 14,
                      color: theme.colorScheme.secondaryForeground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muted one-line hint under exclusive chips for the current selection.
class SettingsSelectedHint extends StatelessWidget {
  const SettingsSelectedHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

/// Exclusive chips with an optional dynamic hint for the selected value.
///
/// Omit [hintFor] for Appearance-style chips where the subsection description
/// already carries the detail.
class SettingsExclusiveChips<T> extends StatelessWidget {
  const SettingsExclusiveChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hintFor,
  });

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T value)? hintFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsChoiceChips<T>(
          options: options,
          value: value,
          onChanged: onChanged,
        ),
        if (hintFor != null) SettingsSelectedHint(hintFor!(value)),
      ],
    );
  }
}

/// Label above a [ShadInput] — presentational only (no save control).
class SettingsLabeledInput extends StatelessWidget {
  const SettingsLabeledInput({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.placeholder,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.small),
        const SizedBox(height: 6),
        ShadInput(
          controller: controller,
          keyboardType: keyboardType,
          placeholder: placeholder,
        ),
      ],
    );
  }
}

/// Two children side-by-side when width ≥ 480, otherwise stacked.
class SettingsWidePair extends StatelessWidget {
  const SettingsWidePair({
    super.key,
    required this.first,
    required this.second,
    this.gap = 12,
    this.stackGap = 8,
  });

  final Widget first;
  final Widget second;
  final double gap;
  final double stackGap;

  static const double breakpoint = 480;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              SizedBox(height: stackGap),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
      },
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
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(subtitle, style: theme.textTheme.small.copyWith(
                        color: theme.colorScheme.mutedForeground,
                      )),
                    ],
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackTrailing =
              trailing != null && constraints.maxWidth < 480;
          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: theme.radius,
                ),
                child: Icon(icon, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(subtitle, style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    )),
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
              const SizedBox(height: 8),
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
          const SizedBox(height: 2),
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
