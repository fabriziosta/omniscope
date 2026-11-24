import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_middleware/agents.dart';
import 'package:http/http.dart' as http;

import '../agent_role_prompts.dart';
import '../chat_models.dart';
import '../llm_model_router.dart';
import '../llm_runtime_settings.dart';
import '../models.dart';
import '../trade_proposal.dart';
import 'agent_peer_delegation.dart';
import 'genkit_runtime_factory.dart';
import 'omniscope_agent_tools.dart';

/// Result of one in-process Genkit chat turn.
class GenkitAgentTurnResult {
  const GenkitAgentTurnResult({
    required this.reply,
    this.delegatedTradeJson,
    this.delegatedTradeRoleId,
    this.delegatedRoleIds = const [],
  });

  /// Orchestrator final text (user-visible).
  final String reply;

  /// Trade JSON extracted from a delegated `intradayTrading` sub-agent, if any.
  final Map<String, dynamic>? delegatedTradeJson;

  /// Role that produced [delegatedTradeJson] (usually `intradayTrading`).
  final String? delegatedTradeRoleId;

  /// Specialty role ids the `agents()` middleware delegated to this turn.
  ///
  /// Empty when the orchestrator answered without calling a specialty.
  final List<String> delegatedRoleIds;
}

/// Specialty role registered for orchestrator delegation.
class GenkitSpecialtySpec {
  const GenkitSpecialtySpec({
    required this.roleId,
    required this.description,
    required this.workload,
    this.modelIdOverride,
  });

  final String roleId;
  final String description;
  final AgentWorkload workload;
  final String? modelIdOverride;
}

/// Optional test hook that replaces the real Genkit turn.
typedef GenkitAgentTurnOverride =
    Future<GenkitAgentTurnResult> Function({
      required LlmResolvedEndpoint endpoint,
      required List<AgentChatMessage> messages,
      OmniscopeAgentToolDeps? toolDeps,
      List<GenkitSpecialtySpec> specialties,
      LlmRuntimeSettings? runtime,
    });

/// Runs Omniscope chat turns through an in-process orchestrator + specialists.
class GenkitAgentRunner {
  GenkitAgentRunner({
    http.Client? httpClient,
    this.turnOverride,
  }) : _factory = GenkitRuntimeFactory(httpClient: httpClient);

  final GenkitRuntimeFactory _factory;

  /// When set (tests), skips Genkit and returns this function's result.
  final GenkitAgentTurnOverride? turnOverride;

  /// Completes one assistant turn via `omniscope_orchestrator`.
  ///
  /// [specialties] are enabled catalog roles registered as sub-agents on the
  /// same Genkit instance (in-process `agents()` middleware — no HTTP).
  Future<GenkitAgentTurnResult> complete({
    required LlmResolvedEndpoint endpoint,
    required List<AgentChatMessage> messages,
    OmniscopeAgentToolDeps? toolDeps,
    List<GenkitSpecialtySpec> specialties = const [],
    LlmRuntimeSettings? runtime,
  }) async {
    final override = turnOverride;
    if (override != null) {
      return override(
        endpoint: endpoint,
        messages: messages,
        toolDeps: toolDeps,
        specialties: specialties,
        runtime: runtime,
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
    final built = _factory.create(endpoint);
    final ai = built.ai;
    final primaryModel = built.model;

    final peerNames = <String>[];
    for (final spec in specialties) {
      final peerTools = OmniscopeAgentTools.forRole(
        ai: ai,
        roleId: spec.roleId,
        deps: toolDeps,
      );
      final weight = spec.workload.preferredModelWeight;
      final specialtyModelId = spec.modelIdOverride?.trim().isNotEmpty == true
          ? spec.modelIdOverride!.trim()
          : _sameProviderModelId(
              runtime: runtime,
              provider: endpoint.provider,
              weight: weight,
            );
      ai.defineAgent(
        name: AgentPeerDelegation.agentName(spec.roleId),
        description: spec.description,
        system: AgentRolePrompts.forRoleId(
          spec.roleId,
          investInterestSymbols: toolDeps.investInterestSymbols,
          focusSymbols: toolDeps.focusSymbols,
          mandateSummary: toolDeps.mandate?.toAgentSummary(),
          memorySummary: toolDeps.memorySummary,
          answerMood: toolDeps.answerMood,
          answerMoodNote: toolDeps.answerMoodNote,
          autopilotEnabled: toolDeps.autopilotEnabled,
          memoryEnabled: toolDeps.memoryEnabled,
        ),
        tools: peerTools,
        model: _factory.specialtyModel(
          primary: endpoint,
          primaryModel: primaryModel,
          specialtyModelId: specialtyModelId,
        ),
        use: [retry()],
        maxTurns: 8,
      );
      peerNames.add(AgentPeerDelegation.agentName(spec.roleId));
    }

    final middleware = <GenerateMiddlewareRef>[
      retry(),
      if (peerNames.isNotEmpty)
        agents(
          agents: peerNames,
          maxDelegations: 5,
          historyLength: 2,
        ),
    ];

    final agent = ai.defineAgent(
      name: AgentPeerDelegation.orchestratorName,
      description:
          'Routes user requests to the right Omniscope specialty agents '
          'and synthesizes a clear answer.',
      system: AgentRolePrompts.orchestratorSystem(
        investInterestSymbols: toolDeps.investInterestSymbols,
        focusSymbols: toolDeps.focusSymbols,
        mandateSummary: toolDeps.mandate?.toAgentSummary(),
        memorySummary: toolDeps.memorySummary,
        specialtyRoleIds: [for (final s in specialties) s.roleId],
        answerMood: toolDeps.answerMood,
        answerMoodNote: toolDeps.answerMoodNote,
        autopilotEnabled: toolDeps.autopilotEnabled,
        memoryEnabled: toolDeps.memoryEnabled,
      ),
      tools: const [],
      model: primaryModel,
      use: middleware,
      maxTurns: 10,
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

      final toolOutputs = _toolOutputsFromMessages(res.messages);
      final delegatedRoleIds =
          AgentPeerDelegation.extractDelegatedRoleIds(toolOutputs);
      final delegatedJson =
          AgentPeerDelegation.extractDelegatedTradeJson(toolOutputs);

      // Also accept trade JSON in the orchestrator reply when it forwards it.
      final replyJson = TradeProposalParser.extractJsonMap(text);
      final tradeJson = delegatedJson ?? replyJson;

      return GenkitAgentTurnResult(
        reply: text,
        delegatedTradeJson: tradeJson,
        delegatedTradeRoleId: tradeJson != null ? 'intradayTrading' : null,
        delegatedRoleIds: delegatedRoleIds,
      );
    } on GenkitAgentException {
      rethrow;
    } catch (e) {
      throw GenkitAgentException.fromProviderError(e);
    }
  }

  static String? _sameProviderModelId({
    required LlmRuntimeSettings? runtime,
    required LlmProvider provider,
    required ModelWeight weight,
  }) {
    final prefs = runtime?.prefsFor(provider);
    return prefs?.resolvedModelId(weight);
  }

  static List<({String toolName, Object? output})> _toolOutputsFromMessages(
    List<Message> messages,
  ) {
    final out = <({String toolName, Object? output})>[];
    for (final m in messages) {
      if (m.role != Role.tool) continue;
      for (final part in m.content) {
        final tr = part.toolResponse;
        if (tr == null) continue;
        out.add((toolName: tr.name, output: tr.output));
      }
    }
    return out;
  }
}
