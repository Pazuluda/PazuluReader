import 'dart:collection';

/// Bounded LRU cache with optional time-to-live and a size budget.
class LruCache<K, V> {
  LruCache({
    required this.maxEntries,
    this.maxWeight,
    this.weigh,
    this.ttl,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries;

  /// Optional total weight (e.g. bytes) with [weigh] computing each value.
  final int? maxWeight;
  final int Function(V value)? weigh;
  final Duration? ttl;
  final DateTime Function() _clock;

  final LinkedHashMap<K, (V, DateTime, int)> _map = LinkedHashMap();
  int _weight = 0;

  int get length => _map.length;
  int get weight => _weight;

  V? get(K key) {
    final entry = _map.remove(key);
    if (entry == null) return null;
    final limit = ttl;
    if (limit != null && _clock().difference(entry.$2) > limit) {
      _weight -= entry.$3;
      return null;
    }
    _map[key] = entry; // move to most-recent position
    return entry.$1;
  }

  void put(K key, V value) {
    final old = _map.remove(key);
    if (old != null) _weight -= old.$3;
    final w = weigh?.call(value) ?? 0;
    final budget = maxWeight;
    if (budget != null && w > budget) return; // never cache oversized items
    _map[key] = (value, _clock(), w);
    _weight += w;
    while (_map.length > maxEntries ||
        (budget != null && _weight > budget && _map.isNotEmpty)) {
      final oldest = _map.keys.first;
      final removed = _map.remove(oldest)!;
      _weight -= removed.$3;
    }
  }

  void remove(K key) {
    final old = _map.remove(key);
    if (old != null) _weight -= old.$3;
  }

  void clear() {
    _map.clear();
    _weight = 0;
  }
}
