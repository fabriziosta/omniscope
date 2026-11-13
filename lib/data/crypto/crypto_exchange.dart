/// Metadata for a crypto venue shown as a Crypto group subgroup.
class CryptoExchange {
  const CryptoExchange({
    required this.id,
    required this.displayName,
    required this.defaultSymbols,
  });

  /// Stable machine id (e.g. `crypto_com`).
  final String id;

  /// User-facing subgroup label (e.g. `Crypto.com`).
  final String displayName;

  /// Curated spot pairs for this exchange's list screen.
  final List<String> defaultSymbols;
}
