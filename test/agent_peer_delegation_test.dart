import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/genkit/agent_peer_delegation.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';

import 'support/agent_test_harness.dart';
import 'support/fake_genkit_agent_runner.dart';
import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('agent names and delegate tools', () {
    expect(
      AgentPeerDelegation.agentName('intradayTrading'),
      'omniscope_intradayTrading',
    );
    expect(
      AgentPeerDelegation.delegateToolName('intradayTrading'),
      'delegate_to_omniscope_intradayTrading',
    );
    expect(AgentPeerDelegation.orchestratorName, 'omniscope_orchestrator');
  });

  test('extractDelegatedTradeJson from tool outputs', () {
    final json = AgentPeerDelegation.extractDelegatedTradeJson([
      (
        toolName: AgentPeerDelegation.delegateToolName('intradayTrading'),
        output: {
          'response':
              'Check done.\n```json\n{"ticker":"AAPL","action":"buy",'
              '"quantity":1,"rationale":"ok","risk_approved":true}\n```',
        },
      ),
    ]);
    expect(json?['ticker'], 'AAPL');
    expect(json?['action'], 'buy');
  });

  test('extractDelegatedRoleIds preserves first-seen order', () {
    final ids = AgentPeerDelegation.extractDelegatedRoleIds([
      (
        toolName: AgentPeerDelegation.delegateToolName('marketResearch'),
        output: {'response': 'brief'},
      ),
      (
        toolName: AgentPeerDelegation.delegateToolName('intradayTrading'),
        output: {'response': 'trade'},
      ),
      (
        toolName: AgentPeerDelegation.delegateToolName('marketResearch'),
        output: {'response': 'again'},
      ),
      (
        toolName: 'getQuotes',
        output: {'ok': true},
      ),
    ]);
    expect(ids, ['marketResearch', 'intradayTrading']);
    expect(
      AgentPeerDelegation.chatMetaLabel('marketResearch'),
      'Market Research',
    );
    expect(
      AgentPeerDelegation.chatMetaLabel('cryptoSpotGuide'),
      'Crypto Spot',
    );
    expect(
      AgentPeerDelegation.chatMetaLabel('marketsLiteracy'),
      'Markets Literacy',
    );
    expect(AgentPeerDelegation.chatMetaLabel('orchestrator'), 'Orchestrator');
  });

  test('controller upserts proposal from delegated trade JSON', () async {
    final store = await memoryConfig();
    final roles = await AgentRoleCatalog.load();
    final agents = AgentsRepository(store: store, roleCatalog: roles);
    await agents.load(roleCatalog: roles);
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
    final marketData = FakeMarketDataClient();
    final tradeExecutor = RoutingTradeExecutor(
      cryptoRegistry: const CryptoExchangeRegistry([]),
      brokerRegistry: BrokerExchangeRegistry.empty,
      dataSources: dataSources,
      portfolio: portfolio,
      marketData: marketData,
    );

    final harness = await buildAgentChatController(
      store: store,
      agents: agents,
      chats: chats,
      marketData: marketData,
      tradeExecutor: tradeExecutor,
      proposals: proposals,
      activity: activity,
      cryptoRegistry: const CryptoExchangeRegistry([]),
      dataSources: dataSources,
      portfolio: portfolio,
      agentRunner: fakeGenkitAgentRunner(
        reply: 'Delegated trade check complete.',
        delegatedTradeJsonFor: (_) => {
          'ticker': 'AAPL',
          'action': 'buy',
          'quantity': 1,
          'rationale': 'test',
          'risk_approved': true,
        },
      ),
    );

    final result = await harness.controller.sendStarter(
      roleId: 'marketResearch',
      symbol: 'AAPL',
    );
    expect(result, isA<dynamic>());
    expect(proposals.proposals, isNotEmpty);
    expect(proposals.proposals.first.symbol, 'AAPL');
    expect(proposals.proposals.first.roleId, 'intradayTrading');
  });
}
