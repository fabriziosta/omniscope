import '../market/market_data_client.dart';
import 'trade_proposal.dart';

/// Realized / notional rollup for agent fills on one symbol.
class AgentPnlSummary {
  const AgentPnlSummary({
    required this.symbol,
    required this.buyNotional,
    required this.sellNotional,
    required this.realizedProfit,
    required this.realizedLoss,
    required this.fillCount,
    required this.openBuyQty,
    this.roleId,
    this.chatId,
    this.unrealizedPnl,
  });

  final String symbol;
  final String? roleId;
  final String? chatId;
  final double buyNotional;
  final double sellNotional;
  final double realizedProfit;
  final double realizedLoss;
  final int fillCount;

  /// Leftover buy quantity after FIFO matching sells in this grain.
  final double openBuyQty;
  final double? unrealizedPnl;

  double get netRealized => realizedProfit - realizedLoss;

  bool get hasActivity => fillCount > 0;

  String toPlainLine() {
    final profit = realizedProfit.toStringAsFixed(2);
    final loss = realizedLoss.toStringAsFixed(2);
    final open = openBuyQty > 0
        ? ' · open ${openBuyQty.toStringAsFixed(openBuyQty == openBuyQty.roundToDouble() ? 0 : 4)}'
        : '';
    return '$symbol · profit \$$profit / loss \$$loss$open';
  }
}

/// Aggregates executed [TradeProposal] fill economics by chat or specialty.
abstract final class AgentPnlService {
  static List<TradeProposal> executedFills(Iterable<TradeProposal> proposals) {
    final out = <TradeProposal>[
      for (final p in proposals)
        if (p.status == TradeProposalStatus.executed &&
            p.side != TradeProposalSide.hold &&
            p.quantity > 0)
          p,
    ];
    out.sort((a, b) {
      final aAt = a.filledAt ?? a.createdAt;
      final bAt = b.filledAt ?? b.createdAt;
      return aAt.compareTo(bAt);
    });
    return out;
  }

  static AgentPnlSummary summaryForChatSymbol({
    required Iterable<TradeProposal> proposals,
    required String chatId,
    required String symbol,
  }) {
    final id = chatId.trim();
    final sym = symbol.trim().toUpperCase();
    return _summarize(
      executedFills(proposals).where(
        (p) => p.chatId == id && p.symbol == sym,
      ),
      symbol: sym,
      chatId: id,
    );
  }

  static AgentPnlSummary summaryForRoleSymbol({
    required Iterable<TradeProposal> proposals,
    required String roleId,
    required String symbol,
  }) {
    final role = roleId.trim();
    final sym = symbol.trim().toUpperCase();
    return _summarize(
      executedFills(proposals).where(
        (p) => p.roleId == role && p.symbol == sym,
      ),
      symbol: sym,
      roleId: role,
    );
  }

  /// One row per (roleId, symbol) with at least one executed fill.
  static List<AgentPnlSummary> summariesByRoleSymbol(
    Iterable<TradeProposal> proposals,
  ) {
    final fills = executedFills(proposals);
    final keys = <String>{};
    final ordered = <(String, String)>[];
    for (final p in fills) {
      final key = '${p.roleId}\u0000${p.symbol}';
      if (keys.add(key)) ordered.add((p.roleId, p.symbol));
    }
    return [
      for (final (roleId, symbol) in ordered)
        summaryForRoleSymbol(
          proposals: fills,
          roleId: roleId,
          symbol: symbol,
        ),
    ];
  }

  /// Primary symbol for a chat strip: latest executed fill's symbol.
  static String? latestFilledSymbolForChat({
    required Iterable<TradeProposal> proposals,
    required String chatId,
  }) {
    final id = chatId.trim();
    final fills = executedFills(proposals).where((p) => p.chatId == id);
    if (fills.isEmpty) return null;
    return fills.last.symbol;
  }

  /// Sum of realized P&L on executed fills in the UTC calendar day of [now].
  static double realizedPnlForUtcDay({
    required Iterable<TradeProposal> proposals,
    required DateTime now,
    bool autopilotOnly = false,
  }) {
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var sum = 0.0;
    for (final p in executedFills(proposals)) {
      if (autopilotOnly && !p.autopilot) continue;
      final at = p.filledAt ?? p.createdAt;
      if (at.isBefore(dayStart) || !at.isBefore(dayEnd)) continue;
      final pnl = p.realizedPnl;
      if (pnl != null) sum += pnl;
    }
    return sum;
  }

