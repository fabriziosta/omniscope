import '../crypto/crypto_exchange.dart';
import '../crypto/crypto_exchange_registry.dart';
import '../settings/data_source_settings.dart';

/// Origin of a portfolio shown in Settings and on the Portfolio tab.
enum PortfolioKind { practice, live }

/// Stable identity for one portfolio subgroup (practice book or live exchange).
class PortfolioDescriptor {
  const PortfolioDescriptor({
    required this.id,
    required this.displayName,
    required this.kind,
  });

  factory PortfolioDescriptor.practice() => const PortfolioDescriptor(
        id: practiceId,
        displayName: 'Practice',
        kind: PortfolioKind.practice,
      );

  factory PortfolioDescriptor.live(CryptoExchange exchange) =>
      PortfolioDescriptor(
        id: exchange.id,
        displayName: exchange.displayName,
        kind: PortfolioKind.live,
      );

  /// Config / accordion id for the local paper book.
  static const practiceId = 'practice';

  final String id;
  final String displayName;
  final PortfolioKind kind;

  bool get isPractice => kind == PortfolioKind.practice;
  bool get isLive => kind == PortfolioKind.live;
}

/// Builds the unified Practice + Live portfolio list for UI.
class PortfolioCatalog {
  const PortfolioCatalog._();

  /// Practice first, then each enabled venue that can fetch a live portfolio.
  ///
  /// When [includePendingLive] is true (Settings), also include enabled venues
  /// that support live portfolio but still need credentials.
  static List<PortfolioDescriptor> list({
    required CryptoExchangeRegistry registry,
    required DataSourceSettings dataSources,
    bool includePendingLive = false,
  }) {
    final out = <PortfolioDescriptor>[PortfolioDescriptor.practice()];
    final seen = <String>{PortfolioDescriptor.practiceId};

    for (final client in registry.portfolioClientsWhere(
      dataSources.isCryptoEnabled,
    )) {
      final id = client.exchange.id;
      if (seen.add(id)) {
        out.add(PortfolioDescriptor.live(client.exchange));
      }
    }

    if (includePendingLive) {
      for (final client in registry.enabledWhere(dataSources.isCryptoEnabled)) {
        if (!client.supportsLivePortfolio) continue;
        final id = client.exchange.id;
        if (seen.add(id)) {
          out.add(PortfolioDescriptor.live(client.exchange));
        }
      }
    }

    return out;
  }
}
