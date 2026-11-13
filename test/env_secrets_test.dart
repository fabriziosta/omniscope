import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/dotenv_asset.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/settings/env_secrets_repository.dart';
import 'package:omniscope/data/settings/user_config_keys.dart';

import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DotEnvAsset.upsert', () {
    test('updates existing keys in place and preserves comments', () {
      const raw = '''
# Local secrets
OMNISCOPE_OPENAI_API_KEY=
OMNISCOPE_GEMINI_API_KEY=old-gemini

# Crypto.com
OMNISCOPE_CRYPTO_COM_API_KEY=
''';
      final next = DotEnvAsset.upsert(raw, {
        'OMNISCOPE_OPENAI_API_KEY': 'sk-openai',
        'OMNISCOPE_GEMINI_API_KEY': 'new-gemini',
        'OMNISCOPE_CRYPTO_COM_API_SECRET': 'cdc-secret',
      });

      expect(next, contains('# Local secrets'));
      expect(next, contains('OMNISCOPE_OPENAI_API_KEY=sk-openai'));
      expect(next, contains('OMNISCOPE_GEMINI_API_KEY=new-gemini'));
      expect(next, contains('# Crypto.com'));
      expect(next, contains('OMNISCOPE_CRYPTO_COM_API_KEY='));
      expect(next, contains('OMNISCOPE_CRYPTO_COM_API_SECRET=cdc-secret'));
      expect(DotEnvAsset.parse(next)['OMNISCOPE_OPENAI_API_KEY'], 'sk-openai');
    });

    test('clears a key with an empty value', () {
      const raw = 'OMNISCOPE_OPENAI_API_KEY=sk-openai\n';
      final next = DotEnvAsset.upsert(raw, {
        'OMNISCOPE_OPENAI_API_KEY': '',
      });
      expect(next.trim(), 'OMNISCOPE_OPENAI_API_KEY=');
      expect(DotEnvAsset.parse(next).containsKey('OMNISCOPE_OPENAI_API_KEY'), isFalse);
    });
  });

  group('EnvSecretsRepository', () {
    test('config secrets overlay wins and setLlmApiKey persists', () async {
      final store = await memoryConfig(initialPrefs: {
        UserConfigKeys.legacySecrets:
            '{"OMNISCOPE_OPENAI_API_KEY":"from-prefs"}',
      });

      final repo = EnvSecretsRepository(store: store, syncEnvFile: false);
      await repo.load();

      // Asset .env may also contribute; config overlay must win for OpenAI.
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
        syncEnvFile: false,
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

    test('promotes bootstrap keys into config when missing or empty', () async {
      final store = await memoryConfig();
      await store.setSlice(UserConfigKeys.secrets, {
        'OMNISCOPE_OPENAI_API_KEY': '',
        'OMNISCOPE_GEMINI_API_KEY': 'keep-from-config',
      });

      final repo = EnvSecretsRepository(store: store, syncEnvFile: false);
      await repo.load(
        additionalBootstrap: {
          'OMNISCOPE_OPENAI_API_KEY': 'from-env',
          'OMNISCOPE_ANTHROPIC_API_KEY': 'claude-from-env',
          'OMNISCOPE_GEMINI_API_KEY': 'ignored-env-gemini',
        },
      );

      expect(repo.llmKeyFor(LlmProvider.openAi), 'from-env');
      expect(repo.llmKeyFor(LlmProvider.anthropic), 'claude-from-env');
      // Non-empty config value wins over bootstrap.
      expect(repo.llmKeyFor(LlmProvider.gemini), 'keep-from-config');

      final secrets = store.getSlice(UserConfigKeys.secrets) as Map;
      expect(secrets['OMNISCOPE_OPENAI_API_KEY'], 'from-env');
      expect(secrets['OMNISCOPE_ANTHROPIC_API_KEY'], 'claude-from-env');
      expect(secrets['OMNISCOPE_GEMINI_API_KEY'], 'keep-from-config');
    });
  });
}
