import 'market_data_client.dart';

/// Metadata for an equities / indices / ETF market-data provider.
class EquityDataSource {
  const EquityDataSource({
    required this.id,
    required this.displayName,
    this.description = '',
  });

  /// Stable machine id (e.g. `yahoo`).
  final String id;

  /// User-facing label (e.g. `Yahoo Finance`).
  final String displayName;

  /// Short muted subtitle in Settings.
  final String description;
}

/// One registered equities provider (metadata + [MarketDataClient]).
class EquityDataSourceEntry {
  const EquityDataSourceEntry({
    required this.source,
    required this.client,
  });

  final EquityDataSource source;
  final MarketDataClient client;
}

/// Catalog of equities market-data providers for Settings and routing.
class EquityDataSourceRegistry {
  const EquityDataSourceRegistry(this.all);

  final List<EquityDataSourceEntry> all;

  EquityDataSourceEntry? entryForId(String id) {
    for (final entry in all) {
      if (entry.source.id == id) return entry;
    }
    return null;
  }

  List<EquityDataSourceEntry> enabledWhere(bool Function(String id) isEnabled) {
    return [
      for (final entry in all)
        if (isEnabled(entry.source.id)) entry,
    ];
  }
}
