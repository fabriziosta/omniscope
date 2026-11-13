import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_role_catalog.dart';
import 'package:omniscope/data/agents/agents_repository.dart';
import 'package:omniscope/data/agents/models.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/portfolio/portfolio_catalog.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/trading/broker_exchange_registry.dart';
import 'package:omniscope/data/trading/trade_executor.dart';
import 'package:omniscope/data/trading/trade_proposal_actions.dart';

import 'support/fake_market_data_client.dart';
import 'support/memory_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
      ({
        TradeProposalActions actions,
        TradeProposalRepository proposals,
        AgentActivityRepository activity,
        PortfolioRepository portfolio,
      })> harness() async {
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
    final actions = TradeProposalActions(
      agents: agents,
      proposals: proposals,
      activity: activity,
      tradeExecutor: executor,
    );
    return (
      actions: actions,
      proposals: proposals,
      activity: activity,
      portfolio: portfolio,
    );
  }

  test('confirm accepts pending proposal into Practice', () async {
    final h = await harness();
    final proposal = TradeProposal(
      id: 'tp_actions_ok',
      roleId: 'hedgeFundDesk',
      exchangeId: 'practice',
      symbol: 'AAPL',
      side: TradeProposalSide.buy,
      quantity: 2,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.confirm(
      proposal.id,
      targetPortfolioId: PortfolioDescriptor.practiceId,
    );
    expect(err, isNull);
    expect(h.proposals.byId(proposal.id)!.status, TradeProposalStatus.executed);
    expect(
      h.proposals.byId(proposal.id)!.status.dashboardLabel,
      'Accepted',
    );
    expect(h.portfolio.state.holdings.first.shares, 2);
    expect(
      h.activity.events.any((e) => e.kind == AgentActivityKind.proposalConfirmed),
      isTrue,
    );
    expect(
      h.activity.events.any((e) => e.kind == AgentActivityKind.orderAck),
      isTrue,
    );
  });

  test('dismiss refuses pending proposal', () async {
    final h = await harness();
    final proposal = TradeProposal(
      id: 'tp_actions_dismiss',
      roleId: 'hedgeFundDesk',
      exchangeId: 'practice',
      symbol: 'MSFT',
      side: TradeProposalSide.sell,
      quantity: 1,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 2),
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.dismiss(proposal.id);
    expect(err, isNull);
    expect(
      h.proposals.byId(proposal.id)!.status,
      TradeProposalStatus.dismissed,
    );
    expect(
      h.proposals.byId(proposal.id)!.status.dashboardLabel,
      'Refused',
    );
    expect(
      h.activity.events.any((e) => e.kind == AgentActivityKind.proposalDismissed),
      isTrue,
    );
  });

  test('pendingActionable excludes holds', () async {
    final h = await harness();
    await h.proposals.upsert(
      TradeProposal(
        id: 'tp_hold',
        roleId: 'hedgeFundDesk',
        exchangeId: 'practice',
        symbol: 'AAPL',
        side: TradeProposalSide.hold,
        quantity: 0,
        rationale: 'wait',
        riskApproved: false,
        status: TradeProposalStatus.pending,
        createdAt: DateTime.utc(2026, 1, 3),
      ),
    );
    await h.proposals.upsert(
      TradeProposal(
        id: 'tp_buy',
        roleId: 'hedgeFundDesk',
        exchangeId: 'practice',
        symbol: 'AAPL',
        side: TradeProposalSide.buy,
        quantity: 1,
        rationale: 'go',
        riskApproved: true,
        status: TradeProposalStatus.pending,
        createdAt: DateTime.utc(2026, 1, 4),
      ),
    );
    expect(h.proposals.pendingActionableCount, 1);
    expect(h.proposals.pendingActionable.single.id, 'tp_buy');
  });
}
