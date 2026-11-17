import 'package:omniscope/data/agents/chat_models.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/genkit/omniscope_agent_tools.dart';
import 'package:omniscope/data/agents/llm_model_router.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';

/// Test runner that returns canned assistant text (no Genkit / network).
GenkitAgentRunner fakeGenkitAgentRunner({
  String reply = 'Test agent reply.',
  String Function(String lastUser)? replyFor,
  Map<String, dynamic>? Function(String lastUser)? delegatedTradeJsonFor,
  List<String> Function(String lastUser)? delegatedRoleIdsFor,
}) {
  return GenkitAgentRunner(
    turnOverride: ({
      required LlmResolvedEndpoint endpoint,
      required List<AgentChatMessage> messages,
      OmniscopeAgentToolDeps? toolDeps,
      List<GenkitSpecialtySpec> specialties = const [],
      LlmRuntimeSettings? runtime,
    }) async {
      final last = messages.isEmpty ? '' : messages.last.content;
      final text = replyFor != null ? replyFor(last) : reply;
      final tradeJson =
          delegatedTradeJsonFor != null ? delegatedTradeJsonFor(last) : null;
      final roleIds = delegatedRoleIdsFor != null
          ? delegatedRoleIdsFor(last)
          : (tradeJson != null
              ? const ['intradayTrading']
              : const <String>[]);
      return GenkitAgentTurnResult(
        reply: text,
        delegatedTradeJson: tradeJson,
        delegatedTradeRoleId:
            tradeJson != null ? 'intradayTrading' : null,
        delegatedRoleIds: roleIds,
      );
    },
  );
}
