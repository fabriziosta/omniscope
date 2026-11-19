import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/data/agents/agent_pnl_service.dart';
import 'package:omniscope/data/agents/trade_proposal.dart';

TradeProposal _fill({
  required String id,
  required String symbol,
  required TradeProposalSide side,
  required double quantity,
  required double fillPrice,
  double? realizedPnl,
  String? chatId,
  String roleId = 'intradayTrading',
  bool autopilot = false,
  DateTime? filledAt,
}) {
  return TradeProposal(
    id: id,
    roleId: roleId,
    exchangeId: 'practice',
    symbol: symbol,
    side: side,
    quantity: quantity,
    rationale: 't',
    riskApproved: true,
    status: TradeProposalStatus.executed,
    createdAt: filledAt ?? DateTime.utc(2026, 1, 1),
    chatId: chatId,
    autopilot: autopilot,
    fillPrice: fillPrice,
    fillNotional: fillPrice * quantity,
    filledAt: filledAt ?? DateTime.utc(2026, 1, 1),
    realizedPnl: realizedPnl,
  );
}

void main() {
  test('JSON missing fill fields loads as null', () {
    final p = TradeProposal.fromJson({
      'id': 'tp_legacy',
      'roleId': 'intradayTrading',
      'exchangeId': 'practice',
      'symbol': 'AAPL',
      'side': 'buy',
      'quantity': 1,
      'rationale': 'x',
      'riskApproved': true,
      'status': 'executed',
      'createdAt': '2026-01-01T00:00:00.000Z',
    });
    expect(p.fillPrice, isNull);
    expect(p.fillNotional, isNull);
    expect(p.filledAt, isNull);
    expect(p.realizedPnl, isNull);
  });

  test('summaryForChatSymbol splits profit and loss', () {
    final proposals = [
      _fill(
        id: 'b1',
        symbol: 'AAPL',
        side: TradeProposalSide.buy,
        quantity: 2,
        fillPrice: 100,
        chatId: 'c1',
      ),
      _fill(
        id: 's1',
        symbol: 'AAPL',
        side: TradeProposalSide.sell,
        quantity: 1,
        fillPrice: 120,
        realizedPnl: 20,
        chatId: 'c1',
        filledAt: DateTime.utc(2026, 1, 2),
      ),
      _fill(
        id: 's2',
        symbol: 'AAPL',
        side: TradeProposalSide.sell,
        quantity: 1,
        fillPrice: 80,
        realizedPnl: -20,
        chatId: 'c1',
        filledAt: DateTime.utc(2026, 1, 3),
      ),
      _fill(
        id: 'other',
        symbol: 'AAPL',
        side: TradeProposalSide.sell,
        quantity: 1,
        fillPrice: 200,
        realizedPnl: 50,
        chatId: 'c2',
      ),
    ];

    final summary = AgentPnlService.summaryForChatSymbol(
      proposals: proposals,
      chatId: 'c1',
      symbol: 'AAPL',
    );
    expect(summary.fillCount, 3);
    expect(summary.realizedProfit, 20);
    expect(summary.realizedLoss, 20);
    expect(summary.openBuyQty, 0);
    expect(summary.buyNotional, 200);
    expect(summary.sellNotional, 200);
  });

  test('summaryForRoleSymbol and daily autopilot counters', () {
    final day = DateTime.utc(2026, 3, 10, 12);
    final proposals = [
      _fill(
        id: 'a1',
        symbol: 'MSFT',
        side: TradeProposalSide.buy,
        quantity: 1,
        fillPrice: 50,
        roleId: 'intradayTrading',
        autopilot: true,
        filledAt: day,
      ),
      _fill(
        id: 'a2',
        symbol: 'MSFT',
        side: TradeProposalSide.sell,
        quantity: 1,
        fillPrice: 40,
        realizedPnl: -10,
        roleId: 'intradayTrading',
        autopilot: true,
        filledAt: day,
      ),
      _fill(
        id: 'manual',
        symbol: 'MSFT',
        side: TradeProposalSide.sell,
        quantity: 1,
        fillPrice: 30,
        realizedPnl: -5,
        roleId: 'intradayTrading',
        autopilot: false,
        filledAt: day,
      ),
    ];

    final byRole = AgentPnlService.summaryForRoleSymbol(
      proposals: proposals,
      roleId: 'intradayTrading',
      symbol: 'MSFT',
    );
    expect(byRole.fillCount, 3);
    expect(byRole.realizedLoss, 15);

    expect(
      AgentPnlService.autopilotFillCountForUtcDay(
        proposals: proposals,
        now: day,
      ),
      2,
    );
    expect(
      AgentPnlService.realizedPnlForUtcDay(
        proposals: proposals,
        now: day,
      ),
      -15,
    );
  });
}
