import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/brokers/alpaca/alpaca_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_com/crypto_com_exchange_client.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/market/exchange_credentials.dart';
import 'package:omniscope/data/portfolio/portfolio_catalog.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
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
        roleId: 'intradayTrading',
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
    test('canTrade is true with Practice even without live credentials',
        () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final client = CryptoComExchangeClient();
      final executor = RoutingTradeExecutor(
        cryptoRegistry: CryptoExchangeRegistry([client]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: FakeMarketDataClient(),
      );
      expect(executor.canTrade, isTrue);
      expect(executor.tradableVenues.first.id, PortfolioDescriptor.practiceId);
      expect(executor.liveVenues, isEmpty);
    });

    test('Alpaca appears in liveVenues only when credentials are set', () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();

      final pending = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry([AlpacaExchangeClient()]),
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: FakeMarketDataClient(),
      );
      expect(pending.liveVenues, isEmpty);

      final ready = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry([
          AlpacaExchangeClient(
            credentials: const ExchangeCredentials(
              apiKey: 'k',
              apiSecret: 's',
            ),
          ),
        ]),
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: FakeMarketDataClient(),
      );
      expect(ready.liveVenues.map((v) => v.id), contains('alpaca'));
    });

    test('submits Practice buy via portfolio quote', () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient(basePrice: 50);
      final executor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );

      final result = await executor.submit(
        const OrderRequest(
          exchangeId: 'practice',
          symbol: 'AAPL',
          side: OrderSide.buy,
          quantity: 2,
          clientOrderId: 'tp1',
        ),
      );
      expect(result.success, isTrue);
      expect(result.orderId, 'paper-tp1');
      expect(portfolio.state.holdings, hasLength(1));
      expect(portfolio.state.holdings.first.symbol, 'AAPL');
      expect(portfolio.state.holdings.first.shares, 2);
      expect(portfolio.state.cash, closeTo(10000 - 100, 1e-6));
    });

    test('routes placeOrder to Crypto.com when credentials set', () async {
      final store = await memoryConfig();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();

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
        portfolio: portfolio,
        marketData: FakeMarketDataClient(),
      );
      expect(executor.canTrade, isTrue);
      expect(executor.liveVenues.map((v) => v.id), contains('crypto_com'));

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

  group('AgentChatController portfolio targets', () {
    test('allows trading Run with Practice only', () async {
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
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient();

      final controller = AgentChatController(
        role: roles.byId('intradayTrading')!,
        agents: agents,
        chats: chats,
        marketData: market,
        agentRunner: fakeGenkitAgentRunner(),
        tradeExecutor: RoutingTradeExecutor(
          cryptoRegistry: const CryptoExchangeRegistry([]),
          brokerRegistry: BrokerExchangeRegistry.empty,
          dataSources: dataSources,
          portfolio: portfolio,
          marketData: market,
        ),
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
      );

      expect(controller.preferredPortfolioId(), PortfolioDescriptor.practiceId);
      // OpenAI-compatible mock body is not a full chat completion; expect
      // failure from LLM client rather than exchange block.
      final result = await controller.sendRun(symbol: 'AAPL');
      expect(result, isNot(isA<AgentChatSendBlockedNoExchange>()));
    });

    test('confirm to Practice updates paper portfolio', () async {
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
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient(basePrice: 100);

      final executor = RoutingTradeExecutor(
        cryptoRegistry: const CryptoExchangeRegistry([]),
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );

      final controller = AgentChatController(
        role: roles.byId('intradayTrading')!,
        agents: agents,
        chats: chats,
        marketData: market,
        agentRunner: fakeGenkitAgentRunner(),
        tradeExecutor: executor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: const CryptoExchangeRegistry([]),
        dataSources: dataSources,
        portfolio: portfolio,
      );

      final proposal = TradeProposal(
        id: 'tp_paper',
        roleId: 'intradayTrading',
        exchangeId: 'practice',
        symbol: 'AAPL',
        side: TradeProposalSide.buy,
        quantity: 3,
        rationale: 'test',
        riskApproved: true,
        status: TradeProposalStatus.pending,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await proposals.upsert(proposal);

      final err = await controller.confirmProposal(
        proposal.id,
        targetPortfolioId: PortfolioDescriptor.practiceId,
      );
      expect(err, isNull);
      expect(proposals.byId(proposal.id)!.status, TradeProposalStatus.executed);
      expect(proposals.byId(proposal.id)!.orderId, 'paper-tp_paper');
      expect(portfolio.state.holdings.first.shares, 3);
    });

    test('ambiguous confirm without target fails until portfolio chosen',
        () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      await agents.connect(
        roleId: 'intradayTrading',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        // No default portfolio.
      );
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();
      final market = FakeMarketDataClient(basePrice: 100);

      var sawCreate = false;
      final httpClient = MockClient((request) async {
        if (request.url.path.contains('create-order')) {
          sawCreate = true;
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
        portfolio: portfolio,
        marketData: market,
      );

      final controller = AgentChatController(
        role: roles.byId('intradayTrading')!,
        agents: agents,
        chats: chats,
        marketData: market,
        agentRunner: fakeGenkitAgentRunner(),
        tradeExecutor: executor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: registry,
        dataSources: dataSources,
        portfolio: portfolio,
      );

      expect(controller.needsPortfolioPicker, isTrue);
      expect(controller.preferredPortfolioId(), isNull);

      final proposal = TradeProposal(
        id: 'tp_ambig',
        roleId: 'intradayTrading',
        exchangeId: 'practice',
        symbol: 'BTC_USD',
        side: TradeProposalSide.buy,
        quantity: 0.02,
        rationale: 'test',
        riskApproved: true,
        status: TradeProposalStatus.pending,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await proposals.upsert(proposal);

      final blocked = await controller.confirmProposal(proposal.id);
      expect(blocked, 'Choose a portfolio before confirming.');
      expect(sawCreate, isFalse);

      final err = await controller.confirmProposal(
        proposal.id,
        targetPortfolioId: 'crypto_com',
      );
      expect(err, isNull);
      expect(sawCreate, isTrue);
      expect(proposals.byId(proposal.id)!.status, TradeProposalStatus.executed);
      expect(proposals.byId(proposal.id)!.exchangeId, 'crypto_com');
    });

    test('confirm submits via TradeExecutor to live when default set', () async {
      final store = await memoryConfig();
      final roles = await AgentRoleCatalog.load();
      final agents = AgentsRepository(store: store, roleCatalog: roles);
      await agents.load(roleCatalog: roles);
      await agents.connect(
        roleId: 'intradayTrading',
        llmProvider: LlmProvider.openAi,
        apiKey: 'sk',
        modelId: 'gpt',
        autopilotExchangeId: 'crypto_com',
      );
      final chats = AgentChatRepository(store: store);
      await chats.load();
      final proposals = TradeProposalRepository(store: store);
      await proposals.load();
      final activity = AgentActivityRepository(store: store);
      await activity.load();
      final dataSources = DataSourceSettings(store: store);
      await dataSources.load();
      final portfolio = PortfolioRepository(store: store);
      await portfolio.load();

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
      final market = FakeMarketDataClient();
      final executor = RoutingTradeExecutor(
        cryptoRegistry: registry,
        brokerRegistry: BrokerExchangeRegistry.empty,
        dataSources: dataSources,
        portfolio: portfolio,
        marketData: market,
      );

      final controller = AgentChatController(
        role: roles.byId('intradayTrading')!,
        agents: agents,
        chats: chats,
        marketData: market,
        agentRunner: fakeGenkitAgentRunner(),
        tradeExecutor: executor,
        proposals: proposals,
        activity: activity,
        cryptoRegistry: registry,
        dataSources: dataSources,
        portfolio: portfolio,
      );

      expect(controller.preferredPortfolioId(), 'crypto_com');
      expect(controller.needsPortfolioPicker, isFalse);

      final proposal = TradeProposal(
        id: 'tp_test',
        roleId: 'intradayTrading',
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
