import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/shell_navigation.dart';
import '../../data/agents/agent_chat_repository.dart';
import '../../data/agents/agent_launch.dart';
import '../../data/agents/agents_repository.dart';
import '../../data/agents/chat_agent_settings.dart';
import '../../data/agents/llm_model_router.dart';
import '../../data/agents/llm_runtime_settings.dart';
import '../../data/crypto/crypto_exchange_registry.dart';
import '../../data/portfolio/portfolio_catalog.dart';
import '../../data/settings/env_secrets_repository.dart';
import '../../data/trading/broker_exchange_registry.dart';
import '../../data/trading/trade_executor.dart';
import '../../widgets/app_toast.dart';

/// Shared navigation for opening orchestrator chat from any screen.
class AgentLaunchActions {
  AgentLaunchActions._();

  /// Serializes CTA launches so double-taps cannot race-create two chats.
  static Future<void>? _launchInFlight;

  /// Create/open a chat on the Agents tab (master–detail), optionally auto-run.
  ///
  /// When [chatId] is omitted, reuses an existing **empty** chat with the same
  /// [title] (intent draft) instead of always creating a duplicate.
  static Future<void> openAgentChat(
    BuildContext context, {
    String? chatId,
    String? title,
    String? starterRoleId,
    String? initialSymbol,
    String? initialExchangeId,
    bool autoRun = false,
    String? side,
    double? quantity,
  }) async {
    final chats = context.read<AgentChatRepository>();
    final shellNav = context.read<ShellNavigationController>();
    final resolvedTitle = _resolveCreateTitle(
      title: title,
      initialSymbol: initialSymbol,
    );

    String id;
    final explicitId = chatId?.trim();
    if (explicitId != null && explicitId.isNotEmpty) {
      id = explicitId;
    } else {
      final reusable = resolvedTitle == null
          ? null
          : chats.emptyChatWithTitle(resolvedTitle);
      if (reusable != null) {
        id = reusable.chatId;
        await chats.touchChat(id);
      } else {
        id = (await chats.createChat(title: resolvedTitle)).chatId;
      }
    }

    final sym = initialSymbol?.trim();
    if (sym != null && sym.isNotEmpty) {
      await chats.pinFocusSymbols(id, [sym]);
    }

    // Clear Asset detail (and any other tab overlays) then open Agents. Do not
    // use [context] after this — popping may unmount the calling route.
    shellNav.goToAgentChat(
      chatId: id,
      starterRoleId: starterRoleId,
      symbol: initialSymbol,
      initialExchangeId: initialExchangeId,
      autoRun: autoRun,
      initialSide: side,
      initialQuantity: quantity,
    );
  }

  /// Resolve intent → starter role and open an orchestrator chat (reuse empty).
  static Future<void> launch(
    BuildContext context, {
    required AgentLaunchIntent intent,
    String? symbol,
    String? exchangeId,
    String? side,
    double? quantity,
  }) async {
    final previous = _launchInFlight;
    if (previous != null) {
      await previous;
      if (!context.mounted) return;
    }
    final gate = Completer<void>();
    _launchInFlight = gate.future;
    try {
      await _launchBody(
        context,
        intent: intent,
        symbol: symbol,
        exchangeId: exchangeId,
        side: side,
        quantity: quantity,
      );
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_launchInFlight, gate.future)) {
        _launchInFlight = null;
      }
    }
  }

  static Future<void> _launchBody(
    BuildContext context, {
    required AgentLaunchIntent intent,
    String? symbol,
    String? exchangeId,
    String? side,
    double? quantity,
  }) async {
    final secrets = context.read<EnvSecretsRepository>();
    final runtime = context.read<LlmRuntimeSettings>();
    if (!LlmModelRouter.hasAnyEndpoint(
      runtime: runtime,
      keys: secrets.llmKeys,
    )) {
      showAppToast(
        context,
        title: 'Add an LLM key',
        description:
            'Add a provider under Settings → Agents, then try again.',
      );
      context.read<ShellNavigationController>().goToSettings(
            sectionId: 'connections',
          );
      return;
    }

    final agents = context.read<AgentsRepository>();
    final chats = context.read<AgentChatRepository>();
    final sym = symbol?.trim();
    final portfolioLabel = intent.isPortfolioLevel
        ? _portfolioLabel(context, exchangeId)
        : null;
    final chatTitle = intent.chatTitle(
      symbol: sym,
      portfolioLabel: portfolioLabel,
    );
    final reusable = chats.emptyChatWithTitle(chatTitle);
    final chatSettings =
        reusable?.agentSettings ?? ChatAgentSettings.defaults;
    final applicable = AgentLaunchResolver.rolesForIntent(
      availableRoles: agents.availableRoles,
      intent: intent,
    );
    final enabled = [
      for (final r in applicable)
        if (chatSettings.isRoleEnabled(r.id)) r,
    ];
    if (enabled.isEmpty) {
      showAppToast(
        context,
        description: 'No agent is available for this action yet.',
        destructive: true,
      );
      context.read<ShellNavigationController>().goToAgents();
      return;
    }

    final preferred = enabled.first;
    // Reuse empty intent chat when present; draft the composer — user sends.
    await openAgentChat(
      context,
      title: chatTitle,
      starterRoleId: preferred.id,
      initialSymbol: sym,
      initialExchangeId: exchangeId,
      autoRun: false,
      side: side,
      quantity: quantity,
    );
  }

  static String? _resolveCreateTitle({
    String? title,
    String? initialSymbol,
  }) {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final sym = initialSymbol?.trim();
    if (sym != null && sym.isNotEmpty) return sym;
    return null;
  }

  static String _portfolioLabel(BuildContext context, String? exchangeId) {
    final id = exchangeId?.trim();
    if (id == null ||
        id.isEmpty ||
        id == PortfolioDescriptor.practiceId) {
      return 'Practice';
    }
    try {
      final venue = context.read<TradeExecutor>().venueForId(id);
      if (venue != null) return venue.displayName;
    } catch (_) {
      // Provider may be absent in isolated tests.
    }
    try {
      final crypto = context.read<CryptoExchangeRegistry>().clientForId(id);
      if (crypto != null) return crypto.displayName;
    } catch (_) {}
    try {
      final broker = context.read<BrokerExchangeRegistry>().clientForId(id);
      if (broker != null) return broker.displayName;
    } catch (_) {}
    return id;
  }
}
