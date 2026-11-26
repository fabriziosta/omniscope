import 'dart:convert';

/// Extracts a fenced or bare JSON object map from assistant text.
abstract final class FencedJsonExtractor {
  static final _fencedJson = RegExp(
    r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
    caseSensitive: false,
  );

  /// Returns the first decoded object that passes [isMatch], or null.
  static Map<String, dynamic>? extractJsonMap(
    String content,
    bool Function(Map<String, dynamic> json) isMatch,
  ) {
    final fenced = _fencedJson.firstMatch(content);
    final candidates = <String>[
      if (fenced != null) fenced.group(1)!,
      content.trim(),
    ];

    for (final raw in candidates) {
      final parsed = tryDecodeObject(raw);
      if (parsed != null && isMatch(parsed)) return parsed;
    }

    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final parsed = tryDecodeObject(content.substring(start, end + 1));
      if (parsed != null && isMatch(parsed)) return parsed;
    }
    return null;
  }

  static Map<String, dynamic>? tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
