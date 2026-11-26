import 'package:genkit/genkit.dart';

import 'agent_tool_registry.dart';
import 'omniscope_agent_tool_helpers.dart';
import 'omniscope_agent_tools.dart';

/// Shared-memory tools (only when the chat has Memory on).
List<Tool<dynamic, dynamic>> defineOmniscopeMemoryTools(
  Genkit ai,
  OmniscopeAgentToolDeps deps,
) {
  if (!deps.memoryEnabled) return const [];

  final inputSchema = OmniscopeAgentToolHelpers.symbolInput;

  final getAgentMemory = ai.defineTool(
    name: AgentToolIds.getAgentMemory,
    description:
        'Read shared durable facts across Memory-on chats. '
        'Input: {} (no fields required).',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final summary = deps.memorySummary?.trim() ?? '';
      if (summary.isEmpty) {
        return .response('Shared agent memory is empty.');
      }
      return .response(summary);
    },
  );

  final rememberFact = ai.defineTool(
    name: AgentToolIds.rememberFact,
    description:
        'Store a short durable fact for other Memory-on chats '
        '(max 280 chars). Applies immediately — no Confirm. '
        'Input: {"text":"User prefers ETFs over single stocks"}.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final remember = deps.rememberFact;
      if (remember == null) {
        return .response('Memory writes are unavailable.');
      }
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final text = map['text']?.toString() ??
          map['fact']?.toString() ??
          '';
      try {
        final fact = await remember(text);
        if (fact == null) {
          return .response(
            'Could not store fact (empty or over 280 characters).',
          );
        }
        return .response(
          'Remembered [${fact.id}]: ${fact.text}',
        );
      } catch (e) {
        return .response('Could not remember fact: $e');
      }
    },
  );

  final forgetFact = ai.defineTool(
    name: AgentToolIds.forgetFact,
    description:
        'Remove a shared memory fact by id or matching text. '
        'Applies immediately. Input: {"id":"m_…"} or {"text":"…"}.',
    inputSchema: inputSchema,
    fn: (input, _) async {
      final forget = deps.forgetFact;
      if (forget == null) {
        return .response('Memory writes are unavailable.');
      }
      final map = OmniscopeAgentToolHelpers.asMap(input);
      final key = (map['id'] ?? map['text'] ?? map['fact'] ?? '')
          .toString()
          .trim();
      if (key.isEmpty) {
        return .response('Provide id or text to forget.');
      }
      try {
        final ok = await forget(key);
        return .response(
          ok ? 'Forgot memory matching "$key".' : 'No matching fact found.',
        );
      } catch (e) {
        return .response('Could not forget fact: $e');
      }
    },
  );

  return [getAgentMemory, rememberFact, forgetFact];
}
