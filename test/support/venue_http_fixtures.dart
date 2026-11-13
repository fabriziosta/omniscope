import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Load checked-in venue API response bodies under `test/fixtures/venues/`.
///
/// Paths are relative to that root, e.g. `crypto_com/get-tickers.json`.
/// Prefer these over inline JSON so schema drift shows up in git diffs when
/// fixtures are refreshed after a live canary parse failure.
class VenueHttpFixtures {
  VenueHttpFixtures._();

  static final Directory _root = () {
    final fromCwd = Directory('test/fixtures/venues');
    if (fromCwd.existsSync()) return fromCwd;
    // Some runners keep CWD elsewhere; walk up from this library file.
    final scriptDir = File(Platform.script.toFilePath()).parent;
    final candidate = Directory('${scriptDir.path}/../fixtures/venues');
    if (candidate.existsSync()) return candidate;
    return fromCwd;
  }();

  static String pathFor(String relativePath) =>
      '${_root.path}/$relativePath';

  static String readString(String relativePath) {
    final file = File(pathFor(relativePath));
    if (!file.existsSync()) {
      throw StateError('Missing venue fixture: ${file.path}');
    }
    return file.readAsStringSync();
  }

  static Map<String, dynamic> readJsonObject(String relativePath) {
    final decoded = jsonDecode(readString(relativePath));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Expected JSON object in $relativePath');
    }
    return decoded;
  }

  static Object? readJson(String relativePath) =>
      jsonDecode(readString(relativePath));

  /// JSON response with `application/json` content-type.
  static http.Response jsonResponse(
    String relativePath, {
    int statusCode = 200,
  }) {
    return http.Response(
      readString(relativePath),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }

  /// Route matcher → fixture (or custom response). Unmatched → 404.
  static MockClient mockClient(
    Map<
            bool Function(http.BaseRequest),
            http.Response Function(http.BaseRequest)>
        routes,
  ) {
    return MockClient((request) async {
      for (final entry in routes.entries) {
        if (entry.key(request)) {
          return entry.value(request);
        }
      }
      return http.Response('not found: ${request.url}', 404);
    });
  }

  static bool pathEndsWith(http.BaseRequest request, String suffix) =>
      request.url.path.endsWith(suffix);

  static bool pathContains(http.BaseRequest request, String fragment) =>
      request.url.path.contains(fragment);

  static bool isGet(http.BaseRequest request) => request.method == 'GET';

  static bool isPost(http.BaseRequest request) => request.method == 'POST';
}
