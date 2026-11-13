/// Runs [mapper] over [items] with at most [concurrency] in flight.
///
/// Results keep input order. Failed items are omitted when [onError] returns
/// null; otherwise the returned value is included. If every item fails and
/// [onError] always returns null, rethrows the last error when
/// [throwIfEmpty] is true.
Future<List<T>> mapPool<S, T>({
  required List<S> items,
  required int concurrency,
  required Future<T> Function(S item) mapper,
  T? Function(S item, Object error)? onError,
  bool throwIfEmpty = true,
}) async {
  if (items.isEmpty) return const [];
  final limit = concurrency < 1 ? 1 : concurrency;
  final results = List<T?>.filled(items.length, null);
  Object? lastError;
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next;
      next += 1;
      if (i >= items.length) return;
      final item = items[i];
      try {
        results[i] = await mapper(item);
      } catch (e) {
        lastError = e;
        if (onError != null) {
          results[i] = onError(item, e);
        }
      }
    }
  }

  final workers = List.generate(
    limit < items.length ? limit : items.length,
    (_) => worker(),
  );
  await Future.wait(workers);

  final out = <T>[
    for (final r in results) ?r,
  ];
  if (out.isEmpty && throwIfEmpty && lastError != null) {
    throw lastError!;
  }
  return out;
}
