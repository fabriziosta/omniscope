import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;

import '../agent_role_prompts.dart';
import '../chat_models.dart';
import '../models.dart';
import 'genkit_runtime_factory.dart';
import 'omniscope_agent_tools.dart';

/// Optional test hook that replaces the real Genkit turn.
typedef GenkitAgentTurnOverride =
    Future<String> Function({
      required AgentConnection connection,
      required String roleId,
      required List<AgentChatMessage> messages,
      OmniscopeAgentToolDeps? toolDeps,
    });

/// Runs Omniscope chat turns through in-process Genkit [defineAgent] + tools.
class GenkitAgentRunner {
  GenkitAgentRunner({
    http.Client? httpClient,
    this.turnOverride,
  }) : _factory = GenkitRuntimeFactory(httpClient: httpClient);

  final GenkitRuntimeFactory _factory;

  /// When set (tests), skips Genkit and returns this function's result.
  final GenkitAgentTurnOverride? turnOverride;

  /// Completes one assistant turn for [roleId] given the Omniscope thread
  /// (including the latest user message).
  Future<String> complete({
    required AgentConnection connection,
    required String roleId,
    required List<AgentChatMessage> messages,
    OmniscopeAgentToolDeps? toolDeps,
  }) async {
    final override = turnOverride;
    if (override != null) {
      return override(
        connection: connection,
        roleId: roleId,
        messages: messages,
        toolDeps: toolDeps,
      );
    }

    if (toolDeps == null) {
      throw GenkitAgentException(
        'Agent tools require market data. Restart the chat and try again.',
      );
    }

    final usable = messages
        .where((m) => m.role != AgentChatRole.system)
        .where((m) => m.content.trim().isNotEmpty)
        .toList(growable: false);
    if (usable.isEmpty) {
      throw GenkitAgentException('Nothing to send to the agent.');
    }

    final last = usable.last;
    if (last.role != AgentChatRole.user) {
      throw GenkitAgentException('Last message must be from the user.');
    }

    final prior = usable.sublist(0, usable.length - 1);
    final runtime = _factory.create(connection);
    final ai = runtime.ai;
    final tools = OmniscopeAgentTools.forRole(
      ai: ai,
      roleId: roleId,
      deps: toolDeps,
    );

    final agent = ai.defineAgent(
      name: 'omniscope_$roleId',
      system: AgentRolePrompts.forRoleId(roleId),
      tools: tools,
      model: runtime.model,
      use: [retry()],
      maxTurns: 8,
    );

    final history = <Message>[
      for (final m in prior)
        Message(
          role: m.role == AgentChatRole.assistant ? Role.model : Role.user,
          content: [TextPart(text: m.content)],
        ),
    ];

    final chat = history.isEmpty
        ? agent.chat()
        : agent.chat(state: SessionState(messages: history));

    try {
      final res = await chat.send(text: last.content);
      final text = res.text.trim();
      if (text.isEmpty) {
        throw GenkitAgentException('Empty response from the agent.');
      }
      return text;
    } on GenkitAgentException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      throw GenkitAgentException(
        msg.length > 240 ? '${msg.substring(0, 237)}…' : msg,
      );
    }
  }
}
