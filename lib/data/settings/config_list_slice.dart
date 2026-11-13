import 'user_config_store.dart';

/// Shared helpers for capped list slices in [UserConfigStore].
class ConfigListSlice {
  ConfigListSlice._();

  /// Parses [slice] as a map, reads [listKey], and maps each item via [parse].
  /// Invalid items are skipped.
  static List<T> parseItems<T>(
    Object? slice,
    String listKey,
    T? Function(Map<String, dynamic> json) parse,
  ) {
    if (slice is! Map) return const [];
    final raw = Map<String, dynamic>.from(slice)[listKey];
    if (raw is! List) return const [];
    final out = <T>[];
    for (final item in raw) {
      try {
        if (item is! Map) continue;
        final value = parse(Map<String, dynamic>.from(item));
        if (value != null) out.add(value);
      } catch (_) {}
    }
    return out;
  }

  /// Prepends [item], optionally dropping existing entries via [exclude], then caps.
  static List<T> prependCapped<T>(
    List<T> current,
    T item, {
    required int maxStored,
    bool Function(T existing)? exclude,
  }) {
    final retained = exclude == null
        ? List<T>.from(current)
        : [
            for (final e in current)
              if (!exclude(e)) e,
          ];
    retained.insert(0, item);
    if (retained.length > maxStored) {
      return retained.sublist(0, maxStored);
    }
    return retained;
  }

  /// Persists [items] under [sliceKey] → [listKey] via [toJson].
  static Future<void> persist<T>(
    UserConfigStore? store, {
    required String sliceKey,
    required String listKey,
    required List<T> items,
    required Map<String, dynamic> Function(T item) toJson,
  }) async {
    await store?.setSlice(sliceKey, {
      listKey: items.map(toJson).toList(),
    });
  }
}
