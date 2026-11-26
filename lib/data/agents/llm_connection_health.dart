/// Outcome of an LLM provider reachability / auth check.
enum LlmConnectionKind {
  /// Authenticated list-models (or chat) succeeded.
  ok,

  /// HTTP 401/403 or clear auth rejection — key expired, rotated, or wrong.
  invalidKey,

  /// Network / DNS / timeout / 5xx — provider not reachable.
  unreachable,

  /// HTTP 429 / quota exhausted.
  rateLimited,

  /// Probe not applicable (e.g. missing Custom base URL).
  unsupported,
}

/// Result of classifying an HTTP response or thrown error.
class LlmConnectionResult {
  const LlmConnectionResult({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final LlmConnectionKind kind;
  final String message;
  final int? statusCode;

  bool get isOk => kind == LlmConnectionKind.ok;

  bool get needsAttention =>
      kind == LlmConnectionKind.invalidKey ||
      kind == LlmConnectionKind.unreachable ||
      kind == LlmConnectionKind.rateLimited ||
      kind == LlmConnectionKind.unsupported;
}

/// Maps HTTP status / exception text → [LlmConnectionKind] + plain copy.
abstract final class LlmConnectionHealth {
  static LlmConnectionResult ok({int? statusCode}) {
    return LlmConnectionResult(
      kind: LlmConnectionKind.ok,
      message: 'Connected',
      statusCode: statusCode ?? 200,
    );
  }

  static LlmConnectionResult fromHttpStatus(
    int statusCode, {
    String? bodySnippet,
  }) {
    final kind = classify(statusCode: statusCode, message: bodySnippet);
    return LlmConnectionResult(
      kind: kind,
      message: userMessage(kind),
      statusCode: statusCode,
    );
  }

  static LlmConnectionResult fromError(Object error, {int? statusCode}) {
    final text = error.toString();
    final code = statusCode ?? _statusFromMessage(text);
    final kind = classify(statusCode: code, message: text);
    return LlmConnectionResult(
      kind: kind,
      message: userMessage(kind),
      statusCode: code,
    );
  }

  /// Classify from an optional HTTP code and/or exception / body text.
  static LlmConnectionKind classify({int? statusCode, String? message}) {
    if (statusCode != null) {
      if (statusCode == 401 || statusCode == 403) {
        return LlmConnectionKind.invalidKey;
      }
      if (statusCode == 429) return LlmConnectionKind.rateLimited;
      if (statusCode >= 200 && statusCode < 300) return LlmConnectionKind.ok;
      if (statusCode >= 500 || statusCode == 408 || statusCode == 504) {
        return LlmConnectionKind.unreachable;
      }
    }

    final lower = (message ?? '').toLowerCase();
    if (lower.isEmpty) return LlmConnectionKind.unreachable;

    if (_looksLikeAuth(lower)) return LlmConnectionKind.invalidKey;
    if (_looksLikeRateLimit(lower)) return LlmConnectionKind.rateLimited;
    if (_looksLikeNetwork(lower)) return LlmConnectionKind.unreachable;

    // Unknown HTTP 4xx without auth wording → treat as bad key-ish for UX.
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return LlmConnectionKind.invalidKey;
    }
    return LlmConnectionKind.unreachable;
  }

  static String userMessage(LlmConnectionKind kind) {
    return switch (kind) {
      LlmConnectionKind.ok => 'Connected',
      LlmConnectionKind.invalidKey =>
        'API key rejected or expired. Update it under Settings → Agents.',
      LlmConnectionKind.unreachable =>
        'Could not reach the model. Check your network and try again.',
      LlmConnectionKind.rateLimited =>
        'Provider rate limit hit. Wait a moment and try again.',
      LlmConnectionKind.unsupported =>
        'Cannot verify this provider yet. Check the base URL and key.',
    };
  }

  /// Short status line for Connections rows (not the full toast copy).
  static String statusLabel(LlmConnectionKind kind) {
    return switch (kind) {
      LlmConnectionKind.ok => 'Connected',
      LlmConnectionKind.invalidKey => 'Needs attention — key rejected',
      LlmConnectionKind.unreachable => 'Needs attention — unreachable',
      LlmConnectionKind.rateLimited => 'Needs attention — rate limited',
      LlmConnectionKind.unsupported => 'Needs attention — cannot verify',
    };
  }

  static bool looksLikeAuthFailure({int? statusCode, String? message}) {
    return classify(statusCode: statusCode, message: message) ==
        LlmConnectionKind.invalidKey;
  }

  static int? _statusFromMessage(String text) {
    final match = RegExp(r'\b([45]\d{2})\b').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static bool _looksLikeAuth(String lower) {
    if (lower.contains('unauthorized') ||
        lower.contains('unauthenticated') ||
        lower.contains('invalid api key') ||
        lower.contains('invalid_api_key') ||
        lower.contains('incorrect api key') ||
        lower.contains('authentication') ||
        lower.contains('permission denied') ||
        lower.contains('forbidden')) {
      return true;
    }
    if (!lower.contains('api key')) return false;
    return lower.contains('invalid') ||
        lower.contains('expired') ||
        lower.contains('revoked') ||
        lower.contains('denied');
  }

  static bool _looksLikeRateLimit(String lower) {
    return lower.contains('rate limit') ||
        lower.contains('too many requests') ||
        lower.contains('resource_exhausted') ||
        lower.contains('resource exhausted') ||
        lower.contains('quota');
  }

  static bool _looksLikeNetwork(String lower) {
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('cors') ||
        lower.contains('xmlhttprequest');
  }
}
