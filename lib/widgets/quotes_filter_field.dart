/// Case-insensitive symbol / name filter for quote lists and tests.
List<T> filterBySymbolQuery<T>({
  required List<T> items,
  required String query,
  required String Function(T item) symbolOf,
  String? Function(T item)? nameOf,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return [
    for (final item in items)
      if (symbolOf(item).toLowerCase().contains(q) ||
          (nameOf?.call(item)?.toLowerCase().contains(q) ?? false))
        item,
  ];
}
