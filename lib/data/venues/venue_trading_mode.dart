/// Paper vs live trading endpoint selection for brokers that support both.
enum VenueTradingMode {
  paper,
  live,
}

extension VenueTradingModeX on VenueTradingMode {
  String get apiValue => name;

  String get label => switch (this) {
        VenueTradingMode.paper => 'Paper',
        VenueTradingMode.live => 'Live',
      };

  static VenueTradingMode? tryParse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'paper' => VenueTradingMode.paper,
      'live' => VenueTradingMode.live,
      _ => null,
    };
  }
}
