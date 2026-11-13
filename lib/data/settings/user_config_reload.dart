import '../venues/venue_catalog.dart';
import 'data_source_settings.dart';
import 'display_settings.dart';
import 'env_secrets_repository.dart';
import 'favorites_repository.dart';
import 'theme_settings.dart';
import 'user_config_store.dart';
import '../agents/agent_chat_repository.dart';
import '../agents/agents_repository.dart';
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
  VenueCatalog? venues,
}) async {
  await theme.load(store: config);
  await display.load(store: config);
  await dataSources.load(store: config);
  await favorites.load(store: config);
  await portfolio.load(store: config);
  await agents.load(store: config);
  await chats.load(store: config);
  await secrets.load(store: config);

  // Refresh live venue clients that hold credentials in memory.
  if (venues != null) {
    for (final id in venues.credentialVenueIds) {
      venues.applyCredentials(id, secrets.exchangeCredentialsFor(id));
    }
  }
}
