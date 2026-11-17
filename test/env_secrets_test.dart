import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnvSecretsRepository', () {
    test('config secrets load and setLlmApiKey persists', () async {
      final store = await memoryConfig(initialPrefs: {
        UserConfigKeys.legacySecrets:
            '{"OMNISCOPE_OPENAI_API_KEY":"from-prefs"}',
      });

      final repo = EnvSecretsRepository(store: store);
      await repo.load();

      expect(repo.llmKeyFor(LlmProvider.openAi), 'from-prefs');

      await repo.setLlmApiKey(LlmProvider.gemini, 'gemini-from-ui');
      expect(repo.llmKeyFor(LlmProvider.gemini), 'gemini-from-ui');

      final secrets = store.getSlice(UserConfigKeys.secrets);
      expect(secrets, isA<Map>());
      expect(
        (secrets as Map)['OMNISCOPE_GEMINI_API_KEY'],
        'gemini-from-ui',
      );
    });

    test('setExchangeCredentials updates Crypto.com and notifies callback',
        () async {
      final store = await memoryConfig();
      ExchangeCredentials? seen;
      final repo = EnvSecretsRepository(
        store: store,
        onExchangeCredentialsChanged: (id, creds) {
          expect(id, 'crypto_com');
          seen = creds;
        },
      );
      await repo.load();

      await repo.setExchangeCredentials(
        'crypto_com',
        const ExchangeCredentials(
          apiKey: 'k',
          apiSecret: 's',
          apiToken: 't',
        ),
      );

      final creds = repo.exchangeCredentialsFor('crypto_com');
      expect(creds.apiKey, 'k');
      expect(creds.apiSecret, 's');
      expect(creds.apiToken, 't');
      expect(creds.isConfigured, isTrue);
      expect(seen?.apiKey, 'k');
      expect(seen?.apiSecret, 's');

      await repo.clearExchangeCredentials('crypto_com');
      expect(repo.exchangeCredentialsFor('crypto_com').isConfigured, isFalse);
      expect(seen?.isConfigured, isFalse);
    });

    test('empty config values clear in-memory keys', () async {
      final store = await memoryConfig();
      await store.setSlice(UserConfigKeys.secrets, {
        'OMNISCOPE_OPENAI_API_KEY': 'sk-openai',
        'OMNISCOPE_GEMINI_API_KEY': '',
      });

      final repo = EnvSecretsRepository(store: store);
      await repo.load();

      expect(repo.llmKeyFor(LlmProvider.openAi), 'sk-openai');
      expect(repo.llmKeyFor(LlmProvider.gemini), isNull);
    });
  });
}
