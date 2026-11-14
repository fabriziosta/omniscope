import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/genkit/omniscope_agent_tools.dart';
import 'package:omniscope/data/agents/models.dart';

/// Test runner that returns canned assistant text (no Genkit / network).
GenkitAgentRunner fakeGenkitAgentRunner({
  String reply = 'Test agent reply.',
  String Function(String roleId, String lastUser)? replyFor,
}) {
  return GenkitAgentRunner(
    turnOverride: ({
      required AgentConnection connection,
      required String roleId,
      required List<AgentChatMessage> messages,
      OmniscopeAgentToolDeps? toolDeps,
    }) async {
      final last = messages.isEmpty ? '' : messages.last.content;
      if (replyFor != null) return replyFor(roleId, last);
      return reply;
    },
  );
}