  /// Count of executed Autopilot fills in the UTC calendar day of [now].
  static int autopilotFillCountForUtcDay({
    required Iterable<TradeProposal> proposals,
    required DateTime now,
  }) {
    final dayStart = DateTime.utc(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    var count = 0;
    for (final p in executedFills(proposals)) {
      if (!p.autopilot) continue;
      final at = p.filledAt ?? p.createdAt;
      if (at.isBefore(dayStart) || !at.isBefore(dayEnd)) continue;
      count++;
    }
    return count;
  }

  static Future<AgentPnlSummary> withUnrealized({
    required AgentPnlSummary summary,
    required Iterable<TradeProposal> proposals,
    required MarketDataClient marketData,
    String? chatId,
    String? roleId,
  }) async {
    if (summary.openBuyQty <= 0) return summary;
    final fills = executedFills(proposals).where((p) {
      if (p.symbol != summary.symbol) return false;
      if (chatId != null && p.chatId != chatId) return false;
      if (roleId != null && p.roleId != roleId) return false;
      return true;
    });
    var openQty = 0.0;
    var openCost = 0.0;
    for (final p in fills) {
      if (p.side == TradeProposalSide.buy) {
        final price = p.fillPrice ?? 0;
        openQty += p.quantity;
        openCost += p.quantity * price;
      } else if (p.side == TradeProposalSide.sell) {
        var remaining = p.quantity;
        while (remaining > 0 && openQty > 0) {
          final take = remaining < openQty ? remaining : openQty;
          final avg = openQty > 0 ? openCost / openQty : 0.0;
          openQty -= take;
          openCost -= avg * take;
          remaining -= take;
        }
      }
    }
    if (openQty <= 0) {
      return AgentPnlSummary(
        symbol: summary.symbol,
        roleId: summary.roleId,
        chatId: summary.chatId,
        buyNotional: summary.buyNotional,
        sellNotional: summary.sellNotional,
        realizedProfit: summary.realizedProfit,
        realizedLoss: summary.realizedLoss,
        fillCount: summary.fillCount,
        openBuyQty: 0,
      );
    }
    try {
      final quotes = await marketData.getQuotes([summary.symbol]);
      if (quotes.isEmpty || quotes.first.price <= 0) return summary;
      final mark = quotes.first.price;
      final avg = openCost / openQty;
      return AgentPnlSummary(
        symbol: summary.symbol,
        roleId: summary.roleId,
        chatId: summary.chatId,
        buyNotional: summary.buyNotional,
        sellNotional: summary.sellNotional,
        realizedProfit: summary.realizedProfit,
        realizedLoss: summary.realizedLoss,
        fillCount: summary.fillCount,
        openBuyQty: openQty,
        unrealizedPnl: (mark - avg) * openQty,
      );
    } catch (_) {
      return summary;
    }
  }

  static AgentPnlSummary _summarize(
    Iterable<TradeProposal> fills, {
    required String symbol,
    String? roleId,
    String? chatId,
  }) {
    var buyNotional = 0.0;
    var sellNotional = 0.0;
    var realizedProfit = 0.0;
    var realizedLoss = 0.0;
    var fillCount = 0;
    var openBuyQty = 0.0;

    for (final p in fills) {
      fillCount++;
      final notional = p.fillNotional ??
          ((p.fillPrice != null) ? p.fillPrice! * p.quantity : 0.0);
      if (p.side == TradeProposalSide.buy) {
        buyNotional += notional;
        openBuyQty += p.quantity;
      } else if (p.side == TradeProposalSide.sell) {
        sellNotional += notional;
        openBuyQty -= p.quantity;
        if (openBuyQty < 0) openBuyQty = 0;
        final pnl = p.realizedPnl;
        if (pnl != null) {
          if (pnl >= 0) {
            realizedProfit += pnl;
          } else {
            realizedLoss += -pnl;
          }
        }
      }
    }

    return AgentPnlSummary(
      symbol: symbol,
      roleId: roleId,
      chatId: chatId,
      buyNotional: buyNotional,
      sellNotional: sellNotional,
      realizedProfit: realizedProfit,
      realizedLoss: realizedLoss,
      fillCount: fillCount,
      openBuyQty: openBuyQty,
    );
  }
}
