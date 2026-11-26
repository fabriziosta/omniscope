import '../venues/venue_catalog.dart';
import 'data_source_settings.dart';
import 'display_settings.dart';
import 'env_secrets_repository.dart';
import 'favorites_repository.dart';
import 'theme_settings.dart';
import 'user_config_bootstrap.dart';
import 'user_config_store.dart';
import '../agents/agent_app_settings.dart';
import '../agents/agent_chat_repository.dart';
import '../agents/agent_memory_repository.dart';
import '../agents/agents_repository.dart';
import '../agents/invest_interest_proposal_repository.dart';
import '../agents/llm_model_catalog.dart';
import '../agents/llm_runtime_settings.dart';
import '../agents/trade_proposal_repository.dart';
import '../portfolio/portfolio_repository.dart';

/// Re-read every config-backed repository after Import / path change.
Future<void> reloadUserConfigConsumers({
  required UserConfigStore config,
  required ThemeSettings theme,
  required DisplaySettings display,
  required DataSourceSettings dataSources,
  required EnvSecretsRepository secrets,
  required FavoritesRepository favorites,
  required PortfolioRepository portfolio,
  required AgentsRepository agents,
  required AgentChatRepository chats,
  LlmRuntimeSettings? llmRuntime,
  AgentAppSettings? agentApp,
  AgentMemoryRepository? agentMemory,
  InvestInterestProposalRepository? investInterestProposals,
  TradeProposalRepository? tradeProposals,
  VenueCatalog? venues,
  LlmModelCatalog? llmModels,
}) {
  return UserConfigBootstrap.reloadConsumers(
    config: config,
    theme: theme,
    display: display,
    dataSources: dataSources,
    secrets: secrets,
    favorites: favorites,
    portfolio: portfolio,
    agents: agents,
    chats: chats,
    llmRuntime: llmRuntime,
    agentApp: agentApp,
    agentMemory: agentMemory,
    investInterestProposals: investInterestProposals,
    tradeProposals: tradeProposals,
    venues: venues,
    llmModels: llmModels,
  );
}
