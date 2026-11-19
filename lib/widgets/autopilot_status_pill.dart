import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Autopilot status chip (Paper/Live-style [ShadBadge]).
///
/// Shows **Autopilot** (primary) or **Autopilot off** (secondary) so chat
/// list rows and the chat header both surface on/off at a glance.
/// When [onTap] is set, the pill is tappable (chat header toggle).
class AutopilotStatusPill extends StatelessWidget {
  const AutopilotStatusPill({
    super.key,
    required this.enabled,
    this.onTap,
  });

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = enabled
        ? const ShadBadge(child: Text('Autopilot'))
        : const ShadBadge.secondary(child: Text('Autopilot off'));

    if (onTap == null) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Align(alignment: Alignment.center, child: child),
      ),
    );
  }
}
