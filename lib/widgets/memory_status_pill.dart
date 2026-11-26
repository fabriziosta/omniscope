import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared-memory status chip (mirrors [AutopilotStatusPill]).
///
/// Shows **Memory** (primary) or **Memory off** (secondary) on Agents list
/// rows. Toggle via list overflow or chat ⋯ settings — not the pill.
class MemoryStatusPill extends StatelessWidget {
  const MemoryStatusPill({
    super.key,
    required this.enabled,
  });

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return enabled
        ? const ShadBadge(child: Text('Memory'))
        : const ShadBadge.secondary(child: Text('Memory off'));
  }
}
