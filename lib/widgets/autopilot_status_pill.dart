import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Autopilot status chip (Paper/Live-style [ShadBadge]).
///
/// Shows **Autopilot** (primary) or **Autopilot off** (secondary) on Agents
/// list rows. Toggle via list overflow or chat ⋯ settings — not the pill.
class AutopilotStatusPill extends StatelessWidget {
  const AutopilotStatusPill({
    super.key,
    required this.enabled,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return enabled
        ? const ShadBadge(child: Text('Autopilot'))
        : const ShadBadge.secondary(child: Text('Autopilot off'));
  }
}
