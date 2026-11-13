import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Non-interactive section label — muted so it never looks like a control.
///
/// Prefer this outside Settings. Accordion bodies under Settings still use
/// `SettingsSubsectionLabel` for local consistency.
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Text(
      text,
      style: theme.textTheme.small.copyWith(
        color: theme.colorScheme.mutedForeground,
      ),
    );
  }
}
