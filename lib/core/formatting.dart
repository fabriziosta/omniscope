import 'package:intl/intl.dart';

/// How money amounts render in Markets, Crypto, Portfolio, and Asset detail.
enum PriceFormat {
  /// Always full currency (e.g. $12,345.67).
  full,

  /// Compact currency for larger amounts (e.g. $12.35K).
  compact,
}

final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
final _compactMoney = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 2);
final _percent = NumberFormat('+0.00%;-0.00%');
final _signedMoney = NumberFormat('+\$#,##0.00;-\$#,##0.00');

String formatMoney(num? value) {
  if (value == null || value.isNaN) return '—';
  return _money.format(value);
}

String formatCompactMoney(num? value) {
  if (value == null || value.isNaN) return '—';
  if (value.abs() >= 10000) return _compactMoney.format(value);
  return _money.format(value);
}

/// Preference-aware money for Markets / Crypto / Portfolio / Asset detail.
String formatDisplayMoney(num? value, PriceFormat format) {
  return switch (format) {
    PriceFormat.full => formatMoney(value),
    PriceFormat.compact => formatCompactMoney(value),
  };
}

String formatSignedMoney(num? value) {
  if (value == null || value.isNaN) return '—';
  return _signedMoney.format(value);
}

String formatPercent(num? value) {
  if (value == null || value.isNaN) return '—';
  return _percent.format(value);
}

String formatShares(num shares) {
  if (shares == shares.roundToDouble()) {
    return shares.toInt().toString();
  }
  return shares.toStringAsFixed(4);
}

final _compactNumber = NumberFormat.compact();

String formatCompactNumber(num? value) {
  if (value == null || value.isNaN) return '—';
  return _compactNumber.format(value);
}

/// Relative label for a UTC (or any) timestamp, shown in local time.
///
/// Recent: `Just now` / `5m ago` / `3h ago` / `2d ago`. Older: `YYYY-MM-DD`.
String formatRelativeTime(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final diff = (now ?? DateTime.now()).difference(local);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
