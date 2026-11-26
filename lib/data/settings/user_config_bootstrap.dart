import '../agents/agent_app_settings.dart';
import '../agents/agent_chat_repository.dart';
import '../agents/agent_memory_repository.dart';
import '../agents/agents_repository.dart';
import '../agents/invest_interest_proposal_repository.dart';
import '../agents/llm_model_catalog.dart';
import '../agents/llm_runtime_settings.dart';
import '../agents/trade_proposal_repository.dart';
import '../notifications/app_notification_repository.dart';
import '../portfolio/portfolio_repository.dart';
import '../venues/venue_catalog.dart';
import 'data_source_settings.dart';
import 'display_settings.dart';
import 'env_secrets_repository.dart';
import 'favorites_repository.dart';
import 'theme_settings.dart';
import 'user_config_keys.dart';
import 'user_config_migrations.dart';
import 'user_config_store.dart';

/// Shared post-load migration steps for cold start and Import reload.
abstract final class UserConfigBootstrap {
  /// Promote legacy connections / global flags into current slices (v1→v2 once).
  ///
  /// Call after [AgentsRepository.load], [LlmRuntimeSettings.load],
  /// [AgentAppSettings.load], and [AgentChatRepository.load].
  static Future<void> runChatAndLlmMigrations({
    required UserConfigStore config,
    required AgentsRepository agents,
    required LlmRuntimeSettings llmRuntime,
    required AgentAppSettings agentApp,
    required AgentChatRepository chats,
    LlmModelCatalog? llmModels,
  }) async {
    await UserConfigMigrations.runOnce(
      config: config,
      agents: agents,
      llmRuntime: llmRuntime,
      agentApp: agentApp,
      chats: chats,
      llmModels: llmModels,
    );
  }

  /// Re-read every config-backed repository after Import / path change.
  static Future<void> reloadConsumers({
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
    AppNotificationRepository? notifications,
    VenueCatalog? venues,
    LlmModelCatalog? llmModels,
  }) async {
    await theme.load(store: config);
    await display.load(store: config);
    await dataSources.load(store: config);
    await favorites.load(store: config);
    await portfolio.load(store: config);
    await agents.load(store: config);
    await chats.load(store: config);
    await secrets.load(store: config);
    if (llmRuntime != null) await llmRuntime.load(store: config);
    if (agentApp != null) await agentApp.load(store: config);
    if (llmRuntime != null && agentApp != null) {
      await runChatAndLlmMigrations(
        config: config,
        agents: agents,
        llmRuntime: llmRuntime,
        agentApp: agentApp,
        chats: chats,
        llmModels: llmModels,
      );
    } else if (UserConfigMigrations.readVersion(config) <
        UserConfigKeys.currentVersion) {
      await chats.migrateGlobalMandateIfNeeded();
      if (agentApp != null) {
        await chats.migrateGlobalAgentSettingsIfNeeded(agentApp);
      }
    } else {
      chats.setWriteLegacyRoleIdKeys(false);
    }
    if (agentMemory != null) await agentMemory.load(store: config);
    if (investInterestProposals != null) {
      await investInterestProposals.load(store: config);
    }
    if (tradeProposals != null) await tradeProposals.load(store: config);
    if (notifications != null) await notifications.load(store: config);

    if (venues != null) {
      for (final id in venues.credentialVenueIds) {
        venues.applyCredentials(id, secrets.exchangeCredentialsFor(id));
      }
    }
  }
}
