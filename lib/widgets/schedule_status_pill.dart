import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/agents/agent_app_settings.dart';
import '../features/agents/agent_schedule_coordinator.dart';
import 'app_tooltip.dart';

/// Schedule status chip for the linked schedule chat (header + list row).
///
/// Shows **Running…** while a batch is in flight, otherwise the next-run ETA
/// (`Due now` / `Next in 12m`). Hidden when Schedule is off or [chatId] is not
/// the linked schedule home chat.
class ScheduleStatusPill extends StatefulWidget {
  const ScheduleStatusPill({
    super.key,
    required this.chatId,
  });

  final String chatId;

  @override
  State<ScheduleStatusPill> createState() => _ScheduleStatusPillState();
}

class _ScheduleStatusPillState extends State<ScheduleStatusPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AgentAppSettings>();
    if (!app.isScheduleChat(widget.chatId)) {
      return const SizedBox.shrink();
    }

    final running = context.select<AgentScheduleCoordinator, bool>(
      (c) => c.isInFlight,
    );
    final label = running
        ? 'Running…'
        : (app.scheduleEtaLabel(DateTime.now().toUtc()) ?? 'Due now');

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: AppTooltip(
        message: running
            ? 'Scheduled research is running'
            : 'Next scheduled research run',
        child: ShadBadge.secondary(child: Text(label)),
      ),
    );
  }
}
