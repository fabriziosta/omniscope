import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/llm_chat_client.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/order_models.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/features/agents/agent_chat_controller.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TradeProposalParser', () {
    test('extracts fenced JSON trade block', () {
      const text = '''
Desk note: buy a little.

```json
{"ticker":"BTC_USD","action":"buy","quantity":0.01,"rationale":"dip","risk_approved":true}
```
''';
      final map = TradeProposalParser.extractJsonMap(text);
      expect(map, isNotNull);
      final proposal = TradeProposal.fromLlmJson(
        map!,
        roleId: 'hedgeFundDesk',
        exchangeId: 'crypto_com',
      );
      expect(proposal.symbol, 'BTC_USD');
      expect(proposal.side, TradeProposalSide.buy);
      expect(proposal.quantity, 0.01);
      expect(proposal.riskApproved, isTrue);
      expect(proposal.isActionable, isTrue);
    });

    test('hold is not actionable', () {
      final proposal = TradeProposal.fromLlmJson(
        {
          'ticker': 'ETH_USD',
          'action': 'hold',
          'quantity': 0,
          'rationale': 'wait',
          'risk_approved': false,
        },
        roleId: 'intradayTrading',
        exchangeId: 'crypto_com',
      );
      expect(proposal.side, TradeProposalSide.hold);
      expect(proposal.isActionable, isFalse);
    });
  });

  group('RoutingTradeExecutor', () {
    test('canTrade is false without credentials', () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final client = CryptoComExchangeClient();
      final executor = RoutingTradeExecutor(
        cryptoRegistry: CryptoExchangeRegistry([client]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
      );
      expect(executor.canTrade, isFalse);
      expect(executor.tradableVenues, isEmpty);
    });

    test('routes placeOrder to Crypto.com when credentials set', () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();

      var sawCreate = false;
      final httpClient = MockClient((request) async {
        if (request.url.path.contains('create-order')) {
          sawCreate = true;
          return http.Response(
            '{"code":0,"result":{"order_id":"ord-1","status":"ACTIVE"}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"code":0,"result":{}}', 200);
      });

      final client = CryptoComExchangeClient(
        httpClient: httpClient,
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      );
      expect(client.canPlaceOrders, isTrue);

      final executor = RoutingTradeExecutor(
        cryptoRegistry: CryptoExchangeRegistry([client]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
      );
      expect(executor.canTrade, isTrue);

      final result = await executor.submit(
        const OrderRequest(
          exchangeId: 'crypto_com',
          symbol: 'BTC_USD',
          side: OrderSide.buy,
          quantity: 0.01,
        ),
      );
      expect(sawCreate, isTrue);
      expect(result.success, isTrue);
      expect(result.orderId, 'ord-1');
    });
  });

  group('AgentChatController trade gate', () {
    test('blocks trading Run when no exchange is tradable', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      await agents.connect(
        roleId: 'intradayTrading',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
      );
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();

      final controller = AgentChatController(
        role: roles.byId('intradayTrading')!,
        agents: agents,
        chats: chats,
        marketData: FakeMarketDataClient(
          emptyQuotes: true,
          emptyHistory: true,
        ),
        llm: LlmChatClient(
          httpClient: MockClient((_) async => http.Response('{}', 500)),
        ),
        tradeExecutor: RoutingTradeExecutor(
          cryptoRegistry: const CryptoExchangeRegistry([]),
          brokerRegistry: BrokerExchangeRegistry.empty,
          dataSources: dataSources,
        ),
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
      );

      final result = await controller.sendRun(symbol: 'BTC_USD');
      expect(result, isA<AgentChatSendBlockedNoExchange>());
      expect(activity.events, isNotEmpty);
      expect(
        activity.events.first.kind.name,
        'runBlockedNoExchange',
      );
    });

    test('confirm submits via TradeExecutor and never needs paper', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      await agents.connect(
        roleId: 'hedgeFundDesk',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
      );
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();

      final httpClient = MockClient((request) async {
        if (request.url.path.contains('create-order')) {
          return http.Response(
            '{"code":0,"result":{"order_id":"live-9"}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"code":0,"result":{"data":[]}}', 200);
      });
      final crypto = CryptoComExchangeClient(
        httpClient: httpClient,
        credentials: const ExchangeCredentials(
          apiKey: 'key',
          apiSecret: 'secret',
        ),
      );
      final registry = CryptoExchangeRegistry([crypto]);
      final executor = RoutingTradeExecutor(
        cryptoRegistry: registry,
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
      );

      final controller = AgentChatController(
        role: roles.byId('hedgeFundDesk')!,
        agents: agents,
        chats: chats,
        marketData: FakeMarketDataClient(
          emptyQuotes: true,
          emptyHistory: true,
        ),
        llm: LlmChatClient(
          httpClient: MockClient((_) async => http.Response('{}', 500)),
        ),
        tradeExecutor: executor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: registry,
        dataSources: dataSources,
      );

      final proposal = TradeProposal(
        id: 'tp_test',
        roleId: 'hedgeFundDesk',
        exchangeId: 'crypto_com',
        symbol: 'BTC_USD',
        side: TradeProposalSide.buy,
        quantity: 0.02,
        rationale: 'test',
        riskApproved: true,
        status: TradeProposalStatus.pending,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await proposals.upsert(proposal);

      final err = await controller.confirmProposal(proposal.id);
      expect(err, isNull);
      expect(proposals.byId(proposal.id)!.status, TradeProposalStatus.executed);
      expect(proposals.byId(proposal.id)!.orderId, 'live-9');
    });
  });

  test('Crypto.com orderResultFromCreate maps order id', () {
    final result = CryptoComExchangeClient.orderResultFromCreate({
      'code': 0,
      'result': {'order_id': 'abc', 'status': 'ACTIVE'},
    });
    expect(result.success, isTrue);
    expect(result.orderId, 'abc');
    expect(result.rawStatus, 'ACTIVE');
  });
}
