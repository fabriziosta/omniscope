import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../trading/order_models.dart';

/// Shared REST helpers for venue adapters (JSON decode + order errors).
class VenueHttp {
  const VenueHttp._();

  static Map<String, dynamic>? decodeObject(http.Response response) {
    if (response.body.isEmpty) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static List<dynamic> decodeList(http.Response response) {
    if (response.body.isEmpty) return const [];
    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded;
    return const [];
  }

  static OrderResult failFromResponse(
    http.Response response, {
    String fallback = 'Request failed',
  }) {
    final body = response.body.trim();
    final detail = body.isEmpty
        ? fallback
        : (body.length > 240 ? '${body.substring(0, 240)}…' : body);
    return OrderResult.fail('HTTP ${response.statusCode}: $detail');
  }

  static bool isSuccessStatus(int code) => code >= 200 && code < 300;
}
