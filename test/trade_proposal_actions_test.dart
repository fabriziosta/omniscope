import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_activity.dart';
import 'package:omniscope/data/agents/agent_activity_repository.dart';
import 'package:omniscope/data/agents/agent_app_settings.dart';
import 'package:omniscope/data/agents/agent_chat_repository.dart';
import 'package:omniscope/data/agents/chat_agent_settings.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';
import 'package:omniscope/data/agents/trade_proposal_repository.dart';
import 'package:omniscope/data/crypto/crypto_exchange_registry.dart';
import 'package:omniscope/data/portfolio/portfolio_catalog.dart';
import 'package:omniscope/data/portfolio/portfolio_repository.dart';
import 'package:omniscope/data/settings/data_source_settings.dart';
import 'package:omniscope/data/settings/mandate_settings.dart';
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
        AgentChatRepository chats,
        String chatId,
        AgentAppSettings appSettings,
      })> harness({ChatMandate? mandate}) async {
    final store = await memoryConfig();
    final appSettings = AgentAppSettings(store: store);
    await appSettings.load();
    final chats = AgentChatRepository(store: store, appSettings: appSettings);
    await chats.load();
    final chat = await chats.createChat(title: 'Rails');
    if (mandate != null) {
      await chats.setMandate(chat.chatId, mandate);
    }
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
      appSettings: appSettings,
      proposals: proposals,
      activity: activity,
      tradeExecutor: executor,
      marketData: market,
      portfolio: portfolio,
      chats: chats,
    );
    return (
      actions: actions,
      proposals: proposals,
      activity: activity,
      portfolio: portfolio,
      chats: chats,
      chatId: chat.chatId,
      appSettings: appSettings,
    );
  }

  test('confirm accepts pending proposal into Practice', () async {
    final h = await harness();
    final proposal = TradeProposal(
      id: 'tp_actions_ok',
      roleId: 'intradayTrading',
      exchangeId: 'practice',
      symbol: 'AAPL',
      side: TradeProposalSide.buy,
      quantity: 2,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 1),
      chatId: h.chatId,
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.confirm(
      proposal.id,
      targetPortfolioId: PortfolioDescriptor.practiceId,
    );
    expect(err, isNull);
    final executed = h.proposals.byId(proposal.id)!;
    expect(executed.status, TradeProposalStatus.executed);
    expect(executed.status.dashboardLabel, 'Accepted');
    expect(executed.fillPrice, 100);
    expect(executed.fillNotional, 200);
    expect(executed.filledAt, isNotNull);
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

  test('confirm enforces max notional', () async {
    final h = await harness(
      mandate: const ChatMandate(maxNotionalPerProposal: 50),
    );
    final proposal = TradeProposal(
      id: 'tp_notional',
      roleId: 'intradayTrading',
      exchangeId: 'practice',
      symbol: 'AAPL',
      side: TradeProposalSide.buy,
      quantity: 2,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 1),
      chatId: h.chatId,
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.confirm(
      proposal.id,
      targetPortfolioId: PortfolioDescriptor.practiceId,
    );
    expect(err, contains('Notional'));
    expect(
      h.proposals.byId(proposal.id)!.status,
      TradeProposalStatus.pending,
    );
  });

  test('autopilot skips when daily fill budget reached', () async {
    final h = await harness(
      mandate: const ChatMandate(maxAutopilotFillsPerDay: 1),
    );
    final now = DateTime.now().toUtc();
    await h.proposals.upsert(
      TradeProposal(
        id: 'tp_prior_fill',
        roleId: 'intradayTrading',
        exchangeId: 'practice',
        symbol: 'AAPL',
        side: TradeProposalSide.buy,
        quantity: 1,
        rationale: 'prior',
        riskApproved: true,
        status: TradeProposalStatus.executed,
        createdAt: now,
        autopilot: true,
        fillPrice: 100,
        fillNotional: 100,
        filledAt: now,
        chatId: h.chatId,
      ),
    );
    final proposal = TradeProposal(
      id: 'tp_budget',
      roleId: 'intradayTrading',
      exchangeId: 'practice',
      symbol: 'AAPL',
      side: TradeProposalSide.buy,
      quantity: 1,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: now,
      chatId: h.chatId,
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.confirm(
      proposal.id,
      autopilot: true,
      targetPortfolioId: PortfolioDescriptor.practiceId,
    );
    expect(err, contains('fill budget'));
    expect(
      h.proposals.byId(proposal.id)!.status,
      TradeProposalStatus.skipped,
    );
  });

  test('sell confirm records realized P&L from Practice avgCost', () async {
    final h = await harness();
    await h.portfolio.buy(symbol: 'AAPL', shares: 2, price: 100);
    final proposal = TradeProposal(
      id: 'tp_sell_pnl',
      roleId: 'intradayTrading',
      exchangeId: 'practice',
      symbol: 'AAPL',
      side: TradeProposalSide.sell,
      quantity: 1,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 5),
      chatId: h.chatId,
    );
    await h.proposals.upsert(proposal);

    final err = await h.actions.confirm(
      proposal.id,
      targetPortfolioId: PortfolioDescriptor.practiceId,
    );
    expect(err, isNull);
    final executed = h.proposals.byId(proposal.id)!;
    expect(executed.fillPrice, 100);
    expect(executed.realizedPnl, 0);
  });

  test('dismiss refuses pending proposal', () async {
    final h = await harness();
    final proposal = TradeProposal(
      id: 'tp_actions_dismiss',
      roleId: 'intradayTrading',
      exchangeId: 'practice',
      symbol: 'MSFT',
      side: TradeProposalSide.sell,
      quantity: 1,
      rationale: 'test',
      riskApproved: true,
      status: TradeProposalStatus.pending,
      createdAt: DateTime.utc(2026, 1, 2),
      chatId: h.chatId,
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
        roleId: 'intradayTrading',
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
        roleId: 'intradayTrading',
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

  test('preferredPortfolioId reads chat agentSettings', () async {
    final h = await harness();
    expect(
      h.actions.preferredPortfolioId(chatId: h.chatId),
      PortfolioDescriptor.practiceId,
    );
    await h.chats.setAgentSettings(
      h.chatId,
      const ChatAgentSettings(autopilotExchangeId: 'practice'),
    );
    expect(h.actions.preferredPortfolioId(chatId: h.chatId), 'practice');
    expect(h.actions.needsPortfolioPicker(chatId: h.chatId), isFalse);
  });
}
