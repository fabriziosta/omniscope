import 'package:flutter/services.dart';

/// Shared loader / serializer for the repo-root `.env` asset (gitignored; see
/// `.env.example`).
///
/// Used for LLM provider keys and exchange/market credentials.
class DotEnvAsset {
  DotEnvAsset._();

  /// Preferred asset path (developer-filled, gitignored).
  static const envAssetPath = '.env';

  /// Committed empty template — always present for builds/tests.
  static const exampleAssetPath = '.env.example';

  /// Loads `.env`, then falls back to `.env.example`, then an empty map.
  static Future<Map<String, String>> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    for (final path in [envAssetPath, exampleAssetPath]) {
      try {
        return parse(await b.loadString(path));
      } catch (_) {
        // Try next path (`.env` may be absent until copied from the example).
      }
    }
    return const {};
  }

  /// Loads the raw text of `.env`, then `.env.example`, then `''`.
  static Future<String> loadRaw({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    for (final path in [envAssetPath, exampleAssetPath]) {
      try {
        return await b.loadString(path);
      } catch (_) {
        // Try next path.
      }
    }
    return '';
  }

  /// Parses dotenv-style `KEY=VALUE` lines. Comments and blank lines are skipped.
  /// Empty values are omitted from the returned map.
  static Map<String, String> parse(String raw) {
    final values = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2) {
        final q = value[0];
        if ((q == '"' || q == "'") && value.endsWith(q)) {
          value = value.substring(1, value.length - 1);
        }
      }
      if (name.isNotEmpty && value.isNotEmpty) {
        values[name] = value;
      }
    }
    return values;
  }

  /// Rewrites [updates] into [raw] while preserving comments and blank lines.
  ///
  /// Existing `KEY=` lines are replaced in place. Missing keys are appended at
  /// the end. An empty update value writes `KEY=` (cleared).
  static String upsert(String raw, Map<String, String> updates) {
    if (updates.isEmpty) return raw;

    final pending = Map<String, String>.of(updates);
    final lines = raw.split('\n');
    final out = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        out.add(line);
        continue;
      }
      final eq = trimmed.indexOf('=');
      if (eq <= 0) {
        out.add(line);
        continue;
      }
      final name = trimmed.substring(0, eq).trim();
      if (!pending.containsKey(name)) {
        out.add(line);
        continue;
      }
      final value = pending.remove(name)!;
      out.add('$name=${_formatValue(value)}');
    }

    if (pending.isNotEmpty) {
      if (out.isNotEmpty && out.last.trim().isNotEmpty) {
        out.add('');
      }
      for (final entry in pending.entries) {
        out.add('${entry.key}=${_formatValue(entry.value)}');
      }
    }

    return out.join('\n');
  }

  static String _formatValue(String value) {
    if (value.isEmpty) return '';
    final needsQuotes = value.contains(' ') ||
        value.contains('#') ||
        value.contains('"') ||
        value.contains("'") ||
        value.contains('\n');
    if (!needsQuotes) return value;
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
