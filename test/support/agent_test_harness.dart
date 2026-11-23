import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_memory_repository.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/genkit_agent_runner.dart';
import 'package:omniscope/data/agents/invest_interest_proposal_repository.dart';
import 'package:omniscope/data/agents/llm_runtime_settings.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/market_data_client.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/favorites_repository.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
import 'package:omniscope/data/settings/user_config_store.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_controller.dart';

import 'fake_genkit_agent_runner.dart';

/// Shared LLM key + light/heavy prefs + agent app settings for tests.
Future<({
  LlmRuntimeSettings llmRuntime,
  AgentAppSettings appSettings,
  EnvSecretsRepository secrets,
})> seedLlmStack(
  UserConfigStore store, {
  LlmProvider provider = LlmProvider.openAi,
  String apiKey = 'sk-test',
  String lightModelId = 'gpt-test-light',
  String heavyModelId = 'gpt-test-heavy',
}) async {
  final llmRuntime = LlmRuntimeSettings(store: store);
  await llmRuntime.load();
  await llmRuntime.upsert(
    LlmProviderRuntimePrefs(
      provider: provider,
      lightModelId: lightModelId,
      heavyModelId: heavyModelId,
      priority: 1,
    ),
  );
  final appSettings = AgentAppSettings(store: store);
  await appSettings.load();
  final secrets = EnvSecretsRepository(store: store);
  await secrets.load();
  await secrets.setLlmApiKey(provider, apiKey);
  return (
    llmRuntime: llmRuntime,
    appSettings: appSettings,
    secrets: secrets,
  );
}

/// Builds an orchestrator [AgentChatController] for tests.
Future<({
  AgentChatController controller,
  String chatId,
  LlmRuntimeSettings llmRuntime,
  AgentAppSettings appSettings,
  EnvSecretsRepository secrets,
})> buildAgentChatController({
  required UserConfigStore store,
  required AgentsRepository agents,
  required AgentChatRepository chats,
  required MarketDataClient marketData,
  required TradeExecutor tradeExecutor,
  required TradeProposalRepository proposals,
  required AgentActivityRepository activity,
  required CryptoExchangeRegistry cryptoRegistry,
  required DataSourceSettings dataSources,
  required PortfolioRepository portfolio,
  GenkitAgentRunner? agentRunner,
  FavoritesRepository? favorites,
  MandateSettings? mandate,
  AgentMemoryRepository? agentMemory,
  InvestInterestProposalRepository? investInterestProposals,
  String reply = 'Test agent reply.',
  Map<String, dynamic>? Function(String lastUser)? delegatedTradeJsonFor,
}) async {
  final seeded = await seedLlmStack(store);

  final chat = await chats.createChat(title: 'Test');
  final controller = AgentChatController(
    chatId: chat.chatId,
    agents: agents,
    chats: chats,
    marketData: marketData,
    agentRunner: agentRunner ??
        fakeGenkitAgentRunner(
          reply: reply,
          delegatedTradeJsonFor: delegatedTradeJsonFor,
        ),
    tradeExecutor: tradeExecutor,
    proposals: proposals,
    activity: activity,
    cryptoRegistry: cryptoRegistry,
    dataSources: dataSources,
    portfolio: portfolio,
    secrets: seeded.secrets,
    llmRuntime: seeded.llmRuntime,
    appSettings: seeded.appSettings,
    favorites: favorites,
    mandate: mandate,
    agentMemory: agentMemory,
    investInterestProposals: investInterestProposals,
  );
  return (
    controller: controller,
    chatId: chat.chatId,
    llmRuntime: seeded.llmRuntime,
    appSettings: seeded.appSettings,
    secrets: seeded.secrets,
  );
}
