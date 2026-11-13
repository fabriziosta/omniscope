@Tags(['live_canary'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../tool/venue_canary.dart';

/// Live network canary — excluded from `make check` / pre-push via tag.
///
/// Run: `make venue-canary` or
/// `flutter test test/venue_canary_test.dart --tags live_canary`
void main() {
  test(
    'venue canary probes Yahoo, Crypto.com, and Alpaca',
    () async {
      final code = await runVenueCanary(
        jsonOut: 'build/venue-canary.json',
        log: print,
      );
      expect(
        code,
        0,
        reason: 'one or more live venue probes failed — see table above '
            'and build/venue-canary.json',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
