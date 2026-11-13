import '../agents/agent_chat_repository.dart';
import '../agents/agents_repository.dart';
import '../crypto/crypto_com/crypto_com_exchange_client.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../portfolio/portfolio_repository.dart';
import 'data_source_settings.dart';
import 'display_settings.dart';
import 'env_secrets_repository.dart';
import 'favorites_repository.dart';
import 'theme_settings.dart';
import 'user_config_store.dart';

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
  CryptoExchangeRegistry? cryptoRegistry,
}) async {
  await theme.load(store: config);
  await display.load(store: config);
  await dataSources.load(store: config);
  await favorites.load(store: config);
  await portfolio.load(store: config);
  await agents.load(store: config);
  await chats.load(store: config);
  await secrets.load(store: config);

  // Refresh live exchange clients that hold credentials in memory.
  if (cryptoRegistry != null) {
    for (final client in cryptoRegistry.exchanges) {
      if (client is CryptoComExchangeClient) {
        client.setCredentials(
          secrets.exchangeCredentialsFor(CryptoComExchangeClient.meta.id),
        );
      }
    }
  }
}
