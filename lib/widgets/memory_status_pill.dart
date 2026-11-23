import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared-memory status chip (mirrors [AutopilotStatusPill]).
///
/// Shows **Memory** (primary) or **Memory off** (secondary) on chat list
/// rows and the chat header. When [onTap] is set, the pill is tappable.
class MemoryStatusPill extends StatelessWidget {
  const MemoryStatusPill({
    super.key,
    required this.enabled,
    this.onTap,
  });

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = enabled
        ? const ShadBadge(child: Text('Memory'))
        : const ShadBadge.secondary(child: Text('Memory off'));

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
