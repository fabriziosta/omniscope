import 'package:schemantic/schemantic.dart';

import '../../../core/formatting.dart';
import '../../market/models.dart';

/// Shared Genkit tool input parsing and quote formatting for Omniscope tools.
abstract final class OmniscopeAgentToolHelpers {
  static final symbolInput = SchemanticType.map(
    SchemanticType.string(),
    SchemanticType.dynamicSchema(),
  );

  static Map<String, dynamic> asMap(dynamic input) {
    if (input is Map<String, dynamic>) return input;
    if (input is Map) {
      return input.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  /// Parses true/false from bool, 1/0, or common string tokens.
  static bool? readBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) {
      if (raw == 1) return true;
      if (raw == 0) return false;
      return null;
    }
    final s = raw?.toString().trim().toLowerCase() ?? '';
    if (s == 'true' || s == 'yes' || s == 'on' || s == '1') return true;
    if (s == 'false' || s == 'no' || s == 'off' || s == '0') return false;
    return null;
  }

  static List<String> readSymbols(dynamic input) {
    final map = asMap(input);
    final out = <String>[];
    final single = map['symbol'];
    if (single is String && single.trim().isNotEmpty) {
      out.add(single.trim().toUpperCase());
    }
    final list = map['symbols'];
    if (list is List) {
      out.addAll(readSymbolList(list));
    }
    return out;
  }

  static List<String> readSymbolList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item?.toString().trim().toUpperCase() ?? '';
      if (s.isEmpty || !seen.add(s)) continue;
      out.add(s);
    }
    return out;
  }

  static String formatQuoteLine(Quote q) {
    final parts = <String>[
      '${q.symbol}: ${formatMoney(q.price)}'
          '${q.currency != null ? ' ${q.currency}' : ''}',
    ];
    if (q.changePercent != null) {
      parts.add('day ${formatPercent(q.changePercent)}');
    }
    if (q.previousClose != null) {
      parts.add('prev ${formatMoney(q.previousClose)}');
    }
    if (q.name != null && q.name!.trim().isNotEmpty) {
      parts.add('name=${q.name!.trim()}');
    }
    if (q.exchange != null && q.exchange!.trim().isNotEmpty) {
      parts.add('ex=${q.exchange!.trim()}');
    }
    if (q.dataSource != null && q.dataSource!.trim().isNotEmpty) {
      parts.add('src=${q.dataSource!.trim()}');
    }
    return parts.join(' · ');
  }
}
