import 'package:flutter_test/flutter_test.dart';
import 'package:omniscope/core/async_pool.dart';

void main() {
  test('mapPool preserves order and bounds concurrency', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final started = <int>[];

    final results = await mapPool<int, int>(
      items: List.generate(8, (i) => i),
      concurrency: 3,
      mapper: (i) async {
        inFlight += 1;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        started.add(i);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight -= 1;
        return i * 10;
      },
    );

    expect(results, [0, 10, 20, 30, 40, 50, 60, 70]);
    expect(maxInFlight, lessThanOrEqualTo(3));
    expect(started, [0, 1, 2, 3, 4, 5, 6, 7]);
  });

  test('mapPool skips failed items via onError', () async {
    final results = await mapPool<int, int>(
      items: const [1, 2, 3],
      concurrency: 2,
      mapper: (i) async {
        if (i == 2) throw StateError('boom');
        return i;
      },
      onError: (_, _) => null,
    );
    expect(results, [1, 3]);
  });
}
