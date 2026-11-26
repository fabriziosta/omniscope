import 'package:genkit/genkit.dart';

import 'agent_tool_registry.dart';
import 'omniscope_agent_tool_helpers.dart';
import 'omniscope_agent_tools.dart';

/// Fleet, Autopilot, and per-chat focus symbol tools.
List<Tool<dynamic, dynamic>> defineOmniscopeFleetTools(
  Genkit ai,
  OmniscopeAgentToolDeps deps,
) {
  final inputSchema = OmniscopeAgentToolHelpers.symbolInput;

  final getAgentFleetStatus = ai.defineTool(
    name: AgentToolIds.getAgentFleetStatus,
    description:
        'Read device-wide operational status: Autopilot-on chats, '
        'Schedule (enabled / running / next ETA), pending Confirm counts, '
        'and today\'s Autopilot fill / realized P&L rails. '
        'No other chat messages. Input: {} (no fields required). '
        'Call before proposing duplicate trades or Invest interest adds. '
        'Do not use this instead of setChatAutopilot when the user asks '
        'to turn Autopilot on or off.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final get = deps.getFleetStatus;
      if (get == null) {
        return .response('Fleet status is not available in this turn.');
      }
      return .response(get());
    },
  );

  final setChatAutopilot = ai.defineTool(
    name: AgentToolIds.setChatAutopilot,
    description:
        'Enable or disable Autopilot for THIS chat only. Applies '
        'immediately (also available via the Autopilot pill). '
        'When enabling, risk-approved trades and add-only Invest interest '
        'may apply without Confirm; at most 5 chats may have Autopilot on. '
        'Input: {"enabled":true} or {"enabled":false}. '
        'When the user asks to enable Autopilot, call this — do not only '
        'check fleet status or ask them to tap the pill first.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final set = deps.setChatAutopilot;
      if (set == null) {
        return .response('Autopilot control is not available in this turn.');
      }
      final enabled = OmniscopeAgentToolHelpers.readBool(
        OmniscopeAgentToolHelpers.asMap(input)['enabled'],
      );
      if (enabled == null) {
        return .response(
          'Provide enabled as true or false, e.g. {"enabled":true}.',
        );
      }
      try {
        return .response(await set(enabled: enabled));
      } catch (e) {
        return .response('Could not update Autopilot: $e');
      }
    },
  );

  final getChatFocusSymbols = ai.defineTool(
    name: AgentToolIds.getChatFocusSymbols,
    description:
        'Read symbols pinned for THIS chat only (focus list shown above '
        'the composer). Not Markets → Invest interest. '
        'Input: {} (no fields required).',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final symbols = [
        for (final s in deps.focusSymbols)
          if (s.trim().isNotEmpty) s.trim().toUpperCase(),
      ];
      if (symbols.isEmpty) {
        return .response(
          'This chat has no focus symbols yet. Pin with pinChatSymbols '
          'when you investigate or trade a concrete ticker.',
        );
      }
      return .response('Chat focus symbols: ${symbols.join(', ')}.');
    },
  );

  final pinChatSymbols = ai.defineTool(
    name: AgentToolIds.pinChatSymbols,
    description:
        'Pin symbols onto THIS chat focus list (chips above composer). '
        'Only you can manage this list — the user has no pin/unpin UI. '
        'Applies immediately — no Confirm. Cap 12; oldest drop. '
        'Not Invest interest. Input: {"symbols":["AAPL","ETH_USD"]}.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final pin = deps.pinChatSymbols;
      if (pin == null) {
        return .response('Chat focus symbols are not available.');
      }
      final symbols = OmniscopeAgentToolHelpers.readSymbols(input);
      if (symbols.isEmpty) {
        return .response(
          'Provide symbols, e.g. {"symbols":["AAPL","ETH_USD"]}.',
        );
      }
      try {
        final next = await pin(symbols);
        return .response(
          next.isEmpty
              ? 'Focus list is empty after pin.'
              : 'Chat focus symbols now: ${next.join(', ')}.',
        );
      } catch (e) {
        return .response('Could not pin symbols: $e');
      }
    },
  );

  final unpinChatSymbols = ai.defineTool(
    name: AgentToolIds.unpinChatSymbols,
    description:
        'Unpin symbols from THIS chat focus list. Only you can manage '
        'this list — the user has no unpin control. Applies immediately. '
        'Input: {"symbols":["AAPL"]}.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final unpin = deps.unpinChatSymbols;
      if (unpin == null) {
        return .response('Chat focus symbols are not available.');
      }
      final symbols = OmniscopeAgentToolHelpers.readSymbols(input);
      if (symbols.isEmpty) {
        return .response('Provide symbols to unpin, e.g. {"symbols":["AAPL"]}.');
      }
      try {
        final next = await unpin(symbols);
        return .response(
          next.isEmpty
              ? 'Chat focus list is now empty.'
              : 'Chat focus symbols now: ${next.join(', ')}.',
        );
      } catch (e) {
        return .response('Could not unpin symbols: $e');
      }
    },
  );

  return [
    getAgentFleetStatus,
    setChatAutopilot,
    getChatFocusSymbols,
    pinChatSymbols,
    unpinChatSymbols,
  ];
}
